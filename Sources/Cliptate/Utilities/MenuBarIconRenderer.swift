import AppKit

@MainActor
enum MenuBarIconRenderer {
  static let targetSize = NSSize(width: 18, height: 18)

  static func makeImage(from appIcon: NSImage) -> NSImage {
    let image = NSImage(size: targetSize)
    image.lockFocus()
    appIcon.draw(in: NSRect(origin: .zero, size: targetSize))
    image.unlockFocus()
    image.isTemplate = false
    return image
  }
}
