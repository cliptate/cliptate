import SwiftUI

struct ControlPanelView: View {
  @EnvironmentObject var config: AppConfiguration
  @StateObject private var presetStore = ConfigPresetStore.shared
  private let configurationRuntime = ConfigurationRuntime.shared
  @State private var selectedPresetID: UUID? = nil
  @State private var isApplyingPreset: Bool = false  // 防止应用预设时触发反向自动保存循环
  @State private var isShowingPresetEditor = false
  @State private var presetEditorMode: PresetEditorMode = .create
  @State private var workingPresetName: String = ""
  @State private var makeDefaultOnCreate: Bool = true
  @State private var renameTarget: ConfigPreset? = nil
  @State private var selectedConfigTab: ConfigTab = .transcription
  @State private var autoSyncTask: Task<Void, Never>? = nil

  @Binding var videoURLs: [URL]
  @Binding var activeVideoURL: URL?
  var sourceMode: AICutEditorSourceMode
  var onSelectFiles: () -> Void
  var onImportURLs: ([URL]) -> Void
  var onTranscribe: () -> Void
  var onTranscribeAll: () -> Void
  var onCancelTranscription: () -> Void
  var onExportAll: (ExportAllRequest) -> Void
  var onExportSingle: (URL) -> Void
  var onAICorrect: () -> Void
  var onAICorrectCurrent: () -> Void
  var onRestoreOriginal: () -> Void
  var onAIEnhance: () -> Void
  var onTranslate: () -> Void

  var isTranscribing: Bool
  var isExporting: Bool
  var isAICorrecting: Bool
  var isAIEnhancing: Bool
  var isTranslating: Bool
  var isFileSelected: Bool
  var segments: [Segment]
  var videoStates: [URL: VideoState]

  private var isAIProviderConfigured: Bool {
    guard config.aiEnabled else { return false }
    guard
      let key = config.aiProviderKeys[config.selectedAIProvider]?.trimmingCharacters(
        in: .whitespacesAndNewlines), !key.isEmpty
    else {
      return false
    }
    return true
  }

  private var hasAnyTranscribedVideo: Bool {
    videoStates.values.contains { !$0.segments.isEmpty }
  }

  private var isOperationInFlight: Bool {
    isTranscribing || isExporting || isAICorrecting || isAIEnhancing || isTranslating
  }

  private var activeVideoHasSegments: Bool {
    guard let active = activeVideoURL else { return false }
    return videoStates[active]?.segments.isEmpty == false
  }

  private var activeVideoState: VideoState? {
    guard let activeVideoURL else { return nil }
    return videoStates[activeVideoURL]
  }

  // Configuration tabs
  enum ConfigTab: String, CaseIterable, Identifiable {
    case transcription = "Transcription"
    case translation = "Translation"
    case enhance = "Enhance"
    case output = "Export"

    var id: String { rawValue }
    var icon: String {
      switch self {
      case .transcription: return "waveform"
      case .translation: return "globe"
      case .output: return "square.and.arrow.up"
      case .enhance: return "wand.and.stars.inverse"
      }
    }
    /// Properly-extracted localized label for Xcode to statically discover.
    var localizedTitle: String {
      switch self {
      case .transcription:
        return String(localized: "Transcription", comment: "Tab label for transcription settings section")
      case .translation:
        return String(localized: "Translation", comment: "Tab label for translation settings section")
      case .enhance:
        return String(localized: "Enhance", comment: "Tab label for enhance settings section")
      case .output:
        return String(localized: "Export", comment: "Tab label for export settings section")
      }
    }
  }

  // 预设自动同步：去掉“脏”状态点，因为只要当前选中的预设会随着配置实时更新。

  var body: some View {
    ScrollView {
      VStack(spacing: 16) {

        sourceSection
          .padding(.top, 8)

        // Presets section placed above other configuration sections
        presetsSection

        // Configuration tabs
        configurationSection
      }
      .padding(.vertical, 8)
      .padding(.horizontal, 8)
    }
    .sheet(isPresented: $isShowingPresetEditor) { presetEditorSheet }
    .onReceive(config.objectWillChange) { _ in
      autoSyncTask?.cancel()
      autoSyncTask = Task { @MainActor in
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard !Task.isCancelled else { return }
        autoSyncPreset()
      }
    }
  }

  // MARK: - Unified Preset Editor Sheet
  private var presetEditorSheet: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(presetEditorMode.title)
        .font(.headline)
      TextField("Preset Name", text: $workingPresetName)
        .textFieldStyle(.roundedBorder)
      if presetEditorMode == .create {
        Toggle("Set as Default", isOn: $makeDefaultOnCreate)
      }
      HStack {
        Spacer()
        Button("Cancel") { isShowingPresetEditor = false }
        Button("Save") { commitPresetEditor() }
          .keyboardShortcut(.defaultAction)
          .disabled(workingPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(24)
    .frame(width: 360)
  }

  private enum PresetEditorMode {
    case create, rename
    var title: String {
      self == .create
        ? String(localized: "New Preset", comment: "Preset editor sheet title when creating")
        : String(localized: "Rename Preset", comment: "Preset editor sheet title when renaming")
    }
  }

  // MARK: - Actions
  private func captureNewPreset(makeDefault: Bool) {
    makeDefaultOnCreate = makeDefault
    presetEditorMode = .create
    workingPresetName = ""
    isShowingPresetEditor = true
  }

  private func beginRename(_ preset: ConfigPreset) {
    renameTarget = preset
    workingPresetName = preset.name
    presetEditorMode = .rename
    isShowingPresetEditor = true
  }

  private func commitPresetEditor() {
    switch presetEditorMode {
    case .create:
      do {
        let preset = try presetStore.create(
          from: config, name: workingPresetName, makeDefault: makeDefaultOnCreate)
        selectedPresetID = preset.id
      } catch {}
    case .rename:
      guard let target = renameTarget else { return }
      do {
        try presetStore.update(id: target.id) { p in p.name = workingPresetName }
      } catch {}
    }
    isShowingPresetEditor = false
  }

  private func duplicatePreset(_ preset: ConfigPreset) {
    do {
      _ = try presetStore.create(from: config, name: preset.name, makeDefault: false)
    } catch {}
  }

  private func deletePreset(_ preset: ConfigPreset) {
    do {
      try presetStore.delete(id: preset.id)
      if selectedPresetID == preset.id { selectedPresetID = presetStore.presets.first?.id }
    } catch {}
  }

  // MARK: - Auto Sync Selected Preset
  private func autoSyncPreset() {
    guard !isApplyingPreset else { return }

    // 如果没有选中预设，尝试使用 Default 预设
    let targetID = selectedPresetID ?? presetStore.presets.first(where: { $0.isDefault })?.id

    guard let id = targetID,
      presetStore.presets.first(where: { $0.id == id }) != nil
    else { return }

    do {
      try presetStore.update(id: id) { p in
        p.payload = presetStore.payload(from: config)
      }
    } catch {
      print("⚠️ Failed to auto-sync preset: \(error.localizedDescription)")
    }
  }

  private func handleExportAll(for mode: ExportMode) {
    config.exportMode = mode
    let request = config.defaultExportRequest()
    onExportAll(request)
  }

}

// MARK: - Source Section
extension ControlPanelView {
  fileprivate var sourceSection: some View {
    SidebarSection("Source", systemImage: "tray.and.arrow.down") {
      VStack(alignment: .leading, spacing: 8) {
        sourceSummaryView
        batchActionsView
        if sourceMode.showsFileList && !videoURLs.isEmpty {
          videoListView
        }
        if sourceMode.showsDropZone {
          dropZoneView
        }
      }
    }
  }
}

extension ControlPanelView {
  @ViewBuilder
  fileprivate var sourceSummaryView: some View {
    if videoURLs.isEmpty {
      Text("No files selected")
        .font(.caption)
        .foregroundColor(.secondary)
    } else {
      VStack(alignment: .leading, spacing: 4) {
        let transcribedCount = videoURLs.filter {
          videoStates[$0]?.segments.isEmpty == false
        }.count
        Text("Total: \(videoURLs.count) (\(transcribedCount) transcribed)")
          .font(.caption)
          .foregroundColor(.secondary)
        if let active = activeVideoURL {
          Text(active.lastPathComponent)
            .font(.caption2)
            .lineLimit(2)
        }
      }
    }
  }

  fileprivate var batchActionsView: some View {
    HStack(spacing: 6) {
      Text("Batch Actions")
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundColor(.secondary)
      Spacer()
      if isOperationInFlight {
        ProgressView()
          .controlSize(.mini)
      }

      if sourceMode.showsAddButton {
        Button(action: onSelectFiles) {
          Image(systemName: "folder.badge.plus")
            .font(.caption2)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.mini)
        .disabled(isOperationInFlight)
        .help(String(localized: "Add files", comment: "Tooltip for batch add files button"))
      }

      if isTranscribing {
        Button(action: onCancelTranscription) {
          Image(systemName: "stop.circle.fill")
            .font(.caption2)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .controlSize(.mini)
        .help(String(localized: "Cancel transcription", comment: "Tooltip for cancel transcription button"))
      } else {
        Button(action: onTranscribeAll) {
          Image(systemName: "waveform.badge.plus")
            .font(.caption2)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .disabled(videoURLs.isEmpty || isTranscribing || isAICorrecting)
        .help(String(localized: "Transcribe all videos", comment: "Tooltip for batch transcribe all button"))
      }

      Button(action: onAICorrect) {
        if isAICorrecting {
          ProgressView().controlSize(.mini)
        } else {
          Image(systemName: "sparkles.rectangle.stack")
            .font(.caption2)
        }
      }
      .buttonStyle(.bordered)
      .controlSize(.mini)
      .disabled(!isAIProviderConfigured || !hasAnyTranscribedVideo || isOperationInFlight)
      .help(String(localized: "AI correct all transcribed videos", comment: "Tooltip for batch AI correct button"))

      Button(action: onAIEnhance) {
        if isAIEnhancing {
          ProgressView().controlSize(.mini)
        } else {
          Image(systemName: "wand.and.stars")
            .font(.caption2)
        }
      }
      .buttonStyle(.bordered)
      .controlSize(.mini)
      .disabled(!activeVideoHasSegments || isOperationInFlight)
      .help(String(localized: "Apply highlight effect to the active video", comment: "Tooltip for batch AI enhance button"))

      Button(action: onTranslate) {
        if isTranslating {
          ProgressView().controlSize(.mini)
        } else {
          Image(systemName: "globe")
            .font(.caption2)
        }
      }
      .buttonStyle(.bordered)
      .controlSize(.mini)
      .disabled(!activeVideoHasSegments || isOperationInFlight)
      .help(String(localized: "Translate segments of the active video", comment: "Tooltip for batch translate button"))

      Menu {
        Button(String(localized: "Merge", comment: "Export mode: merge all videos into one")) {
          handleExportAll(for: .merge)
        }
        Button(String(localized: "Separate", comment: "Export mode: export each video separately")) {
          handleExportAll(for: .separate)
        }
      } label: {
        Image(systemName: "square.and.arrow.up")
          .font(.caption2)
      }
      .menuStyle(.borderedButton)
      .controlSize(.mini)
      .disabled(isExporting || isAICorrecting || !hasAnyTranscribedVideo || !config.hasAnyExportsEnabled)
      .help(
        config.hasAnyExportsEnabled
          ? String(localized: "Export all videos", comment: "Tooltip for batch export button")
          : String(localized: "Enable an export option in Output settings to export all videos", comment: "Tooltip when no export options are enabled")
      )
    }
    .padding(.horizontal, 4)
  }

  fileprivate var videoListView: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 6) {
        ForEach(videoURLs, id: \.self) { url in
          videoRow(for: url)
        }
      }
      .padding(4)
      .frame(maxHeight: 150)
    }
    .background(
      Color.primary.opacity(0.03),
      in: RoundedRectangle(cornerRadius: 8, style: .continuous)
    )
  }

  fileprivate func videoRow(for url: URL) -> some View {
    let isActive = (url == activeVideoURL)
    let hasTranscription = videoStates[url]?.segments.isEmpty == false
    let canRestore = videoStates[url]?.canRestore ?? false
    let aiCorrectDisabled =
      !isAIProviderConfigured || !hasTranscription || isTranscribing || isAICorrecting

    return VStack(alignment: .leading, spacing: 4) {
      Button(action: { activeVideoURL = url }) {
        HStack(spacing: 6) {
          Image(systemName: isActive ? "play.circle.fill" : "video")
            .foregroundColor(isActive ? .accentColor : .secondary)
            .font(.caption)

          Circle()
            .fill(hasTranscription ? Color.green : Color.gray.opacity(0.3))
            .frame(width: 6, height: 6)

          Text(url.lastPathComponent)
            .font(.caption2)
            .lineLimit(1)
          Spacer()
          Button(role: .destructive) {
            videoURLs.removeAll { $0 == url }
            if activeVideoURL == url { activeVideoURL = videoURLs.first }
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.caption)
          }
          .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
      }
      .buttonStyle(.plain)

      HStack(spacing: 4) {
        Button(action: {
          activeVideoURL = url
          onTranscribe()
        }) {
          Image(systemName: "waveform")
            .font(.caption2)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .disabled(isTranscribing || isAICorrecting)
        .help("Transcribe this video")

        Button(action: {
          activeVideoURL = url
          onAICorrectCurrent()
        }) {
          Image(systemName: "sparkles")
            .font(.caption2)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .disabled(aiCorrectDisabled)
        .help("AI correct this video")

        Button(action: {
          activeVideoURL = url
          onAIEnhance()
        }) {
          Image(systemName: "wand.and.stars")
            .font(.caption2)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .disabled(!hasTranscription || isOperationInFlight)
        .help("AI enhance this video")

        Button(action: {
          activeVideoURL = url
          onTranslate()
        }) {
          Image(systemName: "globe")
            .font(.caption2)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .disabled(!hasTranscription || isOperationInFlight)
        .help(String(localized: "Translate this video", comment: "Tooltip for per-video translate button"))

        Button(action: {
          activeVideoURL = url
          onRestoreOriginal()
        }) {
          Image(systemName: "arrow.uturn.backward")
            .font(.caption2)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .disabled(!canRestore || isTranscribing || isAICorrecting)
        .help("Restore original transcription")

        Button(action: {
          activeVideoURL = url
          onExportSingle(url)
        }) {
          Image(systemName: "square.and.arrow.up")
            .font(.caption2)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .disabled(
          !config.hasAnyExportsEnabled || !hasTranscription || isExporting || isAICorrecting
        )
        .help(
          config.hasAnyExportsEnabled
            ? "Export assets for this video using current configuration"
            : "Enable an export option in Output settings to export this video")
      }
      .padding(.horizontal, 8)
      .padding(.bottom, 4)
    }
    .background(
      isActive ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05),
      in: RoundedRectangle(cornerRadius: 6, style: .continuous)
    )
  }

  fileprivate var dropZoneView: some View {
    DropAreaView(title: "Drag & drop videos here") { urls in
      onImportURLs(urls)
    }
  }
}

// MARK: - Presets Section (extracted)
extension ControlPanelView {
  fileprivate var presetsSection: some View {
    SidebarSection("Presets", systemImage: "bookmark") {
      if presetStore.presets.isEmpty {
        HStack(spacing: 8) {
          Image(systemName: "bookmark.slash")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text("No presets")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          Button {
            captureNewPreset(makeDefault: true)
          } label: {
            Label("Save", systemImage: "plus")
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
      } else {
        HStack(spacing: 8) {
          Picker(
            "Preset",
            selection: Binding(
              get: {
                selectedPresetID ?? presetStore.presets.first(where: { $0.isDefault })?.id
              },
              set: { newVal in
                selectedPresetID = newVal
                if let id = newVal {
                  isApplyingPreset = true
                  try? configurationRuntime.applyPreset(id: id, to: config)
                  DispatchQueue.main.async { isApplyingPreset = false }
                }
              }
            )
          ) {
            ForEach(presetStore.presets) { p in
              Text(p.isDefault ? "★ " + p.name : p.name).tag(Optional.some(p.id))
            }
          }
          .labelsHidden()
          .frame(maxWidth: .infinity, alignment: .leading)
          .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedPresetID)

          Menu {
            if let id = selectedPresetID,
              let preset = presetStore.presets.first(where: { $0.id == id })
            {
              Button {
                captureNewPreset(makeDefault: false)
              } label: {
                Label("New Preset", systemImage: "plus")
              }
              Divider()
              Button {
                beginRename(preset)
              } label: {
                Label("Rename", systemImage: "pencil")
              }
              Button {
                duplicatePreset(preset)
              } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
              }
              Button {
                try? presetStore.setDefault(id: preset.id)
              } label: {
                Label("Set Default", systemImage: "star.fill")
              }
              Divider()
              Button {
                configurationRuntime.resetToDefaults(using: config)
                selectedPresetID = presetStore.presets.first(where: { $0.isDefault })?.id
              } label: {
                Label("Reset to Factory Defaults", systemImage: "arrow.counterclockwise")
              }
              Divider()
              Button(role: .destructive) {
                deletePreset(preset)
              } label: {
                Label("Delete", systemImage: "trash")
              }
            } else {
              Button {
                captureNewPreset(makeDefault: true)
              } label: {
                Label("New Preset", systemImage: "plus")
              }
            }
          } label: {
            Image(systemName: "ellipsis.circle")
              .imageScale(.medium)
          }
          .menuIndicator(.hidden)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .onAppear {
      if presetStore.presets.isEmpty { try? presetStore.load() }
      if let createdOrDefault = try? presetStore.ensureDefaultPreset(using: config) {
        if selectedPresetID == nil { selectedPresetID = createdOrDefault.id }
      }
    }
    .padding(10)
    .background {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(.thinMaterial)
        .overlay(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: presetStore.presets.isEmpty)
    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: presetStore.presets.count)
  }
}

// MARK: - Configuration Section with Tabs
extension ControlPanelView {
  fileprivate var configurationSection: some View {
    ControlPanelConfigurationView(
      selectedTab: $selectedConfigTab
    )
  }
}
