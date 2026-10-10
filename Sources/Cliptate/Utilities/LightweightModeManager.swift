import SwiftUI
import os.log

/// Manages lightweight (menu-bar-only) mode transitions at runtime.
///
/// When active, the main window is closed and the app runs as a menu-bar
/// accessory process — no Dock icon, no window, minimal memory footprint.
/// Global hotkeys remain functional via `KeyboardShortcutManager`.
@MainActor
final class LightweightModeManager: ObservableObject {
  static let shared = LightweightModeManager()

  @Published private(set) var isActive: Bool

  private let logger = Logger(subsystem: "com.Cliptate", category: "LightweightMode")

  private init() {
    isActive = UserDefaults.standard.bool(forKey: "launchInLightweightMode")
  }

  /// Enter lightweight mode: close all windows, hide Dock icon, evict cached models.
  func enterLightweightMode() {
    guard !isActive else { return }
    logger.info("Entering lightweight mode")

    UserDefaults.standard.set(true, forKey: "launchInLightweightMode")
    isActive = true

    // Close all visible app windows
    for window in NSApp.windows where window.isVisible && !isMenuBarPanel(window) {
      window.close()
    }

    NSApp.setActivationPolicy(.accessory)

    // Evict non-essential models (TTS/align) but keep ASR and VAD cached
    Task {
      await ModelCacheManager.shared.evictNonEssentialModels()
    }
  }

  /// Exit lightweight mode: show Dock icon, open main window, re-warm ASR model.
  func exitLightweightMode() {
    guard isActive else { return }
    logger.info("Exiting lightweight mode")

    UserDefaults.standard.set(false, forKey: "launchInLightweightMode")
    isActive = false

    showMainWindow()

    // Re-warm the configured ASR model
    TranscriberWarmupCoordinator.shared.triggerWarmup()
  }

  /// Open the UI without changing the user's lightweight startup preference.
  func showMainWindow() {

    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)

    // Give AppKit a moment to register the policy change before opening window
    DispatchQueue.main.async {
      let appWindows = NSApp.windows.filter { !self.isMenuBarPanel($0) }
      if let existingWindow = appWindows.first(where: { $0.isVisible }) {
        existingWindow.makeKeyAndOrderFront(nil)
      } else if let miniaturized = appWindows.first(where: { $0.isMiniaturized }) {
        miniaturized.deminiaturize(nil)
        miniaturized.makeKeyAndOrderFront(nil)
      } else {
        NSApp.sendAction(#selector(NSApplication.newWindowForTab(_:)), to: nil, from: nil)
      }
      NSApp.activate(ignoringOtherApps: true)
    }

  }

  /// Panels used by MenuBarExtra should not be closed when entering lightweight mode.
  private func isMenuBarPanel(_ window: NSWindow) -> Bool {
    window.level == .statusBar || window.level == .popUpMenu
      || String(describing: type(of: window)).contains("MenuBarExtra")
  }
}
