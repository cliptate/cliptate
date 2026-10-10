import Combine
import Sparkle

/// Owns one Sparkle controller for both the full app and its menu bar interface.
/// Sparkle persists its update preferences; they are not transcription presets.
@MainActor
final class AppUpdateManager: ObservableObject {
  static let shared = AppUpdateManager()

  let isAvailable: Bool
  @Published private(set) var canCheckForUpdates = false
  @Published private(set) var automaticallyChecksForUpdates = false
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
    guard canCheckForUpdates else { return }
    controller?.checkForUpdates(nil)
  }

  func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
    controller?.updater.automaticallyChecksForUpdates = enabled
  }
}
