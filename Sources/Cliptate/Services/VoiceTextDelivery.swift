import AppKit
import Foundation

@MainActor
struct VoiceTextDelivery {
  var canInject: () -> Bool = { AccessibilityGate.canInjectText }
  var activate: (Int32) -> Void = { processID in
    NSRunningApplication(processIdentifier: processID)?.activate(options: [])
  }
  var targetIsFocused: (Int32) -> Bool = { processID in
    NSWorkspace.shared.frontmostApplication?.processIdentifier == processID
  }
  var waitForActivation: () async throws -> Void = {
    try await Task.sleep(for: .milliseconds(300))
  }
  var inject: (String) -> Bool = { AccessibilityGate.injectText($0) }
  var copy: (String) async -> Bool = { await ClipboardWriter.write($0) }
  var onCopied: () -> Void = {}

  func deliver(_ text: String, to target: Int32?) async throws {
    try Task.checkCancellation()
    guard canInject(), let target else {
      try await copyText(text)
      return
    }
    activate(target)
    try await waitForActivation()
    try Task.checkCancellation()
    if !targetIsFocused(target) || !inject(text) {
      try await copyText(text)
    }
  }

  private func copyText(_ text: String) async throws {
    try Task.checkCancellation()
    guard await copy(text) else { throw CocoaError(.fileWriteUnknown) }
    try Task.checkCancellation()
    onCopied()
  }
}
