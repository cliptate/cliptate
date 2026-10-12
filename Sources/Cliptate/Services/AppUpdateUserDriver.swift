import AppKit
import Sparkle
import SwiftUI

/// Keeps Sparkle's standard UI except for the verified, ready-to-install prompt.
@MainActor
final class AppUpdateUserDriver: NSObject, SPUUserDriver, NSWindowDelegate {
  private let standard: SPUStandardUserDriver
  private var installationWindow: NSWindow?
  private var installationPrompt: AppUpdateInstallationPrompt?

  init(hostBundle: Bundle) {
    standard = SPUStandardUserDriver(hostBundle: hostBundle, delegate: nil)
    super.init()
  }

  func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
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
    installationPrompt?.respond(.dismiss)
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
    dismissInstallationPrompt()
    standard.showUpdateFound(with: appcastItem, state: state, reply: reply)
  }

  func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
    standard.showUpdateReleaseNotes(with: downloadData)
  }

  func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
    standard.showUpdateReleaseNotesFailedToDownloadWithError(error)
  }

  func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
    dismissInstallationPrompt()
    standard.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement)
  }

  func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
    dismissInstallationPrompt()
    standard.showUpdaterError(error, acknowledgement: acknowledgement)
  }

  func showDownloadInitiated(cancellation: @escaping () -> Void) {
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
    dismissInstallationPrompt()
    standard.showInstallingUpdate(
      withApplicationTerminated: applicationTerminated,
      retryTerminatingApplication: retryTerminatingApplication)
  }

  func showUpdateInstalledAndRelaunched(
    _ relaunched: Bool, acknowledgement: @escaping () -> Void
  ) {
    dismissInstallationPrompt()
    standard.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement)
  }

  func dismissUpdateInstallation() {
    dismissInstallationPrompt()
    standard.dismissUpdateInstallation()
  }

  func showUpdateInFocus() {
    if let installationWindow {
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
