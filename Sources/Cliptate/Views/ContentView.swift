import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

enum AppSection: String, CaseIterable, Identifiable {
  case aiCut = "AI Cut"
  case voiceToText = "Voice To Text"
  case ttsStudio = "Text To Sound"
  case models = "Models"
  case history = "History"
  case dictionary = "Dictionary"
  case permissions = "Permissions"
  case pro = "Pro"
  case setting = "Setting"

  var id: String { rawValue }

  var label: LocalizedStringKey {
    switch self {
    case .permissions: return "Getting Started"
    default: return LocalizedStringKey(rawValue)
    }
  }

  var icon: String {
    switch self {
    case .aiCut: return "waveform"
    case .voiceToText: return "mic"
    case .history: return "clock.fill"
    case .ttsStudio: return "waveform.badge.mic"
    case .models: return "square.and.arrow.down"
    case .setting: return "sparkles"
    case .dictionary: return "text.book.closed"
    case .permissions: return "shield.lefthalf.filled"
    case .pro: return "crown"
    }
  }

  var description: String {
    switch self {
    case .aiCut: return String(localized: "Intelligent Video Editing", comment: "AI Cut sidebar description")
    case .voiceToText: return String(localized: "Real-time dictation", comment: "Voice To Text sidebar description")
    case .history: return String(localized: "Transcript archives", comment: "History sidebar description")
    case .ttsStudio: return String(localized: "Generate narration clips", comment: "TTS Studio sidebar description")
    case .models: return String(localized: "Manage AI models", comment: "Models sidebar description")
    case .setting: return String(localized: "Providers, prompts, startup", comment: "Settings sidebar description")
    case .dictionary: return String(localized: "Manage AI vocabulary", comment: "Dictionary sidebar description")
    case .permissions:
      return String(
        localized: "Permissions and setup guidance",
        comment: "Getting started sidebar description"
      )
    case .pro: return String(localized: "Subscription and benefits", comment: "Pro sidebar description")
    }
  }
}

func visibleAppSections(requiresGettingStarted: Bool) -> [AppSection] {
  AppSection.allCases.filter { requiresGettingStarted || $0 != .permissions }
}

func resolvedAppSection(
  currentSection: AppSection?,
  requiresGettingStarted: Bool,
  autoOpenGettingStarted: Bool = true
) -> AppSection {
  if requiresGettingStarted && autoOpenGettingStarted {
    return .permissions
  }
  if currentSection == .permissions {
    return requiresGettingStarted ? .permissions : .aiCut
  }
  return currentSection ?? (requiresGettingStarted ? .permissions : .aiCut)
}

enum AppNavigationRequestStore {
  private static let pendingSectionKey = "ContentView.pendingSectionRequest"

  static func store(_ section: AppSection, userDefaults: UserDefaults = .standard) {
    userDefaults.set(section.rawValue, forKey: pendingSectionKey)
  }

  static func consume(userDefaults: UserDefaults = .standard) -> AppSection? {
    guard
      let rawValue = userDefaults.string(forKey: pendingSectionKey),
      let section = AppSection(rawValue: rawValue)
    else {
      return nil
    }
    userDefaults.removeObject(forKey: pendingSectionKey)
    return section
  }
}

// Cache transcription results and duration for each video, supporting quick switching between multiple videos
class VideoState: ObservableObject {
  @Published var segments: [Segment] = [] {
    didSet {
      guard segments != oldValue else { return }
      segmentEffects.removeAll()
      lastAppliedEffectConfiguration = nil
      translationSignature = nil
      lastTranslatedLanguage = nil
      processedTranslations.removeAll()
    }
  }
  @Published var originalSegments: [Segment] = []  // 保存原始转录结果
  @Published var audioDuration: TimeInterval? = nil
  @Published var playerViewId: UUID = UUID()  // Used to force VideoPlayerView recreation
  @Published var segmentEffects: [String: SegmentEffectState] = [:]
  @Published var lastAppliedEffectConfiguration: SegmentEffectConfiguration? = nil
  @Published var translationSignature: Int? = nil
  @Published var lastTranslatedLanguage: Language? = nil
  @Published var processedTranslations: [String: SegmentTranslation] = [:]
  @Published var presentationSize: CGSize? = nil
  @Published var removedProcessedSegmentIDs: Set<SegmentIdentifier> = []
  /// Processed segments (after padding, splitting, filler removal, etc.) used for video subtitle rendering.
  /// Updated by AICutView whenever segment processing completes.
  @Published var processedSegments: [Segment] = []
  var historySessionID: UUID? = nil
  let playback: VideoPlaybackCoordinator = .init()  // Immutable reference

  init(segments: [Segment] = [], audioDuration: TimeInterval? = nil) {
    self.segments = segments
    self.originalSegments = segments  // 初始化时保存原始版本
    self.audioDuration = audioDuration
  }

  /// 保存当前 segments 为原始版本
  func saveAsOriginal() {
    originalSegments = segments
    removedProcessedSegmentIDs.removeAll()
  }

  /// 回滚到原始转录结果
  func restoreOriginal() {
    segments = originalSegments
    // 不需要 recreatePlayerView()，VideoPlayerView 会自动响应 segments 变化
    segmentEffects.removeAll()
    lastAppliedEffectConfiguration = nil
    removedProcessedSegmentIDs.removeAll()
  }

  /// Apply translations from a dict (keyed by segment UUID) into processedTranslations.
  func applyTranslations(_ translations: [String: SegmentTranslation], for processedSegments: [Segment]) {
    processedTranslations = translations
  }

  /// Inject translations from a dictionary into segments by matching segment UUID.
  static func injectTranslations(
    _ translations: [String: SegmentTranslation],
    into segments: [Segment]
  ) -> [Segment] {
    guard !translations.isEmpty else { return segments }
    return segments.map { seg in
      guard let t = translations[seg.id] else { return seg }
      return Segment(
        id: seg.id,
        startTime: seg.startTime, endTime: seg.endTime,
        text: seg.text, words: seg.words,
        confidence: seg.confidence, speakerId: seg.speakerId,
        translation: t
      )
    }
  }

  /// Extract embedded translations from segments into processedTranslations dict.
  /// Call after restoring segments from history that have translations embedded.
  func extractTranslationsFromSegments() {
    var extracted: [String: SegmentTranslation] = [:]
    for seg in segments where seg.translation != nil {
      extracted[seg.id] = seg.translation
    }
    if !extracted.isEmpty {
      processedTranslations = extracted
    }
  }

  /// Clear all translations.
  func clearTranslations() {
    processedTranslations.removeAll()
    translationSignature = nil
    lastTranslatedLanguage = nil
  }

  /// 检查是否有原始版本可以回滚
  var canRestore: Bool {
    if !originalSegments.isEmpty && originalSegments != segments {
      return true
    }
    return !removedProcessedSegmentIDs.isEmpty
  }

  func recreatePlayerView() {
    playerViewId = UUID()
  }

  @MainActor
  func applyProcessedDeletion(_ identifier: SegmentIdentifier) -> Bool {
    var current = removedProcessedSegmentIDs
    let (inserted, _) = current.insert(identifier)
    if inserted {
      removedProcessedSegmentIDs = current
    }
    return inserted
  }

  @MainActor
  func revokeProcessedDeletion(_ identifier: SegmentIdentifier) -> Bool {
    var current = removedProcessedSegmentIDs
    guard current.remove(identifier) != nil else { return false }
    removedProcessedSegmentIDs = current
    return true
  }
}

struct ContentView: View {
  @SceneStorage("ContentView.selectedSection") private var selectedSectionStorage: String =
    AppSection.aiCut.rawValue
  @State private var activeVideoURL: URL?
  @State private var selectedVideoURLs: [URL] = []
  @State private var videoStates: [URL: VideoState] = [:]
  @State private var isTranscribing = false
  @State private var isExporting = false
  @State private var batchTranscriptionProgress: (current: Int, total: Int)? = nil
  @State private var statusText = String(localized: "Please select a video file to start", comment: "Initial status message in AI Cut view")
  @State private var isInitializingModel = false
  @State private var modelDownloadProgress: ModelDownloadProgress?

  @EnvironmentObject private var config: AppConfiguration

  @StateObject private var securityScopeManager = SecurityScopedURLAccessManager()
  @StateObject private var permissionStatusManager = PermissionStatusManager.shared
  @ObservedObject private var shortcutTranscriber = VoiceTranscriber.shared
  @ObservedObject private var shortcutState = VoiceShortcutState.shared
  @State private var shortcutPostProcessingTask: Task<Void, Never>?
  @State private var lastCountedShortcutSessionID: UUID?

  var body: some View {
    let selectionBinding = Binding<AppSection?>(
      get: { currentSection },
      set: { newValue in currentSection = newValue }
    )

    NavigationSplitView {
      List(
        visibleAppSections(requiresGettingStarted: permissionStatusManager.requiresGettingStarted),
        selection: selectionBinding
      ) { section in
        HStack(alignment: .center, spacing: 12) {
          Image(systemName: section.icon)
            .font(.title2)
            .foregroundColor(currentSection == section ? .white : .accentColor)
            .frame(width: 28, height: 28)
            .background(
              RoundedRectangle(cornerRadius: 8)
                .fill(
                  currentSection == section ? Color.accentColor : Color.accentColor.opacity(0.1))
            )

          VStack(alignment: .leading, spacing: 2) {
            Text(section.label)
              .font(.headline)
              .fontWeight(.medium)
              .foregroundStyle(.primary)
            Text(section.description)
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .tag(section as AppSection?)
        .contentShape(Rectangle())
        .onTapGesture {
          currentSection = section
        }
        .listRowBackground(
          currentSection == section ? Color.accentColor.opacity(0.1) : Color.clear
        )
        .listRowSeparator(.hidden)
      }
      .navigationTitle("Cliptate")
      .navigationSubtitle("Professional Video Editing Tool")
      .listStyle(.sidebar)
      .background(
        LinearGradient(
          colors: [
            Color.accentColor.opacity(0.05),
            Color.accentColor.opacity(0.02),
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      )
      .navigationSplitViewColumnWidth(min: 0, ideal: 260, max: 360)
    } detail: {
      Group {
        switch currentSection {
        case .aiCut, .none:
          AICutLauncherView()
            .environmentObject(config)
        case .voiceToText:
          VoiceToTextView(transcriber: VoiceTranscriber.shared)
            .environmentObject(config)
        case .history:
          HistoryView()
        case .ttsStudio:
          TTSSynthesisView()
            .environmentObject(config)
        case .models:
          ModelsView()
            .environmentObject(config)
        case .setting:
          AISettingsView()
            .environmentObject(config)
        case .dictionary:
          DictionaryManagerView()
            .environmentObject(config)
        case .permissions:
          PermissionsView(onOpenVoiceToText: { currentSection = .voiceToText })
        case .pro:
          ProHubView()
        }
      }
      .background(Color(NSColor.controlBackgroundColor))
    }
    .navigationSplitViewStyle(.balanced)
    .onReceive(NotificationCenter.default.publisher(for: .openModelsLibrary)) { _ in
      currentSection = .models
    }
    .onReceive(NotificationCenter.default.publisher(for: .openVoiceToText)) { _ in
      currentSection = .voiceToText
    }
    .onReceive(NotificationCenter.default.publisher(for: .openAICutSection)) { _ in
      currentSection = .aiCut
    }
    .onReceive(NotificationCenter.default.publisher(for: .openProSection)) { _ in
      currentSection = .pro
      _ = AppNavigationRequestStore.consume()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) {
      _ in
      permissionStatusManager.refreshAll()
    }
    .onAppear {
      // 注册全局快捷键
      KeyboardShortcutManager.shared.registerDefaultShortcuts()
      KeyboardShortcutManager.shared.bindShortcuts(onEvent: handleGlobalVoiceShortcut)
    }
    .onAppear {
      if let pendingSection = AppNavigationRequestStore.consume() {
        currentSection = pendingSection
      }
      permissionStatusManager.refreshAll()
      syncGettingStartedSection()
    }
    .onAppear {
      securityScopeManager.sync(with: selectedVideoURLs)
    }
    .onChange(of: permissionStatusManager.requiresGettingStarted) { _, _ in
      syncGettingStartedSection(autoOpenGettingStarted: false)
    }
    .onChange(of: selectedVideoURLs) { _, newValue in
      securityScopeManager.sync(with: newValue)
    }
    .onChange(of: shortcutTranscriber.state) { _, newValue in
      if newValue == .idle {
        shortcutFinalizeIfNeeded()
        // Only update stats from ContentView when VoiceToTextView is not active
        // (VoiceToTextView handles its own stats when mounted)
        if currentSection != .voiceToText {
          shortcutUpdateStatsIfNeeded()
        }
      }
    }
    .onChange(of: shortcutTranscriber.isRetranscribing) { _, isRetranscribing in
      // Retranscription fills session text AFTER the idle transition.
      // Retry shortcut finalization and stats persistence once retranscription completes.
      if !isRetranscribing && shortcutTranscriber.state == .idle {
        shortcutFinalizeIfNeeded()
        if currentSection != .voiceToText {
          shortcutUpdateStatsIfNeeded()
        }
      }
    }
    .onChange(of: shortcutState.activeMode) { oldMode, newMode in
      if oldMode != nil && newMode == nil && shortcutTranscriber.state == .idle {
        shortcutFinalizeIfNeeded()
      }
    }
  }
}

extension ContentView {
  private func syncGettingStartedSection(autoOpenGettingStarted: Bool = true) {
    currentSection = resolvedAppSection(
      currentSection: currentSection,
      requiresGettingStarted: permissionStatusManager.requiresGettingStarted,
      autoOpenGettingStarted: autoOpenGettingStarted
    )
  }

  private var currentSection: AppSection? {
    get {
      guard !selectedSectionStorage.isEmpty else { return nil }
      if selectedSectionStorage == "AI Settings" { return .setting }
      return AppSection(rawValue: selectedSectionStorage) ?? .aiCut
    }
    nonmutating set {
      selectedSectionStorage = newValue?.rawValue ?? ""
    }
  }

  private func handleGlobalVoiceShortcut(_ event: KeyboardShortcutManager.ShortcutEvent) {
    let shortcutState = VoiceShortcutState.shared
    switch event.phase {
    case .modeActivated:
      VoiceTranscriber.shared.captureExternalApp()
      shortcutState.activateMode(event.mode)
      // Suppress direct transcript delivery when AI Enhance will post-process the result
      let aiEnhanceActive: Bool = {
        switch event.mode {
        case .dictation: return config.voiceToTextDictationAIEnhanceEnabled && config.aiEnabled
        case .assistant: return config.voiceToTextAssistantAIEnhanceEnabled && config.aiEnabled
        }
      }()
      VoiceTranscriber.shared.deliverTranscriptsDirectly = !aiEnhanceActive

    case .spaceToggle:
      // Space enters hands-free mode in KeyboardShortcutManager.
      // Recording continues uninterrupted — no transcriber start/stop here.
      break

    case .modeDeactivated:
      if shortcutState.phase == .recording {
        shortcutState.stopRecording()
        Task {
          await VoiceTranscriber.shared.stop()
        }
      }
      shortcutState.requestEndSession()

    case .holdRecordingStarted:
      shortcutState.startRecording()
      Task {
        await VoiceTranscriber.shared.start(
          type: config.transcriberType,
          model: config.modelVariant,
          language: config.voiceToTextLanguage
        )
      }

    case .holdRecordingEnded:
      if shortcutState.phase == .recording {
        shortcutState.stopRecording()
        Task {
          await VoiceTranscriber.shared.stop()
        }
      }
      // Session end is handled by .modeDeactivated which follows immediately

    case .escapePressed:
      // Cancel session — stop recording, save to history but no text output
      if shortcutState.phase == .recording {
        shortcutState.stopRecording()
        Task {
          await VoiceTranscriber.shared.stop(reason: .cancelled)
        }
      }
      shortcutState.cancelSession()
    }
  }

  // MARK: - Shortcut session finalization (always-active, independent of VoiceToTextView)

  /// Absorb transcriber text, finalize the shortcut session, and deliver the result.
  /// When VoiceToTextView is the active section it may also run its own finalization,
  /// but `consumePendingResult()` ensures only one consumer wins.
  private func shortcutFinalizeIfNeeded() {
    let shortcutState = VoiceShortcutState.shared
    let transcriber = VoiceTranscriber.shared

    guard transcriber.state == .idle else { return }
    guard contentViewShouldHandleShortcutResult(currentSection: currentSection) else { return }

    // Absorb segment text (deduplicated by VoiceShortcutState)
    shortcutState.absorbSessionTextOnce(
      sessionID: transcriber.session?.id,
      text: transcriber.session?.combinedText ?? ""
    )

    // If still in a mode session, don't finalize yet
    guard shortcutState.activeMode == nil else { return }

    // If a two-phase end was requested, finalize now
    if shortcutState.pendingEndMode != nil {
      shortcutState.finalizeEndSession()
    }

    // Consume the pending result (destructive — only one consumer wins)
    guard let pending = shortcutState.consumePendingResult() else {
      restoreTranscriptDelivery()
      transcriber.dismissOverlay()
      return
    }

    guard !pending.transcript.isEmpty else {
      restoreTranscriptDelivery()
      transcriber.dismissOverlay()
      return
    }

    // Handle result delivery
    switch pending.mode {
    case .dictation:
      shortcutDeliverDictation(transcript: pending.transcript)
    case .assistant:
      shortcutDeliverAssistant(transcript: pending.transcript)
    }
  }

  private func shortcutDeliverDictation(transcript: String) {
    let transcriber = VoiceTranscriber.shared

    guard config.voiceToTextDictationAIEnhanceEnabled, config.aiEnabled else {
      transcriber.deliverAssistantOutput(transcript)
      restoreTranscriptDelivery()
      transcriber.dismissOverlay()
      return
    }

    let provider = config.selectedAIProvider
    guard let apiKey = config.aiProviderKeys[provider], !apiKey.isEmpty else {
      transcriber.deliverAssistantOutput(transcript)
      restoreTranscriptDelivery()
      transcriber.dismissOverlay()
      return
    }

    let model = config.aiModel(for: provider)
    let endpoint = config.aiOpenAIEndpoint
    let dictionaryContext = config.dictionaryContextText
    let language = config.voiceToTextLanguage

    shortcutPostProcessingTask?.cancel()
    transcriber.beginAIEnhanceOverlay()
    shortcutPostProcessingTask = Task {
      do {
        let context = await AssistantContextCollector.shared.collectContext()
        let includeClipboard = config.aiIncludeClipboardContext
        let includeWindow = config.aiIncludeWindowContext
        let userPrompt = AIPrompts.makeDictationUserPrompt(
          transcript: transcript,
          clipboardContext: includeClipboard ? context.clipboardText : nil,
          windowContext: includeWindow ? context.screenText : nil,
          dictionaryContext: dictionaryContext
        )
        let response = try await AICorrector.askAssistant(
          prompt: userPrompt,
          provider: provider,
          model: model,
          systemPrompt: String(format: AIPrompts.dictationSystemPrompt, AIPrompts.languageOutputRule(for: language)),
          apiKey: apiKey,
          openAIBaseURL: endpoint
        )
        await MainActor.run {
          transcriber.deliverAssistantOutput(response)
          restoreTranscriptDelivery()
          transcriber.dismissOverlay()
        }
      } catch is CancellationError {
        // cancelled
      } catch {
        await MainActor.run {
          transcriber.deliverAssistantOutput(transcript)
          restoreTranscriptDelivery()
          transcriber.dismissOverlay()
        }
      }
    }
  }

  private func shortcutDeliverAssistant(transcript: String) {
    let transcriber = VoiceTranscriber.shared

    guard config.voiceToTextAssistantAIEnhanceEnabled, config.aiEnabled else {
      transcriber.deliverAssistantOutput(transcript)
      restoreTranscriptDelivery()
      transcriber.dismissOverlay()
      return
    }

    let provider = config.selectedAIProvider
    guard let apiKey = config.aiProviderKeys[provider], !apiKey.isEmpty else {
      transcriber.deliverAssistantOutput(transcript)
      restoreTranscriptDelivery()
      transcriber.dismissOverlay()
      return
    }

    let model = config.aiModel(for: provider)
    let endpoint = config.aiOpenAIEndpoint
    let dictionaryContext = config.dictionaryContextText

    shortcutPostProcessingTask?.cancel()
    transcriber.beginAIEnhanceOverlay()
    shortcutPostProcessingTask = Task {
      do {
        let context = await AssistantContextCollector.shared.collectContext()
        let includeClipboard = config.voiceToTextAssistantIncludeClipboardContext
        let includeWindow = config.voiceToTextAssistantIncludeWindowContext
        let systemPrompt = AIPrompts.assistantMode + "\n\n" + AIPrompts.assistantLanguageOutputRule(for: config.voiceToTextLanguage)
        let userPrompt = AIPrompts.makeAssistantUserPrompt(
          transcript: transcript,
          clipboardContext: includeClipboard ? context.clipboardText : nil,
          windowContext: includeWindow ? context.screenText : nil,
          dictionaryContext: dictionaryContext
        )
        let response = try await AICorrector.askAssistant(
          prompt: userPrompt,
          provider: provider,
          model: model,
          systemPrompt: systemPrompt,
          apiKey: apiKey,
          openAIBaseURL: endpoint
        )
        await MainActor.run {
          transcriber.deliverAssistantOutput(response)
          restoreTranscriptDelivery()
          transcriber.dismissOverlay()
        }
      } catch is CancellationError {
        // cancelled
      } catch {
        await MainActor.run {
          transcriber.deliverAssistantOutput(transcript)
          restoreTranscriptDelivery()
          transcriber.dismissOverlay()
        }
      }
    }
  }

  /// Update voice-to-text usage stats from the current transcriber session.
  private func shortcutUpdateStatsIfNeeded() {
    let transcriber = VoiceTranscriber.shared
    guard let session = transcriber.session else { return }
    guard session.id != lastCountedShortcutSessionID else { return }
    let trimmed = session.combinedText.trimmingCharacters(in: .whitespacesAndNewlines)

    // If text is still empty, don't mark as counted yet — retranscription
    // may fill it in later (streaming is display-only).
    guard !trimmed.isEmpty else { return }

    let endDate = session.endTime ?? Date()
    let duration = max(0, endDate.timeIntervalSince(session.startTime))
    let characters = voiceTextCharacterCount(in: trimmed)
    let words = voiceTextWordCount(in: trimmed)

    guard duration > 0 || characters > 0 || words > 0 else {
      lastCountedShortcutSessionID = session.id
      return
    }

    config.voiceToTextUsageTotalDuration += duration
    config.voiceToTextUsageSessionCount += 1
    config.voiceToTextUsageTotalCharacters += characters
    config.voiceToTextUsageTotalWords += words
    lastCountedShortcutSessionID = session.id
  }

  private func restoreTranscriptDelivery() {
    if VoiceShortcutState.shared.activeMode == nil {
      VoiceTranscriber.shared.deliverTranscriptsDirectly = true
    }
  }
}

func contentViewShouldHandleShortcutResult(currentSection: AppSection?) -> Bool {
  currentSection != .voiceToText
}

#Preview {
  ContentView()
    .environmentObject(AppConfiguration.shared)
}
