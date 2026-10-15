import CliptateCore
import AVFoundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TTSSynthesisView: View {
    private let ttsSessionRuntime = TTSSessionRuntime.shared
    @EnvironmentObject private var config: AppConfiguration
    @SceneStorage("ContentView.selectedSection") private var selectedSectionStorage: String = "AI Cut"

    @State private var inputText: String = Self.defaultSample
    @State private var isSynthesizing = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var synthesizedAudio: Data?
    @State private var pendingExportAfterSynthesis = false
    @State private var isCheckingStatus = false
    @State private var showHistoryPrompt = false
    @State private var generationTask: Task<Void, Never>?
    @State private var isReferenceAudioDropTarget = false

    // Playback
    @State private var audioPlayer: AVAudioPlayer?
    @State private var playbackDelegate: TTSPlaybackDelegate?
    @State private var isPlaying = false
    @State private var playbackProgress: TimeInterval = 0
    @State private var playbackDuration: TimeInterval = 0
    @State private var playbackTimer: Timer?

    // MLX TTS
    @State private var mlxModelCached = false
    @State private var mlxModelLoading = false
    @State private var referenceAudioURL: URL?

    enum VoiceMode: String, CaseIterable, Identifiable {
        case preset = "Preset"
        case clone = "Voice Clone"
        case emotionControl = "Emotion Control"
        case voiceDesign = "Voice Design"
        var id: String { rawValue }

        var localizedTitle: String {
            switch self {
            case .preset:         return String(localized: "Preset", comment: "TTS voice mode: built-in preset speaker")
            case .clone:          return String(localized: "Voice Clone", comment: "TTS voice mode: clone from reference audio")
            case .emotionControl: return String(localized: "Emotion Control", comment: "TTS voice mode: named speaker with emotion/style prompt")
            case .voiceDesign:    return String(localized: "Voice Design", comment: "TTS voice mode: describe any voice via text")
            }
        }
    }
    @State private var voiceMode: VoiceMode = .preset

    @FocusState private var isEditorFocused: Bool

    private var ttsLanguageBinding: Binding<Language> {
        Binding(
            get: {
                switch config.ttsLanguage {
                case "zh": return .chinese
                case "ja": return .japanese
                case "ko": return .korean
                default: return .english
                }
            },
            set: { newValue in
                switch newValue {
                case .chinese: config.ttsLanguage = "zh"
                case .japanese: config.ttsLanguage = "ja"
                case .korean: config.ttsLanguage = "ko"
                default: config.ttsLanguage = "en"
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    modelStatusCard

                    textEditorCard

                    voiceControlsCard

                    // Status / error feedback (separate from the button now embedded in textEditorCard)
                    feedbackRow

                    if synthesizedAudio != nil {
                        previewCard
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
            }
        }
        .background(AppSurface.pageBackground)
        .appPageHeader {
            AppPageHeader(.ttsStudio)
        }
        .task {
            await refreshStatus()
            // Restore reference audio URL from saved bookmark (preferred) or plain path.
            // Security-scoped bookmarks survive app restarts; plain paths do not work in
            // the sandbox after relaunch because user-selected file access is not persisted.
            if !config.ttsReferenceAudioPath.isEmpty, referenceAudioURL == nil {
                if let bookmarkData = config.ttsReferenceAudioBookmark {
                    do {
                        var isStale = false
                        let resolvedURL = try URL(
                            resolvingBookmarkData: bookmarkData,
                            options: .withSecurityScope,
                            relativeTo: nil,
                            bookmarkDataIsStale: &isStale
                        )
                        if isStale {
                            // Bookmark is stale; clear it so the user can re-select the file
                            print("⚠️ [TTSSynthesisView] Bookmark is stale, clearing reference audio")
                            config.ttsReferenceAudioPath = ""
                            config.ttsReferenceAudioBookmark = nil
                        } else {
                            print("🔍 [TTSSynthesisView] Restored reference audio via bookmark: \(resolvedURL)")
                            referenceAudioURL = resolvedURL
                        }
                    } catch {
                        print("⚠️ [TTSSynthesisView] Failed to resolve bookmark: \(error). Clearing reference audio.")
                        config.ttsReferenceAudioPath = ""
                        config.ttsReferenceAudioBookmark = nil
                    }
                } else {
                    // No bookmark stored — this can happen with data from before the bookmark
                    // feature was introduced. A plain path URL has no sandbox grant after
                    // restart, so using it would cause error -54 when reading the file.
                    // Clear the stale path and let the user re-select the file.
                    print("⚠️ [TTSSynthesisView] No bookmark for reference audio — clearing stale path (sandbox requires bookmark after restart)")
                    config.ttsReferenceAudioPath = ""
                    // referenceAudioURL stays nil; the user must re-pick the file
                }
            }
        }
        .onChange(of: config.ttsEngine) { _, _ in
            Task { await refreshStatus(force: true) }
            synthesizedAudio = nil
            stopPlayback()
        }
        .onChange(of: config.ttsMLXModelId) { _, _ in
            Task { await refreshStatus(force: true) }
            synthesizedAudio = nil
            stopPlayback()
        }
        .onDisappear {
            generationTask?.cancel()
            cleanupPlayback()
        }
    }

    @ViewBuilder
    private var modelStatusCard: some View {
        if config.ttsEngine == .qwen3TTS && !mlxModelCached {
            HStack(spacing: 0) {
                // Orange accent stripe
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.orange)
                    .frame(width: 4)
                    .padding(.vertical, 2)

                HStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Model not installed")
                            .font(.headline)
                        Text("Download a Qwen3 TTS model from the Models page to get started.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        Button {
                            NotificationCenter.default.post(name: .openModelsLibrary, object: nil)
                        } label: {
                            Label("Get Models", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            Task { await refreshStatus(force: true) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .help("Re-check model status")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.orange.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.orange.opacity(0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var textEditorCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card header row
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Script")
                    .font(.headline)
                Spacer()
                // Char count badge
                HStack(spacing: 4) {
                    Text("\(inputCharacterCount)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(inputCharacterCount > 0 ? Color.accentColor : Color.secondary)
                    Text("chars · ~\(estimatedSpeechDuration, specifier: "%.1f")s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.secondary.opacity(0.08)))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 12)

            // Text editor
            ZStack(alignment: .topLeading) {
                TextEditor(text: $inputText)
                    .font(.system(size: 15, design: .default))
                    .frame(minHeight: 180)
                    .padding(12)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .focused($isEditorFocused)

                if inputText.isEmpty {
                    Text("Paste or type the narration you want to synthesize…")
                        .foregroundStyle(Color.secondary.opacity(0.6))
                        .font(.system(size: 15))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
            .padding(.bottom, 4)

            // Bottom row: Generate button pinned to bottom-right of the script card
            HStack {
                Spacer()
                Button(action: { isSynthesizing ? cancelSynthesis() : generateAudio(shouldExport: false) }) {
                    HStack(spacing: 6) {
                        Image(systemName: isSynthesizing ? "xmark" : "sparkles")
                            .symbolEffect(.pulse.byLayer, options: isSynthesizing ? .repeating : .nonRepeating, value: isSynthesizing)
                        Text(mlxModelLoading
                             ? String(localized: "Loading model…", comment: "Button label while TTS model loads")
                             : isSynthesizing
                             ? String(localized: "Synthesizing…", comment: "Button label while TTS is running")
                             : String(localized: "Generate Speech", comment: "Button label to start TTS synthesis")
                        )
                            .fontWeight(.semibold)
                    }
                    .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent)
                .tint(isSynthesizing ? .red : .accentColor)
                .disabled(!isEngineReady && !isSynthesizing)
                .animation(.easeInOut(duration: 0.2), value: isSynthesizing)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppSurface.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isEditorFocused ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.15),
                    lineWidth: isEditorFocused ? 1.5 : 1
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isEditorFocused)
    }

    private var voiceControlsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "person.wave.2")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Voice Settings")
                    .font(.headline)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 12)

            mlxVoiceControls
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(AppSurface.cardBackground))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.secondary.opacity(0.15)))
    }


    private var mlxVoiceControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            let selectedDef = MLXTTSModelDefinition.availableModels.first {
                $0.huggingFaceRepo == config.ttsMLXModelId
            }

            // Active model row
            HStack(spacing: 12) {
                Text("Model").font(.subheadline).foregroundStyle(.secondary)
                Text(selectedDef?.displayName ?? config.ttsMLXModelId)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Button {
                    NotificationCenter.default.post(name: .openModelsLibrary, object: nil)
                } label: {
                    Label("Manage", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }

            ModelAwareLanguageSelectionView(
                title: String(localized: "Language", comment: "Label for selecting TTS language"),
                selectedLanguage: ttsLanguageBinding,
                contextProvider: {
                    .tts(engine: .qwen3TTS, modelID: config.ttsMLXModelId)
                },
                helpText: String(localized: "Filtered to languages supported by the selected TTS model.", comment: "Help text for TTS language selection")
            )

            // Voice mode tabs driven by model family.
            // Base    → Preset (speaker picker) + Clone (reference audio)
            // Custom  → single Emotion Control section (speaker picker + voice parameter)
            // Design  → single Voice Design section (free-form voice parameter text)
            let availableModes: [VoiceMode] = {
                switch selectedDef?.family {
                case .base:        return [.preset, .clone]
                case .customVoice: return [.emotionControl]
                case .voiceDesign: return [.voiceDesign]
                case .none:        return []
                }
            }()

            if !availableModes.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    if availableModes.count > 1 {
                        Picker("Voice Mode", selection: $voiceMode) {
                            ForEach(availableModes) { mode in
                                Text(mode.localizedTitle).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: availableModes) { _, modes in
                            if !modes.contains(voiceMode) {
                                voiceMode = modes.first ?? .preset
                            }
                        }
                    }

                    switch voiceMode {
                    case .preset:
                        presetSpeakerSection
                    case .clone:
                        voiceCloneSection
                    case .emotionControl:
                        emotionControlSection
                    case .voiceDesign:
                        voiceDesignSection
                    }
                }
                // Normalise voiceMode on first load and whenever the model changes.
                // `.onChange` only fires on subsequent changes, not initial render —
                // so a VoiceDesign model selected at launch would show the wrong section.
                .task(id: config.ttsMLXModelId) {
                    let family = MLXTTSModelDefinition.availableModels
                        .first { $0.huggingFaceRepo == config.ttsMLXModelId }?.family
                    switch family {
                    case .customVoice where voiceMode != .emotionControl:
                        voiceMode = .emotionControl
                    case .voiceDesign where voiceMode != .voiceDesign:
                        voiceMode = .voiceDesign
                    case .base where voiceMode == .emotionControl || voiceMode == .voiceDesign:
                        voiceMode = .preset
                    default:
                        break
                    }
                }
            }
        }
    }

    private var presetSpeakerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Select a built-in voice for synthesis.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text("Speaker")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Speaker", selection: $config.ttsPresetSpeaker) {
                    Text("Default").tag("")
                    Divider()
                    Section("中文") {
                        ForEach(TTSPresetSpeaker.speakers(for: .chinese)) { s in
                            Text(s.name.replacingOccurrences(of: "_", with: " ")).tag(s.name)
                        }
                    }
                    Section("English") {
                        ForEach(TTSPresetSpeaker.speakers(for: .english)) { s in
                            Text(s.name).tag(s.name)
                        }
                    }
                    Section("日本語") {
                        ForEach(TTSPresetSpeaker.speakers(for: .japanese)) { s in
                            Text(s.name.replacingOccurrences(of: "_", with: " ")).tag(s.name)
                        }
                    }
                    Section("한국어") {
                        ForEach(TTSPresetSpeaker.speakers(for: .korean)) { s in
                            Text(s.name).tag(s.name)
                        }
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
            }

            // Speaker description card
            if !config.ttsPresetSpeaker.isEmpty,
               let speaker = TTSPresetSpeaker.all.first(where: { $0.name == config.ttsPresetSpeaker }) {
                HStack(spacing: 10) {
                    Image(systemName: "person.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(speaker.description)
                            .font(.caption)
                            .foregroundStyle(.primary)
                        Text(speaker.nativeLanguage)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.07))
                )
            }
        }
    }

    private var voiceDesignSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enter a text description for the voice parameter passed to the model.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Voice Parameter")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField(
                    "e.g. A warm female voice with a confident, friendly tone",
                    text: $config.ttsVoiceDescription
                )
                .textFieldStyle(.roundedBorder)
            }

            Text("Describe age, gender, accent, emotion, and pace — the more detail, the closer the result.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emotionControlSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Select a speaker and optionally describe the emotion or speaking style.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text("Speaker")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Speaker", selection: $config.ttsPresetSpeaker) {
                    Text("Default").tag("")
                    Divider()
                    Section("中文") {
                        ForEach(TTSPresetSpeaker.speakers(for: .chinese)) { s in
                            Text(s.name.replacingOccurrences(of: "_", with: " ")).tag(s.name)
                        }
                    }
                    Section("English") {
                        ForEach(TTSPresetSpeaker.speakers(for: .english)) { s in
                            Text(s.name).tag(s.name)
                        }
                    }
                    Section("日本語") {
                        ForEach(TTSPresetSpeaker.speakers(for: .japanese)) { s in
                            Text(s.name.replacingOccurrences(of: "_", with: " ")).tag(s.name)
                        }
                    }
                    Section("한국어") {
                        ForEach(TTSPresetSpeaker.speakers(for: .korean)) { s in
                            Text(s.name).tag(s.name)
                        }
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Emotion / Style")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField(
                    "e.g. very happy and excited, warm and friendly",
                    text: $config.ttsEmotionPrompt
                )
                .textFieldStyle(.roundedBorder)
            }

            // Preview of the composed voice string
            let composed = MLXTTSModelDefinition.customVoiceString(
                speaker: config.ttsPresetSpeaker,
                emotionPrompt: config.ttsEmotionPrompt
            )
            if let voiceStr = composed {
                HStack(spacing: 6) {
                    Image(systemName: "quote.bubble.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(voiceStr)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.07))
                )
            }

            Text("The speaker name and style are composed as \"Speaker, emotion\" and passed to the model.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var voiceCloneSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Upload a short audio sample to clone that voice.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        if let url = referenceAudioURL {
                            Label(url.lastPathComponent, systemImage: "waveform")
                                .font(.subheadline)
                                .lineLimit(1)
                        } else {
                            Text("No reference audio selected")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Choose Audio…") {
                            chooseReferenceAudio()
                        }
                        .buttonStyle(.bordered)
                        if referenceAudioURL != nil {
                            Button(role: .destructive) {
                                clearReferenceAudioSelection()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                        }
                    }

                    Text("Drag and drop files or click to choose from Finder")
                        .font(.caption)
                        .foregroundStyle(isReferenceAudioDropTarget ? Color.accentColor : .secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(isReferenceAudioDropTarget ? 0.12 : 0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isReferenceAudioDropTarget ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.18),
                            style: StrokeStyle(lineWidth: isReferenceAudioDropTarget ? 1.5 : 1, dash: [6, 4])
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onTapGesture(perform: chooseReferenceAudio)
                .onDrop(of: [UTType.fileURL.identifier, UTType.audio.identifier], isTargeted: $isReferenceAudioDropTarget, perform: handleDroppedReferenceAudio)
            }

            TextField("Reference transcript (what the audio says)", text: $config.ttsReferenceText)
                .textFieldStyle(.roundedBorder)

            Text("Provide a 3-10 second audio sample and its transcript for best results.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // Status / error feedback row shown below voiceControlsCard
    @ViewBuilder
    private var feedbackRow: some View {
        if let statusMessage {
            HStack(spacing: 6) {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if showHistoryPrompt {
                    Button("View in History →") {
                        selectedSectionStorage = "History"
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
                Spacer()
            }
            .padding(.horizontal, 4)
        }
        if let errorMessage {
            HStack {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, 4)
        }
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Preview")
                    .font(.headline)
                Spacer()
                if playbackDuration > 0 {
                    Text(timecode(playbackProgress) + " / " + timecode(playbackDuration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 12)

            VStack(spacing: 14) {
                // Progress track
                if playbackDuration > 0 {
                    GeometryReader { geo in
                        let progress = playbackDuration > 0 ? playbackProgress / playbackDuration : 0
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.accentColor.opacity(0.8), Color.accentColor],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * CGFloat(progress), height: 6)
                        }
                        .frame(height: 6)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let ratio = max(0, min(1, value.location.x / geo.size.width))
                                    seek(to: ratio * playbackDuration)
                                }
                        )
                    }
                    .frame(height: 20)
                }

                // Controls row
                HStack(spacing: 16) {
                    // Circular play/pause button
                    Button(action: togglePlayback) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 44, height: 44)
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .offset(x: isPlaying ? 0 : 1.5)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(playbackDuration == 0)

                    Button(action: stopPlayback) {
                        ZStack {
                            Circle()
                                .fill(Color.secondary.opacity(0.1))
                                .frame(width: 36, height: 36)
                            Image(systemName: "stop.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!isPlaying && playbackProgress == 0)

                    Spacer()

                    // Export shortcut from preview
                    if synthesizedAudio != nil {
                        Button(action: { exportAudio() }) {
                            Label("Export WAV", systemImage: "square.and.arrow.up")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppSurface.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button(action: { generateAudio(shouldExport: false) }) {
                    Label("Generate Preview", systemImage: "sparkles")
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isEngineReady || isSynthesizing)

                Button(action: { exportAudio() }) {
                    Label("Export WAV", systemImage: "square.and.arrow.up")
                        .frame(minWidth: 140)
                }
                .buttonStyle(.bordered)
                .disabled(isSynthesizing || !isEngineReady)

                if isSynthesizing {
                    ProgressView()
                        .progressViewStyle(.circular)
                }

                Spacer()
            }

            if let statusMessage {
                Label(statusMessage, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundColor(.orange)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppSurface.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.15))
        )
    }

    // MARK: - Voice helpers


    private func voiceSummary(_ profile: TTSVoiceProfile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(profile.displayName)
                    .font(.system(size: 18, weight: .semibold))
                if profile.isRecommended {
                    Text("Recommended")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.2)))
                }
            }
            Text(profile.descriptor)
                .font(.subheadline)
            Text(profile.locale.localizedDisplayName)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !profile.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(profile.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                    }
                }
            }
        }
    }

    private func variantHint(for preference: TTSVariantPreference) -> String {
        switch preference {
        case .automatic:
            return String(localized: "Automatically switches between 5s and 15s variants based on text length.", comment: "Hint for automatic TTS variant selection")
        case .short:
            return String(localized: "Uses the 5-second variant for lowest latency and crisp enunciation.", comment: "Hint for short TTS variant")
        case .extended:
            return String(localized: "Prefers the 15-second variant for longer narration chunks.", comment: "Hint for extended TTS variant")
        }
    }

    // MARK: - Actions

    private func generateAudio(shouldExport: Bool) {
        guard isEngineReady else {
            errorMessage = String(localized: "Download a Qwen3 TTS model before synthesizing.", comment: "Error shown when no TTS model is installed")
            return
        }
        guard !isSynthesizing else { return }
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = String(localized: "Enter some text to synthesize.", comment: "Error shown when the text input is empty")
            return
        }

        isSynthesizing = true
        pendingExportAfterSynthesis = shouldExport
        statusMessage = String(localized: "Synthesizing…", comment: "Status shown while TTS synthesis is running")
        errorMessage = nil
        showHistoryPrompt = false

        generationTask?.cancel()
        generationTask = Task {
            do {
                let audio: Data
                let historySourceName: String
                switch config.ttsEngine {
                case .qwen3TTS:
                    let modelDef = MLXTTSModelDefinition.availableModels.first {
                        $0.huggingFaceRepo == config.ttsMLXModelId
                    } ?? MLXTTSModelDefinition.availableModels[0]
                    historySourceName = modelDef.displayName
                    let engine = config.ttsEngine
                    let modelID = modelDef.huggingFaceRepo

                    print("🔍 [TTSSynthesisView] Model: \(modelDef.displayName)")
                    print("🔍 [TTSSynthesisView] Supports voice clone: \(modelDef.supportsVoiceClone)")
                    print("🔍 [TTSSynthesisView] referenceAudioURL: \(String(describing: referenceAudioURL))")
                    print("🔍 [TTSSynthesisView] config.ttsReferenceText: \(config.ttsReferenceText)")

                    if !mlxModelLoading {
                        await MainActor.run { mlxModelLoading = true; statusMessage = String(localized: "Loading model…", comment: "Status shown while loading TTS model") }
                    }

                    _ = try await ModelCacheManager.shared.ensureTTSModel(
                        engine: engine,
                        modelID: modelID
                    )
                    defer {
                        Task {
                            await ModelCacheManager.shared.releaseTTSModel(engine: engine, modelID: modelID)
                        }
                    }

                    await MainActor.run {
                        mlxModelLoading = false
                        statusMessage = String(localized: "Generating speech…", comment: "Status shown while TTS is actively generating audio")
                    }

                    audio = try await ttsSessionRuntime.synthesize(
                        text: trimmed,
                        modelDefinition: modelDef,
                        voiceDescription: {
                            switch voiceMode {
                            case .voiceDesign:
                                return config.ttsVoiceDescription.isEmpty ? nil : config.ttsVoiceDescription
                            case .emotionControl:
                                return MLXTTSModelDefinition.customVoiceString(
                                    speaker: config.ttsPresetSpeaker,
                                    emotionPrompt: config.ttsEmotionPrompt
                                )
                            case .preset:
                                return config.ttsPresetSpeaker.isEmpty ? nil : config.ttsPresetSpeaker
                            case .clone:
                                return nil
                            }
                        }(),
                        referenceAudioURL: voiceMode == .clone ? referenceAudioURL : nil,
                        referenceText: voiceMode == .clone ? config.ttsReferenceText : nil,
                        language: config.ttsLanguage,
                        variantPreference: config.ttsVariantPreference
                    )
                }
                await MainActor.run {
                    synthesizedAudio = audio
                    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                    statusMessage = String(localized: "Preview updated (\(timestamp)).", comment: "Status shown after synthesis completes, with timestamp")
                    preparePlayback(with: audio)
                    isSynthesizing = false
                    mlxModelLoading = false
                    generationTask = nil
                    showHistoryPrompt = true
                }
                Task(priority: .utility) {
                    await persistTTSSynthesisHistory(
                        text: trimmed,
                        audioData: audio,
                        sourceName: historySourceName
                    )
                }
                if shouldExport {
                    await MainActor.run {
                        presentSavePanel(with: audio)
                        pendingExportAfterSynthesis = false
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    statusMessage = nil
                    errorMessage = nil
                    isSynthesizing = false
                    mlxModelLoading = false
                    pendingExportAfterSynthesis = false
                    generationTask = nil
                    showHistoryPrompt = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    statusMessage = nil
                    isSynthesizing = false
                    mlxModelLoading = false
                    pendingExportAfterSynthesis = false
                    generationTask = nil
                }
            }
        }
    }

    private func cancelSynthesis() {
        pendingExportAfterSynthesis = false
        generationTask?.cancel()
    }

    private func exportAudio() {
        guard isEngineReady else {
            errorMessage = String(localized: "Download a Qwen3 TTS model before exporting.", comment: "Error shown when trying to export without a TTS model installed")
            return
        }
        if let data = synthesizedAudio {
            presentSavePanel(with: data)
        } else {
            pendingExportAfterSynthesis = true
            generateAudio(shouldExport: true)
        }
    }

    private func persistTTSSynthesisHistory(text: String, audioData: Data, sourceName: String) async {
        await MainActor.run {
            ttsSessionRuntime.persistSynthesisHistory(
                text: text,
                audioData: audioData,
                sourceName: sourceName
            )
        }
    }

    private func presentSavePanel(with data: Data) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = defaultFilename()
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                statusMessage = "Saved to \(url.lastPathComponent)"
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Playback

    private func preparePlayback(with data: Data) {
        stopPlayback()
        do {
            let player = try AVAudioPlayer(data: data)
            player.prepareToPlay()
            playbackDuration = player.duration
            playbackProgress = 0
            isPlaying = false

            let delegate = TTSPlaybackDelegate {
                Task { @MainActor in
                    isPlaying = false
                    playbackProgress = 0
                    stopPlaybackTimer()
                }
            }
            playbackDelegate = delegate
            player.delegate = delegate
            audioPlayer = player
        } catch {
            audioPlayer = nil
            errorMessage = "Failed to prepare preview: \(error.localizedDescription)"
        }
    }

    private func togglePlayback() {
        if audioPlayer == nil, let data = synthesizedAudio {
            preparePlayback(with: data)
        }
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

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        playbackProgress = 0
        playbackDuration = 0
        stopPlaybackTimer()
        playbackDelegate = nil
    }

    private func seek(to time: TimeInterval) {
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

    private func cleanupPlayback() {
        stopPlayback()
    }

    private func timecode(_ value: TimeInterval) -> String {
        guard value.isFinite else { return "0:00" }
        let minutes = Int(value) / 60
        let seconds = Int(value) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Model status

    private func refreshStatus(force: Bool = false) async {
        if isCheckingStatus && !force { return }
        await MainActor.run { isCheckingStatus = true }

        var cachedModels: [MLXTTSModelDefinition] = []
        for def in MLXTTSModelDefinition.availableModels {
            let cached = await ModelDownloadManager.shared.hasLocalArtifacts(for: def.modelVariant)
            if cached { cachedModels.append(def) }
        }
        let mlxCached = cachedModels.contains { $0.huggingFaceRepo == config.ttsMLXModelId }

        await MainActor.run {
            mlxModelCached = mlxCached
            isCheckingStatus = false
            if !mlxCached {
                synthesizedAudio = nil
                stopPlayback()
            }
        }
    }

    private var isEngineReady: Bool {
        mlxModelCached
    }

    private func chooseReferenceAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.wav, .mp3, .aiff, .audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            applyReferenceAudioSelection(url)
        }
    }

    // MARK: - Derived values

    private var inputCharacterCount: Int {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    private var estimatedSpeechDuration: Double {
        TTSScriptMetrics.estimatedSpeechDuration(for: inputText)
    }

    private func applyReferenceAudioSelection(_ url: URL) {
        print("🔍 [TTSSynthesisView] Selected reference audio: \(url)")
        print("🔍 [TTSSynthesisView] URL path: \(url.path)")
        print("🔍 [TTSSynthesisView] File exists: \(FileManager.default.fileExists(atPath: url.path))")
        referenceAudioURL = url
        config.ttsReferenceAudioPath = url.path
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            config.ttsReferenceAudioBookmark = bookmarkData
            print("🔍 [TTSSynthesisView] Stored security-scoped bookmark (\(bookmarkData.count) bytes)")
        } catch {
            print("⚠️ [TTSSynthesisView] Failed to create bookmark: \(error)")
            config.ttsReferenceAudioBookmark = nil
        }
    }

    private func clearReferenceAudioSelection() {
        referenceAudioURL = nil
        config.ttsReferenceAudioPath = ""
        config.ttsReferenceAudioBookmark = nil
    }

    private func handleDroppedReferenceAudio(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ||
            $0.hasItemConformingToTypeIdentifier(UTType.audio.identifier)
        }) else {
            return false
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let url = TTSSynthesisReferenceAudioDrop.fileURL(fromDroppedItem: item),
                      Self.isSupportedReferenceAudioURL(url) else {
                    return
                }

                Task { @MainActor in
                    applyReferenceAudioSelection(url)
                }
            }
            return true
        }

        provider.loadInPlaceFileRepresentation(forTypeIdentifier: UTType.audio.identifier) { url, _, _ in
            guard let url, Self.isSupportedReferenceAudioURL(url) else {
                return
            }

            Task { @MainActor in
                applyReferenceAudioSelection(url)
            }
        }
        return true
    }

    nonisolated private static func isSupportedReferenceAudioURL(_ url: URL) -> Bool {
        if let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType {
            return type.conforms(to: .audio)
        }
        if let type = UTType(filenameExtension: url.pathExtension) {
            return type.conforms(to: .audio)
        }
        return false
    }

    private func defaultFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let prefix = "Qwen3TTS"
        return "\(prefix)-\(formatter.string(from: Date())).wav"
    }

    private static let defaultSample =
        "Introducing Cliptate — a macOS-native app that transcribes videos, filters out filler words, and exports studio-ready subtitles. Paste your launch script here to hear how it sounds."
}

private final class TTSPlaybackDelegate: NSObject, AVAudioPlayerDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onFinish()
    }
}

enum TTSSynthesisReferenceAudioDrop {
    static func fileURL(fromDroppedItem item: Any?) -> URL? {
        switch item {
        case let url as URL:
            return normalizedFileURL(from: url)
        case let data as Data:
            if let url = URL(dataRepresentation: data, relativeTo: nil) {
                return normalizedFileURL(from: url)
            }
            return nil
        case let string as String:
            return normalizedFileURL(from: string)
        default:
            return nil
        }
    }

    private static func normalizedFileURL(from url: URL) -> URL? {
        if url.isFileURL {
            return url
        }

        if url.scheme == nil {
            return URL(fileURLWithPath: url.path.isEmpty ? url.relativePath : url.path)
        }

        return nil
    }

    private static func normalizedFileURL(from string: String) -> URL? {
        if string.hasPrefix("file://"), let url = URL(string: string) {
            return url
        }

        return URL(fileURLWithPath: string)
    }
}
