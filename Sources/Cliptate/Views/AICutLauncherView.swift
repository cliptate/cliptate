import AppKit
import SwiftUI

struct AICutLauncherView: View {
  @EnvironmentObject private var config: AppConfiguration

  var body: some View {
    GeometryReader { proxy in
      ScrollView {
        AICutLandingView(
          onImportURLs: { urls in
            AICutDetachedSessionWindowManager.shared.openSession(urls: urls, config: config)
          },
          onTap: presentVideoPicker
        )
        .frame(minHeight: proxy.size.height)
      }
    }
    .background(AppSurface.contentBackground)
    .appPageHeader {
      AppPageHeader(.aiCut, background: AppSurface.contentBackground)
    }
  }

  @MainActor
  private func presentVideoPicker() {
    let panel = NSOpenPanel()
    panel.prompt = String(localized: "Choose Videos")
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    panel.allowedContentTypes = [.movie, .video]

    if panel.runModal() == .OK {
      AICutDetachedSessionWindowManager.shared.openSession(urls: panel.urls, config: config)
    }
  }
}
