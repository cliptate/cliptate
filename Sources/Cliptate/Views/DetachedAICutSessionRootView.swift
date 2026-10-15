import CliptateCore
import SwiftUI

struct DetachedAICutSessionRootView: View {
  let initialURLs: [URL]
  let restoredVideoStates: [URL: VideoState]
  let onSessionEnded: () -> Void

  @State private var selectedVideoURLs: [URL] = []
  @State private var activeVideoURL: URL?
  @State private var videoStates: [URL: VideoState] = [:]
  @State private var isTranscribing = false
  @State private var isExporting = false
  @State private var statusText = String(localized: "Preparing AI Cut session...", comment: "Initial status when opening a detached AI Cut window")
  @State private var isInitializingModel = false
  @State private var modelDownloadProgress: ModelDownloadProgress?
  @State private var batchTranscriptionProgress: (current: Int, total: Int)?

  init(initialURLs: [URL], restoredVideoStates: [URL: VideoState] = [:], onSessionEnded: @escaping () -> Void) {
    self.initialURLs = initialURLs
    self.restoredVideoStates = restoredVideoStates
    self.onSessionEnded = onSessionEnded
  }

  var body: some View {
    AICutView(
      selectedVideoURLs: $selectedVideoURLs,
      activeVideoURL: $activeVideoURL,
      videoStates: $videoStates,
      isTranscribing: $isTranscribing,
      isExporting: $isExporting,
      statusText: $statusText,
      isInitializingModel: $isInitializingModel,
      modelDownloadProgress: $modelDownloadProgress,
      batchTranscriptionProgress: $batchTranscriptionProgress,
      launchURLs: initialURLs,
      restoredVideoStates: restoredVideoStates,
      onSessionEnded: onSessionEnded
    )
  }
}
