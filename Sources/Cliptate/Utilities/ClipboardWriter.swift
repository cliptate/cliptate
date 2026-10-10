import AppKit

enum ClipboardWriter {
  @discardableResult
  static func write(_ text: String) async -> Bool {
    guard !text.isEmpty else { return false }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    return pasteboard.setString(text, forType: .string)
  }
}
