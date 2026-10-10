import AppKit
import Combine
import Foundation
import Sparkle

/// Owns one Sparkle controller for both the full app and its menu bar interface.
/// Sparkle persists its update preferences; they are not transcription presets.
@MainActor
final class AppUpdateManager: ObservableObject {
  static let shared = AppUpdateManager()

  let isAvailable: Bool
  @Published private(set) var canCheckForUpdates = false
  @Published private(set) var automaticallyChecksForUpdates = false
  @Published private(set) var isCheckingFeed = false
  private var controller: SPUStandardUpdaterController?

  private init() {
    isAvailable = AppUpdateConfiguration.current.isEnabled
  }

  func start() {
    guard isAvailable, !RuntimeEnvironment.isRunningTests, controller == nil else { return }
    let controller = SPUStandardUpdaterController(
      startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    self.controller = controller
    controller.updater.publisher(for: \.canCheckForUpdates)
      .assign(to: &$canCheckForUpdates)
    controller.updater.publisher(for: \.automaticallyChecksForUpdates)
      .assign(to: &$automaticallyChecksForUpdates)
    controller.startUpdater()
  }

  func checkForUpdates() {
    guard canCheckForUpdates, !isCheckingFeed, let controller else { return }
    isCheckingFeed = true
    Task {
      defer { isCheckingFeed = false }
      if let feed = controller.updater.feedURL,
        (try? await Self.isFeedMissing(feed)) == true
      {
        showUnpublishedFeedNotice()
        return
      }
      // Sparkle retains normal error reporting and signature verification for all other results.
      guard canCheckForUpdates else { return }
      controller.checkForUpdates(nil)
    }
  }

  nonisolated static func isFeedMissing(
    _ feed: URL,
    fetch: @Sendable (URLRequest) async throws -> URLResponse = {
      try await URLSession.shared.data(for: $0).1
    }
  ) async throws -> Bool {
    var request = URLRequest(url: feed, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
    request.httpMethod = "HEAD"
    let response = try await fetch(request)
    return (response as? HTTPURLResponse)?.statusCode == 404
  }

  private func showUnpublishedFeedNotice() {
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = String(localized: "Update information is not published yet.")
    alert.informativeText = String(
      localized: "This update channel does not have a published update feed yet. Please check the GitHub releases page for available downloads."
    )
    alert.addButton(withTitle: String(localized: "OK"))
    alert.addButton(withTitle: String(localized: "View Releases"))
    NSApp.activate()
    if alert.runModal() == .alertSecondButtonReturn,
      let url = URL(string: "https://github.com/cliptate/cliptate/releases")
    {
      NSWorkspace.shared.open(url)
    }
  }

  func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
    controller?.updater.automaticallyChecksForUpdates = enabled
  }
}
