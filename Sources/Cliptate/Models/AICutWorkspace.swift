import Foundation

struct AICutWorkspace {
  let selectedVideoURLs: [URL]
  let activeVideoURL: URL?
  let videoStates: [URL: VideoState]

  var hasSelection: Bool {
    !selectedVideoURLs.isEmpty
  }

  var transcribedURLs: [URL] {
    selectedVideoURLs.filter { url in
      videoStates[url]?.segments.isEmpty == false
    }
  }

  var firstTranscribedURL: URL? {
    transcribedURLs.first
  }
}
