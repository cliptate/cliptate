import AppKit
import SwiftUI

enum AICutEditorSourceMode: Equatable {
  case importable
  case editingOnly

  var showsFileList: Bool {
    true
  }

  var showsAddButton: Bool {
    switch self {
    case .importable:
      return true
    case .editingOnly:
      return false
    }
  }

  var showsDropZone: Bool {
    switch self {
    case .importable:
      return true
    case .editingOnly:
      return false
    }
  }
}

enum AICutUserDefaultsKeys {
  static let statusPanelVisible = "AICutEditor.statusPanelVisible"
}

struct AICutEditorView: View {
  @EnvironmentObject private var config: AppConfiguration
  @AppStorage(AICutUserDefaultsKeys.statusPanelVisible) private var isStatusPanelVisible: Bool = true

  let securityScopeManager: SecurityScopedURLAccessManager
  @Binding var selectedVideoURLs: [URL]
  @Binding var activeVideoURL: URL?

  let sourceMode: AICutEditorSourceMode
  let videoStates: [URL: VideoState]
  let statusText: String
  let modelDownloadProgress: ModelDownloadProgress?
  let isInitializingModel: Bool
  let batchTranscriptionProgress: (current: Int, total: Int)?
  let isTranscribing: Bool
  let isExporting: Bool
  let exportProgress: ExportProgressState
  var onDismissExport: (() -> Void)? = nil
  let isAICorrecting: Bool
  let isAIEnhancing: Bool
  let isTranslating: Bool
  let activeVideoState: VideoState?
  let processedSegments: [Segment]
  let translationsVersion: Int
  let currentPlayback: VideoPlaybackCoordinator
  let previewSegments: [Segment]
  let previewEffects: [String: SegmentEffectState]
  let onSelectFiles: () -> Void
  let onImportURLs: ([URL]) -> Void
  let onTranscribe: () -> Void
  let onTranscribeAll: () -> Void
  let onCancelTranscription: () -> Void
  let onExportAll: (ExportAllRequest) -> Void
  let onExportSingle: (URL) -> Void
  let onAICorrect: () -> Void
  let onAICorrectCurrent: () -> Void
  let onRestoreOriginal: () -> Void
  let onAIEnhance: () -> Void
  let onTranslate: () -> Void
  let onPreviewSegmentDelete: (Segment) -> Void
  let onSegmentUpdate: (SegmentsPanelView.DisplaySeg, String) -> Void
  let onTranslationUpdate: (SegmentsPanelView.DisplaySeg, String?) -> Void
  let onSegmentDelete: (SegmentsPanelView.DisplaySeg) -> Void

  var body: some View {
    let cachedSegments = processedSegments

    HSplitView {
      VStack(spacing: 14) {
        ControlPanelView(
          videoURLs: $selectedVideoURLs,
          activeVideoURL: $activeVideoURL,
          sourceMode: sourceMode,
          onSelectFiles: onSelectFiles,
          onImportURLs: onImportURLs,
          onTranscribe: onTranscribe,
          onTranscribeAll: onTranscribeAll,
          onCancelTranscription: onCancelTranscription,
          onExportAll: onExportAll,
          onExportSingle: onExportSingle,
          onAICorrect: onAICorrect,
          onAICorrectCurrent: onAICorrectCurrent,
          onRestoreOriginal: onRestoreOriginal,
          onAIEnhance: onAIEnhance,
          onTranslate: onTranslate,
          isTranscribing: isTranscribing,
          isExporting: isExporting,
          isAICorrecting: isAICorrecting,
          isAIEnhancing: isAIEnhancing,
          isTranslating: isTranslating,
          isFileSelected: activeVideoURL != nil,
          segments: cachedSegments,
          videoStates: videoStates
        )
        .environmentObject(config)

        StatusView(
          statusText: statusText,
          modelDownloadProgress: modelDownloadProgress,
          isInitializingModel: isInitializingModel,
          batchTranscriptionProgress: batchTranscriptionProgress,
          onDismiss: {
            isStatusPanelVisible = false
          },
          onShow: {
            isStatusPanelVisible = true
          },
          isVisible: isStatusPanelVisible
        )
      }
      .frame(minWidth: 360, idealWidth: 400, maxWidth: 520)
      .padding(.vertical, 12)

      GeometryReader { proxy in
        let containerSize = proxy.size

        ZStack {
          if let activeURL = activeVideoURL, let state = videoStates[activeURL] {
            SecurityScopedAccessView(url: activeURL, securityScopeManager: securityScopeManager) {
              VideoPlayerView(
                url: activeURL,
                videoState: state,
                segments: previewSegments,
                filterSilentSegments: config.filterSilent,
                playback: currentPlayback,
                activeURL: activeVideoURL,
                effects: previewEffects,
                translationPlacement: config.translationPlacement,
                styleConfiguration: config.subtitleStyles,
                onSegmentDelete: onPreviewSegmentDelete
              )
              .id("\(activeURL.absoluteString)-\(state.playerViewId.uuidString)")
            }
            .frame(width: containerSize.width, height: containerSize.height)
            .transition(.opacity)
          } else {
            editorPlaceholder
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
          ExportProgressOverlay(exportProgress: exportProgress, onDismiss: onDismissExport)
            .padding(.bottom, 16)
        }
      }
      .frame(minWidth: 260, idealWidth: 320, maxWidth: .infinity)
      .layoutPriority(2)

      ZStack {
        if cachedSegments.isEmpty {
          VStack(spacing: 8) {
            Image(systemName: "text.bubble")
              .font(.system(size: 28))
              .foregroundStyle(.secondary)
            Text("No Segments")
              .font(.headline)
              .foregroundStyle(.primary)
            Text("Please transcribe the video to view segment details")
              .font(.caption)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }
          .padding(24)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(.thinMaterial)
          .clipShape(RoundedRectangle(cornerRadius: 14))
          .overlay(
            RoundedRectangle(cornerRadius: 14)
              .strokeBorder(.separator.opacity(0.25), lineWidth: 1)
          )
          .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }

        if let vs = activeVideoState {
          SegmentsPanelView(
            videoState: vs,
            effects: previewEffects,
            playback: currentPlayback,
            onSegmentUpdate: onSegmentUpdate,
            onTranslationUpdate: onTranslationUpdate,
            onSegmentDelete: onSegmentDelete
          )
          .environmentObject(config)
          .opacity(vs.segments.isEmpty ? 0 : 1)
          .animation(.easeInOut(duration: 0.25), value: vs.segments.isEmpty)
        }
      }
      .padding(12)
      .frame(minWidth: 320, idealWidth: 400, maxWidth: 580)
      .layoutPriority(1)
      .id(activeVideoURL)
    }
  }

  private var editorPlaceholder: some View {
    VStack(spacing: 20) {
      ZStack {
        Circle()
          .fill(Color.accentColor.opacity(0.1))
          .frame(width: 120, height: 120)

        Image(systemName: "video.fill")
          .font(.system(size: 48))
          .foregroundStyle(Color.accentColor)
      }

      VStack(spacing: 12) {
        Text("Select a Video")
          .font(.title2)
          .fontWeight(.semibold)
          .foregroundStyle(.primary)

        Text("Choose a source from the sidebar to preview and edit it here.")
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.regularMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .overlay(
      RoundedRectangle(cornerRadius: 16)
        .strokeBorder(.separator.opacity(0.3), lineWidth: 1)
    )
    .padding(24)
  }
}
