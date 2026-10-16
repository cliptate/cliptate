import AppKit

enum ClipboardWriter {
  @discardableResult
  @concurrent static func write(_ text: String) async -> Bool {
    guard !Task.isCancelled, !text.isEmpty else { return false }

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    return pasteboard.setString(text, forType: .string)
  }
}
