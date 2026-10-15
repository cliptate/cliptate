import AppKit
import SwiftUI

@MainActor
final class AICutDetachedSessionWindowManager {
  static let shared = AICutDetachedSessionWindowManager()

  private final class WindowDelegateProxy: NSObject, NSWindowDelegate {
    var willCloseHandler: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
      willCloseHandler?()
    }
  }

  private var windows: [ObjectIdentifier: NSWindow] = [:]
  private var delegates: [ObjectIdentifier: WindowDelegateProxy] = [:]
  private var suppressWindowPresentationForTesting = false

  func openSession(urls: [URL], config: AppConfiguration) {
    _ = makeSessionWindow(urls: urls, restoredVideoStates: [:], config: config)
  }

  func openSession(urls: [URL], preloadedVideoStates: [URL: VideoState], config: AppConfiguration) {
    _ = makeSessionWindow(urls: urls, restoredVideoStates: preloadedVideoStates, config: config)
  }

  @discardableResult
  private func makeSessionWindow(
    urls: [URL], restoredVideoStates: [URL: VideoState], config: AppConfiguration
  ) -> NSWindow? {
    let normalizedURLs = normalizedFileURLs(from: urls)
    guard !normalizedURLs.isEmpty else { return nil }

    let window = NSWindow(
      contentRect: preferredSessionFrame(),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = sessionTitle(for: normalizedURLs)
    window.isReleasedWhenClosed = false
    window.center()

    let delegate = WindowDelegateProxy()
    let key = ObjectIdentifier(window)
    delegate.willCloseHandler = { [weak self, weak window] in
      guard let self, let window else { return }
      let key = ObjectIdentifier(window)
      self.windows.removeValue(forKey: key)
      self.delegates.removeValue(forKey: key)
    }

    window.delegate = delegate
    delegates[key] = delegate
    windows[key] = window

    if !suppressWindowPresentationForTesting {
      let securityScopeManager = SecurityScopedURLAccessManager()
      let rootView = DetachedAICutSessionRootView(
        initialURLs: normalizedURLs,
        restoredVideoStates: restoredVideoStates,
        onSessionEnded: { [weak window] in
          window?.close()
        }
      )
      .environmentObject(config)
      .environmentObject(securityScopeManager)

      window.contentViewController = NSHostingController(rootView: rootView)
    }
    // Keep the host window invisible — it is a headless state container.
    // The progress and editor windows (opened by AICutWindowCoordinator) are the
    // only windows the user interacts with. Setting alphaValue = 0 makes the window
    // transparent while keeping it in the window hierarchy so that SwiftUI lifecycle
    // events (.task, .onAppear) still fire correctly.
    window.alphaValue = 0
    if suppressWindowPresentationForTesting {
      window.orderOut(nil)
    } else {
      window.orderFront(nil)
    }
    return window
  }

  private func normalizedFileURLs(from urls: [URL]) -> [URL] {
    let unique = Array(NSOrderedSet(array: urls.filter(\.isFileURL))) as? [URL] ?? []
    return unique
  }

  private func sessionTitle(for urls: [URL]) -> String {
    guard let first = urls.first else { return String(localized: "File Transcription Session") }
    if urls.count == 1 {
      return String(localized: "File Transcription: \(first.lastPathComponent)")
    }
    return String(localized: "File Transcription: \(first.lastPathComponent) +\(urls.count - 1)")
  }

  private func preferredSessionFrame() -> NSRect {
    if let sourceWindow = NSApp.windows
      .filter({
        $0.title != AICutWindowCoordinator.progressWindowTitle
          && $0.title != AICutWindowCoordinator.editorWindowTitle && $0.isVisible
      })
      .max(by: { lhs, rhs in
        lhs.frame.width * lhs.frame.height < rhs.frame.width * rhs.frame.height
      })
    {
      return sourceWindow.frame
    }

    return NSRect(x: 0, y: 0, width: 1280, height: 800)
  }
}

extension AICutDetachedSessionWindowManager {
  var activeDetachedWindowCount: Int {
    windows.count
  }

  func resetForTesting() {
    let currentWindows = Array(windows.values)
    windows.removeAll()
    delegates.removeAll()
    suppressWindowPresentationForTesting = false
    for window in currentWindows {
      window.contentViewController = nil
      window.contentView = nil
      window.orderOut(nil)
    }
  }

  @discardableResult
  func openSessionWindowForTesting(urls: [URL], config: AppConfiguration) -> NSWindow {
    suppressWindowPresentationForTesting = true
    return makeSessionWindow(urls: urls, restoredVideoStates: [:], config: config)!
  }
}
