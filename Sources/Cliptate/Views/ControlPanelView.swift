import CliptateCore
import SwiftUI

struct ControlPanelView: View {
  @EnvironmentObject var config: AppConfiguration
  @State private var selectedConfigTab: ConfigTab = .transcription

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

  var body: some View {
    VStack(spacing: 0) {
      sourceSection
      Divider()
      EditorPresetsView()
      Divider()
      ControlPanelConfigurationView(selectedTab: $selectedConfigTab)
    }
    .background(AppSurface.pageBackground)
  }

  private func handleExportAll(for mode: ExportMode) {
    config.exportMode = mode
    onExportAll(config.defaultExportRequest())
  }
}

// MARK: - Source Section
extension ControlPanelView {
  fileprivate var sourceSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Source").font(.headline)
        Spacer()
        sourceSummaryView
      }
      VStack(alignment: .leading, spacing: 8) {
        batchActionsView
        if sourceMode.showsFileList && !videoURLs.isEmpty {
          videoListView
        }
        if sourceMode.showsDropZone {
          dropZoneView
        }
      }
    }
    .padding(12)
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
          .controlSize(.small)
      }

      if sourceMode.showsAddButton {
        Button(action: onSelectFiles) {
          Image(systemName: "folder.badge.plus")
            .font(.caption2)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
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
        .controlSize(.small)
        .help(String(localized: "Cancel transcription", comment: "Tooltip for cancel transcription button"))
      } else {
        Button(action: onTranscribeAll) {
          Image(systemName: "waveform.badge.plus")
            .font(.caption2)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(videoURLs.isEmpty || isTranscribing || isAICorrecting)
        .help(String(localized: "Transcribe all videos", comment: "Tooltip for batch transcribe all button"))
      }

      Button(action: onAICorrect) {
        if isAICorrecting {
          ProgressView().controlSize(.small)
        } else {
          Image(systemName: "sparkles.rectangle.stack")
            .font(.caption2)
        }
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .disabled(!isAIProviderConfigured || !hasAnyTranscribedVideo || isOperationInFlight)
      .help(String(localized: "AI correct all transcribed videos", comment: "Tooltip for batch AI correct button"))

      Button(action: onAIEnhance) {
        if isAIEnhancing {
          ProgressView().controlSize(.small)
        } else {
          Image(systemName: "wand.and.stars")
            .font(.caption2)
        }
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .disabled(!activeVideoHasSegments || isOperationInFlight)
      .help(String(localized: "Apply highlight effect to the active video", comment: "Tooltip for batch AI enhance button"))

      Button(action: onTranslate) {
        if isTranslating {
          ProgressView().controlSize(.small)
        } else {
          Image(systemName: "globe")
            .font(.caption2)
        }
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
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
      .fixedSize()
      .controlSize(.small)
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
    List(selection: $activeVideoURL) {
      ForEach(videoURLs, id: \.self) { url in
        EditorSourceRow(
          url: url,
          hasTranscription: videoStates[url]?.segments.isEmpty == false
        ) {
          sourceActions(for: url)
        }
        .tag(url)
        .contextMenu { sourceActions(for: url) }
      }
    }
    .listStyle(.inset)
    .scrollContentBackground(.hidden)
    .frame(height: min(CGFloat(videoURLs.count) * 36 + 20, 164))
  }

  @ViewBuilder
  private func sourceActions(for url: URL) -> some View {
    let hasTranscription = videoStates[url]?.segments.isEmpty == false
    Button("Transcribe this video", systemImage: "waveform") {
      activeVideoURL = url
      onTranscribe()
    }
    .disabled(isTranscribing || isAICorrecting)
    Button("AI correct this video", systemImage: "sparkles") {
      activeVideoURL = url
      onAICorrectCurrent()
    }
    .disabled(!isAIProviderConfigured || !hasTranscription || isTranscribing || isAICorrecting)
    Button("AI enhance this video", systemImage: "wand.and.stars") {
      activeVideoURL = url
      onAIEnhance()
    }
    .disabled(!hasTranscription || isOperationInFlight)
    Button("Translate this video", systemImage: "globe") {
      activeVideoURL = url
      onTranslate()
    }
    .disabled(!hasTranscription || isOperationInFlight)
    Button("Restore original transcription", systemImage: "arrow.uturn.backward") {
      activeVideoURL = url
      onRestoreOriginal()
    }
    .disabled(!(videoStates[url]?.canRestore ?? false) || isTranscribing || isAICorrecting)
    Divider()
    Button("Export assets for this video using current configuration", systemImage: "square.and.arrow.up") {
      activeVideoURL = url
      onExportSingle(url)
    }
    .disabled(!config.hasAnyExportsEnabled || !hasTranscription || isExporting || isAICorrecting)
    Divider()
    Button("Delete", systemImage: "trash", role: .destructive) {
      videoURLs.removeAll { $0 == url }
      if activeVideoURL == url { activeVideoURL = videoURLs.first }
    }
  }

  fileprivate var dropZoneView: some View {
    DropAreaView(title: "Drag & drop videos here") { urls in
      onImportURLs(urls)
    }
  }
}
