import SwiftUI

enum AppSurface {
  /// Shared light-gray canvas for pages, retaining the system background in dark mode.
  static let pageBackground = Color(
    nsColor: NSColor(name: nil) { appearance in
      if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
        return .windowBackgroundColor
      }
      return NSColor(srgbRed: 242 / 255, green: 242 / 255, blue: 242 / 255, alpha: 1)
    }
  )
  static let cardBackground = Color(nsColor: .controlBackgroundColor)
}
