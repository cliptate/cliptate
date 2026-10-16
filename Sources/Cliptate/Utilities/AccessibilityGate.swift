import AppKit
import os.log

import ApplicationServices
import CoreGraphics

/// Owns Accessibility trust checks and focused-field text injection.
enum AccessibilityGate {
  private static let logger = Logger(subsystem: "com.Cliptate", category: "AccessibilityGate")

  /// Whether Accessibility-backed capabilities exist in this build at all.
  static var isSupported: Bool {
    return true
  }

  /// Whether the process is currently trusted for Accessibility, without ever
  /// presenting the system prompt.
  static var isProcessTrusted: Bool {
    return AXIsProcessTrusted()
  }

  /// Whether direct text injection can be attempted right now.
  static var canInjectText: Bool {
    isSupported && isProcessTrusted
  }

  /// Type `text` directly into the focused field of the frontmost app via
  /// synthesized keyboard events. Returns `false` when untrusted or injection fails,
  /// so the caller can fall back to the clipboard.
  @discardableResult
  static func injectText(_ text: String) -> Bool {
    guard canInjectText else { return false }
    return typeTextDirectly(text)
  }

  private static func typeTextDirectly(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    guard let source = CGEventSource(stateID: .hidSystemState) else { return false }

    let unicodeUnits = Array(text.utf16)
    guard !unicodeUnits.isEmpty else { return false }

    let chunkSize = 64
    for chunkStart in stride(from: 0, to: unicodeUnits.count, by: chunkSize) {
      let chunk = Array(unicodeUnits[chunkStart..<min(chunkStart + chunkSize, unicodeUnits.count)])

      guard
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
      else {
        return false
      }

      chunk.withUnsafeBufferPointer { buffer in
        guard let baseAddress = buffer.baseAddress else { return }
        keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
        keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
      }

      keyDown.post(tap: .cgSessionEventTap)
      usleep(10_000)
      keyUp.post(tap: .cgSessionEventTap)
    }

    return true
  }
}
