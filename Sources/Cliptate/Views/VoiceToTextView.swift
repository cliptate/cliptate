import CliptateCore
import AVFoundation
import AppKit
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers
import os.log

struct VoiceToTextView: View {
  // Logger for voice transcription service
  private let logger = Logger(subsystem: "com.cliptate.app", category: "VoiceToTextView")
  private let batchTranscriptionRuntime = BatchTranscriptionRuntime.shared
  private let historyRuntime = HistoryRuntime.shared

  @EnvironmentObject private var config: AppConfiguration
  @SceneStorage("ContentView.selectedSection") private var selectedSectionStorage = "Home"
  @ObservedObject private var transcriber: VoiceTranscriber
  @ObservedObject private var historyStore = HistoryRuntime.shared
  @ObservedObject private var warmupCoordinator = TranscriberWarmupCoordinator.shared
  @State private var showingPermissionAlert = false
  @State private var selectionModelStatuses: [ModelVariant: ModelDownloadStatus] = [:]
  @State private var showingMissingModelAlert = false
  @ObservedObject private var shortcutState = VoiceShortcutState.shared
  @ObservedObject private var shortcutManager = KeyboardShortcutManager.shared
  @State private var postProcessingTask: Task<Void, Never>?
  @State private var isPostProcessing = false
  @State private var postProcessingErrorMessage: String?
  @State private var postProcessingStatusMessage: String?
  @State private var lastAssistantSourceText: String = ""
  @State private var dictionaryEntryDraft: String = ""
  @State private var dictionaryAlertMessage: String?
  @State private var dictionaryStatusMessage: String?

  private var isBusy: Bool {
    switch transcriber.state {
    case .preparing, .requestingPermission, .stopping:
      return true
    default:
      return false
    }
  }

  private var isRecording: Bool {
    transcriber.state == .running
  }

  @State private var selectedSession: TranscriptSession?
  @State private var waveformSnapshot: WaveformSnapshot?
  @State private var waveformTask: Task<Void, Never>?
  @State private var audioPlayer: AVAudioPlayer?
  @State private var playbackDelegate: PlaybackDelegate?
  @State private var isPlaying: Bool = false
  @State private var playbackProgress: Double = 0.0
  @State private var playbackDuration: Double = 0.0
  @State private var playbackTimer: Timer?
  @State private var historyActionTask: Task<Void, Never>?
  @State private var reprocessingSessionID: UUID?
  @State private var reprocessingProgress: Double?
  @State private var historyStatusSessionID: UUID?
  @State private var historyStatusMessage: String?
  @State private var historyErrorSessionID: UUID?
  @State private var historyErrorMessage: String?
  @State private var lastCountedSessionID: UUID?
  @State private var isIndicatorExpanded = true
  @State private var contextSheet: ContextSheet?
  @AppStorage("historyShowSpeaker") private var historyShowSpeaker = true
  @AppStorage("historyShowTimestamp") private var historyShowTimestamp = true

  private enum ContextSheet: String, Identifiable {
    case dictation
    case assistant

    var id: Self { self }
  }

  private var selectedSignature: (TranscriberType, ModelVariant) {
    (config.activeVoiceToTextTranscriberType, config.activeVoiceToTextModelVariant)
  }

  private var warmupStatus: TranscriberWarmupCoordinator.Status {
    warmupCoordinator.status(
      for: config.activeVoiceToTextTranscriberType,
      model: config.activeVoiceToTextModelVariant
    )
  }

  private var isWarmingModel: Bool { warmupStatus.isWarming }

  private var warmupStatusText: String? { warmupStatus.progressDescription }

  private var warmupErrorMessage: String? { warmupStatus.errorMessage }

  private var hasValidSelectedModel: Bool {
    selectedModelStatus == .downloaded
  }

  private var selectedModelStatus: ModelDownloadStatus {
    selectionModelStatuses[config.activeVoiceToTextModelVariant] ?? .checking
  }

  private var transcriptText: String {
    if let session = transcriber.session, !session.lines.isEmpty {
      // Show speaker prefixes only after session is finished (batch diarization complete)
      let formatted = session.endTime != nil ? session.speakerFormattedText : session.combinedText
      return formatted.isEmpty ? "Transcription will appear here" : formatted
    }
    return transcriber.liveText.isEmpty ? "Transcription will appear here" : transcriber.liveText
  }

  private var historySessions: [TranscriptSession] {
    historyStore.recentDictationSessions
  }

  private var assistantSourceSummary: String? {
    guard !lastAssistantSourceText.isEmpty else { return nil }
    let count = lastAssistantSourceText.count
    return count == 1
      ? String(localized: "Last assistant input • \(count) character", comment: "Voice to text: assistant source summary, singular")
      : String(localized: "Last assistant input • \(count) characters", comment: "Voice to text: assistant source summary, plural")
  }

  init(transcriber: VoiceTranscriber) {
    _transcriber = ObservedObject(wrappedValue: transcriber)
  }

  var body: some View {
    primaryLayout
      .alert("Microphone Access Required", isPresented: $showingPermissionAlert) {
        Button("Open Settings", role: .none) { openSystemSettings() }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "Voice transcription requires microphone access. Please enable it in System Settings > Privacy & Security > Microphone."
        )
      }
      .alert("Model Required", isPresented: $showingMissingModelAlert) {
        Button("Open Models Library", role: .none) {
          NotificationCenter.default.post(name: .openModelsLibrary, object: nil)
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          "Download and install at least one transcription model before starting voice transcription."
        )
      }
      .alert(
        "Dictionary",
        isPresented: Binding(
          get: { dictionaryAlertMessage != nil },
          set: { if !$0 { dictionaryAlertMessage = nil } }
        )
      ) {
        Button("OK", role: .cancel) { dictionaryAlertMessage = nil }
      } message: {
        Text(dictionaryAlertMessage ?? "")
      }
      .sheet(item: $contextSheet) { target in
        switch target {
        case .dictation:
          VoiceContextSettingsView(
            title: "Dictation Context",
            includeClipboard: $config.aiIncludeClipboardContext,
            includeWindow: $config.aiIncludeWindowContext
          )
        case .assistant:
          VoiceContextSettingsView(
            title: "Assistant Context",
            includeClipboard: $config.voiceToTextAssistantIncludeClipboardContext,
            includeWindow: $config.voiceToTextAssistantIncludeWindowContext
          )
        }
      }
  }

  private var primaryLayout: some View {
    mainPanel
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(AppSurface.contentBackground)
    .appPageHeader {
      AppPageHeader(background: AppSurface.contentBackground) {
        header
      }
    }
    .task { await transcriber.refreshMicrophoneStatus() }
    .onAppear {
      refreshSelectedModelStatus()
      requestWarmupForSelectedModel(reason: .viewAppeared)
      configureTranscriptDeliveryOnAppear()
      // Check microphone permission status and show alert if needed
      if transcriber.microphoneStatus == .denied || transcriber.microphoneStatus == .restricted {
        showingPermissionAlert = true
      }
      if selectedSession == nil, let first = historySessions.first {
        selectSession(first)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .modelArtifactsDidChange)) { _ in
      refreshSelectedModelStatus()
    }
    .onDisappear {
      Task { await transcriber.stop() }
      waveformTask?.cancel()
      waveformTask = nil
      stopPlayback()
      postProcessingTask?.cancel()
      postProcessingTask = nil
      isPostProcessing = false
      postProcessingStatusMessage = nil
      postProcessingErrorMessage = nil
      historyActionTask?.cancel()
      historyActionTask = nil
      reprocessingSessionID = nil
      reprocessingProgress = nil
      historyStatusSessionID = nil
      historyStatusMessage = nil
      historyErrorSessionID = nil
      historyErrorMessage = nil
      lastAssistantSourceText = ""
      finishShortcutSessionOnDisappear()
    }
    .onChange(of: transcriber.session?.combinedText ?? "") { _, newValue in
      if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        postProcessingErrorMessage = nil
        postProcessingStatusMessage = nil
        lastAssistantSourceText = ""
      }
    }
    .onChange(of: transcriber.state) { _, newValue in
      handleTranscriberStateChange(newValue)
    }
    .onChange(of: transcriber.isRetranscribing) { _, isRetranscribing in
      // Retranscription fills session text AFTER the idle transition.
      // Retry shortcut processing and stats persistence once retranscription completes.
      if !isRetranscribing && transcriber.state == .idle {
        processShortcutPostProcessingIfNeeded()
        updateUsageStatsFromCurrentSessionIfNeeded()
      }
    }
    .onChange(of: shortcutState.activeMode) { oldMode, newMode in
      // When mode becomes nil (session ended) and transcriber is already idle,
      // trigger post-processing that won't get another .idle state change.
      if oldMode != nil && newMode == nil && transcriber.state == .idle {
        processShortcutPostProcessingIfNeeded()
      }
    }
    .onAppear {
      // When the view is recreated (e.g. after navigating away and back),
      // @State lastCountedSessionID resets to nil. If the transcriber already
      // has a finished session whose stats were persisted, mark it as counted
      // to avoid counting it again.
      if transcriber.state == .idle,
        !transcriber.isRetranscribing,
        let session = transcriber.session,
        !session.combinedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        lastCountedSessionID = session.id
      }
    }
    .onReceive(historyStore.objectWillChange) { _ in
      if selectedSession == nil, let first = historySessions.first {
        selectSession(first)
      } else if let current = selectedSession,
        !historySessions.contains(where: { $0.id == current.id })
      {
        selectedSession = nil
        waveformSnapshot = nil
        waveformTask?.cancel()
        waveformTask = nil
        stopPlayback()
      }
    }
  }

  private var mainPanel: some View {
    ScrollView {
      controls
        .frame(maxWidth: 840, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 12) {
      AppPageTitle(
        title: "Voice Dictation",
        subtitle: String(localized: "Dictate and transcribe audio in real time")
      )

      Spacer()

      if isWarmingModel {
        HStack(spacing: 6) {
          ProgressView()
            .controlSize(.small)
          Text(warmupStatusText ?? String(localized: "Model warming up…", comment: "Voice to text: model warmup in progress"))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppSurface.subtleFill)
        .cornerRadius(6)
      } else if isRecording {
        HStack(spacing: 6) {
          Circle()
            .fill(Color.red)
            .frame(width: 8, height: 8)
          Text("Recording")
            .font(.caption)
            .foregroundStyle(.red)
            .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.red.opacity(0.08))
        .cornerRadius(6)
      } else if transcriber.isRetranscribing {
        HStack(spacing: 6) {
          ProgressView()
            .controlSize(.mini)
          Text(transcriber.retranscriptionStatus ?? String(localized: "Transcribing…", comment: "Voice to text: re-transcription in progress"))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.accentColor.opacity(0.08))
        .cornerRadius(6)
      }
    }
  }

  private var controls: some View {
    VStack(alignment: .leading, spacing: 20) {
      warmupErrorLabel

      if let issue = transcriber.inputIssue {
        VoiceInputFeedbackView(
          issue: issue, inputDeviceName: transcriber.inputDeviceName,
          canDismiss: transcriber.canDismissInputIssue,
          onDismiss: { transcriber.dismissInputIssue() }
        )
      }

      modelConfigurationCard
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: config.activeVoiceToTextModelVariant) { _, _ in
          refreshSelectedModelStatus()
          requestWarmupForSelectedModel(force: false, reason: .voiceToTextSelection)
        }
        .onChange(of: config.activeVoiceToTextTranscriberType) { _, _ in
          refreshSelectedModelStatus()
          requestWarmupForSelectedModel(force: false, reason: .voiceToTextSelection)
        }

      shortcutModesSection

      DisclosureGroup(isExpanded: $isIndicatorExpanded) {
        MicIndicatorStyleSettingsView(selection: $config.micIndicatorStyle)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, 12)
      } label: {
        HStack {
          Text("Dictation Indicator")
            .font(.headline)
          Spacer()
          Text(config.micIndicatorStyle.displayName)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private var modelConfigurationCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Model Configuration")
          .font(.headline)
        Spacer()
        Button {
          NotificationCenter.default.post(name: .openModelsLibrary, object: nil)
        } label: {
          Text("Manage in Models")
        }
        .buttonStyle(.link)
        .font(.caption)
        .accessibilityLabel("Open Models page")
      }

      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline) {
          Text("Model")
          Spacer(minLength: 16)
          VStack(alignment: .trailing, spacing: 4) {
            Text(config.activeVoiceToTextModelVariant.displayName)
              .multilineTextAlignment(.trailing)
              .textSelection(.enabled)
            modelAvailabilityLabel
          }
        }

        Divider()

        ModelAwareLanguageSelectionView(
          title: String(localized: "Language"),
          selectedLanguage: $config.voiceToTextLanguage,
          contextProvider: {
            .asr(
              type: config.activeVoiceToTextTranscriberType,
              model: config.activeVoiceToTextModelVariant
            )
          },
          helpText: String(localized: "Language list matches the active Voice Dictation ASR model."),
          compactControl: true
        )
      }
      .padding(14)
      .background(AppSurface.settingsBackground, in: RoundedRectangle(cornerRadius: 10))
    }
  }

  @ViewBuilder
  private var modelAvailabilityLabel: some View {
    switch selectedModelStatus {
    case .checking:
      HStack(spacing: 6) {
        ProgressView()
          .controlSize(.mini)
        Text("Checking model availability...")
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    case .downloaded:
      Label("Model ready", systemImage: "checkmark.circle")
        .font(.caption)
        .foregroundStyle(.secondary)
    case .notDownloaded:
      Label("Selected model is not downloaded", systemImage: "exclamationmark.triangle.fill")
        .font(.caption)
        .foregroundStyle(.orange)
    }
  }

  @ViewBuilder
  private var warmupErrorLabel: some View {
    if let warmupErrorMessage {
      Label(warmupErrorMessage, systemImage: "exclamationmark.triangle")
        .font(.caption2)
        .foregroundStyle(.orange)
    }
  }

  private var shortcutModesSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Shortcut Modes")
        .font(.headline)

      if enhancementAvailability != .available {
        VStack(alignment: .leading, spacing: 6) {
          Text(enhancementAvailability == .disabled
            ? String(localized: "AI features are off. Enable them in Settings to use enhancement.")
            : String(localized: "AI enhancement needs a provider API key."))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          Button("Configure AI") { selectedSectionStorage = AppSection.setting.rawValue }
            .buttonStyle(.link)
            .font(.caption)
        }
      }

      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Label("Dictation", systemImage: "mic")
              .fontWeight(.medium)

            Spacer(minLength: 16)

            Picker("Key", selection: Binding(
              get: { shortcutManager.dictationPreset },
              set: { shortcutManager.updatePreset($0, for: .dictation) }
            )) {
              ForEach(VoiceToggleShortcutPreset.allCases.filter { $0 != .custom }) { preset in
                Text(preset.displayName).tag(preset)
              }
            }
            .labelsHidden()
            .accessibilityLabel("Dictation shortcut")
            .frame(maxWidth: 210)
          }

          Text("Tap to enter, Space to handsfree. AI Enhance uses context to improve accuracy.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

          ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) {
              aiEnhanceToggle($config.voiceToTextDictationAIEnhanceEnabled)
              Spacer(minLength: 16)
              contextSettingsButton(
                .dictation, clipboard: config.aiIncludeClipboardContext,
                window: config.aiIncludeWindowContext
              )
            }
            VStack(alignment: .leading, spacing: 10) {
              aiEnhanceToggle($config.voiceToTextDictationAIEnhanceEnabled)
              contextSettingsButton(
                .dictation, clipboard: config.aiIncludeClipboardContext,
                window: config.aiIncludeWindowContext
              )
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)

        Divider()

        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Label("Assistant", systemImage: "text.bubble")
              .fontWeight(.medium)

            Spacer(minLength: 16)

            Picker("Key", selection: Binding(
              get: { shortcutManager.assistantPreset },
              set: { shortcutManager.updatePreset($0, for: .assistant) }
            )) {
              ForEach(VoiceToggleShortcutPreset.allCases.filter { $0 != .custom }) { preset in
                Text("\(preset.displayName) + Shift").tag(preset)
              }
            }
            .labelsHidden()
            .accessibilityLabel("Assistant shortcut")
            .frame(maxWidth: 210)
          }

          Text("Voice assistant. Tap to enter, Space to handsfree. AI Enhance uses context to improve responses.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

          ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) {
              aiEnhanceToggle($config.voiceToTextAssistantAIEnhanceEnabled)
              Spacer(minLength: 16)
              contextSettingsButton(
                .assistant, clipboard: config.voiceToTextAssistantIncludeClipboardContext,
                window: config.voiceToTextAssistantIncludeWindowContext
              )
            }
            VStack(alignment: .leading, spacing: 10) {
              aiEnhanceToggle($config.voiceToTextAssistantAIEnhanceEnabled)
              contextSettingsButton(
                .assistant, clipboard: config.voiceToTextAssistantIncludeClipboardContext,
                window: config.voiceToTextAssistantIncludeWindowContext
              )
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
      }
      .background(AppSurface.settingsBackground, in: RoundedRectangle(cornerRadius: 10))

      // Phase indicator
      modePhaseIndicator

      // Status Area
      if isPostProcessing || postProcessingStatusMessage != nil || assistantSourceSummary != nil
        || postProcessingErrorMessage != nil
      {
        HStack(spacing: 8) {
          if isPostProcessing {
            ProgressView()
              .controlSize(.small)
            Text(postProcessingStatusMessage ?? String(localized: "Processing...", comment: "Voice to text: AI post-processing in progress"))
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") {
              postProcessingTask?.cancel()
              cancelPostProcessing()
            }
            .controlSize(.mini)
          } else {
            VStack(alignment: .leading, spacing: 2) {
              if let status = postProcessingStatusMessage {
                Text(status).font(.caption)
              }
              if let summary = assistantSourceSummary {
                Text(summary).font(.caption2).foregroundStyle(.secondary)
              }
              if let error = postProcessingErrorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
              }
            }
          }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppSurface.cardBackground)
        .cornerRadius(8)
      }
    }
  }

  @ViewBuilder
  private var modePhaseIndicator: some View {
    if let mode = shortcutState.activeMode {
      HStack(spacing: 8) {
        switch shortcutState.phase {
        case .ready:
          Image(systemName: "circle")
            .foregroundStyle(.green)
          Text(
            "\(mode == .dictation ? String(localized: "Dictation", comment: "Voice mode name") : String(localized: "Assistant", comment: "Voice mode name")) ready — press Space to record"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        case .recording:
          Image(systemName: "record.circle.fill")
            .foregroundStyle(.red)
            .symbolEffect(.pulse)
          Text("Recording… press Space to stop")
            .font(.caption)
            .foregroundStyle(.secondary)
        case .idle:
          EmptyView()
        }
        Spacer()
      }
      .padding(10)
      .background(AppSurface.cardBackground)
      .cornerRadius(8)
    }
  }

  private var historySidebar: some View {
    ScrollView {
      historySidebarContent
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.bottom, historyScrollBottomPadding)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      historySidebarFloatingPreview
    }
  }

  private var historyScrollBottomPadding: CGFloat {
    (selectedSession != nil || !historySessions.isEmpty) ? 220 : 40
  }

  @ViewBuilder
  private var historySidebarFloatingPreview: some View {
    if selectedSession != nil || !historySessions.isEmpty {
      VStack(spacing: 8) {
        selectedSessionSection
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .background(.ultraThinMaterial)
      .overlay(
        Divider()
          .padding(.top, -4),
        alignment: .top
      )
      .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: -2)
    }
  }

  private var historySidebarContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      historySidebarHeader
      Divider()
        .padding(.vertical, 4)
      historyListSection
    }
  }

  private var historySidebarHeader: some View {
    HStack(alignment: .center, spacing: 8) {
      Label("History", systemImage: "clock.fill")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
      Text("Last 24 Hours")
        .font(.caption2)
        .foregroundStyle(.secondary)
      Spacer()
      Toggle(isOn: $historyShowSpeaker) {
        Image(systemName: "person.wave.2")
      }
      .toggleStyle(.checkbox)
      .controlSize(.mini)
      .help(String(localized: "Show speaker labels", comment: "History toggle tooltip"))
      Toggle(isOn: $historyShowTimestamp) {
        Image(systemName: "clock")
      }
      .toggleStyle(.checkbox)
      .controlSize(.mini)
      .help(String(localized: "Show timestamps", comment: "History toggle tooltip"))
      if !historySessions.isEmpty {
        Text("\(historySessions.count)")
          .font(.caption2.weight(.semibold))
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Color.accentColor.opacity(0.12))
          .foregroundStyle(Color.accentColor)
          .cornerRadius(4)
        Button(action: clearHistory) {
          Image(systemName: "trash")
            .font(.caption)
        }
        .buttonStyle(.borderless)
        .help("Clear all history")
      }
    }
  }

  @ViewBuilder
  private var selectedSessionSection: some View {
    if let session = selectedSession {
      selectedSessionCard(for: session)
    } else if historySessions.isEmpty {
      EmptyView()
    } else {
      VStack(alignment: .leading, spacing: 6) {
        Text("Playback panel")
          .font(.footnote.weight(.semibold))
        Text("Select a session to preview recordings and quick actions.")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(14)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .stroke(AppSurface.border, lineWidth: 1)
      )
    }
  }

  @ViewBuilder
  private var historyListSection: some View {
    if historySessions.isEmpty {
      historyEmptyState
        .frame(maxWidth: .infinity, alignment: .center)
    } else {
      LazyVStack(spacing: 8) {
        ForEach(historySessions) { session in
          HistorySessionRow(
            session: session,
            isSelected: session.id == selectedSession?.id,
            isProcessing: session.id == reprocessingSessionID,
            statusMessage: session.id == historyStatusSessionID ? historyStatusMessage : nil,
            errorMessage: session.id == historyErrorSessionID ? historyErrorMessage : nil,
            progress: session.id == reprocessingSessionID ? reprocessingProgress : nil,
            showSpeaker: historyShowSpeaker,
            showTimestamp: historyShowTimestamp,
            onSelect: { selectSession(session) },
            onCopy: { copySession(session) },
            onReveal: { revealRecording(for: session) },
            onRetranscribe: { retranscribe(session) },
            onDelete: { deleteSession(session) }
          )
        }
      }
      .padding(.vertical, 2)
    }
  }

  private func selectedSessionCard(for session: TranscriptSession) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 2) {
          Text("Session Preview")
            .font(.footnote.weight(.semibold))
          Text(
            session.startTime.formatted(
              .dateTime.month(.abbreviated).day().hour().minute()
            )
          )
          .font(.caption2)
          .foregroundStyle(.secondary)
        }
        Spacer()
        if let duration = formattedSessionDuration(session) {
          Text(duration)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(AppSurface.subtleFill)
            .cornerRadius(5)
        }
      }

      SessionMetadataBadges(session: session)

      if session.recordingURL == nil {
        Text("No audio recording available for this session.")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else if let snapshot = waveformSnapshot {
        WaveformPreview(
          snapshot: snapshot,
          session: session,
          isPlaying: isPlaying,
          playbackProgress: playbackProgress,
          playbackDuration: playbackDuration,
          onTogglePlayback: togglePlayback,
          onSeek: seekTo
        )
      } else {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Loading waveform...")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 16)
      }

      selectedSessionActionRow(for: session)

      if reprocessingSessionID == session.id {
        HStack(spacing: 8) {
          ProgressView(value: reprocessingProgress ?? 0)
            .progressViewStyle(.linear)
          Text(historyStatusMessage ?? String(localized: "Re-transcribing...", comment: "Voice to text history: re-transcription in progress"))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } else if historyStatusSessionID == session.id, let status = historyStatusMessage {
        Label(status, systemImage: "checkmark.circle")
          .font(.caption)
          .foregroundStyle(.green)
      }

      if historyErrorSessionID == session.id, let error = historyErrorMessage {
        Label(error, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(.orange)
      }
    }
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 14)
        .fill(AppSurface.inputBackground)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14)
        .stroke(AppSurface.border, lineWidth: 1)
    )
  }

  private func selectedSessionActionRow(for session: TranscriptSession) -> some View {
    HStack(spacing: 8) {
      Button(action: { copySession(session) }) {
        Label("Copy", systemImage: "doc.on.doc")
      }

      Button(action: { revealRecording(for: session) }) {
        Label("Show in Finder", systemImage: "folder")
      }
      .disabled(session.recordingURL == nil)

      Button(action: { retranscribe(session) }) {
        Label("Re-transcribe", systemImage: "arrow.triangle.2.circlepath")
      }
      .tint(.accentColor)
      .disabled(
        session.recordingURL == nil
          || reprocessingSessionID == session.id
      )

      Spacer()

      Button(role: .destructive, action: { deleteSession(session) }) {
        Label("Delete", systemImage: "trash")
      }
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
  }

  private var historyEmptyState: some View {
    VStack(spacing: 10) {
      Image(systemName: "doc.text.magnifyingglass")
        .font(.system(size: 24))
        .foregroundStyle(.secondary)
      Text("No sessions yet")
        .font(.footnote.weight(.semibold))
      Text("Live dictations appear here as soon as they finish.")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(18)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .stroke(AppSurface.border, lineWidth: 1)
    )
  }

  private func clearHistory() {
    historyActionTask?.cancel()
    historyActionTask = nil
    reprocessingSessionID = nil
    reprocessingProgress = nil
    historyStatusSessionID = nil
    historyStatusMessage = nil
    historyErrorSessionID = nil
    historyErrorMessage = nil

    historyStore.removeAll(source: .voiceDictation)
    selectedSession = nil
    waveformSnapshot = nil
    waveformTask?.cancel()
    waveformTask = nil
    stopPlayback()
  }


  private var statusRow: some View {
    EmptyView()
  }

  private var shortcutRow: some View {
    EmptyView()
  }

  private func aiEnhanceToggle(_ binding: Binding<Bool>) -> some View {
    Toggle("AI Enhance", isOn: Binding(
      get: { enhancementAvailability == .available && binding.wrappedValue },
      set: { binding.wrappedValue = $0 }
    ))
    .disabled(enhancementAvailability != .available)
    .toggleStyle(.switch)
    .controlSize(.small)
    .font(.caption)
    .fixedSize(horizontal: true, vertical: false)
  }

  private var enhancementAvailability: VoiceEnhancementAvailability {
    VoiceEnhancementAvailability(
      aiEnabled: config.aiEnabled,
      apiKey: config.aiProviderKeys[config.selectedAIProvider]
    )
  }

  private func contextSettingsButton(
    _ target: ContextSheet, clipboard: Bool, window: Bool
  ) -> some View {
    let summary: String
    switch (clipboard, window) {
    case (true, true): summary = String(localized: "Clipboard and window")
    case (true, false): summary = String(localized: "Clipboard Context")
    case (false, true): summary = String(localized: "Window Context")
    case (false, false): summary = String(localized: "Context is off")
    }

    return Button {
      contextSheet = target
    } label: {
      HStack(spacing: 6) {
        Text(summary)
        Image(systemName: "chevron.right")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
      }
      .font(.caption)
      .contentShape(Rectangle())
    }
    .buttonStyle(.link)
    .accessibilityLabel(
      target == .dictation ? Text("Dictation Context") : Text("Assistant Context")
    )
    .accessibilityValue(summary)
  }

  private func characterCount(in text: String) -> Int {
    voiceTextCharacterCount(in: text)
  }

  private func wordCount(in text: String) -> Int {
    voiceTextWordCount(in: text)
  }

  private func addDictionaryEntry() {
    let trimmed = dictionaryEntryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let previousCount = config.voiceToTextCustomDictionary.count
    config.addDictionaryEntry(trimmed)
    let added = config.voiceToTextCustomDictionary.count - previousCount
    dictionaryEntryDraft = ""
    dictionaryStatusMessage =
      added > 0
      ? String(localized: "Added \"\(trimmed)\" to the dictionary.", comment: "Dictionary: entry added confirmation")
      : String(localized: "\"\(trimmed)\" was already in the dictionary.", comment: "Dictionary: duplicate entry notice")
  }

  private func removeDictionaryEntry(_ entry: String) {
    let previousCount = config.voiceToTextCustomDictionary.count
    config.removeDictionaryEntry(entry)
    if config.voiceToTextCustomDictionary.count < previousCount {
      dictionaryStatusMessage = String(localized: "Removed \"\(entry)\" from the dictionary.", comment: "Dictionary: entry removed confirmation")
    }
  }

  private func refreshSelectedModelStatus() {
    let model = config.activeVoiceToTextModelVariant
    Task {
      await MainActor.run {
        selectionModelStatuses[model] = .checking
      }
      let statuses = await ModelDownloadStatusChecker.shared.getStatuses(for: [model])
      let status: ModelDownloadStatus = (statuses[model] == true) ? .downloaded : .notDownloaded
      await MainActor.run {
        selectionModelStatuses[model] = status
      }
      if status == .downloaded {
        requestWarmupForSelectedModel(force: false, reason: .downloadStatusUpdated)
      }
    }
  }

  private func toggleTranscription() async {
    guard hasValidSelectedModel else {
      if selectedModelStatus == .notDownloaded {
        await MainActor.run { showingMissingModelAlert = true }
      }
      return
    }

    switch transcriber.microphoneStatus {
    case .denied, .restricted:
      showingPermissionAlert = true
    default:
      await transcriber.toggle(
        type: config.activeVoiceToTextTranscriberType,
        model: config.activeVoiceToTextModelVariant,
        language: config.voiceToTextLanguage
      )
    }
  }

  private func requestWarmupForSelectedModel(
    force: Bool = false,
    reason: TranscriberWarmupCoordinator.WarmupReason
  ) {
    let (type, model) = selectedSignature
    guard type.supportedModels.contains(model) else { return }
    guard !isRecording, !isBusy else { return }
    guard selectionModelStatuses[model] == .downloaded else { return }
    warmupCoordinator.scheduleWarmup(
      for: type,
      model: model,
      reason: reason,
      force: force
    )
    warmupCoordinator.ensureStreamingWarmup(
      for: type,
      model: model,
      force: force
    )
  }

  private func openSystemSettings() {
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    {
      NSWorkspace.shared.open(url)
    }
  }

  private func handleTranscriberStateChange(_ newValue: VoiceTranscriber.State) {
    switch newValue {
    case .running:
      postProcessingTask?.cancel()
      postProcessingTask = nil
      isPostProcessing = false
      postProcessingStatusMessage = nil
      postProcessingErrorMessage = nil
      lastAssistantSourceText = ""
    case .idle:
      processShortcutPostProcessingIfNeeded()
      updateUsageStatsFromCurrentSessionIfNeeded()
    default:
      break
    }
  }

  func configureTranscriptDeliveryOnAppear() {
    // A shortcut may already be awaiting AI enhancement when this view mounts.
    // Its delivery choice belongs to the session that activated it.
    transcriber.autoTypeEnabled = true
  }

  func finishShortcutSessionOnDisappear() {
    // Navigation can run before the asynchronous stop supplies final text.
    // Let ContentView finish the pending shortcut after transcription completes.
    VoiceShortcutState.shared.requestEndSession()
    restoreTranscriptDeliveryIfNeeded()
  }

  private func updateUsageStatsFromCurrentSessionIfNeeded() {
    guard let session = transcriber.session else { return }
    guard session.id != lastCountedSessionID else { return }
    let trimmed = session.combinedText.trimmingCharacters(in: .whitespacesAndNewlines)

    // If text is still empty, don't mark as counted yet — retranscription
    // may fill it in later (streaming is display-only, session lines are
    // empty until batch retranscription completes).
    guard !trimmed.isEmpty else { return }

    let endDate = session.endTime ?? Date()
    let duration = max(0, endDate.timeIntervalSince(session.startTime))
    let characters = characterCount(in: trimmed)
    let words = wordCount(in: trimmed)

    guard duration > 0 || characters > 0 || words > 0 else {
      lastCountedSessionID = session.id
      return
    }

    config.voiceToTextUsageTotalDuration += duration
    config.voiceToTextUsageSessionCount += 1
    config.voiceToTextUsageTotalCharacters += characters
    config.voiceToTextUsageTotalWords += words
    lastCountedSessionID = session.id
  }

  private func processShortcutPostProcessingIfNeeded() {
    guard transcriber.state == .idle else { return }
    let shortcutState = VoiceShortcutState.shared

    // Absorb segment text (deduplicated via VoiceShortcutState.absorbSessionTextOnce)
    shortcutState.absorbSessionTextOnce(
      sessionID: transcriber.session?.id,
      text: transcriber.session?.combinedText ?? ""
    )

    // If still in a mode session, don't post-process yet
    guard shortcutState.activeMode == nil else { return }

    // If a session end was requested (two-phase), finalize now that text is available
    if shortcutState.pendingEndMode != nil {
      shortcutState.finalizeEndSession()
    }

    // Session ended — consume pending result
    guard let pending = shortcutState.consumePendingResult() else {
      restoreTranscriptDeliveryIfNeeded()
      transcriber.dismissOverlay()
      return
    }

    guard !pending.transcript.isEmpty else {
      restoreTranscriptDeliveryIfNeeded()
      transcriber.dismissOverlay()
      return
    }

    switch pending.mode {
    case .dictation:
      startDictationAutofix(transcript: pending.transcript, sessionIDs: pending.sessionIDs)
    case .assistant:
      startAssistantCommand(transcript: pending.transcript)
    }
  }

  private func startDictationAutofix(transcript: String, sessionIDs: [UUID]) {
    guard config.voiceToTextDictationAIEnhanceEnabled else {
      transcriber.deliverAssistantOutput(transcript)
      restoreTranscriptDeliveryIfNeeded()
      transcriber.dismissOverlay()
      return
    }

    guard config.aiEnabled else {
      transcriber.deliverAssistantOutput(transcript)
      restoreTranscriptDeliveryIfNeeded()
      transcriber.dismissOverlay()
      return
    }

    let provider = config.selectedAIProvider
    guard let apiKey = config.aiProviderKeys[provider], !apiKey.isEmpty else {
      postProcessingErrorMessage = String(localized: "No API key available for \(provider.displayName).", comment: "Error: AI provider missing API key")
      restoreTranscriptDeliveryIfNeeded()
      transcriber.dismissOverlay()
      return
    }

    startPostProcessing(
      mode: .dictation,
      status: String(localized: "Cleaning transcript with AI (\(transcript.count) characters)…", comment: "AI post-processing status: cleaning dictation transcript")
    )

    let model = config.aiModel(for: provider)
    let endpoint = config.aiOpenAIEndpoint
    let dictionaryContext = config.dictionaryContextText
    let language = config.voiceToTextLanguage

    postProcessingTask = Task {
      do {
        let context: AssistantContextSnapshot = await AssistantContextCollector.shared
          .collectContext()
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

        logger.notice("Dictation autofix prompt: (\(userPrompt))\nresponse: \(response)")

        try Task.checkCancellation()
        await MainActor.run {
          guard !Task.isCancelled else { return }
          finishPostProcessing(
            mode: .dictation,
            response: response,
            transcript: transcript,
            statusMessage: "Transcript corrected and delivered via AI."
          )
          do {
            try historyRuntime.recordDictationCorrection(sessionIDs: sessionIDs, original: transcript,
              corrected: response, provider: provider.rawValue, model: model, language: language.rawValue)
          } catch {
            postProcessingErrorMessage = String(format: String(localized:
              "AI text was applied, but correction history could not be saved: %@."), error.localizedDescription)
          }
        }
      } catch is CancellationError {
        await MainActor.run {
          cancelPostProcessing()
        }
      } catch {
        await MainActor.run {
          failPostProcessing(with: error.localizedDescription)
        }
      }
    }
  }

  private func startAssistantCommand(transcript: String) {
    guard config.voiceToTextAssistantAIEnhanceEnabled else {
      lastAssistantSourceText = transcript
      transcriber.deliverAssistantOutput(transcript)
      restoreTranscriptDeliveryIfNeeded()
      transcriber.dismissOverlay()
      return
    }

    guard config.aiEnabled else {
      lastAssistantSourceText = transcript
      transcriber.deliverAssistantOutput(transcript)
      restoreTranscriptDeliveryIfNeeded()
      transcriber.dismissOverlay()
      return
    }

    let provider = config.selectedAIProvider
    guard let apiKey = config.aiProviderKeys[provider], !apiKey.isEmpty else {
      postProcessingErrorMessage = String(localized: "No API key available for \(provider.displayName).", comment: "Error: AI provider missing API key")
      restoreTranscriptDeliveryIfNeeded()
      transcriber.dismissOverlay()
      return
    }

    startPostProcessing(
      mode: .assistant,
      status: String(localized: "Sending assistant request (\(transcript.count) characters + context)…", comment: "AI post-processing status: sending assistant request")
    )

    let model = config.aiModel(for: provider)
    let endpoint = config.aiOpenAIEndpoint
    let dictionaryContext = config.dictionaryContextText

    postProcessingTask = Task {
      do {
        let context = await AssistantContextCollector.shared.collectContext()
        let includeClipboard = config.voiceToTextAssistantIncludeClipboardContext
        let includeWindow = config.voiceToTextAssistantIncludeWindowContext
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
          systemPrompt: AIPrompts.assistantMode + "\n\n" + AIPrompts.assistantLanguageOutputRule(for: config.voiceToTextLanguage),
          apiKey: apiKey,
          openAIBaseURL: endpoint
        )

        logger.notice("Assistant prompt: (\(userPrompt))\nresponse: \(response)")

        await MainActor.run {
          finishPostProcessing(
            mode: .assistant,
            response: response,
            transcript: transcript,
            statusMessage: "Assistant response delivered to the focused input."
          )
        }
      } catch is CancellationError {
        await MainActor.run {
          cancelPostProcessing()
        }
      } catch {
        await MainActor.run {
          failPostProcessing(with: error.localizedDescription)
        }
      }
    }
  }

  private func startPostProcessing(mode: VoiceShortcutMode, status: String) {
    postProcessingTask?.cancel()
    postProcessingTask = nil
    isPostProcessing = true
    postProcessingStatusMessage = status
    postProcessingErrorMessage = nil
    transcriber.beginAIEnhanceOverlay()
  }

  private func finishPostProcessing(
    mode: VoiceShortcutMode,
    response: String,
    transcript: String,
    statusMessage: String
  ) {
    transcriber.deliverAssistantOutput(response)
    postProcessingStatusMessage = statusMessage
    postProcessingTask = nil
    isPostProcessing = false
    postProcessingErrorMessage = nil
    if mode == .assistant {
      lastAssistantSourceText = transcript
    } else {
      lastAssistantSourceText = ""
    }
    restoreTranscriptDeliveryIfNeeded()
    transcriber.dismissOverlay()
  }

  private func failPostProcessing(with message: String) {
    postProcessingStatusMessage = nil
    postProcessingErrorMessage = message
    postProcessingTask = nil
    isPostProcessing = false
    restoreTranscriptDeliveryIfNeeded()
    transcriber.dismissOverlay()
  }

  private func cancelPostProcessing() {
    postProcessingStatusMessage = nil
    postProcessingTask = nil
    isPostProcessing = false
    restoreTranscriptDeliveryIfNeeded()
    transcriber.dismissOverlay()
  }

  private func restoreTranscriptDeliveryIfNeeded() {
    let shortcut = VoiceShortcutState.shared
    guard shortcut.activeMode == nil, shortcut.pendingEndMode == nil,
      shortcut.pendingResult == nil, !isPostProcessing else { return }
    transcriber.deliverTranscriptsDirectly = true
  }

  private func revealRecording(for session: TranscriptSession) {
    guard let url = session.recordingURL else {
      historyErrorSessionID = session.id
      historyErrorMessage = "No recording found for this session."
      return
    }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  private func retranscribe(_ session: TranscriptSession) {
    guard let url = session.recordingURL else {
      historyErrorSessionID = session.id
      historyErrorMessage = "This session has no saved audio to re-transcribe."
      return
    }

    historyActionTask?.cancel()
    historyActionTask = nil

    let targetType = config.activeVoiceToTextTranscriberType
    let targetModel = config.activeVoiceToTextModelVariant
    let targetLanguage = config.voiceToTextLanguage
    historyErrorSessionID = nil
    historyErrorMessage = nil
    historyStatusSessionID = session.id
    historyStatusMessage = String(localized: "Preparing \(targetModel.displayName)...", comment: "History retranscription status: loading model")
    reprocessingSessionID = session.id
    reprocessingProgress = 0

    historyActionTask = Task(priority: .userInitiated) {
      do {
        let output = try await batchTranscriptionRuntime.transcribe(
          request: BatchTranscriptionRequest(
            sourceURL: url,
            workflow: .dictationHistoryReprocessing,
            transcriberType: targetType,
            asrModel: targetModel,
            vadModel: config.vadModelVariant,
            alignModel: config.alignModelVariant,
            language: targetLanguage,
            dictionaryEntries: config.voiceToTextCustomDictionary
          ),
          modelProgressHandler: { progress in
            Task { @MainActor in
              guard self.reprocessingSessionID == session.id else { return }
              self.historyStatusSessionID = session.id
              self.historyStatusMessage = progress.currentStep
            }
          },
          progressHandler: { progress in
            Task { @MainActor in
              guard self.reprocessingSessionID == session.id else { return }
              self.reprocessingProgress = Double(progress.progress)
              self.historyStatusSessionID = session.id
              self.historyStatusMessage = progress.statusMessage
            }
          }
        )

        var updatedSession = session
        let newLines = buildTranscriptLines(from: output.result.segments)
        if !newLines.isEmpty {
          updatedSession.replaceLines(with: newLines)
        }
        // updatedSession.endTime = Date()
        updatedSession.transcriberType = targetType
        updatedSession.modelVariant = targetModel
        updatedSession.language = targetLanguage

        await MainActor.run {
          historyRuntime.replace(updatedSession)
          reprocessingSessionID = nil
          reprocessingProgress = nil
          historyStatusSessionID = updatedSession.id
          historyStatusMessage = String(localized: "Re-transcribed with \(targetModel.displayName)", comment: "History retranscription status: completed successfully")
          historyErrorSessionID = nil
          historyErrorMessage = nil
          historyActionTask = nil
          if selectedSession?.id == updatedSession.id {
            selectSession(updatedSession)
          }
        }
      } catch is CancellationError {
        await MainActor.run {
          if reprocessingSessionID == session.id {
            reprocessingSessionID = nil
            reprocessingProgress = nil
          }
          if historyActionTask?.isCancelled == true {
            historyActionTask = nil
          }
          if historyStatusSessionID == session.id {
            historyStatusSessionID = nil
            historyStatusMessage = nil
          }
        }
      } catch {
        await MainActor.run {
          reprocessingSessionID = nil
          reprocessingProgress = nil
          historyActionTask = nil
          historyErrorSessionID = session.id
          historyErrorMessage = error.localizedDescription
          if historyStatusSessionID == session.id {
            historyStatusSessionID = nil
            historyStatusMessage = nil
          }
        }
      }
    }
  }

  private func buildTranscriptLines(from segments: [Segment]) -> [TranscriptLine] {
    segments.compactMap { segment in
      let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return nil }
      return TranscriptLine(timestamp: max(0, segment.startTime), text: trimmed)
    }
  }

  private func copySession(_ session: TranscriptSession) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(
      session.formattedText(showSpeaker: historyShowSpeaker, showTimestamp: historyShowTimestamp),
      forType: .string
    )
  }

  private func deleteSession(_ session: TranscriptSession) {
    if selectedSession?.id == session.id {
      selectedSession = nil
      waveformSnapshot = nil
      waveformTask?.cancel()
      waveformTask = nil
      stopPlayback()
    }
    if reprocessingSessionID == session.id {
      historyActionTask?.cancel()
      historyActionTask = nil
      reprocessingSessionID = nil
      reprocessingProgress = nil
    }
    if historyStatusSessionID == session.id {
      historyStatusSessionID = nil
      historyStatusMessage = nil
    }
    if historyErrorSessionID == session.id {
      historyErrorSessionID = nil
      historyErrorMessage = nil
    }
    historyRuntime.remove(id: session.id)
  }

  private func selectSession(_ session: TranscriptSession) {
    guard session.recordingURL != nil || !session.lines.isEmpty else { return }
    if selectedSession?.id == session.id { return }
    selectedSession = session
    waveformSnapshot = nil
    waveformTask?.cancel()
    stopPlayback()
    if let url = session.recordingURL {
      waveformTask = Task {
        do {
          let snapshot = try await WaveformRepository.shared.loadWaveform(
            for: url,
            targetPointCount: 800,
            mixToMono: true
          )
          try Task.checkCancellation()
          await MainActor.run {
            guard self.selectedSession?.id == session.id else { return }
            self.waveformSnapshot = snapshot
          }
        } catch is CancellationError {
          return
        } catch {
          await MainActor.run {
            guard self.selectedSession?.id == session.id else { return }
            self.waveformSnapshot = nil
          }
        }
      }
      preparePlayback(for: session)
    } else {
      waveformTask = nil
      waveformSnapshot = nil
    }
  }

  private func preparePlayback(for session: TranscriptSession) {
    guard let url = session.recordingURL else { return }
    do {
      audioPlayer = try AVAudioPlayer(contentsOf: url)
      audioPlayer?.prepareToPlay()
      playbackDuration = audioPlayer?.duration ?? 0
      playbackProgress = 0

      let delegate = PlaybackDelegate(
        onFinish: {
          Task { @MainActor in
            self.isPlaying = false
            self.playbackProgress = 0
            self.stopPlaybackTimer()
          }
        }
      )
      playbackDelegate = delegate
      audioPlayer?.delegate = delegate
    } catch {
      audioPlayer = nil
    }
  }

  private func togglePlayback() {
    guard let player = audioPlayer else { return }
    if player.isPlaying {
      player.pause()
      isPlaying = false
      stopPlaybackTimer()
    } else {
      player.play()
      isPlaying = true
      startPlaybackTimer()
    }
  }

  private func seekTo(_ time: Double) {
    guard let player = audioPlayer else { return }
    player.currentTime = min(max(time, 0), player.duration)
    playbackProgress = player.currentTime
  }

  private func startPlaybackTimer() {
    stopPlaybackTimer()
    playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
      Task { @MainActor in
        guard let player = self.audioPlayer, player.isPlaying else { return }
        self.playbackProgress = player.currentTime
      }
    }
  }

  private func stopPlaybackTimer() {
    playbackTimer?.invalidate()
    playbackTimer = nil
  }

  private func stopPlayback() {
    audioPlayer?.stop()
    audioPlayer = nil
    isPlaying = false
    playbackProgress = 0
    playbackDuration = 0
    playbackDelegate = nil
    stopPlaybackTimer()
  }
}

/// Count all characters in text (including whitespace).
func voiceTextCharacterCount(in text: String) -> Int {
  text.count
}

/// Count words using the system linguistic tokenizer, which handles CJK word boundaries.
func voiceTextWordCount(in text: String) -> Int {
  var count = 0
  text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { _, _, _, _ in
    count += 1
  }
  return count
}

struct VoiceUsageStats {
  let totalDuration: TimeInterval
  let sessionCount: Int
  let totalCharacters: Int
  let totalWords: Int

  var hasHistory: Bool {
    totalDuration > 0 || totalCharacters > 0 || totalWords > 0 || sessionCount > 0
  }

  var averageWordsPerMinute: Double {
    guard totalDuration > 0, totalWords > 0 else { return 0 }
    return Double(totalWords) / (totalDuration / 60)
  }

  var savedSeconds: TimeInterval {
    guard totalWords > 0 else { return 0 }
    // Compare against composition typing speed (20 WPM), which accounts for
    // the thinking/drafting overhead of manual text entry. Raw transcription
    // typing (40 WPM) is too fast a baseline and causes voice sessions with
    // natural pauses to falsely report zero time saved.
    let typingSeconds = Double(totalWords) / 20.0 * 60.0
    return max(0, typingSeconds - totalDuration)
  }
}

private struct VoiceContextSettingsView: View {
  let title: LocalizedStringKey
  @Binding var includeClipboard: Bool
  @Binding var includeWindow: Bool
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        Text(title)
          .font(.headline)
          .accessibilityAddTraits(.isHeader)
        Spacer()
        Button("Done") { dismiss() }
          .keyboardShortcut(.defaultAction)
      }

      VStack(alignment: .leading, spacing: 0) {
        Toggle(isOn: $includeClipboard) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Clipboard Context")
            Text("Use clipboard text to help AI understand your request.")
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel("Clipboard Context")
        .padding(14)

        Divider()

        Toggle(isOn: $includeWindow) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Window Context")
            Text("Use text from the active window to help AI understand your request.")
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel("Window Context")
        .padding(14)
      }
      .toggleStyle(.switch)
      .controlSize(.small)
      .background(AppSurface.settingsBackground, in: RoundedRectangle(cornerRadius: 10))

      Text("Context is used only when AI features and AI Enhance are enabled and a provider API key is configured.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(24)
    .frame(width: 460)
    .background(AppSurface.contentBackground)
    .onExitCommand { dismiss() }
  }
}

enum VoiceEnhancementAvailability: Equatable {
  case disabled
  case missingKey
  case available

  init(aiEnabled: Bool, apiKey: String?) {
    if !aiEnabled {
      self = .disabled
    } else if apiKey?.isEmpty != false {
      self = .missingKey
    } else {
      self = .available
    }
  }
}

private final class PlaybackDelegate: NSObject, AVAudioPlayerDelegate {
  private let onFinish: () -> Void

  init(onFinish: @escaping () -> Void) {
    self.onFinish = onFinish
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    onFinish()
  }
}

private struct WaveformPreview: View {
  let snapshot: WaveformSnapshot
  let session: TranscriptSession
  let isPlaying: Bool
  let playbackProgress: Double
  let playbackDuration: Double
  let onTogglePlayback: () -> Void
  let onSeek: (Double) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          WaveformGraph(snapshot: snapshot)
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
              RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )

          // 播放进度覆盖层
          if playbackDuration > 0 {
            Rectangle()
              .fill(Color.accentColor.opacity(0.2))
              .frame(width: geometry.size.width * (playbackProgress / playbackDuration))
              .clipShape(RoundedRectangle(cornerRadius: 14))
          }

          if snapshot.pointCount > 1 {
            Button(action: onTogglePlayback) {
              Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.85))
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.white.opacity(0.9)))
            }
            .buttonStyle(.plain)
            .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 6)
          }
        }
        .contentShape(Rectangle())
        .onTapGesture { location in
          // 点击波形图跳转
          let ratio = location.x / geometry.size.width
          let targetTime = max(0, min(ratio * playbackDuration, playbackDuration))
          onSeek(targetTime)
        }
      }
      .frame(height: 120)

      HStack(spacing: 12) {
        if playbackDuration > 0 {
          Label(
            "\(formatTime(playbackProgress)) / \(formatTime(playbackDuration))",
            systemImage: "clock"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        } else if let durationText = formattedDuration(snapshot.duration) {
          Label(durationText, systemImage: "clock")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if let linesCount = lineSummary {
          Label(linesCount, systemImage: "text.alignleft")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
    }
  }

  private var lineSummary: String? {
    let count = session.lines.count
    guard count > 0 else { return nil }
    return count == 1 ? "1 line" : "\(count) lines"
  }

  private func formatTime(_ seconds: Double) -> String {
    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return String(format: "%d:%02d", mins, secs)
  }

  private func formattedDuration(_ duration: TimeInterval) -> String? {
    guard duration > 0 else { return nil }
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = duration >= 60 ? [.minute, .second] : [.second]
    formatter.unitsStyle = .abbreviated
    return formatter.string(from: duration)
  }
}

private struct WaveformGraph: View {
  let snapshot: WaveformSnapshot
  var verticalGain: CGFloat = 1.85

  var body: some View {
    Canvas { context, size in
      guard let channel = snapshot.channels.first, channel.count > 1 else { return }

      let width = size.width
      let height = size.height
      let midY = height / 2
      let step = width / CGFloat(channel.count - 1)

      var path = Path()
      path.move(to: CGPoint(x: 0, y: midY))

      for (index, sample) in channel.enumerated() {
        let x = CGFloat(index) * step
        let amplitude = CGFloat(min(max(sample, 0), 1)) * verticalGain
        let y = midY - min(amplitude, 1) * midY
        path.addLine(to: CGPoint(x: x, y: y))
      }

      path.addLine(to: CGPoint(x: width, y: midY))

      for index in stride(from: channel.count - 1, through: 0, by: -1) {
        let x = CGFloat(index) * step
        let amplitude = CGFloat(min(max(channel[index], 0), 1)) * verticalGain
        let y = midY + min(amplitude, 1) * midY
        path.addLine(to: CGPoint(x: x, y: y))
      }

      path.closeSubpath()

      context.fill(
        path,
        with: .linearGradient(
          Gradient(colors: [
            Color.accentColor.opacity(0.48),
            Color.accentColor.opacity(0.20),
          ]),
          startPoint: .zero,
          endPoint: CGPoint(x: width, y: height)
        )
      )

      var upperStroke = Path()
      upperStroke.move(to: CGPoint(x: 0, y: midY))
      for (index, sample) in channel.enumerated() {
        let x = CGFloat(index) * step
        let amplitude = CGFloat(min(max(sample, 0), 1)) * verticalGain
        let y = midY - min(amplitude, 1) * midY
        upperStroke.addLine(to: CGPoint(x: x, y: y))
      }

      var lowerStroke = Path()
      lowerStroke.move(to: CGPoint(x: 0, y: midY))
      for (index, sample) in channel.enumerated() {
        let x = CGFloat(index) * step
        let amplitude = CGFloat(min(max(sample, 0), 1)) * verticalGain
        let y = midY + min(amplitude, 1) * midY
        lowerStroke.addLine(to: CGPoint(x: x, y: y))
      }

      context.stroke(upperStroke, with: .color(Color.white.opacity(0.65)), lineWidth: 1)
      context.stroke(lowerStroke, with: .color(Color.white.opacity(0.35)), lineWidth: 1)
    }
    .background(
      LinearGradient(
        colors: [
          Color.black.opacity(0.28),
          Color.black.opacity(0.18),
        ],
        startPoint: .top,
        endPoint: .bottom
      )
    )
  }
}

#Preview {
  VoiceToTextView(transcriber: VoiceTranscriber.shared)
    .environmentObject(AppConfiguration.shared)
}

private struct HistorySessionRow: View {
  let session: TranscriptSession
  let isSelected: Bool
  let isProcessing: Bool
  let statusMessage: String?
  let errorMessage: String?
  let progress: Double?
  let showSpeaker: Bool
  let showTimestamp: Bool
  let onSelect: () -> Void
  let onCopy: () -> Void
  let onReveal: () -> Void
  let onRetranscribe: () -> Void
  let onDelete: () -> Void

  @State private var isExpanded = false
  @State private var shouldShowExpandControl = false
  @State private var measuredWidth: CGFloat = 0
  private let previewLineLimit = 5

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header
      SessionMetadataBadges(session: session)
      transcriptPreview
      statusLabel
      errorLabel
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(isSelected ? AppSurface.selectedFill : AppSurface.cardBackground)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(
          isSelected ? AppSurface.selectedBorder : AppSurface.border,
          lineWidth: isSelected ? 1.2 : 1)
    )
    .contentShape(RoundedRectangle(cornerRadius: 12))
    .onTapGesture(perform: onSelect)
  }

  @ViewBuilder
  private var header: some View {
    HStack(alignment: .center, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(
          session.startTime.formatted(.dateTime.month(.abbreviated).day().year())
            + " " + session.startTime.formatted(.dateTime.hour().minute().second())
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        if let summary = formattedSessionDuration(session) {
          Text(summary)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
      if isProcessing {
        ProgressView(value: progress ?? 0)
          .frame(width: 60)
      }
      headerActions
        .padding(.leading, 2)
    }
  }

  private var headerActions: some View {
    HStack(spacing: 6) {
      Button(action: onCopy) {
        actionChip(systemName: "doc.on.doc")
      }
      .buttonStyle(.plain)
      .help("Copy transcript")

      Button(action: onReveal) {
        actionChip(systemName: "folder")
      }
      .buttonStyle(.plain)
      .help("Reveal recording in Finder")
      .disabled(session.recordingURL == nil)

      Button(action: onRetranscribe) {
        actionChip(systemName: "arrow.triangle.2.circlepath", tint: .accentColor)
      }
      .buttonStyle(.plain)
      .help("Re-transcribe this session")
      .disabled(session.recordingURL == nil || isProcessing)

      Button(role: .destructive, action: onDelete) {
        actionChip(systemName: "trash", tint: .red)
      }
      .buttonStyle(.plain)
      .help("Delete session")
    }
  }

  @ViewBuilder
  private var transcriptPreview: some View {
    let displayText = session.formattedText(showSpeaker: showSpeaker, showTimestamp: showTimestamp)
    VStack(alignment: .leading, spacing: 4) {
      Text(displayText)
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineLimit(isExpanded ? nil : previewLineLimit)
        .onWidthChange { width in
          guard width > 0 else { return }
          measuredWidth = width
          updateShowMoreState(for: width)
        }

      if shouldShowExpandControl {
        Button {
          withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded.toggle()
          }
        } label: {
          HStack(spacing: 4) {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
              .font(.caption2)
            Text(isExpanded ? "Show Less" : "Show More")
              .font(.caption2)
          }
        }
        .buttonStyle(.link)
        .font(.caption2)
      }
    }
    .onChange(of: session.combinedText) { _, _ in
      updateShowMoreState(for: measuredWidth)
    }
    .onChange(of: showSpeaker) { _, _ in
      updateShowMoreState(for: measuredWidth)
    }
    .onChange(of: showTimestamp) { _, _ in
      updateShowMoreState(for: measuredWidth)
    }
  }

  @ViewBuilder
  private var statusLabel: some View {
    if let statusMessage {
      Label(
        statusMessage,
        systemImage: isProcessing ? "arrow.triangle.2.circlepath" : "checkmark.circle"
      )
      .font(.caption)
      .foregroundStyle(isProcessing ? Color.secondary : Color.green)
    }
  }

  @ViewBuilder
  private var errorLabel: some View {
    if let errorMessage {
      Label(errorMessage, systemImage: "exclamationmark.triangle")
        .font(.caption)
        .foregroundStyle(.orange)
    }
  }

  private func updateShowMoreState(for width: CGFloat) {
    let trimmed = session.combinedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard width > 0, !trimmed.isEmpty else {
      if shouldShowExpandControl {
        shouldShowExpandControl = false
      }
      if isExpanded {
        isExpanded = false
      }
      return
    }

    let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    let attributed = NSAttributedString(string: trimmed, attributes: [.font: font])
    let bounding = attributed.boundingRect(
      with: CGSize(width: width, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    let limitHeight = font.lineHeight * CGFloat(previewLineLimit)
    let needsToggle = bounding.height - limitHeight > 1

    if needsToggle != shouldShowExpandControl {
      shouldShowExpandControl = needsToggle
      if !needsToggle && isExpanded {
        isExpanded = false
      }
    }
  }

  private func actionChip(systemName: String, tint: Color = .primary) -> some View {
    Image(systemName: systemName)
      .font(.caption.weight(.semibold))
      .foregroundStyle(tint)
      .frame(width: 26, height: 26)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(AppSurface.subtleFill)
      )
  }
}

private struct SessionMetadataBadges: View {
  let session: TranscriptSession

  var body: some View {
    if session.transcriberType != nil || session.modelVariant != nil || session.language != nil {
      HStack(spacing: 6) {
        if let type = session.transcriberType {
          let tint: Color = .secondary
          badge(text: type.displayName, systemImage: "waveform", tint: tint)
        }
        if let model = session.modelVariant {
          badge(text: model.displayName, systemImage: "cpu", tint: .secondary)
        }
        if let language = session.language {
          badge(text: language.displayName, systemImage: "globe", tint: .secondary)
        }
      }
    }
  }

  private func badge(text: String, systemImage: String, tint: Color) -> some View {
    Label(text, systemImage: systemImage)
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(tint.opacity(0.12))
      .foregroundStyle(tint)
      .clipShape(Capsule())
  }
}

private func formattedSessionDuration(_ session: TranscriptSession) -> String? {
  guard let end = session.endTime else { return nil }
  let interval = max(0, end.timeIntervalSince(session.startTime))
  guard interval > 0 else { return nil }
  let formatter = DateComponentsFormatter()
  formatter.allowedUnits = interval >= 60 ? [.minute, .second] : [.second]
  formatter.unitsStyle = .abbreviated
  return formatter.string(from: interval)
}

private struct WidthPreferenceKey: PreferenceKey {
  static let defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

extension View {
  fileprivate func onWidthChange(_ action: @escaping (CGFloat) -> Void) -> some View {
    background(
      GeometryReader { proxy in
        Color.clear.preference(key: WidthPreferenceKey.self, value: proxy.size.width)
      }
    )
    .onPreferenceChange(WidthPreferenceKey.self, perform: action)
  }
}

extension NSFont {
  fileprivate var lineHeight: CGFloat {
    (ascender - descender) + leading
  }
}


private struct VoiceInputFeedbackView: View {
  let issue: VoiceInputIssue
  let inputDeviceName: String?
  let canDismiss: Bool
  let onDismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top) {
        Label(issue.title, systemImage: "exclamationmark.triangle.fill")
          .font(.headline)
          .foregroundStyle(.orange)
        Spacer()
        if canDismiss {
          Button("Dismiss warning", systemImage: "xmark", action: onDismiss)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Dismiss warning")
        }
      }
      Text(issue.message)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      if issue == .noInput || issue == .quietInput {
        if let inputDeviceName {
          Text(String(format: String(localized: "Input device: %@"), inputDeviceName))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Button("Open Sound Settings", systemImage: "slider.horizontal.3") {
          if let url = URL(string: "x-apple.systempreferences:com.apple.preference.sound") {
            NSWorkspace.shared.open(url)
          }
        }
        .buttonStyle(.bordered)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    .accessibilityElement(children: .contain)
  }
}
