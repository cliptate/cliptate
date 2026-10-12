import AppKit
import SwiftUI

struct AICutLauncherView: View {
  @EnvironmentObject private var config: AppConfiguration

  var body: some View {
    ScrollView {
      AICutLandingView(
        onImportURLs: { urls in
          AICutDetachedSessionWindowManager.shared.openSession(urls: urls, config: config)
        },
        onTap: {
          presentVideoPicker()
        }
      )
    }
    .defaultScrollAnchor(.center, for: .alignment)
    .appPageHeader {
      AppPageHeader(.aiCut)
    }
  }

  @MainActor
  private func presentVideoPicker() {
    let panel = NSOpenPanel()
    panel.prompt = "Open AI Cut Task"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    panel.allowedContentTypes = [.movie, .video]

    if panel.runModal() == .OK {
      AICutDetachedSessionWindowManager.shared.openSession(urls: panel.urls, config: config)
    }
  }
}
