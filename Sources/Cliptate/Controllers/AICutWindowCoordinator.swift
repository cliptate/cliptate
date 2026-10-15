import AppKit
import SwiftUI

@MainActor
final class AICutWindowCoordinator: ObservableObject {
  static var editorWindowTitle: String { String(localized: "File Transcription Editor") }
  static var progressWindowTitle: String { String(localized: "File Transcription Progress") }

  enum TransitionEvent: Equatable {
    case closeProgressWindow
    case runBeforeOpenAction
    case openEditorWindow
    case activateEditorWindow
    case notifyEditorWindowClosed
  }

  private final class TestingProbe {
    private(set) var events: [TransitionEvent] = []

    func reset() {
      events = []
    }

    func record(_ event: TransitionEvent) {
      events.append(event)
    }
  }

  private final class WindowDelegateProxy: NSObject, NSWindowDelegate {
    var shouldCloseHandler: (() -> Bool)?
    var willCloseHandler: (() -> Void)?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
      shouldCloseHandler?() ?? true
    }

    func windowWillClose(_ notification: Notification) {
      willCloseHandler?()
    }
  }

  private final class EditorContentHost: ObservableObject {
    @Published var content: AnyView = AnyView(EmptyView())
  }

  private struct EditorWindowRootView: View {
    @ObservedObject var host: EditorContentHost

    var body: some View {
      host.content
    }
  }

  private var importSetupWindow: NSWindow?
  private var importSetupWindowDelegate: WindowDelegateProxy?
  private var progressWindow: NSWindow?
  private var editorWindow: NSWindow?
  private var progressWindowDelegate: WindowDelegateProxy?
  private var editorWindowDelegate: WindowDelegateProxy?
  private var testingProbe: TestingProbe?
  private var allowsProgressWindowClose = false
  private var editorWindowCloseHandler: (() -> Void)?
  private let editorContentHost = EditorContentHost()
  private var suppressWindowPresentationForTesting = false
  /// The app window whose frame the editor should adopt on first open.
  /// Captured before the progress window steals key-window focus.
  private weak var editorFrameSourceWindow: NSWindow?

  func presentImportSetupWindow(content: AnyView) {
    let window = importSetupWindow ?? makeWindow(
      title: "Prepare Import",
      size: NSSize(width: 580, height: 520)
    )

    if importSetupWindow == nil {
      importSetupWindow = window
      let delegate = WindowDelegateProxy()
      delegate.willCloseHandler = { [weak self] in
        self?.importSetupWindow = nil
        self?.importSetupWindowDelegate = nil
      }
      window.delegate = delegate
      importSetupWindowDelegate = delegate
    }

    update(window: window, title: "Prepare Import", content: content)
    if !window.isVisible {
      centerWindow(window, relativeTo: NSApp.keyWindow ?? NSApp.mainWindow)
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
    }
  }

  func closeImportSetupWindow() {
    guard let window = importSetupWindow else { return }
    importSetupWindow = nil
    importSetupWindowDelegate = nil
    window.close()
  }

  func attachProgressWindow(_ window: NSWindow) {
    progressWindow = window
  }

  func attachEditorWindow(_ window: NSWindow) {
    editorWindow = window
  }

  func closeProgressWindow() {
    closeProgressWindow(recordingTo: nil)
  }

  func presentProgressWindow(content: AnyView, onCancelRequest: @escaping () -> Void) {
    let window = progressWindow ?? makeWindow(
      title: Self.progressWindowTitle,
      size: NSSize(width: 520, height: 360)
    )

    if progressWindow == nil {
      progressWindow = window
      let delegate = WindowDelegateProxy()
      delegate.shouldCloseHandler = { [weak self] in
        guard let self else { return true }
        guard !self.allowsProgressWindowClose else { return true }
        onCancelRequest()
        return false
      }
      delegate.willCloseHandler = { [weak self] in
        self?.progressWindow = nil
        self?.progressWindowDelegate = nil
      }
      window.delegate = delegate
      progressWindowDelegate = delegate
    } else {
      progressWindowDelegate?.shouldCloseHandler = { [weak self] in
        guard let self else { return true }
        guard !self.allowsProgressWindowClose else { return true }
        onCancelRequest()
        return false
      }
    }

    update(window: window, title: Self.progressWindowTitle, content: content)
    if !window.isVisible {
      // Capture the current app window BEFORE the progress window steals key focus.
      // This frame is used by preferredEditorFrame() when the editor opens later.
      if editorFrameSourceWindow == nil {
        editorFrameSourceWindow = NSApp.keyWindow ?? NSApp.mainWindow
      }
      centerWindow(window, relativeTo: NSApp.keyWindow ?? NSApp.mainWindow)
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
    }
  }

  func updateEditorWindow(content: AnyView, onCloseRequest: @escaping () -> Void) {
    editorWindowCloseHandler = onCloseRequest
    editorContentHost.content = content
    guard let editorWindow else { return }
    ensureEditorHosting(in: editorWindow)
    editorWindow.title = Self.editorWindowTitle
  }

  func transitionFromProgressToEditor(
    beforeOpen: () -> Void,
    editorContent: () -> AnyView,
    onEditorCloseRequest: @escaping () -> Void
  ) {
    transitionFromProgressToEditor(
      recordingTo: nil,
      recordBeforeOpenAction: false,
      beforeOpen: beforeOpen,
      editorContent: editorContent,
      onEditorCloseRequest: onEditorCloseRequest
    )
  }

  private func closeProgressWindow(recordingTo probe: TestingProbe?) {
    guard let progressWindow else { return }
    allowsProgressWindowClose = true
    probe?.record(.closeProgressWindow)
    if suppressWindowPresentationForTesting {
      progressWindow.delegate = nil
      progressWindow.orderOut(nil)
    } else {
      progressWindow.close()
    }
    allowsProgressWindowClose = false
    self.progressWindow = nil
    progressWindowDelegate = nil
  }

  private func openEditorWindow(
    content: AnyView,
    onCloseRequest: @escaping () -> Void,
    recordingTo probe: TestingProbe?
  ) {
    editorWindowCloseHandler = onCloseRequest
    if editorWindow == nil {
      let window = makeWindow(title: Self.editorWindowTitle, frame: preferredEditorFrame())
      window.minSize = NSSize(width: 1100, height: 720)
      let delegate = WindowDelegateProxy()
      delegate.willCloseHandler = { [weak self] in
        self?.handleEditorWindowClosed(recordingTo: nil)
      }
      window.delegate = delegate
      editorWindow = window
      editorWindowDelegate = delegate
    }
    probe?.record(.openEditorWindow)
    if let editorWindow {
      if !suppressWindowPresentationForTesting {
        editorContentHost.content = content
        ensureEditorHosting(in: editorWindow)
      }
      editorWindow.title = Self.editorWindowTitle
    }
    if suppressWindowPresentationForTesting {
      editorWindow?.orderOut(nil)
    } else {
      editorWindow?.orderFront(nil)
    }
  }

  private func activateEditorWindow(recordingTo probe: TestingProbe?) {
    guard let editorWindow else { return }
    probe?.record(.activateEditorWindow)
    guard !suppressWindowPresentationForTesting else { return }
    NSApp.activate(ignoringOtherApps: true)
    editorWindow.makeKeyAndOrderFront(nil)
  }

  private func transitionFromProgressToEditor(
    recordingTo probe: TestingProbe?,
    recordBeforeOpenAction: Bool,
    beforeOpen: () -> Void,
    editorContent: () -> AnyView,
    onEditorCloseRequest: @escaping () -> Void
  ) {
    closeProgressWindow(recordingTo: probe)
    if recordBeforeOpenAction {
      probe?.record(.runBeforeOpenAction)
    }
    beforeOpen()
    openEditorWindow(
      content: editorContent(),
      onCloseRequest: onEditorCloseRequest,
      recordingTo: probe
    )
    activateEditorWindow(recordingTo: probe)
  }

  private func handleEditorWindowClosed(recordingTo probe: TestingProbe?) {
    guard editorWindow != nil else { return }
    let closeHandler = editorWindowCloseHandler
    editorWindow = nil
    editorWindowDelegate = nil
    editorWindowCloseHandler = nil
    probe?.record(.notifyEditorWindowClosed)
    closeHandler?()
  }

  private func update(window: NSWindow, title: String, content: AnyView) {
    if let hostingController = window.contentViewController as? NSHostingController<AnyView> {
      hostingController.rootView = content
    } else {
      window.contentViewController = NSHostingController(rootView: content)
    }
    window.title = title
  }

  private func ensureEditorHosting(in window: NSWindow) {
    if window.contentView is NSHostingView<EditorWindowRootView> {
      return
    }
    // Use NSHostingView (not NSHostingController) so the SwiftUI content fills
    // the window's existing frame rather than resizing the window to fit the view.
    let hostingView = NSHostingView(rootView: EditorWindowRootView(host: editorContentHost))
    window.contentView = hostingView
  }

  private func preferredEditorFrame() -> NSRect {
    // Return the CONTENT RECT for the new editor window (makeWindow uses contentRect:).
    let excluded: Set<String> = [Self.editorWindowTitle, Self.progressWindowTitle]

    // Prefer the explicitly-captured source window (set before progress window
    // stole key focus). Fall back to the current key/main window, then scan all
    // windows, to handle environments where the source wasn't captured.
    let source: NSWindow? = {
      if let w = editorFrameSourceWindow, !excluded.contains(w.title) { return w }
      for candidate in [NSApp.keyWindow, NSApp.mainWindow].compactMap({ $0 }) {
        if !excluded.contains(candidate.title) { return candidate }
      }
      return NSApp.windows.first {
        !excluded.contains($0.title)
          && $0.frame.width >= 1100
          && $0.frame.height >= 700
      }
    }()

    if let source {
      // Convert the candidate's frame to a content rect so that the editor
      // window's full frame equals the candidate's full frame.
      return NSWindow.contentRect(
        forFrameRect: source.frame,
        styleMask: [.titled, .closable, .miniaturizable, .resizable]
      )
    }

    // Fallback: 88% of the visible screen area, minimum 1200×780.
    let screen = NSScreen.main ?? NSScreen.screens.first
    let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let width = max(1200, (visibleFrame.width * 0.88).rounded())
    let height = max(780, (visibleFrame.height * 0.88).rounded())
    let x = visibleFrame.origin.x + ((visibleFrame.width - width) / 2).rounded()
    let y = visibleFrame.origin.y + ((visibleFrame.height - height) / 2).rounded()
    return NSRect(x: x, y: y, width: width, height: height)
  }

  private func makeWindow(title: String, size: NSSize) -> NSWindow {
    makeWindow(
      title: title,
      frame: NSRect(x: 0, y: 0, width: size.width, height: size.height)
    )
  }

  private func makeWindow(title: String, frame: NSRect) -> NSWindow {
    let window = NSWindow(
      contentRect: frame,
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = title
    window.isReleasedWhenClosed = false
    centerWindow(window, relativeTo: NSApp.keyWindow ?? NSApp.mainWindow)
    return window
  }

  private func centerWindow(_ window: NSWindow, relativeTo parent: NSWindow?) {
    // Try the provided parent first
    if let parent, parent !== window {
      let pf = parent.frame
      let wf = window.frame
      let x = (pf.midX - wf.width / 2).rounded()
      let y = (pf.midY - wf.height / 2).rounded()
      window.setFrameOrigin(NSPoint(x: x, y: y))
      return
    }
    // Fallback: center relative to any other visible, non-miniaturised app window
    if let anyVisible = NSApp.windows.first(where: {
      $0 !== window && $0.isVisible && !$0.isMiniaturized && $0.isOnActiveSpace
    }) {
      let pf = anyVisible.frame
      let wf = window.frame
      let x = (pf.midX - wf.width / 2).rounded()
      let y = (pf.midY - wf.height / 2).rounded()
      window.setFrameOrigin(NSPoint(x: x, y: y))
      return
    }
    window.center()
  }
}

extension AICutWindowCoordinator {
  // MARK: - Testing seam

  var lastTransitionEvents: [TransitionEvent] {
    testingProbe?.events ?? []
  }

  var editorWindowForTesting: NSWindow? { editorWindow }

  func markProgressWindowOpenForTesting(sourceWindow: NSWindow? = nil) {
    suppressWindowPresentationForTesting = true
    testingProbe = TestingProbe()
    testingProbe?.reset()
    editorFrameSourceWindow = sourceWindow
    progressWindow = makeWindow(title: Self.progressWindowTitle, size: NSSize(width: 520, height: 360))
  }

  func transitionFromProgressToEditorForTesting(
    beforeOpen: (() -> Void)? = nil,
    onEditorClose: (() -> Void)? = nil
  ) {
    let probe = testingProbe ?? TestingProbe()
    testingProbe = probe
    probe.reset()
    transitionFromProgressToEditor(
      recordingTo: probe,
      recordBeforeOpenAction: beforeOpen != nil,
      beforeOpen: { beforeOpen?() },
      editorContent: {
        AnyView(Color.clear.frame(minWidth: 1, minHeight: 1))
      },
      onEditorCloseRequest: { onEditorClose?() }
    )
  }

  func simulateEditorWindowCloseForTesting() {
    let probe = testingProbe ?? TestingProbe()
    testingProbe = probe
    handleEditorWindowClosed(recordingTo: probe)
  }

  func resetForTesting() {
    let windows = [importSetupWindow, progressWindow, editorWindow].compactMap { $0 }
    importSetupWindow = nil
    importSetupWindowDelegate = nil
    progressWindow = nil
    editorWindow = nil
    progressWindowDelegate = nil
    editorWindowDelegate = nil
    testingProbe = nil
    allowsProgressWindowClose = false
    editorWindowCloseHandler = nil
    editorFrameSourceWindow = nil
    suppressWindowPresentationForTesting = false
    for window in windows {
      window.delegate = nil
      window.contentViewController = nil
      window.contentView = nil
      window.orderOut(nil)
    }
  }
}
