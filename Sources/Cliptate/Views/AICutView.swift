import AVFoundation
import AppKit
import SwiftUI
import Translation
import UniformTypeIdentifiers

struct AICutView: View {
  @Binding var selectedVideoURLs: [URL]
  @Binding var activeVideoURL: URL?
  @Binding var videoStates: [URL: VideoState]
  @Binding var isTranscribing: Bool
  @Binding var isExporting: Bool
  @Binding var statusText: String
  @Binding var isInitializingModel: Bool
  @Binding var modelDownloadProgress: ModelDownloadProgress?
  @Binding var batchTranscriptionProgress: (current: Int, total: Int)?
  let launchURLs: [URL]
  /// Pre-loaded segments keyed by URL, bypassing transcription when present.
  let restoredVideoStates: [URL: VideoState]
  let onSessionEnded: (() -> Void)?

  @State private var isAICorrecting = false
  @State private var isAIEnhancing = false
  @State private var aiErrorMessage: String? = nil
  @State private var showCustomPromptDialog = false
  @State private var pendingCorrectionType: CorrectionType?
  @State private var showRestoreConfirmation = false
  @State private var activeTranscriptionTask: Task<Void, Never>?
  @State private var activeTranscriptionTaskGeneration: UInt64 = 0
  @State private var aiCutSessionGeneration: UInt64 = 0
  @State private var isTranslating = false
  @State private var exportProgress = ExportProgressState()
  @State private var activeTranslationTask: Task<Void, Never>?
  @State private var pendingTranslationRequest: PendingTranslationRequest?
  @State private var translationConfigurationStorage: Any?
  @State private var processedSegments: [Segment] = []
  @State private var effectsVersion: Int = 0
  @State private var translationsVersion: Int = 0
  @State private var dictionaryTermsFromCorrection: [String] = []
  @State private var showCorrectionDictionarySheet = false
  @StateObject private var flowModel = AICutFlowModel()
  @StateObject private var windowCoordinator = AICutWindowCoordinator()
  @State private var hasConsumedLaunchURLs = false
  private let batchTranscriptionRuntime = BatchTranscriptionRuntime.shared
  private let historyRuntime = HistoryRuntime.shared
  private let dubbingRuntime = DubbingRuntime.shared

  private enum CorrectionType {
    case current
    case all
  }

  private struct ImportedBatchVideoResult {
    let segments: [Segment]
    let audioDuration: TimeInterval
    let sourceURLBookmark: Data?
  }

  private struct ExistingVideoStateSnapshot {
    let segments: [Segment]
    let audioDuration: TimeInterval?
  }

  private struct PendingTranslationRequest {
    let url: URL
    let segments: [Segment]
    let sourceLanguage: Language
    let targetLanguage: Language
    let sessionGeneration: UInt64
  }

  @EnvironmentObject private var config: AppConfiguration
  @EnvironmentObject private var securityScopeManager: SecurityScopedURLAccessManager
  @Environment(\.undoManager) private var undoManager
  @StateObject private var fallbackPlayback = VideoPlaybackCoordinator()

  init(
    selectedVideoURLs: Binding<[URL]>,
    activeVideoURL: Binding<URL?>,
    videoStates: Binding<[URL: VideoState]>,
    isTranscribing: Binding<Bool>,
    isExporting: Binding<Bool>,
    statusText: Binding<String>,
    isInitializingModel: Binding<Bool>,
    modelDownloadProgress: Binding<ModelDownloadProgress?>,
    batchTranscriptionProgress: Binding<(current: Int, total: Int)?>,
    launchURLs: [URL] = [],
    restoredVideoStates: [URL: VideoState] = [:],
    onSessionEnded: (() -> Void)? = nil
  ) {
    _selectedVideoURLs = selectedVideoURLs
    _activeVideoURL = activeVideoURL
    _videoStates = videoStates
    _isTranscribing = isTranscribing
    _isExporting = isExporting
    _statusText = statusText
    _isInitializingModel = isInitializingModel
    _modelDownloadProgress = modelDownloadProgress
    _batchTranscriptionProgress = batchTranscriptionProgress
    self.launchURLs = launchURLs
    self.restoredVideoStates = restoredVideoStates
    self.onSessionEnded = onSessionEnded
  }

  private var currentPlayback: VideoPlaybackCoordinator {
    if let url = activeVideoURL, let state = videoStates[url] {
      return state.playback
    }
    return fallbackPlayback
  }

  private var currentSegments: [Segment] {
    if let url = activeVideoURL, videoStates[url] != nil {
      return paddedSegments(for: url)
    } else {
      return []
    }
  }

  /// Hash of all config/state inputs that affect segment processing.
  /// Used to trigger debounced recomputation via `.task(id:)`.
  private var segmentProcessingSignature: Int {
    var hasher = Hasher()
    hasher.combine(activeVideoURL)
    hasher.combine(config.filterSilent)
    hasher.combine(config.splitBySentence)
    hasher.combine(config.maxCharsPerSegment)
    hasher.combine(config.leftPadMs)
    hasher.combine(config.rightPadMs)
    hasher.combine(config.effectFilterFillerWords)
    hasher.combine(config.effectFillerWords)
    if let url = activeVideoURL, let state = videoStates[url] {
      hasher.combine(state.segments.count)
      hasher.combine(state.segments.first?.startTime ?? -1)
      hasher.combine(state.segments.last?.endTime ?? -1)
      hasher.combine(state.removedProcessedSegmentIDs.count)
      // Include text content so text-only edits also trigger reprocessing
      for seg in state.segments {
        hasher.combine(seg.text)
      }
    }
    return hasher.finalize()
  }

  private var workspaceState: AICutWorkspace {
    AICutWorkspace(
      selectedVideoURLs: selectedVideoURLs,
      activeVideoURL: activeVideoURL,
      videoStates: videoStates
    )
  }

  var body: some View {
    baseView
  }

  private var baseView: some View {
    landingView
      .background(
        AICutWindowSyncBridge(
          coordinator: windowCoordinator,
          phase: flowModel.phase,
          importSetupContent: AnyView(importSetupWindowContent),
          progressContent: AnyView(progressWindowContent),
          progressCancelAction: dismissProgressShell,
          editorContent: AnyView(editorWindowContent),
          editorCloseAction: exitEditingSession
        )
      )
    .onChange(of: activeVideoURL) { oldURL, newURL in
      if let oldURL, let oldPlayback = videoStates[oldURL]?.playback, oldPlayback.isPlaying {
        oldPlayback.pause()
        oldPlayback._updatePlaying(false)
      }
      if let newURL, let newPlayback = videoStates[newURL]?.playback {
        // Ensure the newly selected video remains paused until the user chooses to play it
        newPlayback.pause()
        newPlayback._updatePlaying(false)
      }
      processedSegments = currentSegments
    }
    .task(id: segmentProcessingSignature) {
      if processedSegments.isEmpty && !currentSegments.isEmpty {
        processedSegments = currentSegments
        return
      }
      try? await Task.sleep(for: .milliseconds(150))
      guard !Task.isCancelled else { return }
      let newSegments = currentSegments
      if newSegments != processedSegments {
        processedSegments = newSegments
      }
    }
    .onChange(of: processedSegments) { _, newValue in
      // Sync processed segments to the active VideoState so VideoPlayerView
      // can observe changes directly without relying on the AnyView prop chain.
      if let url = activeVideoURL, let state = videoStates[url] {
        state.processedSegments = newValue
      }
    }
    .onChange(of: config.translationTargetLanguage) { _, newLanguage in
      for (url, state) in videoStates {
        if let lastLanguage = state.lastTranslatedLanguage, lastLanguage != newLanguage {
          state.clearTranslations()
            markTranslationsChanged(for: url, state: state)
        }
      }
      statusText =
        String(localized: "Translation target set to \(newLanguage.displayName). Run Translate to refresh subtitles.", comment: "AI Cut status message")
    }
    .onChange(of: flowModel.phase) { oldPhase, newPhase in
      // When the user cancels the import-setup sheet the phase returns to .landing.
      // The host window is invisible at that point, so close the detached session.
      if oldPhase == .importSetup && newPhase == .landing {
        onSessionEnded?()
      }
    }
    .task(id: launchURLs) {
      consumeLaunchURLsIfNeeded()
    }
  }

  @available(macOS 15.0, *)
  private var activeTranslationConfiguration: TranslationSession.Configuration? {
    translationConfigurationStorage as? TranslationSession.Configuration
  }

  private var landingView: some View {
    AICutLandingView(
      onImportURLs: { urls in
        beginImport(urls: urls)
      },
      onTap: {
        presentVideoPicker()
      }
    )
  }

  private var importSetupWindowContent: some View {
    AICutImportSetupView(
      urls: flowModel.pendingURLs,
      language: $flowModel.selectedLanguage,
      onRemove: { url in
        flowModel.removePendingURL(url)
      },
      onCancel: {
        flowModel.cancelImport()
      },
      onStart: {
        startImportBatch()
      },
      contextProvider: currentLanguageContext
    )
  }

  private var progressWindowContent: some View {
    AICutProgressView(
      presentation: AICutProgressPresentation(
        batch: flowModel.currentBatch,
        statusMessage: statusText,
        isInitializingModel: isInitializingModel,
        modelDownloadProgress: modelDownloadProgress
      ),
      batch: flowModel.currentBatch,
      modelDownloadProgress: modelDownloadProgress,
      isInitializingModel: isInitializingModel,
      onCancel: {
        dismissProgressShell()
      }
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.regularMaterial)
  }

  @ViewBuilder
  private var editorWindowContent: some View {
    if #available(macOS 15.0, *) {
      editorWindowCoreContent.translationTask(activeTranslationConfiguration) { session in
        await runPendingTranslation(using: session)
      }
    } else {
      editorWindowCoreContent
    }
  }

  private var editorWindowCoreContent: some View {
    AICutEditorView(
      securityScopeManager: securityScopeManager,
      selectedVideoURLs: $selectedVideoURLs,
      activeVideoURL: $activeVideoURL,
      sourceMode: .editingOnly,
      videoStates: videoStates,
      statusText: statusText,
      modelDownloadProgress: modelDownloadProgress,
      isInitializingModel: isInitializingModel,
      batchTranscriptionProgress: batchTranscriptionProgress,
      isTranscribing: isTranscribing,
      isExporting: isExporting,
      exportProgress: exportProgress,
      onDismissExport: { exportProgress.reset() },
      isAICorrecting: isAICorrecting,
      isAIEnhancing: isAIEnhancing,
      isTranslating: isTranslating,
      activeVideoState: activeVideoURL.flatMap { videoStates[$0] },
      processedSegments: processedSegments,
      translationsVersion: translationsVersion,
      currentPlayback: currentPlayback,
      previewSegments: activeVideoURL.flatMap { videoStates[$0] } != nil ? currentSegments : [],
      previewEffects: resolvedEffects(for: activeVideoURL),
      onSelectFiles: {
        presentVideoPicker()
      },
      onImportURLs: { urls in
        beginImport(urls: urls)
      },
      onTranscribe: {
        if let url = activeVideoURL { transcribeVideo(url: url) }
      },
      onTranscribeAll: {
        transcribeAllVideos()
      },
      onCancelTranscription: {
        cancelTranscription()
      },
      onExportAll: { mode in
        exportAllTranscribedVideos(request: mode)
      },
      onExportSingle: { url in
        exportSingleVideo(url: url)
      },
      onAICorrect: {
        pendingCorrectionType = .all
        showCustomPromptDialog = true
      },
      onAICorrectCurrent: {
        pendingCorrectionType = .current
        showCustomPromptDialog = true
      },
      onRestoreOriginal: {
        showRestoreConfirmation = true
      },
      onAIEnhance: {
        applyEffectEnhancement()
      },
      onTranslate: translateActiveSegments,
      onPreviewSegmentDelete: { segment in
        deleteSegment(segment: segment)
      },
      onSegmentUpdate: { displaySegment, newText in
        applyManualSegmentEdit(displaySegment: displaySegment, newText: newText)
      },
      onTranslationUpdate: { displaySegment, newText in
        applyManualTranslationEdit(displaySegment: displaySegment, newText: newText)
      },
      onSegmentDelete: { displaySegment in
        deleteSegment(displaySegment: displaySegment)
      }
    )
    .environmentObject(config)
    .sheet(isPresented: $showCustomPromptDialog) {
      CustomPromptDialog(isPresented: $showCustomPromptDialog) { customPrompt in
        guard let type = pendingCorrectionType else { return }

        switch type {
        case .current:
          if let url = activeVideoURL {
            correctTranscriptionWithAI(url: url, customPrompt: customPrompt)
          }
        case .all:
          correctAllTranscriptionsWithAI(customPrompt: customPrompt)
        }
        pendingCorrectionType = nil
      }
    }
    .alert("Restore Original Transcription", isPresented: $showRestoreConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Restore", role: .destructive) {
        restoreOriginalTranscription()
      }
    } message: {
      Text(
        "This action will undo all AI corrections and restore the original transcription results. Continue?"
      )
    }
    .alert(
      String(localized: "AI Request Failed", comment: "Alert title for AI error"),
      isPresented: Binding(
        get: { aiErrorMessage != nil },
        set: { if !$0 { aiErrorMessage = nil } }
      )
    ) {
      Button("OK", role: .cancel) { aiErrorMessage = nil }
    } message: {
      if let msg = aiErrorMessage {
        Text(msg)
      }
    }
    .overlay {
      Color.clear
        .frame(width: 0, height: 0)
        .sheet(isPresented: $showCorrectionDictionarySheet) {
          DictionaryTermsReviewSheet(
            terms: dictionaryTermsFromCorrection,
            existingTerms: Set(config.voiceToTextCustomDictionary.map { $0.lowercased() }),
            onAdd: { newTerms in
              config.replaceDictionaryEntries(
                with: config.voiceToTextCustomDictionary + newTerms)
              showCorrectionDictionarySheet = false
            },
            onDismiss: { showCorrectionDictionarySheet = false }
          )
        }
    }
  }

  private func currentLanguageContext() -> ModelLanguageContext {
    .asr(type: config.transcriberType, model: config.modelVariant)
  }

  // MARK: - Private Methods

  @MainActor
  private func currentAICutSessionGeneration() -> UInt64 {
    aiCutSessionGeneration
  }

  @MainActor
  private func beginAICutImportSession() -> UInt64 {
    aiCutSessionGeneration &+= 1
    return aiCutSessionGeneration
  }

  @MainActor
  private func establishAICutEditorSession() -> UInt64 {
    aiCutSessionGeneration &+= 1
    flowModel.establishEditingSession()
    return aiCutSessionGeneration
  }

  @MainActor
  private func invalidateAICutSession() {
    activeTranslationTask?.cancel()
    activeTranslationTask = nil
    aiCutSessionGeneration &+= 1
    clearModelPreparationState()
  }

  @MainActor
  private func applyIfCurrentAICutSession(
    _ sessionGeneration: UInt64,
    update: () -> Void
  ) {
    guard AICutSessionGuard.shouldApplyUpdate(
      capturedGeneration: sessionGeneration,
      activeGeneration: aiCutSessionGeneration
    ) else { return }
    update()
  }

  @MainActor
  private func startTranscriptionTask(operation: @Sendable @escaping () async -> Void) {
    activeTranscriptionTask?.cancel()
    activeTranscriptionTaskGeneration &+= 1
    let taskGeneration = activeTranscriptionTaskGeneration
    let task = Task(priority: .userInitiated) {
      await operation()
      await MainActor.run {
        if AICutTranscriptionTaskGuard.shouldClearActiveTask(
          finishedGeneration: taskGeneration,
          activeGeneration: self.activeTranscriptionTaskGeneration
        ) {
          self.activeTranscriptionTask = nil
        }
      }
    }
    activeTranscriptionTask = task
  }

  private func cancelTranscription() {
    Task { @MainActor in
      guard let task = activeTranscriptionTask else { return }
      statusText = String(localized: "Cancelling transcription...", comment: "AI Cut status message")
      task.cancel()
    }
  }

  /// Saves a completed file transcription session to the shared history store.
  /// Never stores the source video URL as a recording (we don't own that file).
  @MainActor
  private func saveFileTranscriptionToHistory(
    url: URL,
    segments: [Segment],
    duration: TimeInterval,
    sourceURLBookmark: Data? = nil
  ) {
    guard !segments.isEmpty else { return }
    _ = saveFileTranscriptionToHistory(
      url: url,
      segments: segments,
      lastTranslatedLanguage: nil,
      sourceURLBookmark: sourceURLBookmark,
      duration: duration,
      existingSessionID: historyRuntime.existingFileTranscriptionSessionID(
        forSourceURL: url),
      replacingTranscription: true
    )
  }

  @discardableResult
  @MainActor
  private func saveFileTranscriptionToHistory(
    url: URL,
    segments: [Segment],
    lastTranslatedLanguage: Language?,
    processedTranslations: [String: SegmentTranslation]? = nil,
    removedSegmentIDs: Set<SegmentIdentifier>? = nil,
    sourceURLBookmark: Data? = nil,
    duration: TimeInterval,
    existingSessionID: UUID?,
    replacingTranscription: Bool = false
  ) -> UUID? {
    guard !segments.isEmpty else { return existingSessionID }
    do {
      let resolvedBookmark =
        sourceURLBookmark
        ?? historyRuntime.sourceURLBookmark(for: existingSessionID)
      let session = try FileTranscriptionHistorySessionFactory.makeSession(
        existingSessionID: existingSessionID,
        url: url,
        segments: segments,
        originalSegments: replacingTranscription ? segments
          : (videoStates[url]?.originalSegments.isEmpty == false ? videoStates[url]?.originalSegments : nil),
        lastTranslatedLanguage: lastTranslatedLanguage,
        processedTranslations: processedTranslations,
        removedSegmentIDs: removedSegmentIDs,
        sourceURLBookmark: resolvedBookmark,
        duration: duration,
        transcriberType: config.transcriberType,
        modelVariant: config.modelVariant,
        language: config.language
      )
      historyRuntime.add(session, replacingTranscription: replacingTranscription)
      return session.id
    } catch {
      print("[AICutView] Failed to persist file transcription history: \(error.localizedDescription)")
      return existingSessionID
    }
  }

  @MainActor
  private func ensureTranscriber(preparingMessage: String) async throws {
    let selectedType = config.transcriberType
    let selectedModel = config.modelVariant
    let sessionGeneration = currentAICutSessionGeneration()

    applyIfCurrentAICutSession(sessionGeneration) {
      statusText = preparingMessage
      isInitializingModel = true
      modelDownloadProgress = ModelDownloadProgress(currentStep: "Preparing model...", progress: 0)
    }

    do {
      _ = try await ModelCacheManager.shared.getASRTranscriber(
        type: selectedType,
        model: selectedModel
      ) { progress in
        Task { @MainActor in
          self.applyIfCurrentAICutSession(sessionGeneration) {
            self.modelDownloadProgress = progress
            self.statusText = AICutModelPreparationStatus.message(for: progress)
          }
        }
      }
      let diagnostic = await resolveAICutSpeakerDiagnostic()
      if let alignVariant = diagnostic.alignVariant {
        try await ModelCacheManager.shared.preloadAlignModel(
          model: alignVariant
        ) { progress in
          Task { @MainActor in
            self.applyIfCurrentAICutSession(sessionGeneration) {
              self.modelDownloadProgress = progress
              self.statusText = progress.currentStep
            }
          }
        }
      }
      guard AICutSessionGuard.shouldApplyUpdate(
        capturedGeneration: sessionGeneration,
        activeGeneration: aiCutSessionGeneration
      ) else { throw CancellationError() }
      applyIfCurrentAICutSession(sessionGeneration) {
        modelDownloadProgress = nil
        isInitializingModel = false
      }
    } catch {
      guard AICutSessionGuard.shouldApplyUpdate(
        capturedGeneration: sessionGeneration,
        activeGeneration: aiCutSessionGeneration
      ) else { throw error }
      applyIfCurrentAICutSession(sessionGeneration) {
        modelDownloadProgress = nil
        isInitializingModel = false
        if error is CancellationError {
          statusText = String(localized: "Model preparation cancelled", comment: "AI Cut status message")
        } else {
          statusText = String(localized: "Model preparation failed: \(error.localizedDescription)", comment: "AI Cut status message")
        }
      }
      throw error
    }
  }

  @MainActor
  private func resolveAICutSpeakerDiagnostic() async -> AICutSpeakerDiagnosticResult {
    if let configuredAligner = config.alignModelVariant {
      let isAlignerDownloaded = await ModelDownloadManager.shared.isModelDownloaded(configuredAligner)
      return AICutSpeakerDiagnostics.resolve(
        configuredAligner: configuredAligner,
        isAlignerDownloaded: isAlignerDownloaded,
        autoDiscoveredAligner: nil
      )
    }

    var autoDiscoveredAligner: ModelVariant?
    for model in ModelVariant.alignerModels {
      if await ModelDownloadManager.shared.isModelDownloaded(model) {
        autoDiscoveredAligner = model
        break
      }
    }

    return AICutSpeakerDiagnostics.resolve(
      configuredAligner: nil,
      isAlignerDownloaded: false,
      autoDiscoveredAligner: autoDiscoveredAligner
    )
  }


  @MainActor
  private func warmUpModel() {
    let type = config.transcriberType
    let model = config.modelVariant
    statusText = String(localized: "Preparing \(model.displayName) in background...", comment: "AI Cut status message")
    TranscriberWarmupCoordinator.shared.scheduleWarmup(
      for: type,
      model: model,
      reason: .userInitiated
    )
    modelDownloadProgress = nil
    isInitializingModel = false
  }

  @MainActor
  private func presentVideoPicker() {
    let panel = NSOpenPanel()
    panel.prompt = "Add"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    panel.allowedContentTypes = [.movie, .video]

    if panel.runModal() == .OK {
      beginImport(urls: panel.urls)
    }
  }

  @MainActor
  private func beginImport(urls: [URL]) {
    guard !urls.isEmpty else { return }

    if let blockingMessage = AICutImportGuard.blockingMessage(
      phase: flowModel.phase,
      hasPendingTranscriptionTask: hasPendingTranscriptionTask
    ) {
      statusText = blockingMessage
      return
    }

    let newURLs = urls.filter { $0.isFileURL && !selectedVideoURLs.contains($0) }
    guard !newURLs.isEmpty else {
      if let first = urls.first {
        statusText = String(localized: "Already added: \(first.lastPathComponent)", comment: "AI Cut status message")
      }
      return
    }

    flowModel.selectedLanguage = config.language
    flowModel.beginImport(urls: newURLs)
  }

  @MainActor
  private func startImportBatch() {
    guard !flowModel.pendingURLs.isEmpty else {
      flowModel.cancelImport()
      return
    }

    config.language = flowModel.selectedLanguage
    let batch = flowModel.startBatch()
    let sessionGeneration = beginAICutImportSession()
    statusText = String(localized: "Preparing batch transcription...", comment: "AI Cut status message")
    startTranscriptionTask {
      await self.performImportedBatchTranscription(
        urls: batch.urls,
        sessionGeneration: sessionGeneration
      )
    }
  }

  @MainActor
  private func dismissProgressShell() {
    windowCoordinator.closeProgressWindow()
    if let task = activeTranscriptionTask {
      statusText = String(localized: "Cancelling transcription...", comment: "AI Cut status message")
      task.cancel()
    }
    if flowModel.phase != .editing {
      invalidateAICutSession()
      flowModel.cancelImport()
      onSessionEnded?()
    }
  }

  @MainActor
  private func exitEditingSession() {
    activeTranscriptionTask?.cancel()
    activeTranslationTask?.cancel()
    invalidateAICutSession()
    clearEditorModalState()
    isAICorrecting = false
    isExporting = false
    isTranscribing = false
    isTranslating = false
    pendingTranslationRequest = nil
    translationConfigurationStorage = nil
    batchTranscriptionProgress = nil
    processedSegments = []
    activeVideoURL = nil
    selectedVideoURLs = []
    videoStates = [:]
    flowModel.cancelImport()
    statusText = String(localized: "AI Cut editor closed.", comment: "AI Cut status message")
    onSessionEnded?()
  }

  @MainActor
  private func consumeLaunchURLsIfNeeded() {
    guard !hasConsumedLaunchURLs, !launchURLs.isEmpty else { return }
    hasConsumedLaunchURLs = true

    // Split launch URLs: restored ones skip transcription, new ones go through import.
    let restoredURLs = launchURLs.filter { restoredVideoStates[$0] != nil }
    let newURLs = launchURLs.filter { restoredVideoStates[$0] == nil }

    if !restoredURLs.isEmpty {
      restoreSession(urls: restoredURLs)
    }
    if !newURLs.isEmpty {
      beginImport(urls: newURLs)
    }
  }

  /// Directly opens the editor for URLs that already have pre-loaded segments,
  /// bypassing the transcription import flow entirely.
  @MainActor
  private func restoreSession(urls: [URL]) {
    for url in urls {
      guard let state = restoredVideoStates[url] else { continue }
      if !selectedVideoURLs.contains(url) {
        selectedVideoURLs.append(url)
      }
      videoStates[url] = state
    }

    if activeVideoURL == nil {
      activeVideoURL = urls.first
    }
    processedSegments = currentSegments
    statusText = String(localized: "Session restored from history.", comment: "AI Cut status message")

    let sessionGeneration = establishAICutEditorSession()
    windowCoordinator.transitionFromProgressToEditor(
      beforeOpen: {},
      editorContent: { AnyView(self.editorWindowContent) },
      onEditorCloseRequest: { self.exitEditingSession() }
    )
    applyIfCurrentAICutSession(sessionGeneration) {
      statusText = String(localized: "Session restored from history.", comment: "AI Cut status message")
    }
  }

  @MainActor
  private func clearEditorModalState() {
    showCustomPromptDialog = false
    showRestoreConfirmation = false
    pendingCorrectionType = nil
  }

  @MainActor
  private func clearModelPreparationState() {
    modelDownloadProgress = nil
    isInitializingModel = false
  }

  @MainActor
  private func transcribeVideo(url: URL) {
    let sessionGeneration = currentAICutSessionGeneration()
    startTranscriptionTask {
      await self.performSingleTranscription(for: url, sessionGeneration: sessionGeneration)
    }
  }

  @MainActor
  private func transcribeAllVideos() {
    guard !selectedVideoURLs.isEmpty else {
      statusText = String(localized: "No videos selected to transcribe.", comment: "AI Cut status message")
      return
    }
    let sessionGeneration = currentAICutSessionGeneration()
    startTranscriptionTask {
      await self.performBatchTranscription(
        urls: self.selectedVideoURLs,
        sessionGeneration: sessionGeneration
      )
    }
  }

  @MainActor
  private var hasPendingTranscriptionTask: Bool {
    activeTranscriptionTask != nil
  }

  @MainActor
  private func performSingleTranscription(for url: URL, sessionGeneration: UInt64) async {
    let previousSegments = videoStates[url]?.segments ?? []
    let previousDuration = videoStates[url]?.audioDuration

    defer {
      applyIfCurrentAICutSession(sessionGeneration) {
        isTranscribing = false
        batchTranscriptionProgress = nil
      }
    }

    do {
      _ = try await ensureTranscriber(
        preparingMessage: "Preparing model for transcription...")
      applyIfCurrentAICutSession(sessionGeneration) {
        statusText = String(localized: "Model ready. Starting transcription...", comment: "AI Cut status message")
      }

      applyIfCurrentAICutSession(sessionGeneration) {
        if videoStates[url] == nil {
          videoStates[url] = VideoState()
        }
        videoStates[url]?.segments = []
        videoStates[url]?.removedProcessedSegmentIDs.removeAll()
        videoStates[url]?.audioDuration = nil
      }

      applyIfCurrentAICutSession(sessionGeneration) {
        isTranscribing = true
        statusText = String(localized: "Transcribing with \(config.transcriberType.displayName)...", comment: "AI Cut status message")
      }

      let progressThrottle = ProgressThrottle()

      // Create progress handler for transcription
      let progressHandler: @Sendable (TranscriptionProgress) -> Void = { progress in
        Task {
          let shouldUpdate = await progressThrottle.shouldReport(progress.progress)
          let statusMessage: String = {
            var message = progress.statusMessage
            if let remaining = progress.estimatedTimeRemaining {
              let minutes = Int(remaining) / 60
              let seconds = Int(remaining) % 60
              message += " - Est. \(minutes):\(String(format: "%02d", seconds)) remaining"
            }
            message += " (\(Int(progress.progress * 100))%)"
            return message
          }()

          await MainActor.run {
            self.applyIfCurrentAICutSession(sessionGeneration) {
              if self.videoStates[url] == nil {
                self.videoStates[url] = VideoState()
              }
              if shouldUpdate {
                self.videoStates[url]?.segments = progress.currentSegments
                self.videoStates[url]?.removedProcessedSegmentIDs.removeAll()
              }
              self.statusText = statusMessage
            }
          }
        }
      }

      let diagnostic = await resolveAICutSpeakerDiagnostic()
      if let alignVariant = diagnostic.alignVariant {
        _ = alignVariant
        statusText = String(localized: "Running VAD -> ASR -> ForcedAlign pipeline...", comment: "AI Cut status message")
      } else if let message = diagnostic.missingRequirementMessage {
        statusText =
          message == AICutSpeakerDiagnostics.missingAlignModelMessage
          ? AICutSpeakerDiagnostics.localizedMissingAlignModelMessage
          : message
      } else {
        statusText = String(localized: "Running VAD -> ASR pipeline...", comment: "AI Cut status message when using VAD and ASR without alignment")
      }

      let output = try await batchTranscriptionRuntime.transcribe(
        request: BatchTranscriptionRequest(
          sourceURL: url,
          workflow: .fileTranscription,
          transcriberType: config.transcriberType,
          asrModel: config.modelVariant,
          vadModel: config.vadModelVariant,
          alignModel: diagnostic.alignVariant,
          language: config.language,
          dictionaryEntries: config.voiceToTextCustomDictionary
        ),
        modelProgressHandler: { progress in
          Task { @MainActor in
            self.applyIfCurrentAICutSession(sessionGeneration) {
              self.statusText = progress.currentStep
            }
          }
        },
        progressHandler: progressHandler
      )
      let speakerAnnotatedSegments = output.result.segments

      applyIfCurrentAICutSession(sessionGeneration) {
        if videoStates[url] == nil {
          videoStates[url] = VideoState()
        }
        videoStates[url]?.segments = speakerAnnotatedSegments
        videoStates[url]?.removedProcessedSegmentIDs.removeAll()
        videoStates[url]?.audioDuration = output.result.totalDuration
        videoStates[url]?.originalSegments = speakerAnnotatedSegments
        statusText =
          String(localized: "Transcription complete! Found \(speakerAnnotatedSegments.count) segments in \(String(format: "%.1f", output.result.processingTime))s", comment: "AI Cut status message: transcription done with segment count and time")
        saveFileTranscriptionToHistory(
          url: url,
          segments: speakerAnnotatedSegments,
          duration: output.result.totalDuration,
          sourceURLBookmark: output.sourceURLBookmark
        )
      }
    } catch is CancellationError {
      applyIfCurrentAICutSession(sessionGeneration) {
        if videoStates[url] == nil {
          videoStates[url] = VideoState()
        }
        videoStates[url]?.segments = previousSegments
        videoStates[url]?.removedProcessedSegmentIDs.removeAll()
        videoStates[url]?.audioDuration = previousDuration
        statusText = String(localized: "Transcription cancelled.", comment: "AI Cut status message")
      }
    } catch {
      applyIfCurrentAICutSession(sessionGeneration) {
        if videoStates[url] == nil {
          videoStates[url] = VideoState()
        }
        videoStates[url]?.segments = previousSegments
        videoStates[url]?.removedProcessedSegmentIDs.removeAll()
        videoStates[url]?.audioDuration = previousDuration
        statusText = AICutTranscriptionFailureStatus.singleMessage(for: error)
      }
    }
  }

  @MainActor
  private func performImportedBatchTranscription(urls: [URL], sessionGeneration: UInt64) async {
    let totalVideos = urls.count
    var importedResults: [URL: ImportedBatchVideoResult] = [:]

    defer {
      applyIfCurrentAICutSession(sessionGeneration) {
        isTranscribing = false
        batchTranscriptionProgress = nil
      }
    }

    do {
      _ = try await ensureTranscriber(
        preparingMessage: "Preparing model for batch transcription...")
      applyIfCurrentAICutSession(sessionGeneration) {
        statusText = String(localized: "Model ready. Starting batch transcription...", comment: "AI Cut status message")
      }

      applyIfCurrentAICutSession(sessionGeneration) {
        isTranscribing = true
        batchTranscriptionProgress = (current: 0, total: totalVideos)
      }

      var completedVideos = 0
      var failedVideos: [String] = []
      for (index, url) in urls.enumerated() {
        if Task.isCancelled {
          throw CancellationError()
        }

        applyIfCurrentAICutSession(sessionGeneration) {
          flowModel.markFileRunning(url)
          batchTranscriptionProgress = (current: index + 1, total: totalVideos)
          statusText = String(localized: "Transcribing \(index + 1)/\(totalVideos): \(url.lastPathComponent)...", comment: "AI Cut status message")
        }

        do {
          let result = try await transcribeBatchVideo(
            url: url,
            index: index,
            totalVideos: totalVideos,
            sessionGeneration: sessionGeneration
          ) { _, _, statusMessage in
            self.applyIfCurrentAICutSession(sessionGeneration) {
              self.statusText = statusMessage
            }
          }

          importedResults[url] = result
          applyIfCurrentAICutSession(sessionGeneration) {
            flowModel.markFileSucceeded(url)
            saveFileTranscriptionToHistory(
              url: url,
              segments: result.segments,
              duration: result.audioDuration,
              sourceURLBookmark: result.sourceURLBookmark
            )
          }
          completedVideos += 1
        } catch is CancellationError {
          throw CancellationError()
        } catch {
          applyIfCurrentAICutSession(sessionGeneration) {
            flowModel.markFileFailed(url, message: error.localizedDescription)
          }
          failedVideos.append(url.lastPathComponent)
          applyIfCurrentAICutSession(sessionGeneration) {
            statusText =
              String(localized: "Failed to transcribe \(url.lastPathComponent): \(error.localizedDescription)", comment: "AI Cut status message")
          }
        }
      }

      if flowModel.phase == .readyToEdit {
        let successfulURLs = flowModel.successfulEditingURLs
        windowCoordinator.transitionFromProgressToEditor(
          beforeOpen: {
            finalizeImportedBatchWorkspace(
              results: importedResults,
              orderedSuccessfulURLs: successfulURLs
            )
          },
          editorContent: {
            AnyView(editorWindowContent)
          },
          onEditorCloseRequest: {
            exitEditingSession()
          }
        )
        let editorSessionGeneration = establishAICutEditorSession()
        applyIfCurrentAICutSession(editorSessionGeneration) {
          isTranscribing = false
          batchTranscriptionProgress = nil
        }
        updateBatchCompletionStatus(
          completedVideos: completedVideos,
          failedVideos: failedVideos,
          sessionGeneration: editorSessionGeneration
        )
        return
      }

      updateBatchCompletionStatus(
        completedVideos: completedVideos,
        failedVideos: failedVideos,
        sessionGeneration: sessionGeneration
      )
    } catch is CancellationError {
      applyIfCurrentAICutSession(sessionGeneration) {
        statusText = String(localized: "Batch transcription cancelled.", comment: "AI Cut status message")
        if flowModel.phase != .editing {
          invalidateAICutSession()
          flowModel.cancelImport()
        }
      }
    } catch {
      applyIfCurrentAICutSession(sessionGeneration) {
        statusText = AICutTranscriptionFailureStatus.batchMessage(for: error)
      }
    }
  }

  @MainActor
  private func performBatchTranscription(urls: [URL], sessionGeneration: UInt64) async {
    let totalVideos = urls.count

    defer {
      applyIfCurrentAICutSession(sessionGeneration) {
        isTranscribing = false
        batchTranscriptionProgress = nil
      }
    }

    do {
      _ = try await ensureTranscriber(
        preparingMessage: "Preparing model for batch transcription...")
      applyIfCurrentAICutSession(sessionGeneration) {
        statusText = String(localized: "Model ready. Starting batch transcription...", comment: "AI Cut status message")
      }

      applyIfCurrentAICutSession(sessionGeneration) {
        isTranscribing = true
        batchTranscriptionProgress = (current: 0, total: totalVideos)
      }

      var completedVideos = 0
      var failedVideos: [String] = []

      for (index, url) in urls.enumerated() {
        if Task.isCancelled {
          throw CancellationError()
        }

        applyIfCurrentAICutSession(sessionGeneration) {
          batchTranscriptionProgress = (current: index + 1, total: totalVideos)
          statusText = String(localized: "Transcribing \(index + 1)/\(totalVideos): \(url.lastPathComponent)...", comment: "AI Cut status message")
        }
        let previousState = prepareEditorBatchVideoState(for: url)

        do {
          let result = try await transcribeBatchVideo(
            url: url,
            index: index,
            totalVideos: totalVideos,
            sessionGeneration: sessionGeneration
          ) { url, segments, statusMessage in
            self.applyIfCurrentAICutSession(sessionGeneration) {
              if self.videoStates[url] == nil {
                self.videoStates[url] = VideoState()
              }
              if !segments.isEmpty {
                self.videoStates[url]?.segments = segments
                self.videoStates[url]?.removedProcessedSegmentIDs.removeAll()
              }
              self.statusText = statusMessage
            }
          }

          applyIfCurrentAICutSession(sessionGeneration) {
            if videoStates[url] == nil {
              videoStates[url] = VideoState()
            }
            videoStates[url]?.segments = result.segments
            videoStates[url]?.removedProcessedSegmentIDs.removeAll()
            videoStates[url]?.audioDuration = result.audioDuration
            videoStates[url]?.originalSegments = result.segments
            saveFileTranscriptionToHistory(
              url: url,
              segments: result.segments,
              duration: result.audioDuration,
              sourceURLBookmark: result.sourceURLBookmark
            )
          }
          completedVideos += 1
        } catch is CancellationError {
          applyIfCurrentAICutSession(sessionGeneration) {
            restoreEditorBatchVideoState(previousState, for: url)
          }
          throw CancellationError()
        } catch {
          applyIfCurrentAICutSession(sessionGeneration) {
            restoreEditorBatchVideoState(previousState, for: url)
          }
          failedVideos.append(url.lastPathComponent)
          applyIfCurrentAICutSession(sessionGeneration) {
            statusText =
              String(localized: "Failed to transcribe \(url.lastPathComponent): \(error.localizedDescription)", comment: "AI Cut status message")
          }
        }
      }

      updateBatchCompletionStatus(
        completedVideos: completedVideos,
        failedVideos: failedVideos,
        sessionGeneration: sessionGeneration
      )
    } catch is CancellationError {
      applyIfCurrentAICutSession(sessionGeneration) {
        statusText = String(localized: "Batch transcription cancelled.", comment: "AI Cut status message")
      }
    } catch {
      applyIfCurrentAICutSession(sessionGeneration) {
        statusText = AICutTranscriptionFailureStatus.batchMessage(for: error)
      }
    }
  }

  @MainActor
  private func prepareEditorBatchVideoState(for url: URL) -> ExistingVideoStateSnapshot {
    let snapshot = ExistingVideoStateSnapshot(
      segments: videoStates[url]?.segments ?? [],
      audioDuration: videoStates[url]?.audioDuration
    )

    if videoStates[url] == nil {
      videoStates[url] = VideoState()
    }
    videoStates[url]?.segments = []
    videoStates[url]?.removedProcessedSegmentIDs.removeAll()
    videoStates[url]?.audioDuration = nil

    return snapshot
  }

  @MainActor
  private func restoreEditorBatchVideoState(_ snapshot: ExistingVideoStateSnapshot, for url: URL) {
    if videoStates[url] == nil {
      videoStates[url] = VideoState()
    }
    videoStates[url]?.segments = snapshot.segments
    videoStates[url]?.removedProcessedSegmentIDs.removeAll()
    videoStates[url]?.audioDuration = snapshot.audioDuration
  }

  @MainActor
  private func transcribeBatchVideo(
    url: URL,
    index: Int,
    totalVideos: Int,
    sessionGeneration: UInt64,
    progressUpdate: @escaping @MainActor (URL, [Segment], String) -> Void
  ) async throws -> ImportedBatchVideoResult {
    let progressThrottle = ProgressThrottle()
    let progressHandler: @Sendable (TranscriptionProgress) -> Void = { progress in
      Task {
        let shouldUpdate = await progressThrottle.shouldReport(progress.progress)
        let statusMessage: String = {
          var message = "[\(index + 1)/\(totalVideos)] \(progress.statusMessage)"
          if let remaining = progress.estimatedTimeRemaining {
            let minutes = Int(remaining) / 60
            let seconds = Int(remaining) % 60
            message += " - Est. \(minutes):\(String(format: "%02d", seconds)) remaining"
          }
          message += " (\(Int(progress.progress * 100))%)"
          return message
        }()

        await MainActor.run {
          progressUpdate(url, shouldUpdate ? progress.currentSegments : [], statusMessage)
        }
      }
    }

    let diagnostic = await resolveAICutSpeakerDiagnostic()
    if let alignVariant = diagnostic.alignVariant {
      _ = alignVariant
      applyIfCurrentAICutSession(sessionGeneration) {
        statusText = String(localized: "[\(index + 1)/\(totalVideos)] Running VAD -> ASR -> ForcedAlign...", comment: "AI Cut status message")
      }
    } else if let message = diagnostic.missingRequirementMessage {
      applyIfCurrentAICutSession(sessionGeneration) {
        statusText =
          message == AICutSpeakerDiagnostics.missingAlignModelMessage
          ? AICutSpeakerDiagnostics.localizedMissingAlignModelMessage
          : message
      }
    } else {
      applyIfCurrentAICutSession(sessionGeneration) {
        statusText = String(localized: "[\(index + 1)/\(totalVideos)] Running VAD -> ASR...", comment: "AI Cut status message for batch without alignment")
      }
    }

    let output = try await batchTranscriptionRuntime.transcribe(
      request: BatchTranscriptionRequest(
        sourceURL: url,
        workflow: .fileTranscription,
        transcriberType: config.transcriberType,
        asrModel: config.modelVariant,
        vadModel: config.vadModelVariant,
        alignModel: diagnostic.alignVariant,
        language: config.language,
        dictionaryEntries: config.voiceToTextCustomDictionary
      ),
      modelProgressHandler: { progress in
        Task { @MainActor in
          self.applyIfCurrentAICutSession(sessionGeneration) {
            self.statusText = "[\(index + 1)/\(totalVideos)] \(progress.currentStep)"
          }
        }
      },
      progressHandler: progressHandler
    )
    let speakerAnnotatedSegments = output.result.segments

    return ImportedBatchVideoResult(
      segments: speakerAnnotatedSegments,
      audioDuration: output.result.totalDuration,
      sourceURLBookmark: output.sourceURLBookmark
    )
  }

  @MainActor
  private func updateBatchCompletionStatus(
    completedVideos: Int,
    failedVideos: [String],
    sessionGeneration: UInt64
  ) {
    applyIfCurrentAICutSession(sessionGeneration) {
      if failedVideos.isEmpty {
        statusText =
          String(localized: "Batch transcription completed! Successfully processed \(completedVideos) videos.", comment: "AI Cut status message")
        if activeVideoURL == nil, let first = selectedVideoURLs.first {
          activeVideoURL = first
        }
      } else {
        statusText =
          String(localized: "Batch transcription finished. \(completedVideos) succeeded, \(failedVideos.count) failed: \(failedVideos.joined(separator: ", "))", comment: "AI Cut status message: batch done with counts and failed file names")
        if activeVideoURL == nil {
          for url in selectedVideoURLs where videoStates[url]?.segments.isEmpty == false {
            activeVideoURL = url
            break
          }
        }
      }
    }
  }

  @MainActor
  private func finalizeImportedBatchWorkspace(
    results: [URL: ImportedBatchVideoResult],
    orderedSuccessfulURLs: [URL]
  ) {
    guard !orderedSuccessfulURLs.isEmpty else { return }

    var mergedURLs = selectedVideoURLs
    for url in orderedSuccessfulURLs where !mergedURLs.contains(url) {
      mergedURLs.append(url)
    }
    selectedVideoURLs = mergedURLs

    for url in orderedSuccessfulURLs {
      guard let result = results[url] else { continue }

      let state = videoStates[url] ?? VideoState()
      state.segments = result.segments
      state.originalSegments = result.segments
      state.audioDuration = result.audioDuration
      state.removedProcessedSegmentIDs.removeAll()
      state.historySessionID = state.historySessionID
        ?? historyRuntime.existingFileTranscriptionSessionID(forSourceURL: url)
      videoStates[url] = state
    }

    if let activeVideoURL, selectedVideoURLs.contains(activeVideoURL) {
      processedSegments = currentSegments
      return
    }

    activeVideoURL = orderedSuccessfulURLs.first ?? selectedVideoURLs.first
    processedSegments = currentSegments
  }

  private enum ExportError: LocalizedError {
    case noSegments

    var errorDescription: String? {
      switch self {
      case .noSegments:
        return String(localized: "No transcription data available for export.", comment: "Error: export failed because there are no transcribed segments")
      }
    }
  }

  private func exportAllTranscribedVideos(request: ExportAllRequest) {
    let sessionGeneration = currentAICutSessionGeneration()
    Task { @MainActor in
      let exportPlan = ExportPlan.aiCut(request: request, urls: workspaceState.transcribedURLs)
      let transcribedURLs = exportPlan.urls

      guard !transcribedURLs.isEmpty else {
        statusText = String(localized: "No transcribed videos to export. Please transcribe some videos first.", comment: "AI Cut status message")
        return
      }

      guard
        exportPlan.includes(.fcpxml)
          || exportPlan.includes(.subtitle)
          || exportPlan.includes(.video)
          || exportPlan.includes(.audio)
      else {
        statusText = String(localized: "Select at least one export option to continue.", comment: "AI Cut status message")
        return
      }

      if request.includeFCPXML && !config.fcpxmlEnabled {
        statusText =
          String(localized: "Enable FCPXML export in Output settings before exporting Final Cut projects.", comment: "AI Cut status message")
        return
      }

      if request.includeSubtitleFiles && config.subtitleExportFormats.isEmpty {
        statusText =
          String(localized: "No subtitle file formats are enabled. Choose at least one format in Output settings.", comment: "AI Cut status message")
        return
      }

      if request.includeAudio && !config.audioExportEnabled {
        statusText = String(localized: "Enable audio export in Output settings before exporting audio files.", comment: "AI Cut status message")
        return
      }

      guard
        let destinationDirectory = promptForExportDirectory(
          message: String(localized: "Select a folder to store exported projects and assets", comment: "Export panel folder picker prompt")
        )
      else {
        statusText = String(localized: "Export cancelled", comment: "AI Cut status message")
        return
      }

      let mediaFiles: [MediaFile]
      do {
        mediaFiles = try await buildMediaFiles(for: transcribedURLs)
      } catch {
        applyIfCurrentAICutSession(sessionGeneration) {
          statusText = String(localized: "Export failed: \(error.localizedDescription)", comment: "AI Cut status message")
        }
        return
      }

      guard !mediaFiles.isEmpty else {
        statusText = String(localized: "No transcription data available for export.", comment: "AI Cut status message")
        return
      }

      let mediaByURL = Dictionary(uniqueKeysWithValues: mediaFiles.map { ($0.url, $0) })

      applyIfCurrentAICutSession(sessionGeneration) {
        isExporting = true
        exportProgress.reset()
      }
      defer {
        applyIfCurrentAICutSession(sessionGeneration) {
          isExporting = false
        }
      }

      var completedSections: [String] = []
      var failureMessages: [String] = []

      if exportPlan.includes(.fcpxml) {
        exportProgress.startPhase(.fcpxml)
        do {
          applyIfCurrentAICutSession(sessionGeneration) {
            statusText = String(localized: "Exporting Final Cut projects...", comment: "AI Cut status message")
          }
          let projectName = config.makeFCPXMLProjectName(additionalComponents: [])
          let (outputs, failures) = try performBatchFCPXMLExport(
            urls: transcribedURLs,
            mediaByURL: mediaByURL,
            mode: request.exportMode,
            destinationDirectory: destinationDirectory,
            baseProjectName: projectName
          )
          exportProgress.completePhase(.fcpxml)
          if !outputs.isEmpty {
            completedSections.append("FCPXML (\(outputs.count))")
          }
          if !failures.isEmpty {
            let summary = failures.map { "\($0.key): \($0.value)" }.joined(separator: "; ")
            failureMessages.append("FCPXML issues – \(summary)")
          }
        } catch {
          exportProgress.failPhase(.fcpxml, message: error.localizedDescription)
          failureMessages.append("FCPXML failed – \(error.localizedDescription)")
        }
      }

      if exportPlan.includes(.subtitle) {
        exportProgress.startPhase(.subtitle)
        do {
          applyIfCurrentAICutSession(sessionGeneration) {
            statusText = String(localized: "Exporting subtitle files...", comment: "AI Cut status message")
          }
          let (outputs, failures) = try performBatchSubtitleExport(
            urls: transcribedURLs,
            mediaByURL: mediaByURL,
            mode: request.exportMode,
            destinationDirectory: destinationDirectory,
            formats: config.subtitleExportFormats
          )
          exportProgress.completePhase(.subtitle)
          if !outputs.isEmpty {
            completedSections.append("Subtitles")
          }
          if !failures.isEmpty {
            let summary = failures.map { "\($0.key): \($0.value)" }.joined(separator: "; ")
            failureMessages.append("Subtitle issues – \(summary)")
          }
        } catch {
          exportProgress.failPhase(.subtitle, message: error.localizedDescription)
          failureMessages.append("Subtitles failed – \(error.localizedDescription)")
        }
      }

      if exportPlan.includes(.video) {
        exportProgress.startPhase(.video)
        do {
          applyIfCurrentAICutSession(sessionGeneration) {
            statusText =
              request.burnSubtitlesIntoVideo
              ? "Exporting burned-in videos..."
              : "Copying source videos..."
          }
          let (outputs, failures) = try await performBatchVideoExport(
            urls: transcribedURLs,
            mode: request.exportMode,
            destinationDirectory: destinationDirectory,
            burnIn: request.burnSubtitlesIntoVideo,
            format: config.videoExportFormat,
            quality: request.videoQuality,
            sessionGeneration: sessionGeneration
          )
          exportProgress.completePhase(.video)
          if !outputs.isEmpty {
            let label = request.burnSubtitlesIntoVideo ? "Videos (burned)" : "Videos (clean)"
            completedSections.append("\(label) \(outputs.count)")
          }
          if !failures.isEmpty {
            let summary = failures.map { "\($0.key): \($0.value)" }.joined(separator: "; ")
            failureMessages.append("Video issues – \(summary)")
          }
        } catch {
          exportProgress.failPhase(.video, message: error.localizedDescription)
          failureMessages.append("Video export failed – \(error.localizedDescription)")
        }
      }

      if exportPlan.includes(.audio) {
        exportProgress.startPhase(.audio)
        do {
          applyIfCurrentAICutSession(sessionGeneration) {
            statusText = String(localized: "Exporting audio files...", comment: "AI Cut status message")
          }
          let (outputs, failures) = try await performBatchAudioExport(
            urls: transcribedURLs,
            mode: request.exportMode,
            destinationDirectory: destinationDirectory,
            format: request.audioFormat,
            sessionGeneration: sessionGeneration
          )
          exportProgress.completePhase(.audio)
          if !outputs.isEmpty {
            completedSections.append("Audio (\(outputs.count))")
          }
          if !failures.isEmpty {
            let summary = failures.map { "\($0.key): \($0.value)" }.joined(separator: "; ")
            failureMessages.append("Audio issues – \(summary)")
          }
        } catch {
          exportProgress.failPhase(.audio, message: error.localizedDescription)
          failureMessages.append("Audio export failed – \(error.localizedDescription)")
        }
      }

      applyIfCurrentAICutSession(sessionGeneration) {
        let finalSummary = completedSections.joined(separator: ", ")
        if failureMessages.isEmpty {
          statusText =
            finalSummary.isEmpty
            ? "Export completed."
            : "Exported \(finalSummary) to selected folder."
        } else {
          let issues = failureMessages.joined(separator: "; ")
          if finalSummary.isEmpty {
            statusText = String(localized: "Export encountered issues: \(issues)", comment: "AI Cut status message")
          } else {
            statusText =
              String(localized: "Exported \(finalSummary) with issues: \(issues). Files saved in selected folder.", comment: "AI Cut status message")
          }
        }
      }
    }
  }

  @MainActor
  private func promptForExportDirectory(message: String) -> URL? {
    let panel = NSOpenPanel()
    panel.message = message
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.prompt = "Choose"
    return panel.runModal() == .OK ? panel.url : nil
  }

  @MainActor
  private func performBatchFCPXMLExport(
    urls: [URL],
    mediaByURL: [URL: MediaFile],
    mode: ExportMode,
    destinationDirectory: URL,
    baseProjectName: String
  ) throws -> (outputs: [URL], failures: [String: String]) {
    var outputs: [URL] = []
    var failures: [String: String] = [:]

    switch mode {
    case .merge:
      let media = urls.compactMap { mediaByURL[$0] }
      guard !media.isEmpty else { throw ExportError.noSegments }

      let baseName = sanitizedFileName(from: baseProjectName)
      let fileName = baseName.isEmpty ? "Project_fcpxml" : "\(baseName)_fcpxml"
      let destination = destinationDirectory.appendingPathComponent(fileName)
        .appendingPathExtension("fcpxml")

      try performFCPXMLExport(
        mediaFiles: media,
        destinationURL: destination,
        projectName: baseProjectName,
        includeSubtitleFiles: false
      )

      outputs.append(destination)

    case .separate:
      for url in urls {
        let baseName = sanitizedFileName(from: url.deletingPathExtension().lastPathComponent)
        let fileName = baseName.isEmpty ? "Video_fcpxml" : "\(baseName)_fcpxml"
        let destination = destinationDirectory.appendingPathComponent(fileName)
          .appendingPathExtension("fcpxml")

        guard let media = mediaByURL[url] else {
          failures[url.lastPathComponent] = ExportError.noSegments.localizedDescription
          continue
        }

        let projectName = config.makeFCPXMLProjectName(additionalComponents: [baseName])

        do {
          try performFCPXMLExport(
            mediaFiles: [media],
            destinationURL: destination,
            projectName: projectName,
            includeSubtitleFiles: false
          )
          outputs.append(destination)
        } catch {
          failures[url.lastPathComponent] = error.localizedDescription
        }
      }

      if outputs.isEmpty {
        throw ExportError.noSegments
      }
    }

    return (outputs, failures)
  }

  @MainActor
  private func performBatchSubtitleExport(
    urls: [URL],
    mediaByURL: [URL: MediaFile],
    mode: ExportMode,
    destinationDirectory: URL,
    formats: Set<SubtitleExportFormat>
  ) throws -> (outputs: [URL], failures: [String: String]) {
    var outputs: [URL] = []
    var failures: [String: String] = [:]

    guard !formats.isEmpty else { return (outputs, failures) }

    switch mode {
    case .merge:
      for format in formats {
        let baseName = "Project"
        let fileName = "\(baseName)_subtitle.\(format.fileExtension)"
        let destination = destinationDirectory.appendingPathComponent(fileName)

        let media = urls.compactMap { mediaByURL[$0] }
        guard !media.isEmpty else {
          failures["Project"] = ExportError.noSegments.localizedDescription
          continue
        }

        do {
          try SubtitleFileExporter.export(
            mediaFiles: media,
            formats: [format],
            directory: destinationDirectory,
            filterSilentSegments: config.filterSilent
          )
          outputs.append(destination)
        } catch {
          failures["Project"] = error.localizedDescription
        }
      }

    case .separate:
      for url in urls {
        let baseName = sanitizedFileName(from: url.deletingPathExtension().lastPathComponent)
        let fileBaseName = baseName.isEmpty ? "Video" : baseName

        guard let media = mediaByURL[url] else {
          failures[url.lastPathComponent] = ExportError.noSegments.localizedDescription
          continue
        }

        for format in formats {
          let fileName = "\(fileBaseName)_subtitle.\(format.fileExtension)"
          let destination = destinationDirectory.appendingPathComponent(fileName)

          do {
            try SubtitleFileExporter.export(
              mediaFiles: [media],
              formats: [format],
              directory: destinationDirectory,
              filterSilentSegments: config.filterSilent
            )
            outputs.append(destination)
          } catch {
            failures[url.lastPathComponent] = error.localizedDescription
          }
        }
      }
    }

    return (outputs, failures)
  }

  @MainActor
  private func performBatchVideoExport(
    urls: [URL],
    mode: ExportMode,
    destinationDirectory: URL,
    burnIn: Bool,
    format: VideoExportFormat,
    quality: VideoExportQuality,
    sessionGeneration: UInt64
  ) async throws -> (outputs: [URL], failures: [String: String]) {
    var outputs: [URL] = []
    var failures: [String: String] = [:]

    let exporter = VideoExporter()

    for (index, url) in urls.enumerated() {
      applyIfCurrentAICutSession(sessionGeneration) {
        exportProgress.updateProgress(for: .video, current: index, total: urls.count)
        statusText =
          burnIn
          ? "Exporting video [\(index + 1)/\(urls.count)]: \(url.lastPathComponent)..."
          : "Copying video [\(index + 1)/\(urls.count)]: \(url.lastPathComponent)..."
      }

      let baseName = sanitizedFileName(from: url.deletingPathExtension().lastPathComponent)

      do {
        let extensionName: String
        if burnIn {
          extensionName = format.fileExtension
        } else {
          let originalExt = url.pathExtension
          extensionName = originalExt.isEmpty ? format.fileExtension : originalExt
        }

        let fileName: String
        if mode == .merge {
          fileName = "Project_video"
        } else {
          fileName = baseName.isEmpty ? "Video_video" : "\(baseName)_video"
        }

        let outputURL = destinationDirectory.appendingPathComponent(fileName)
          .appendingPathExtension(extensionName)

        if FileManager.default.fileExists(atPath: outputURL.path) {
          try FileManager.default.removeItem(at: outputURL)
        }

        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }

        if burnIn {
          let segments = paddedSegments(for: url)
          guard !segments.isEmpty else {
            throw ExportError.noSegments
          }

          let exportSegments = ExportTextNormalizer.normalize(
            segments: segments,
            keepPunctuation: config.keepPunctuationOnExport
          )
          let effects = resolvedEffects(for: url)
          let placement = config.translationPlacement
          let styles = config.subtitleStyles

          try await exporter.exportVideoWithSubtitles(
            videoURL: url,
            segments: exportSegments,
            outputURL: outputURL,
            filterSilentSegments: config.filterSilent,
            effects: effects,
            translationPlacement: placement,
            styleConfiguration: styles,
            quality: quality
          )
        } else {
          try await exportOriginalVideo(
            sourceURL: url,
            destinationURL: outputURL,
            preferredFormat: format,
            quality: quality
          )
        }

        outputs.append(outputURL)
      } catch let error as ExportError {
        failures[url.lastPathComponent] = error.localizedDescription
      } catch {
        failures[url.lastPathComponent] = error.localizedDescription
      }
    }

    if outputs.isEmpty {
      throw NSError(
        domain: "VideoExport",
        code: 51,
        userInfo: [NSLocalizedDescriptionKey: failures.values.first ?? "Video export failed."]
      )
    }

    return (outputs, failures)
  }

  @MainActor
  private func performBatchAudioExport(
    urls: [URL],
    mode: ExportMode,
    destinationDirectory: URL,
    format: AudioExportFormat,
    sessionGeneration: UInt64
  ) async throws -> (outputs: [URL], failures: [String: String]) {
    // When dubbing is enabled, attempt DubbingService with graceful fallback
    if config.audioDubbingEnabled {
      // Check if a voice-clone-capable model can be resolved
      guard let modelDef = dubbingRuntime.resolveVoiceCloneModel(
        preferredRepo: config.ttsMLXModelId
      ) else {
        // No voice-clone model available at all; fall back to regular export
        return try await performPlainAudioExport(
          urls: urls, mode: mode, destinationDirectory: destinationDirectory,
          format: format, sessionGeneration: sessionGeneration
        )
      }

      // Check if segments have translations for dubbing
      let firstURL = urls.first
      let hasTranslatableContent = firstURL.map { url in
        dubbingRuntime.canPerformDubbing(
          segments: paddedSegments(for: url),
          ttsLanguage: config.translationTargetLanguage.rawValue
        )
      } ?? false

      if hasTranslatableContent {
        return try await performBatchDubbingExport(
          urls: urls, mode: mode, destinationDirectory: destinationDirectory,
          format: format, sessionGeneration: sessionGeneration,
          resolvedModel: modelDef
        )
      } else {
        // Dubbing enabled but preconditions not met; fall back to regular export
        return try await performPlainAudioExport(
          urls: urls, mode: mode, destinationDirectory: destinationDirectory,
          format: format, sessionGeneration: sessionGeneration
        )
      }
    }

    return try await performPlainAudioExport(
      urls: urls, mode: mode, destinationDirectory: destinationDirectory,
      format: format, sessionGeneration: sessionGeneration
    )
  }

  @MainActor
  private func performPlainAudioExport(
    urls: [URL],
    mode: ExportMode,
    destinationDirectory: URL,
    format: AudioExportFormat,
    sessionGeneration: UInt64
  ) async throws -> (outputs: [URL], failures: [String: String]) {
    var outputs: [URL] = []
    var failures: [String: String] = [:]
    let exporter = AudioExporter()

    for (index, url) in urls.enumerated() {
      applyIfCurrentAICutSession(sessionGeneration) {
        exportProgress.updateProgress(for: .audio, current: index, total: urls.count)
        statusText = String(localized: "Exporting audio [\(index + 1)/\(urls.count)]: \(url.lastPathComponent)...", comment: "AI Cut status message")
      }

      let baseName = sanitizedFileName(from: url.deletingPathExtension().lastPathComponent)
      let fileName: String
      if mode == .merge {
        fileName = "Project_audio"
      } else {
        fileName = baseName.isEmpty ? "Video_audio" : "\(baseName)_audio"
      }

      let outputURL = destinationDirectory.appendingPathComponent(fileName)
        .appendingPathExtension(format.fileExtension)

      let needsStop = url.startAccessingSecurityScopedResource()
      defer { if needsStop { url.stopAccessingSecurityScopedResource() } }

      do {
        let segmentsForFilter: [Segment]? = config.filterSilent ? paddedSegments(for: url) : nil
        try await exporter.exportAudio(
          from: url, to: outputURL, format: format, segments: segmentsForFilter)
        outputs.append(outputURL)
      } catch {
        failures[url.lastPathComponent] = error.localizedDescription
      }
    }

    if outputs.isEmpty {
      throw NSError(
        domain: "AudioExport",
        code: 61,
        userInfo: [NSLocalizedDescriptionKey: failures.values.first ?? "Audio export failed."]
      )
    }

    return (outputs, failures)
  }

  /// Dubbing-specific batch export: synthesize dubbed audio for each video using TTS voice cloning.
  private func performBatchDubbingExport(
    urls: [URL],
    mode: ExportMode,
    destinationDirectory: URL,
    format: AudioExportFormat,
    sessionGeneration: UInt64,
    resolvedModel: MLXTTSModelDefinition
  ) async throws -> (outputs: [URL], failures: [String: String]) {
    var outputs: [URL] = []
    var failures: [String: String] = [:]

    // Acquire TTS model through ModelCacheManager for proper memory management.
    // This ensures we reuse the same model instance as the TTS preview page
    // and prevents redundant model loads.
    let engine = config.ttsEngine
    let modelID = resolvedModel.huggingFaceRepo
    _ = try await ModelCacheManager.shared.ensureTTSModel(engine: engine, modelID: modelID)
    defer {
      Task {
        await ModelCacheManager.shared.releaseTTSModel(engine: engine, modelID: modelID)
      }
    }

    for (index, url) in urls.enumerated() {
      applyIfCurrentAICutSession(sessionGeneration) {
        exportProgress.updateProgress(for: .audio, current: index, total: urls.count)
      }
      let segments = paddedSegments(for: url)
      guard !segments.isEmpty else {
        failures[url.lastPathComponent] = "No segments available."
        continue
      }

      let totalDuration = videoStates[url]?.audioDuration
        ?? segments.last?.endTime ?? 0

      let baseName = sanitizedFileName(from: url.deletingPathExtension().lastPathComponent)
      let fileName: String
      if mode == .merge {
        fileName = "Project_dubbed"
      } else {
        fileName = baseName.isEmpty ? "Video_dubbed" : "\(baseName)_dubbed"
      }

      let outputURL = destinationDirectory.appendingPathComponent(fileName)
        .appendingPathExtension(format.fileExtension)

      let needsStop = url.startAccessingSecurityScopedResource()
      defer { if needsStop { url.stopAccessingSecurityScopedResource() } }

      do {
        // Resolve custom voice reference if configured
        var customRefURL: URL? = nil
        var customRefText: String? = nil
        if config.dubbingVoiceReferenceMode == .custom {
          customRefURL = resolveReferenceAudioURL()
          customRefText = config.ttsReferenceText.isEmpty ? nil : config.ttsReferenceText
        }

        let result = try await dubbingRuntime.generateDubbedAudio(
          sourceMediaURL: url,
          segments: segments,
          totalDuration: totalDuration,
          ttsModelDefinition: resolvedModel,
          ttsLanguage: config.translationTargetLanguage.rawValue,
          outputURL: outputURL,
          outputFormat: format,
          presetSpeaker: config.ttsPresetSpeaker.isEmpty ? nil : config.ttsPresetSpeaker,
          customReferenceAudioURL: customRefURL,
          customReferenceText: customRefText,
          progress: { progress in
            Task { @MainActor in
              switch progress.phase {
              case .extractingReference:
                self.statusText = String(localized: "Extracting voice reference...", comment: "Dubbing status message")
              case .synthesizing:
                let samplesInfo = progress.generatedSamples > 0
                  ? String(localized: " (\(String(format: "%.1f", Double(progress.generatedSamples) / 24000.0))s generated)", comment: "Dubbing status: seconds of audio generated")
                  : ""
                self.statusText = String(localized: "Dubbing segment [\(progress.currentSegment)/\(progress.totalSegments)]\(samplesInfo)...", comment: "Dubbing status message")
              case .composing:
                self.statusText = String(localized: "Composing dubbed audio...", comment: "Dubbing status message")
              case .exporting:
                self.statusText = String(localized: "Exporting dubbed audio...", comment: "Dubbing status message")
              }
            }
          }
        )
        outputs.append(result.audioFileURL)
      } catch {
        failures[url.lastPathComponent] = error.localizedDescription
      }
    }

    if outputs.isEmpty {
      throw NSError(
        domain: "DubbingExport",
        code: 62,
        userInfo: [NSLocalizedDescriptionKey: failures.values.first ?? "Dubbing export failed."]
      )
    }

    return (outputs, failures)
  }

  private func exportSingleVideo(url: URL) {
    let sessionGeneration = currentAICutSessionGeneration()
    Task { @MainActor in
      guard videoStates[url]?.segments.isEmpty == false else {
        statusText = String(localized: "Nothing to export for this video. Please transcribe it first.", comment: "AI Cut status message")
        return
      }

      let request = config.defaultExportRequest()
      guard
        request.includeFCPXML
          || request.includeSubtitleFiles
          || request.includeVideos
          || request.includeAudio
      else {
        statusText = String(localized: "Enable at least one export option in Output settings before exporting.", comment: "AI Cut status message")
        return
      }

      if request.includeFCPXML && !config.fcpxmlEnabled {
        statusText = String(localized: "Enable FCPXML export in Output settings to include Final Cut projects.", comment: "AI Cut status message")
        return
      }

      if request.includeSubtitleFiles && config.subtitleExportFormats.isEmpty {
        statusText =
          String(localized: "No subtitle file formats are enabled. Choose at least one format in Output settings.", comment: "AI Cut status message")
        return
      }

      if request.includeAudio && !config.audioExportEnabled {
        statusText = String(localized: "Enable audio export in Output settings before exporting audio files.", comment: "AI Cut status message")
        return
      }

      let promptMessage = "Select a folder to store exports for \(url.lastPathComponent)"
      guard let destinationDirectory = promptForExportDirectory(message: promptMessage) else {
        statusText = String(localized: "Export cancelled", comment: "AI Cut status message")
        return
      }

      let mediaFiles: [MediaFile]
      do {
        mediaFiles = try await buildMediaFiles(for: [url])
      } catch {
        applyIfCurrentAICutSession(sessionGeneration) {
          statusText = String(localized: "Export failed: \(error.localizedDescription)", comment: "AI Cut status message")
        }
        return
      }

      guard let media = mediaFiles.first else {
        statusText = String(localized: "No transcription data available for export.", comment: "AI Cut status message")
        return
      }

      let baseName = sanitizedFileName(from: url.deletingPathExtension().lastPathComponent)
      let projectName = config.makeFCPXMLProjectName(additionalComponents: [baseName])

      let mediaByURL: [URL: MediaFile] = [url: media]

      applyIfCurrentAICutSession(sessionGeneration) {
        isExporting = true
        exportProgress.reset()
      }
      defer {
        applyIfCurrentAICutSession(sessionGeneration) {
          isExporting = false
        }
      }

      var completedSections: [String] = []
      var failureMessages: [String: String] = [:]
      var fcpxmlOutputs: [URL] = []

      if request.includeFCPXML {
        exportProgress.startPhase(.fcpxml)
        do {
          applyIfCurrentAICutSession(sessionGeneration) {
            statusText = String(localized: "Exporting Final Cut project...", comment: "AI Cut status message")
          }
          let result = try performBatchFCPXMLExport(
            urls: [url],
            mediaByURL: mediaByURL,
            mode: request.exportMode,
            destinationDirectory: destinationDirectory,
            baseProjectName: projectName
          )
          fcpxmlOutputs = result.outputs
          exportProgress.completePhase(.fcpxml)
          if !result.outputs.isEmpty { completedSections.append("FCPXML") }
          failureMessages.merge(result.failures) { $1 }
        } catch {
          exportProgress.failPhase(.fcpxml, message: error.localizedDescription)
          failureMessages[url.lastPathComponent] = error.localizedDescription
        }
      }

      if request.includeSubtitleFiles {
        exportProgress.startPhase(.subtitle)
        do {
          applyIfCurrentAICutSession(sessionGeneration) {
            statusText = String(localized: "Exporting subtitle files...", comment: "AI Cut status message")
          }
          let result = try performBatchSubtitleExport(
            urls: [url],
            mediaByURL: mediaByURL,
            mode: request.exportMode,
            destinationDirectory: destinationDirectory,
            formats: config.subtitleExportFormats
          )
          exportProgress.completePhase(.subtitle)
          if !result.outputs.isEmpty { completedSections.append("Subtitles") }
          failureMessages.merge(result.failures) { $1 }
        } catch {
          exportProgress.failPhase(.subtitle, message: error.localizedDescription)
          failureMessages[url.lastPathComponent] = error.localizedDescription
        }
      }

      if request.includeVideos {
        exportProgress.startPhase(.video)
        do {
          applyIfCurrentAICutSession(sessionGeneration) {
            statusText =
              request.burnSubtitlesIntoVideo
              ? "Exporting burned-in video..."
              : "Copying source video..."
          }
          let result = try await performBatchVideoExport(
            urls: [url],
            mode: request.exportMode,
            destinationDirectory: destinationDirectory,
            burnIn: request.burnSubtitlesIntoVideo,
            format: config.videoExportFormat,
            quality: request.videoQuality,
            sessionGeneration: sessionGeneration
          )
          exportProgress.completePhase(.video)
          if !result.outputs.isEmpty {
            let label = request.burnSubtitlesIntoVideo ? "Video (burned)" : "Video"
            completedSections.append(label)
          }
          failureMessages.merge(result.failures) { $1 }
        } catch {
          exportProgress.failPhase(.video, message: error.localizedDescription)
          failureMessages[url.lastPathComponent] = error.localizedDescription
        }
      }

      if request.includeAudio {
        exportProgress.startPhase(.audio)
        do {
          applyIfCurrentAICutSession(sessionGeneration) {
            statusText = String(localized: "Exporting audio...", comment: "AI Cut status message")
          }
          let result = try await performBatchAudioExport(
            urls: [url],
            mode: request.exportMode,
            destinationDirectory: destinationDirectory,
            format: request.audioFormat,
            sessionGeneration: sessionGeneration
          )
          exportProgress.completePhase(.audio)
          if !result.outputs.isEmpty {
            completedSections.append("Audio")
          }
          failureMessages.merge(result.failures) { $1 }
        } catch {
          exportProgress.failPhase(.audio, message: error.localizedDescription)
          failureMessages[url.lastPathComponent] = error.localizedDescription
        }
      }

      if request.includeFCPXML, let fcpxml = fcpxmlOutputs.first {
        await openInFinalCutPro(fcpxmlURL: fcpxml, sessionGeneration: sessionGeneration)
      }

      applyIfCurrentAICutSession(sessionGeneration) {
        if failureMessages.isEmpty {
          let summary = completedSections.joined(separator: ", ")
          statusText =
            summary.isEmpty
            ? "Export completed."
            : "Exported \(summary) to selected folder."
        } else {
          let issues = failureMessages.map { "\($0.key): \($0.value)" }.joined(separator: "; ")
          if completedSections.isEmpty {
            statusText = String(localized: "Export encountered issues: \(issues)", comment: "AI Cut status message")
          } else {
            let summary = completedSections.joined(separator: ", ")
            statusText = String(localized: "Exported \(summary) with issues: \(issues). Files saved in selected folder.", comment: "AI Cut status message")
          }
        }
      }
    }
  }

  @MainActor
  private func exportSeparateFCPXMLFiles(for urls: [URL]) async {
    await exportSeparateFCPXMLFiles(for: urls, includeSubtitleFiles: true)
  }

  @MainActor
  private func exportSeparateFCPXMLFiles(for urls: [URL], includeSubtitleFiles: Bool) async {
    let sessionGeneration = currentAICutSessionGeneration()
    let panel = NSOpenPanel()
    panel.message = "Select a folder to store FCPXML files"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.prompt = "Export"
    if panel.runModal() != .OK {
      statusText = String(localized: "Export cancelled", comment: "AI Cut status message")
      return
    }
    guard let directory = panel.url else {
      statusText = String(localized: "No export folder selected", comment: "AI Cut status message")
      return
    }

    var failures: [String: String] = [:]

    guard AICutSessionGuard.shouldApplyUpdate(
      capturedGeneration: sessionGeneration,
      activeGeneration: aiCutSessionGeneration
    ) else { return }

    applyIfCurrentAICutSession(sessionGeneration) {
      isExporting = true
      exportProgress.reset()
      exportProgress.startPhase(.fcpxml)
    }
    defer {
      applyIfCurrentAICutSession(sessionGeneration) {
        isExporting = false
      }
    }

    let mediaFiles: [MediaFile]
    do {
      mediaFiles = try await buildMediaFiles(for: urls)
    } catch {
      applyIfCurrentAICutSession(sessionGeneration) {
        statusText = String(localized: "FCPXML export failed: \(error.localizedDescription)", comment: "AI Cut status message")
      }
      return
    }
    let mediaByURL = Dictionary(uniqueKeysWithValues: mediaFiles.map { ($0.url, $0) })

    for (index, url) in urls.enumerated() {
      applyIfCurrentAICutSession(sessionGeneration) {
        exportProgress.updateProgress(for: .fcpxml, current: index, total: urls.count)
        statusText = String(localized: "Exporting FCPXML [\(index + 1)/\(urls.count)]: \(url.lastPathComponent)...", comment: "AI Cut status message")
      }
      do {
        let fileBase = sanitizedFileName(from: url.deletingPathExtension().lastPathComponent)
        let projectName = config.makeFCPXMLProjectName(additionalComponents: [fileBase])
        let outputURL = directory.appendingPathComponent(fileBase).appendingPathExtension("fcpxml")
        guard let media = mediaByURL[url] else {
          throw ExportError.noSegments
        }
        try performFCPXMLExport(
          mediaFiles: [media],
          destinationURL: outputURL,
          projectName: projectName,
          includeSubtitleFiles: includeSubtitleFiles
        )
      } catch {
        failures[url.lastPathComponent] = error.localizedDescription
      }
    }

    applyIfCurrentAICutSession(sessionGeneration) {
      if failures.isEmpty {
        exportProgress.completePhase(.fcpxml)
        statusText = String(localized: "FCPXML files exported to \(directory.lastPathComponent).", comment: "AI Cut status message")
      } else {
        let messages = failures.map { "\($0.key): \($0.value)" }.joined(separator: "; ")
        exportProgress.failPhase(.fcpxml, message: messages)
        statusText = String(localized: "FCPXML export completed with issues: \(messages)", comment: "AI Cut status message")
      }
    }
  }

  @MainActor
  private func performFCPXMLExport(
    mediaFiles: [MediaFile],
    destinationURL: URL,
    projectName: String,
    includeSubtitleFiles: Bool = true,
    subtitleDirectory: URL? = nil
  ) throws {
    guard !mediaFiles.isEmpty else {
      throw ExportError.noSegments
    }

    let exportSettings = FCPXMLExportSettings(
      frameRate: config.fcpxmlFrameRate,
      projectName: projectName,
      includeSubtitles: config.fcpxmlIncludeSubtitles,
      filterEmptySegments: config.filterSilent,
      isResolve: config.fcpxmlIsResolveCompatible,
      speed: config.fcpxmlSpeed
    )

    let content = FCPXMLExporter.exportFCPXML(mediaFiles: mediaFiles, settings: exportSettings)
    try content.write(to: destinationURL, atomically: true, encoding: .utf8)

    if includeSubtitleFiles, !config.subtitleExportFormats.isEmpty {
      let targetDirectory = subtitleDirectory ?? destinationURL.deletingLastPathComponent()
      try FileManager.default.createDirectory(
        at: targetDirectory, withIntermediateDirectories: true
      )
      try SubtitleFileExporter.export(
        mediaFiles: mediaFiles,
        formats: config.subtitleExportFormats,
        directory: targetDirectory,
        filterSilentSegments: config.filterSilent
      )
    }
  }

  @MainActor
  private func buildMediaFiles(for urls: [URL]) async throws -> [MediaFile] {
    var mediaFiles: [MediaFile] = []

    for videoURL in urls {
      guard let videoState = videoStates[videoURL], videoState.segments.isEmpty == false else {
        continue
      }

      let segments = paddedSegments(for: videoURL)
      guard !segments.isEmpty else { continue }
      let exportSegments = ExportTextNormalizer.normalize(
        segments: segments,
        keepPunctuation: config.keepPunctuationOnExport
      )

      var duration = videoState.audioDuration ?? 0
      let needsStop = videoURL.startAccessingSecurityScopedResource()
      defer { if needsStop { videoURL.stopAccessingSecurityScopedResource() } }

      let asset = AVURLAsset(
        url: videoURL,
        options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
      )
      let presentationSize = try? await Self.presentationSize(for: asset)
      if duration <= 0 {
        duration = try await asset.load(.duration).seconds
      }

      if let state = videoStates[videoURL] {
        state.presentationSize = presentationSize
      }

      mediaFiles.append(
        MediaFile(
          url: videoURL,
          segments: exportSegments,
          duration: duration,
          presentationSize: presentationSize,
          effects: videoState.segmentEffects.adjusted(for: config.effectConfiguration),
          translationPlacement: config.translationPlacement,
          styleConfiguration: config.subtitleStyles
        )
      )
    }

    return mediaFiles
  }

  private func resolvedEffects(for url: URL?) -> [String: SegmentEffectState] {
    _ = effectsVersion  // depend on effectsVersion so body re-renders after applyEffectEnhancement
    guard let url, let state = videoStates[url] else { return [:] }
    return state.segmentEffects.adjusted(for: config.effectConfiguration)
  }

  /// Persists current segment text edits to the history store, keeping translations and deletions in sync.
  @MainActor
  private func markSegmentsChanged(for url: URL, state: VideoState) {
    guard let duration = state.audioDuration else { return }
    let segmentsWithTranslations = VideoState.injectTranslations(
      state.processedTranslations, into: state.segments)
    let sessionID =
      state.historySessionID
      ?? historyRuntime.existingFileTranscriptionSessionID(forSourceURL: url)
    let translationsToSave = state.processedTranslations.isEmpty ? nil : state.processedTranslations
    let removedToSave =
      state.removedProcessedSegmentIDs.isEmpty ? nil : state.removedProcessedSegmentIDs
    state.historySessionID = saveFileTranscriptionToHistory(
      url: url,
      segments: segmentsWithTranslations,
      lastTranslatedLanguage: state.lastTranslatedLanguage,
      processedTranslations: translationsToSave,
      removedSegmentIDs: removedToSave,
      duration: duration,
      existingSessionID: sessionID
    )
  }

  @MainActor
  private func markTranslationsChanged(for url: URL, state: VideoState) {
    translationsVersion &+= 1
    guard let duration = state.audioDuration else { return }
    // Embed translations into segment copies before persisting
    let segmentsWithTranslations = VideoState.injectTranslations(
      state.processedTranslations, into: state.segments)
    let sessionID =
      state.historySessionID
      ?? historyRuntime.existingFileTranscriptionSessionID(forSourceURL: url)
    // Save processedTranslations dict directly alongside segments.
    // The dict is keyed by post-processing segment IDs which may differ from raw segment IDs
    // when splitting is enabled, so embedding into raw segments alone is lossy.
    let translationsToSave = state.processedTranslations.isEmpty ? nil : state.processedTranslations
    let removedToSave = state.removedProcessedSegmentIDs.isEmpty ? nil : state.removedProcessedSegmentIDs
    state.historySessionID = saveFileTranscriptionToHistory(
      url: url,
      segments: segmentsWithTranslations,
      lastTranslatedLanguage: state.lastTranslatedLanguage,
      processedTranslations: translationsToSave,
      removedSegmentIDs: removedToSave,
      duration: duration,
      existingSessionID: sessionID
    )
  }

  @MainActor
  private func markDeletionsChanged(for url: URL, state: VideoState) {
    guard let duration = state.audioDuration else { return }
    let segmentsWithTranslations = VideoState.injectTranslations(
      state.processedTranslations, into: state.segments)
    let sessionID =
      state.historySessionID
      ?? historyRuntime.existingFileTranscriptionSessionID(forSourceURL: url)
    let translationsToSave = state.processedTranslations.isEmpty ? nil : state.processedTranslations
    let removedToSave = state.removedProcessedSegmentIDs.isEmpty ? nil : state.removedProcessedSegmentIDs
    state.historySessionID = saveFileTranscriptionToHistory(
      url: url,
      segments: segmentsWithTranslations,
      lastTranslatedLanguage: state.lastTranslatedLanguage,
      processedTranslations: translationsToSave,
      removedSegmentIDs: removedToSave,
      duration: duration,
      existingSessionID: sessionID
    )
  }

  private static func presentationSize(for asset: AVAsset) async throws -> CGSize? {
    let videoTracks = try await asset.loadTracks(withMediaType: .video)
    guard let track = videoTracks.first else { return nil }

    let naturalSize = try await track.load(.naturalSize)
    let preferredTransform = try await track.load(.preferredTransform)

    let width =
      abs(naturalSize.width * preferredTransform.a)
      + abs(naturalSize.height * preferredTransform.c)
    let height =
      abs(naturalSize.width * preferredTransform.b)
      + abs(naturalSize.height * preferredTransform.d)

    let computed = CGSize(width: width, height: height)
    if computed.width > 0 && computed.height > 0 {
      return computed
    }

    if naturalSize.width > 0 && naturalSize.height > 0 {
      return naturalSize
    }

    return nil
  }

  private func exportOriginalVideo(
    sourceURL: URL,
    destinationURL: URL,
    preferredFormat: VideoExportFormat,
    quality: VideoExportQuality
  ) async throws {
    let asset = AVURLAsset(
      url: sourceURL,
      options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
    )

    let allPresets = AVAssetExportSession.allExportPresets()
    let availablePresets = allPresets.filter {
      AVAssetExportSession(asset: asset, presetName: $0) != nil
    }
    guard !availablePresets.isEmpty else {
      throw NSError(
        domain: "VideoExport",
        code: 20,
        userInfo: [NSLocalizedDescriptionKey: "No compatible export presets for source asset."]
      )
    }

    let presetName = quality.resolvedPreset(from: availablePresets, burnIn: false)

    guard
      let exportSession = AVAssetExportSession(
        asset: asset,
        presetName: presetName
      )
    else {
      throw NSError(
        domain: "VideoExport",
        code: 21,
        userInfo: [NSLocalizedDescriptionKey: "Could not create export session."]
      )
    }

    let supportedTypes = exportSession.supportedFileTypes
    let targetType: AVFileType
    if let preferredType = preferredFileType(
      for: preferredFormat, supportedTypes: supportedTypes)
    {
      targetType = preferredType
    } else if let fallback = supportedTypes.first {
      targetType = fallback
    } else {
      throw NSError(
        domain: "VideoExport",
        code: 22,
        userInfo: [NSLocalizedDescriptionKey: "No supported file types for clean export."]
      )
    }

    try await exportSession.export(to: destinationURL, as: targetType)
  }

  private func preferredFileType(
    for format: VideoExportFormat,
    supportedTypes: [AVFileType]
  ) -> AVFileType? {
    switch format {
    case .mp4:
      if supportedTypes.contains(.mp4) { return .mp4 }
      if supportedTypes.contains(.m4v) { return .m4v }
    case .mov:
      if supportedTypes.contains(.mov) { return .mov }
    case .m4v:
      if supportedTypes.contains(.m4v) { return .m4v }
      if supportedTypes.contains(.mp4) { return .mp4 }
    }
    return nil
  }

  private func sanitizedFileName(from raw: String) -> String {
    let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:").union(.whitespacesAndNewlines)
    let components = raw.components(separatedBy: invalid)
    let sanitized = components.filter { !$0.isEmpty }.joined(separator: "_")
    return sanitized.isEmpty ? "Export" : sanitized
  }

  /// Resolve custom reference audio URL from security-scoped bookmark or raw path.
  private func resolveReferenceAudioURL() -> URL? {
    if let bookmark = config.ttsReferenceAudioBookmark {
      var isStale = false
      if let url = try? URL(
        resolvingBookmarkData: bookmark,
        options: .withSecurityScope,
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      ) {
        _ = url.startAccessingSecurityScopedResource()
        return url
      }
    }
    let path = config.ttsReferenceAudioPath
    guard !path.isEmpty else { return nil }
    let url = URL(fileURLWithPath: path)
    return FileManager.default.fileExists(atPath: path) ? url : nil
  }

  /// 针对指定 URL 生成 padding 后 segments（不存在则空）
  private func paddedSegments(for url: URL) -> [Segment] {
    guard let state = videoStates[url], !state.segments.isEmpty else { return [] }
    let input = SegmentComputer.Input(
      segments: state.segments,
      totalDuration: state.audioDuration ?? (state.segments.last?.endTime ?? 0),
      filterSilent: config.filterSilent,
      splitBySentence: config.splitBySentence,
      maxCharsPerSegment: config.maxCharsPerSegment,
      leftPadMs: config.leftPadMs,
      rightPadMs: config.rightPadMs,
      effectFilterFillerWords: config.effectFilterFillerWords,
      fillerWords: config.effectFillerWords,
      dictionaryEntries: config.voiceToTextCustomDictionary,
      removedSegmentIDs: state.removedProcessedSegmentIDs,
      processedTranslations: state.processedTranslations
    )
    return SegmentComputer.compute(input)
  }

  @MainActor
  private func applyManualSegmentEdit(
    displaySegment: SegmentsPanelView.DisplaySeg,
    newText: String
  ) {
    guard let url = activeVideoURL,
      let videoState = videoStates[url]
    else {
      statusText = String(localized: "Select a video before editing subtitles.", comment: "AI Cut status message")
      return
    }

    var baseSegments = videoState.segments
    guard !baseSegments.isEmpty else { return }

    guard let index = findSegmentIndex(for: displaySegment, in: baseSegments) else { return }

    let originalSegment = baseSegments[index]
    if originalSegment.text == newText {
      return
    }

    baseSegments[index] = Segment(
      id: originalSegment.id,
      startTime: originalSegment.startTime,
      endTime: originalSegment.endTime,
      text: newText,
      words: originalSegment.words,
      confidence: originalSegment.confidence,
      speakerId: originalSegment.speakerId,
      translation: originalSegment.translation
    )

    // Preserve translations and effects: segments.didSet clears them on any mutation,
    // but a manual text-only edit must not erase AI-generated translations/effects.
    let savedTranslations = videoState.processedTranslations
    let savedEffects = videoState.segmentEffects
    let savedEffectConfig = videoState.lastAppliedEffectConfiguration
    videoState.segments = baseSegments
    if !savedTranslations.isEmpty {
      videoState.processedTranslations = savedTranslations
    }
    if !savedEffects.isEmpty {
      videoState.segmentEffects = savedEffects
      videoState.lastAppliedEffectConfiguration = savedEffectConfig
    }
    processedSegments = currentSegments  // update video player subtitles
    markSegmentsChanged(for: url, state: videoState)
    statusText = String(localized: "Updated subtitle at \(formatTimecode(originalSegment.startTime)).", comment: "AI Cut status message")
  }

  @MainActor
  private func applyManualTranslationEdit(
    displaySegment: SegmentsPanelView.DisplaySeg,
    newText: String?
  ) {
    guard let url = activeVideoURL,
      let videoState = videoStates[url]
    else {
      statusText = String(localized: "Select a video before editing translation.", comment: "AI Cut status message")
      return
    }

    let targetSegment = displaySegment.segment
    let segmentId = targetSegment.id
    let trimmed = (newText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed.isEmpty {
      if videoState.processedTranslations.removeValue(forKey: segmentId) != nil {
        processedSegments = currentSegments  // update video player subtitles
        markTranslationsChanged(for: url, state: videoState)
        statusText = String(localized: "Removed translation at \(formatTimecode(targetSegment.startTime)).", comment: "AI Cut status message")
      }
      return
    }

    let existing = videoState.processedTranslations[segmentId]
    if existing?.text == trimmed { return }

    if var updated = existing {
      updated.text = trimmed
      updated.translatedAt = Date()
      videoState.processedTranslations[segmentId] = updated
    } else {
      let language = config.translationTargetLanguage
      videoState.processedTranslations[segmentId] = SegmentTranslation(text: trimmed, language: language)
    }

    processedSegments = currentSegments  // update video player subtitles
    markTranslationsChanged(for: url, state: videoState)
    statusText = String(localized: "Updated translation at \(formatTimecode(targetSegment.startTime)).", comment: "AI Cut status message")
  }

  @MainActor
  private func deleteSegment(displaySegment: SegmentsPanelView.DisplaySeg) {
    deleteSegment(
      originalStart: displaySegment.originalStart, originalEnd: displaySegment.originalEnd)
  }

  @MainActor
  private func deleteSegment(segment: Segment) {
    deleteSegment(originalStart: segment.startTime, originalEnd: segment.endTime)
  }

  @MainActor
  private func deleteSegment(originalStart: TimeInterval, originalEnd: TimeInterval) {
    let identifier = SegmentIdentifier(startTime: originalStart, endTime: originalEnd)
    deleteProcessedSegment(identifier: identifier, referenceStart: originalStart)
  }

  @MainActor
  private func deleteProcessedSegment(
    identifier: SegmentIdentifier,
    referenceStart: TimeInterval
  ) {
    guard let url = activeVideoURL,
      let videoState = videoStates[url]
    else {
      statusText = String(localized: "Select a video before deleting segments.", comment: "AI Cut status message")
      return
    }

    let processedSegments = paddedSegments(for: url)
    guard processedSegments.contains(where: { SegmentIdentifier(segment: $0) == identifier }) else {
      statusText = String(localized: "Segment already removed.", comment: "AI Cut status message")
      return
    }

    let removed = videoState.applyProcessedDeletion(identifier)
    guard removed else {
      statusText = String(localized: "Segment already removed.", comment: "AI Cut status message")
      return
    }

    markDeletionsChanged(for: url, state: videoState)

    let timecode = formatTimecode(referenceStart)
    statusText = String(localized: "Deleted segment at \(timecode). Press Command+Z to undo.", comment: "AI Cut status message")

    guard let undoManager else { return }
    let statusHandler: (String) -> Void = { message in
      statusText = message
    }
    let transaction = ProcessedSegmentUndoTransaction(
      videoState: videoState,
      identifier: identifier,
      description: timecode,
      undoManager: undoManager,
      statusHandler: statusHandler
    )
    undoManager.registerUndo(withTarget: transaction) { target in
      target.undo()
    }
    undoManager.setActionName("Delete Segment")
  }

  private func findSegmentIndex(
    for displaySegment: SegmentsPanelView.DisplaySeg,
    in segments: [Segment]
  ) -> Int? {
    findSegmentIndex(
      originalStart: displaySegment.originalStart,
      originalEnd: displaySegment.originalEnd,
      in: segments
    )
  }

  private func findSegmentIndex(
    for segment: Segment,
    in segments: [Segment]
  ) -> Int? {
    findSegmentIndex(
      originalStart: segment.startTime,
      originalEnd: segment.endTime,
      in: segments
    )
  }

  private func findSegmentIndex(
    originalStart: TimeInterval,
    originalEnd: TimeInterval,
    in segments: [Segment]
  ) -> Int? {
    let tolerance: TimeInterval = 0.05
    if let exact = segments.firstIndex(where: {
      abs($0.startTime - originalStart) < tolerance
        && abs($0.endTime - originalEnd) < tolerance
    }) {
      return exact
    }

    return segments.enumerated().min { lhs, rhs in
      let lhsDelta =
        abs(lhs.element.startTime - originalStart)
        + abs(lhs.element.endTime - originalEnd)
      let rhsDelta =
        abs(rhs.element.startTime - originalStart)
        + abs(rhs.element.endTime - originalEnd)
      return lhsDelta < rhsDelta
    }?.offset
  }

  private final class ProcessedSegmentUndoTransaction: @unchecked Sendable {
    weak var videoState: VideoState?
    let identifier: SegmentIdentifier
    let description: String
    weak var undoManager: UndoManager?
    let statusHandler: (String) -> Void

    init(
      videoState: VideoState,
      identifier: SegmentIdentifier,
      description: String,
      undoManager: UndoManager,
      statusHandler: @escaping (String) -> Void
    ) {
      self.videoState = videoState
      self.identifier = identifier
      self.description = description
      self.undoManager = undoManager
      self.statusHandler = statusHandler
    }

    func undo() {
      guard let state = videoState else { return }
      Task { @MainActor in
        if state.revokeProcessedDeletion(identifier) {
          statusHandler("Restored segment at \(description).")
        }
        registerRedo()
      }
    }

    func redo() {
      guard let state = videoState else { return }
      Task { @MainActor in
        if state.applyProcessedDeletion(identifier) {
          statusHandler("Deleted segment at \(description). Press Command+Z to undo.")
        }
        registerUndo()
      }
    }

    @MainActor
    private func registerUndo() {
      guard let undoManager else { return }
      let transaction = ProcessedSegmentUndoTransaction(
        videoState: videoState!,
        identifier: identifier,
        description: description,
        undoManager: undoManager,
        statusHandler: statusHandler
      )
      undoManager.registerUndo(withTarget: transaction) { target in
        target.undo()
      }
      undoManager.setActionName("Delete Segment")
    }

    @MainActor
    private func registerRedo() {
      guard let undoManager else { return }
      let transaction = ProcessedSegmentUndoTransaction(
        videoState: videoState!,
        identifier: identifier,
        description: description,
        undoManager: undoManager,
        statusHandler: statusHandler
      )
      undoManager.registerUndo(withTarget: transaction) { target in
        target.redo()
      }
      undoManager.setActionName("Delete Segment")
    }
  }

  private func formatTimecode(_ time: TimeInterval) -> String {
    guard time.isFinite else { return "0:00.000" }
    let totalMilliseconds = Int((time * 1000).rounded())
    let minutes = totalMilliseconds / 60000
    let seconds = (totalMilliseconds % 60000) / 1000
    let milliseconds = totalMilliseconds % 1000
    return String(format: "%d:%02d.%03d", minutes, seconds, milliseconds)
  }

  /// 自动打开 Final Cut Pro 并导入 FCPXML 项目
  private func openInFinalCutPro(fcpxmlURL: URL, sessionGeneration: UInt64) async {
    do {
      // 检查 Final Cut Pro 是否已安装
      let finalCutProPath = "/Applications/Final Cut Pro.app"
      if !FileManager.default.fileExists(atPath: finalCutProPath) {
        await MainActor.run {
          applyIfCurrentAICutSession(sessionGeneration) {
            statusText = String(localized: "Final Cut Pro not found. FCPXML exported successfully.", comment: "AI Cut status message")
          }
        }
        return
      }

      // 使用 NSWorkspace 直接用 Final Cut Pro 打开 FCPXML 文件
      let workspace = NSWorkspace.shared
      let finalCutProURL = URL(fileURLWithPath: finalCutProPath)

      // 配置打开选项
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true  // 激活应用程序窗口
      configuration.addsToRecentItems = true  // 添加到最近使用项目

      // 异步打开文件
      try await workspace.open(
        [fcpxmlURL],
        withApplicationAt: finalCutProURL,
        configuration: configuration)

      await MainActor.run {
        applyIfCurrentAICutSession(sessionGeneration) {
          statusText = String(localized: "Final Cut Pro opened with project: \(fcpxmlURL.lastPathComponent)", comment: "AI Cut status message")
        }
      }
    } catch {
      await MainActor.run {
        applyIfCurrentAICutSession(sessionGeneration) {
          statusText =
            String(localized: "Failed to open Final Cut Pro: \(error.localizedDescription). FCPXML exported successfully.", comment: "AI Cut status message")
        }
      }
    }
  }

  // MARK: - AI Correction

  private func resolvedCorrectionPrompt(customPrompt: String?) -> String? {
    if let customPrompt,
      !customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let defaultPrompt = config.aiDefaultCorrectionPrompt
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return defaultPrompt.isEmpty ? nil : defaultPrompt
  }

  private func correctAllTranscriptionsWithAI(customPrompt: String? = nil) {
    let sessionGeneration = currentAICutSessionGeneration()
    Task { @MainActor in
      // 检查 AI 配置
      guard config.aiEnabled else {
        statusText = String(localized: "AI features are disabled. Please enable in configuration.", comment: "AI Cut status message")
        return
      }

      guard let apiKey = config.aiProviderKeys[config.selectedAIProvider],
        !apiKey.isEmpty
      else {
        statusText = String(localized: "No API key configured for \(config.selectedAIProvider.displayName)", comment: "AI Cut status message")
        return
      }

      // 获取所有有转录的视频
      let transcribedURLs = selectedVideoURLs.filter { url in
        videoStates[url]?.segments.isEmpty == false
      }

      guard !transcribedURLs.isEmpty else {
        statusText = String(localized: "No transcriptions to correct. Please transcribe some videos first.", comment: "AI Cut status message")
        return
      }

      guard AICutSessionGuard.shouldApplyUpdate(
        capturedGeneration: sessionGeneration,
        activeGeneration: aiCutSessionGeneration
      ) else { return }

      applyIfCurrentAICutSession(sessionGeneration) {
        isAICorrecting = true
        statusText = String(localized: "AI correcting transcriptions using \(config.selectedAIProvider.displayName)...", comment: "AI Cut status message")
      }
      let totalVideos = transcribedURLs.count
      var correctedCount = 0
      var failedVideos: [String] = []
      var allCorrectedTexts: [String] = []

      let promptToUse = resolvedCorrectionPrompt(customPrompt: customPrompt)
      let correctionProvider = config.selectedAIProvider
      let correctionLanguage = config.language
      let correctionModel = config.aiModel(for: correctionProvider)
      let correctionSystemPrompt = AppConfiguration.defaultSystemCorrectionPrompt

      for (index, url) in transcribedURLs.enumerated() {
        guard let videoState = videoStates[url] else { continue }

        // 在第一次 AI 纠错前保存原始转录
        if videoState.originalSegments.isEmpty {
          videoState.saveAsOriginal()
        }

        applyIfCurrentAICutSession(sessionGeneration) {
          statusText = String(localized: "AI correcting [\(index + 1)/\(totalVideos)]: \(url.lastPathComponent)...", comment: "AI Cut status message")
        }

        // 准备批量纠错的数据
        var segmentsToCorrect: [(index: Int, segment: Segment)] = []
        let inputSegments = videoState.segments
        var appliedCorrections: [AICorrector.CorrectionItem] = []
        var correctedSegments: [Segment] = inputSegments

        // 收集需要纠错的 segment
        for (segIndex, segment) in videoState.segments.enumerated() {
          let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
          if !trimmed.isEmpty && trimmed != "..." && trimmed != "[*]" {
            segmentsToCorrect.append((segIndex, segment))
          }
        }

        // 如果没有需要纠错的内容,跳过
        guard !segmentsToCorrect.isEmpty else {
          correctedCount += 1
          continue
        }

        do {
          // 使用 diff 模式纠错：LLM 只返回需要修改的词/短语
          let textsToCorrect = segmentsToCorrect.map { $0.segment.text }
          let (correctedTexts, corrections) = try await AICorrector.correctBatchDiff(
            textsToCorrect,
            provider: correctionProvider,
            model: correctionModel,
            systemPrompt: correctionSystemPrompt,
            apiKey: apiKey,
            language: correctionLanguage,
            customPrompt: promptToUse,
            openAIBaseURL: config.aiOpenAIEndpoint
          )

          guard AICutSessionGuard.shouldApplyUpdate(
            capturedGeneration: sessionGeneration,
            activeGeneration: aiCutSessionGeneration
          ), videoStates[url] === videoState, videoState.segments == inputSegments else {
            applyIfCurrentAICutSession(sessionGeneration) { isAICorrecting = false }
            return
          }
          appliedCorrections = corrections

          // 将纠正后的文本应用回 segment
          for (arrayIndex, (segIndex, originalSegment)) in segmentsToCorrect.enumerated() {
            if arrayIndex < correctedTexts.count {
              correctedSegments[segIndex] = Segment(
                id: originalSegment.id,
                startTime: originalSegment.startTime,
                endTime: originalSegment.endTime,
                text: correctedTexts[arrayIndex],
                words: originalSegment.words,
                confidence: originalSegment.confidence,
                speakerId: originalSegment.speakerId,
                translation: originalSegment.translation
              )
            }
          }

          // Only collect corrected terms for dictionary extraction
          allCorrectedTexts.append(contentsOf: corrections.map(\.corrected))
          correctedCount += 1

        } catch {
          // 纠错失败时保留原始文本
          failedVideos.append(url.lastPathComponent)
          print("⚠️ Failed to correct \(url.lastPathComponent): \(error.localizedDescription)")
        }

        // 更新视频状态 (already on @MainActor — no need for MainActor.run)
        applyIfCurrentAICutSession(sessionGeneration) {
          if videoStates[url] == nil {
            videoStates[url] = VideoState()
          }
          videoStates[url]?.segments = correctedSegments
          videoStates[url]?.removedProcessedSegmentIDs.removeAll()
          if url == activeVideoURL {
            processedSegments = currentSegments
          }
          if let state = videoStates[url] {
            markSegmentsChanged(for: url, state: state)
            persistAICorrectionEvidence(appliedCorrections, segments: segmentsToCorrect.map { $0.segment },
              state: state, provider: correctionProvider, model: correctionModel, language: correctionLanguage)
          }
        }
      }

      applyIfCurrentAICutSession(sessionGeneration) {
        isAICorrecting = false

        if failedVideos.isEmpty {
          statusText =
            String(localized: "AI correction completed! ✨ Successfully corrected \(correctedCount) video(s).", comment: "AI Cut status message")
        } else {
          let failedList = failedVideos.joined(separator: ", ")
          statusText =
            String(localized: "AI correction finished. \(correctedCount) succeeded, \(failedVideos.count) had errors: \(failedList)", comment: "AI Cut status message: AI correction done with counts and failed file names")
          aiErrorMessage = String(
            localized: "AI correction failed for: \(failedList). Please check your API key and network connection.",
            comment: "AI Cut error alert message for batch correction failures"
          )
        }
      }

      // 直接使用纠错结果作为词典建议
      if !allCorrectedTexts.isEmpty {
        dictionaryTermsFromCorrection = allCorrectedTexts
        showCorrectionDictionarySheet = true
      }
    }
  }

  /// AI 纠错当前激活的视频
  private func correctTranscriptionWithAI(url: URL, customPrompt: String? = nil) {
    let sessionGeneration = currentAICutSessionGeneration()
    Task { @MainActor in
      // 检查 AI 配置
      guard config.aiEnabled else {
        statusText = String(localized: "AI features are disabled. Please enable in configuration.", comment: "AI Cut status message")
        return
      }

      guard let apiKey = config.aiProviderKeys[config.selectedAIProvider],
        !apiKey.isEmpty
      else {
        statusText = String(localized: "No API key configured for \(config.selectedAIProvider.displayName)", comment: "AI Cut status message")
        return
      }

      // 检查是否有转录数据
      guard let videoState = videoStates[url],
        !videoState.segments.isEmpty
      else {
        statusText = String(localized: "No transcription to correct. Please transcribe the video first.", comment: "AI Cut status message")
        return
      }

      // 在第一次 AI 纠错前保存原始转录
      if videoState.originalSegments.isEmpty {
        videoState.saveAsOriginal()
      }

      guard AICutSessionGuard.shouldApplyUpdate(
        capturedGeneration: sessionGeneration,
        activeGeneration: aiCutSessionGeneration
      ) else { return }

      applyIfCurrentAICutSession(sessionGeneration) {
        isAICorrecting = true
        statusText =
          String(localized: "AI correcting \(url.lastPathComponent) using \(config.selectedAIProvider.displayName)...", comment: "AI Cut status message")
      }
      let promptToUse = resolvedCorrectionPrompt(customPrompt: customPrompt)
      let correctionProvider = config.selectedAIProvider
      let correctionLanguage = config.language
      let correctionModel = config.aiModel(for: correctionProvider)

      // 准备批量纠错的数据
      var segmentsToCorrect: [(index: Int, segment: Segment)] = []
      let inputSegments = videoState.segments
      var appliedCorrections: [AICorrector.CorrectionItem] = []
      var correctedSegments: [Segment] = inputSegments
      var hasErrors = false
      var correctedTextForDictionary: [String]? = nil

      // 收集需要纠错的 segment
      for (segIndex, segment) in videoState.segments.enumerated() {
        let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != "..." && trimmed != "[*]" {
          segmentsToCorrect.append((segIndex, segment))
        }
      }

      // 如果有需要纠错的内容
      if !segmentsToCorrect.isEmpty {
        do {
          // 使用 diff 模式纠错：LLM 只返回需要修改的词/短语
          let textsToCorrect = segmentsToCorrect.map { $0.segment.text }
          let (correctedTexts, corrections) = try await AICorrector.correctBatchDiff(
            textsToCorrect,
            provider: correctionProvider,
            model: correctionModel,
            systemPrompt: AppConfiguration.defaultSystemCorrectionPrompt,
            apiKey: apiKey,
            language: correctionLanguage,
            customPrompt: promptToUse,
            openAIBaseURL: config.aiOpenAIEndpoint
          )

          guard AICutSessionGuard.shouldApplyUpdate(
            capturedGeneration: sessionGeneration,
            activeGeneration: aiCutSessionGeneration
          ), videoStates[url] === videoState, videoState.segments == inputSegments else {
            applyIfCurrentAICutSession(sessionGeneration) { isAICorrecting = false }
            return
          }
          appliedCorrections = corrections

          // 将纠正后的文本应用回 segment
          for (arrayIndex, (segIndex, originalSegment)) in segmentsToCorrect.enumerated() {
            if arrayIndex < correctedTexts.count {
              correctedSegments[segIndex] = Segment(
                id: originalSegment.id,
                startTime: originalSegment.startTime,
                endTime: originalSegment.endTime,
                text: correctedTexts[arrayIndex],
                words: originalSegment.words,
                confidence: originalSegment.confidence,
                speakerId: originalSegment.speakerId,
                translation: originalSegment.translation
              )
            }
          }

          // Only extract dictionary terms if AI found actual corrections
          if !corrections.isEmpty {
            correctedTextForDictionary = corrections.map(\.corrected)
          }

        } catch {
          // 纠错失败时保留原始文本
          hasErrors = true
          let errorDesc = error.localizedDescription
          print("⚠️ Failed to correct \(url.lastPathComponent): \(errorDesc)")
          aiErrorMessage = String(
            localized: "AI correction failed for \(url.lastPathComponent): \(errorDesc)",
            comment: "AI Cut error alert message"
          )
        }
      }

      // 更新视频状态 (already on @MainActor — no need for MainActor.run)
      applyIfCurrentAICutSession(sessionGeneration) {
        if videoStates[url] == nil {
          videoStates[url] = VideoState()
        }
        videoStates[url]?.segments = correctedSegments
        videoStates[url]?.removedProcessedSegmentIDs.removeAll()
        processedSegments = currentSegments  // force UI refresh after text correction
        if let state = videoStates[url] {
          markSegmentsChanged(for: url, state: state)
          persistAICorrectionEvidence(appliedCorrections, segments: segmentsToCorrect.map { $0.segment },
            state: state, provider: correctionProvider, model: correctionModel, language: correctionLanguage)
        }

        isAICorrecting = false

        if hasErrors {
          statusText = String(localized: "AI correction finished for \(url.lastPathComponent) with some errors. ⚠️", comment: "AI Cut status message")
        } else {
          statusText = String(localized: "AI correction completed for \(url.lastPathComponent)! ✨", comment: "AI Cut status message")
        }
      }

      // 直接使用纠错结果作为词典建议（不再需要额外的 AI 调用）
      if let terms = correctedTextForDictionary, !terms.isEmpty {
        dictionaryTermsFromCorrection = terms
        showCorrectionDictionarySheet = true
      }
    }
  }

  @MainActor
  private func persistAICorrectionEvidence(
    _ corrections: [AICorrector.CorrectionItem], segments: [Segment], state: VideoState,
    provider: AIProvider, model: String, language: Language
  ) {
    guard !corrections.isEmpty, let sessionID = state.historySessionID else { return }
    do {
      try historyRuntime.recordFileCorrections(corrections, segments: segments, for: sessionID,
        provider: provider.rawValue, model: model, language: language.rawValue)
    } catch {
      aiErrorMessage = String(format: String(localized:
        "AI text was applied, but correction history could not be saved: %@."), error.localizedDescription)
    }
  }

  // MARK: - Restore Original Transcription

  /// Extracts domain terms from corrected text in the background and shows the review sheet.
  /// Silently no-ops if AI is not configured or no terms are found.
  @MainActor
  private func extractAndShowDictionaryTerms(from text: String) async {
    guard config.aiEnabled,
      let apiKey = config.aiProviderKeys[config.selectedAIProvider],
      !apiKey.isEmpty,
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }
    do {
      let terms = try await AICorrector.extractDictionaryTerms(
        from: text,
        provider: config.selectedAIProvider,
        model: config.aiModel(for: config.selectedAIProvider),
        apiKey: apiKey,
        openAIBaseURL: config.aiOpenAIEndpoint
      )
      if !terms.isEmpty {
        dictionaryTermsFromCorrection = terms
        showCorrectionDictionarySheet = true
      }
    } catch {
      print("⚠️ Dictionary extraction after AI correction failed: \(error.localizedDescription)")
    }
  }

  private func restoreOriginalTranscription() {
    guard let url = activeVideoURL,
      let videoState = videoStates[url],
      videoState.canRestore
    else {
      statusText = String(localized: "No original transcription to restore", comment: "AI Cut status message")
      return
    }

    videoState.restoreOriginal()
    processedSegments = currentSegments
    if let sessionID = videoState.historySessionID {
      do { try historyRuntime.markCorrections(for: sessionID, status: .reverted) }
      catch {
        aiErrorMessage = String(format: String(localized:
          "Correction history status could not be saved: %@."), error.localizedDescription)
      }
    }
    markSegmentsChanged(for: url, state: videoState)
    statusText = String(localized: "Restored original transcription for \(url.lastPathComponent)", comment: "AI Cut status message")
  }

  private func applyEffectEnhancement() {
    guard let url = activeVideoURL else {
      statusText = String(localized: "Select a video before applying AI Enhance.", comment: "AI Cut status message")
      return
    }
    guard let videoState = videoStates[url], videoState.segments.isEmpty == false else {
      statusText = String(localized: "No transcription available for the selected video.", comment: "AI Cut status message")
      return
    }

    let configuration = config.effectConfiguration
    let segments = paddedSegments(for: url)
    guard !segments.isEmpty else {
      statusText = String(localized: "No segments available after processing.", comment: "AI Cut status message")
      return
    }
    let provider = config.selectedAIProvider
    let apiKey = config.aiProviderKeys[provider]
    let aiEnabled = config.aiEnabled
    let language = config.language
    let context = SegmentEffectGenerator.KeywordExtractionContext(
      isEnabled: aiEnabled,
      provider: provider,
      apiKey: apiKey,
      language: language,
      maxKeywords: 4,
      openAIEndpoint: config.aiOpenAIEndpoint,
      model: config.aiModel(for: provider),
      systemPrompt: AppConfiguration.defaultSystemKeywordPrompt
    )
    let targetState = videoState
    let sessionGeneration = currentAICutSessionGeneration()

    statusText = String(localized: "Applying AI Enhance...", comment: "AI Cut status message")
    isAIEnhancing = true

    Task(priority: .userInitiated) {
      let result = await SegmentEffectGenerator.generateEffects(
        for: segments,
        configuration: configuration,
        keywordContext: context
      )

      await MainActor.run {
        applyIfCurrentAICutSession(sessionGeneration) {
          isAIEnhancing = false
          targetState.segmentEffects = result.effects
          targetState.lastAppliedEffectConfiguration = configuration
          effectsVersion &+= 1  // force re-render of editorWindowContent with updated effects

          if configuration.extractHighlights {
            if result.usedAI {
              statusText = String(localized: "AI Enhance applied — highlights generated via \(provider.displayName).", comment: "AI Cut status message")
            } else if let error = result.errorMessage {
              statusText = String(localized: "AI Enhance failed: \(error)", comment: "AI Cut status message")
              aiErrorMessage = String(
                localized: "AI Enhance failed: \(error)",
                comment: "AI Cut error alert message for enhance failure"
              )
            } else if context.isEnabled && !context.canUseAI {
              statusText = String(localized: "AI Enhance skipped — API key missing for \(provider.displayName).", comment: "AI Cut status message")
            } else if !context.isEnabled {
              statusText = String(localized: "AI Enhance applied — enable AI to extract highlights.", comment: "AI Cut status message")
            } else {
              statusText = String(localized: "AI Enhance completed — no keywords returned.", comment: "AI Cut status message")
            }
          } else if configuration.enableScaling {
            statusText = String(localized: "AI Enhance applied — scaling updated.", comment: "AI Cut status message")
          } else {
            statusText = String(localized: "AI Enhance applied with default settings.", comment: "AI Cut status message")
          }
        }
      }
    }
  }

  private func translateActiveSegments() {
    guard let url = activeVideoURL else {
      revealStatusPanel()
      statusText = String(localized: "Select a video before translating.", comment: "AI Cut status message")
      return
    }

    let segments = paddedSegments(for: url)
    guard !segments.isEmpty else {
      revealStatusPanel()
      statusText = String(localized: "No segments to translate.", comment: "AI Cut status message")
      return
    }

    if isTranslating {
      revealStatusPanel()
      statusText = String(localized: "Translation already in progress.", comment: "AI Cut status message")
      return
    }

    guard AppleTranslationAvailability.isRuntimeSupported else {
      revealStatusPanel()
      statusText = AppleTranslationAvailability.minimumRequirementMessage
      return
    }

    guard #available(macOS 15.0, *) else {
      revealStatusPanel()
      statusText = AppleTranslationAvailability.minimumRequirementMessage
      return
    }

    let sessionGeneration = currentAICutSessionGeneration()
    applyIfCurrentAICutSession(sessionGeneration) {
      revealStatusPanel()
      isTranslating = true
      statusText =
        String(localized: "Translating \(segments.count) segments to \(config.translationTargetLanguage.displayName)...", comment: "AI Cut status message")
    }

    let sourceLanguage = config.language
    let targetLanguage = config.translationTargetLanguage

    if #available(macOS 26.0, *) {
      let request = AICutTranslationRequest(
        url: url,
        segments: segments,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage
      )
      activeTranslationTask?.cancel()
      activeTranslationTask = Task(priority: .userInitiated) { @MainActor in
        await runDirectTranslation(request: request, sessionGeneration: sessionGeneration)
      }
      return
    }

    pendingTranslationRequest = PendingTranslationRequest(
      url: url,
      segments: segments,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      sessionGeneration: sessionGeneration
    )
    refreshTranslationConfiguration(source: sourceLanguage, target: targetLanguage)
  }

  @available(macOS 15.0, *)
  @MainActor
  private func refreshTranslationConfiguration(source: Language, target: Language) {
    var configuration = TranslationSession.Configuration()
    configuration.source = Locale.Language(identifier: source.rawValue)
    configuration.target = Locale.Language(identifier: target.rawValue)
    configuration.invalidate()
    translationConfigurationStorage = configuration
  }

  @available(macOS 26.0, *)
  @MainActor
  private func runDirectTranslation(
    request: AICutTranslationRequest,
    sessionGeneration: UInt64
  ) async {
    let executor = AICutTranslationExecutor { request, progress in
      try await AppleTranslator.translateSegments(
        request.segments,
        from: request.sourceLanguage,
        to: request.targetLanguage,
        progress: progress
      )
    }

    defer {
      applyIfCurrentAICutSession(sessionGeneration) {
        isTranslating = false
        activeTranslationTask = nil
      }
    }

    do {
      if videoStates[request.url] == nil {
        videoStates[request.url] = VideoState()
      }
      guard let state = videoStates[request.url] else { return }

      try await executor.execute(request: request, state: state) { status in
        applyIfCurrentAICutSession(sessionGeneration) {
          if isTranslating {
            statusText = status
          }
        }
      }
      markTranslationsChanged(for: request.url, state: state)
    } catch is CancellationError {
      applyIfCurrentAICutSession(sessionGeneration) {
        statusText = String(localized: "Translation cancelled.", comment: "AI Cut status message")
      }
    } catch let translationError as AppleTranslationError {
      applyIfCurrentAICutSession(sessionGeneration) {
        statusText = translationError.localizedDescription
      }
    } catch {
      applyIfCurrentAICutSession(sessionGeneration) {
        statusText = String(
          localized: "Translation failed: \(error.localizedDescription)",
          comment: "AI Cut status message"
        )
      }
    }
  }

  @available(macOS 15.0, *)
  @MainActor
  private func runPendingTranslation(using session: TranslationSession) async {
    guard let request = pendingTranslationRequest else { return }

    defer {
      pendingTranslationRequest = nil
      translationConfigurationStorage = nil
      applyIfCurrentAICutSession(request.sessionGeneration) {
        isTranslating = false
      }
    }

    do {
      let translations = try await AppleTranslator.translateSegments(
        request.segments,
        using: session,
        from: request.sourceLanguage,
        to: request.targetLanguage,
        progress: { completed, total in
          applyIfCurrentAICutSession(request.sessionGeneration) {
            if isTranslating {
              statusText = String(localized: "Translating \(completed)/\(total) segments...", comment: "AI Cut status message")
            }
          }
        }
      )

      applyIfCurrentAICutSession(request.sessionGeneration) {
        if videoStates[request.url] == nil { videoStates[request.url] = VideoState() }
        if let state = videoStates[request.url] {
          state.applyTranslations(translations, for: request.segments)
          state.translationSignature = SegmentSignature.compute(for: request.segments)
          state.lastTranslatedLanguage = request.targetLanguage
          markTranslationsChanged(for: request.url, state: state)
        }
        statusText =
          String(localized: "Translation complete: \(translations.count)/\(request.segments.count) segments translated to \(request.targetLanguage.displayName).", comment: "AI Cut status message")
      }
    } catch is CancellationError {
      applyIfCurrentAICutSession(request.sessionGeneration) {
        statusText = String(localized: "Translation cancelled.", comment: "AI Cut status message")
      }
    } catch let translationError as AppleTranslationError {
      applyIfCurrentAICutSession(request.sessionGeneration) {
        statusText = translationError.localizedDescription
      }
    } catch {
      applyIfCurrentAICutSession(request.sessionGeneration) {
        statusText = String(localized: "Translation failed: \(error.localizedDescription)", comment: "AI Cut status message")
      }
    }
  }

  private func revealStatusPanel() {
    UserDefaults.standard.set(true, forKey: AICutUserDefaultsKeys.statusPanelVisible)
  }
}

private struct AICutWindowSyncBridge: NSViewRepresentable {
  @ObservedObject var coordinator: AICutWindowCoordinator

  let phase: AICutFlowPhase
  let importSetupContent: AnyView
  let progressContent: AnyView
  let progressCancelAction: () -> Void
  let editorContent: AnyView
  let editorCloseAction: () -> Void

  func makeNSView(context: Context) -> NSView {
    NSView(frame: .zero)
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    switch phase {
    case .landing:
      // Window was created with alphaValue = 0 — leave it invisible so SwiftUI
      // lifecycle (.task) can still fire without the window appearing on screen.
      coordinator.closeImportSetupWindow()
      coordinator.closeProgressWindow()
    case .importSetup:
      // Present import setup as a standalone window; host remains invisible.
      coordinator.presentImportSetupWindow(content: importSetupContent)
      coordinator.closeProgressWindow()
    case .transcribing, .readyToEdit:
      // Hide the host window; the progress window takes over.
      coordinator.closeImportSetupWindow()
      nsView.window?.orderOut(nil)
      coordinator.presentProgressWindow(
        content: progressContent,
        onCancelRequest: progressCancelAction
      )
    case .editing:
      // Keep the host window hidden; the editor window is active.
      coordinator.closeImportSetupWindow()
      nsView.window?.orderOut(nil)
      coordinator.closeProgressWindow()
      coordinator.updateEditorWindow(
        content: editorContent,
        onCloseRequest: editorCloseAction
      )
    }
  }
}

enum AICutImportGuard {
  @MainActor
  static func blockingMessage(
    phase: AICutFlowPhase,
    hasPendingTranscriptionTask: Bool
  ) -> String? {
    if phase == .transcribing || phase == .readyToEdit {
      return String(localized: "Finish or cancel the current AI Cut import batch before starting another one.", comment: "Blocker: batch transcription already in progress")
    }

    if phase == .editing {
      return String(localized: "Close the current AI Cut editor before importing more videos.", comment: "Blocker: editor already open")
    }

    if hasPendingTranscriptionTask {
      return String(localized: "Please wait for the current AI Cut transcription to finish cancelling before starting another import.", comment: "Blocker: transcription cancellation in progress")
    }

    return nil
  }
}

enum AICutTranscriptionTaskGuard {
  static func shouldClearActiveTask(
    finishedGeneration: UInt64,
    activeGeneration: UInt64
  ) -> Bool {
    finishedGeneration == activeGeneration
  }
}

enum AICutSessionGuard {
  static func shouldApplyUpdate(
    capturedGeneration: UInt64,
    activeGeneration: UInt64
  ) -> Bool {
    capturedGeneration == activeGeneration
  }
}

enum AICutModelPreparationStatus {
  static func message(for progress: ModelDownloadProgress) -> String {
    if let eta = progress.estimatedTimeRemaining, eta > 0 {
      let minutes = Int(eta) / 60
      let seconds = Int(eta) % 60
      if minutes > 0 {
        return String(localized: "\(progress.currentStep) (ETA: \(minutes)m \(seconds)s)", comment: "Model preparation progress with ETA in minutes and seconds; %@ is step name")
      }
      return String(localized: "\(progress.currentStep) (ETA: \(seconds)s)", comment: "Model preparation progress with ETA in seconds; %@ is step name")
    }
    return progress.currentStep
  }
}

enum AICutTranscriptionFailureStatus {
  static func singleMessage(for error: Error) -> String {
    String(localized: "Transcription failed: \(error.localizedDescription)", comment: "Error: single-video transcription failed; %@ is the error description")
  }

  static func batchMessage(for error: Error) -> String {
    String(localized: "Batch transcription failed: \(error.localizedDescription)", comment: "Error: batch transcription failed; %@ is the error description")
  }
}

private actor ProgressThrottle {
  private var lastReportedProgress: Float = 0

  func shouldReport(_ newProgress: Float) -> Bool {
    if newProgress < lastReportedProgress {
      lastReportedProgress = newProgress
      return true
    }

    if newProgress >= 0.99 || (newProgress - lastReportedProgress) >= 0.05 {
      lastReportedProgress = newProgress
      return true
    }

    return false
  }
}

#Preview {
  AICutView(
    selectedVideoURLs: .constant([]),
    activeVideoURL: .constant(nil),
    videoStates: .constant([:]),
    isTranscribing: .constant(false),
    isExporting: .constant(false),
    statusText: .constant("Please select a video file to get started"),
    isInitializingModel: .constant(false),
    modelDownloadProgress: .constant(nil),
    batchTranscriptionProgress: .constant(nil)
  )
  .environmentObject(AppConfiguration.shared)
  .environmentObject(SecurityScopedURLAccessManager())
}
