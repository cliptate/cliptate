import AppKit
import os.log

#if !APP_STORE
  import ApplicationServices
  import CoreGraphics
#endif

/// The single seam that owns whether macOS Accessibility-backed text injection
/// is available.
///
/// Callers go through this type and never touch `AXIsProcessTrusted` or
/// `kAXTrusted` directly, so the App Store build (compiled with `APP_STORE`)
/// neither requests nor links Accessibility APIs.
///
/// Removing the App Store channel later is deleting the `#if APP_STORE` branches
/// in this one file and the Xcode flag; call sites are untouched and
/// `isSupported` becomes a constant `true`.
enum AccessibilityGate {
  private static let logger = Logger(subsystem: "com.Cliptate", category: "AccessibilityGate")

  /// Whether Accessibility-backed capabilities exist in this build at all.
  /// `false` in App Store builds so callers fall back to non-Accessibility paths.
  static var isSupported: Bool {
    #if APP_STORE
      return false
    #else
      return true
    #endif
  }

  /// Whether the process is currently trusted for Accessibility, without ever
  /// presenting the system prompt. Always `false` when unsupported.
  static var isProcessTrusted: Bool {
    #if APP_STORE
      return false
    #else
      let options =
        [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as NSDictionary
      return AXIsProcessTrustedWithOptions(options)
    #endif
  }

  /// Whether direct text injection can be attempted right now.
  static var canInjectText: Bool {
    isSupported && isProcessTrusted
  }

  /// Type `text` directly into the focused field of the frontmost app via
  /// synthesized keyboard events. Returns `false` when unsupported or untrusted,
  /// so the caller can fall back to the clipboard.
  @discardableResult
  static func injectText(_ text: String) -> Bool {
    #if APP_STORE
      return false
    #else
      guard canInjectText else { return false }
      return typeTextDirectly(text)
    #endif
  }

  #if !APP_STORE
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
  #endif
}
