import AppKit

@MainActor
final class CliptateApplicationDelegate: NSObject, NSApplicationDelegate {
  #if !APP_STORE
  private let cliDelegate = CLIApplicationDelegate()

  func application(_ application: NSApplication, open urls: [URL]) {
    cliDelegate.application(application, open: urls)
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    cliDelegate.applicationShouldHandleReopen(sender, hasVisibleWindows: flag)
  }
  #endif

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard !RuntimeEnvironment.isRunningTests else { return }
    AnalyticsRuntime.shared.bind(to: AppConfiguration.shared)
    AnalyticsRuntime.shared.record(.appLaunched)
  }
}
