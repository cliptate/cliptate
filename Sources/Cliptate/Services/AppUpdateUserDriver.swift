import AppKit
import Sparkle
import SwiftUI

/// Offers a gentle update reminder and keeps Sparkle's download and installation flow.
@MainActor
final class AppUpdateUserDriver: NSObject, SPUUserDriver, NSWindowDelegate {
  private let standard: SPUStandardUserDriver
  private var installationWindow: NSWindow?
  private var installationPrompt: AppUpdateInstallationPrompt?
  private var availableUpdate: AppUpdateOffer?
  private var availableUpdateWindow: NSWindow?
  private let updateChanged: (AppUpdateOffer?) -> Void

  init(hostBundle: Bundle, updateChanged: @escaping (AppUpdateOffer?) -> Void = { _ in }) {
    self.updateChanged = updateChanged
    standard = SPUStandardUserDriver(hostBundle: hostBundle, delegate: nil)
    super.init()
  }

  func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
    dismissAvailableUpdate()
    // Sparkle reaches this callback only after installer preparation and validation.
    // Finding an appcast item or finishing a download is not verification evidence.
    dismissInstallationPrompt()
    standard.dismissUpdateInstallation()
    let prompt = AppUpdateInstallationPrompt { [weak self] choice in
      self?.dismissInstallationPrompt()
      reply(choice)
    }
    installationPrompt = prompt
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 440, height: 210),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = String(localized: "Software Update")
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.contentView = NSHostingView(rootView: VerifiedAppUpdateView(prompt: prompt))
    window.center()
    installationWindow = window
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
    NSApp.requestUserAttention(.informationalRequest)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    if sender === availableUpdateWindow {
      availableUpdate?.prompt.respond(.dismiss)
    } else {
      installationPrompt?.respond(.dismiss)
    }
    return false
  }

  private func dismissInstallationPrompt() {
    installationPrompt?.invalidate()
    installationPrompt = nil
    installationWindow?.delegate = nil
    installationWindow?.close()
    installationWindow = nil
  }

  func show(
    _ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void
  ) {
    standard.show(request, reply: reply)
  }

  func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
    standard.showUserInitiatedUpdateCheck(cancellation: cancellation)
  }

  func showUpdateFound(
    with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
    reply: @escaping (SPUUserUpdateChoice) -> Void
  ) {
    offerUpdate(details: AppUpdateDetails(item: appcastItem), reply: reply)
    // A visible app uses its sidebar reminder. Menu-bar-only mode still needs a visible offer.
    if state.userInitiated || !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
      showAvailableUpdateWindow(activate: state.userInitiated)
    }
  }

  func offerUpdate(details: AppUpdateDetails, reply: @escaping (SPUUserUpdateChoice) -> Void) {
    dismissAvailableUpdate()
    dismissInstallationPrompt()
    standard.dismissUpdateInstallation()
    let offer = AppUpdateOffer(details: details) { [weak self] choice in
      self?.dismissAvailableUpdate()
      reply(choice)
    }
    availableUpdate = offer
    updateChanged(offer)
  }

  private func showAvailableUpdateWindow(activate: Bool) {
    guard let update = availableUpdate else { return }
    if availableUpdateWindow == nil {
      let hosting = NSHostingView(rootView: AvailableAppUpdateView(update: update))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 260),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
      window.title = String(localized: "Software Update")
      window.isReleasedWhenClosed = false
      window.delegate = self
      window.contentView = hosting
      window.setContentSize(hosting.fittingSize)
      window.center()
      availableUpdateWindow = window
    }
    if activate {
      NSApp.activate()
      availableUpdateWindow?.makeKeyAndOrderFront(nil)
    } else {
      availableUpdateWindow?.orderFront(nil)
    }
  }

  private func dismissAvailableUpdate() {
    guard let update = availableUpdate else { return }
    update.prompt.invalidate()
    availableUpdate = nil
    availableUpdateWindow?.delegate = nil
    availableUpdateWindow?.close()
    availableUpdateWindow = nil
    updateChanged(nil)
  }

  func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
    standard.showUpdateReleaseNotes(with: downloadData)
  }

  func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
    standard.showUpdateReleaseNotesFailedToDownloadWithError(error)
  }

  func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
    dismissAvailableUpdate()
    dismissInstallationPrompt()
    standard.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement)
  }

  func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
    dismissAvailableUpdate()
    dismissInstallationPrompt()
    standard.showUpdaterError(error, acknowledgement: acknowledgement)
  }

  func showDownloadInitiated(cancellation: @escaping () -> Void) {
    dismissAvailableUpdate()
    dismissInstallationPrompt()
    standard.showDownloadInitiated(cancellation: cancellation)
  }

  func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
    standard.showDownloadDidReceiveExpectedContentLength(expectedContentLength)
  }

  func showDownloadDidReceiveData(ofLength length: UInt64) {
    standard.showDownloadDidReceiveData(ofLength: length)
  }

  func showDownloadDidStartExtractingUpdate() {
    standard.showDownloadDidStartExtractingUpdate()
  }

  func showExtractionReceivedProgress(_ progress: Double) {
    standard.showExtractionReceivedProgress(progress)
  }

  func showInstallingUpdate(
    withApplicationTerminated applicationTerminated: Bool,
    retryTerminatingApplication: @escaping () -> Void
  ) {
    dismissAvailableUpdate()
    dismissInstallationPrompt()
    standard.showInstallingUpdate(
      withApplicationTerminated: applicationTerminated,
      retryTerminatingApplication: retryTerminatingApplication)
  }

  func showUpdateInstalledAndRelaunched(
    _ relaunched: Bool, acknowledgement: @escaping () -> Void
  ) {
    dismissAvailableUpdate()
    dismissInstallationPrompt()
    standard.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement)
  }

  func dismissUpdateInstallation() {
    dismissAvailableUpdate()
    dismissInstallationPrompt()
    standard.dismissUpdateInstallation()
  }

  func showUpdateInFocus() {
    if availableUpdate != nil {
      showAvailableUpdateWindow(activate: true)
    } else if let installationWindow {
      NSApp.activate()
      installationWindow.makeKeyAndOrderFront(nil)
    } else {
      standard.showUpdateInFocus()
    }
  }
}

/// Completes Sparkle's installation choice once, even if the window closes during a click.
@MainActor
final class AppUpdateInstallationPrompt: ObservableObject {
  @Published private(set) var isActive = true
  private var reply: ((SPUUserUpdateChoice) -> Void)?

  init(reply: @escaping (SPUUserUpdateChoice) -> Void) {
    self.reply = reply
  }

  func respond(_ choice: SPUUserUpdateChoice) {
    guard let reply else { return }
    invalidate()
    reply(choice)
  }

  func invalidate() {
    reply = nil
    isActive = false
  }
}
