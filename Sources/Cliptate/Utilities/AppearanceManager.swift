import AppKit

@MainActor
enum AppearanceManager {
  static func apply(mode: String) {
    switch mode {
    case "light":
      NSApplication.shared.appearance = NSAppearance(named: .aqua)
    case "dark":
      NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    default:
      NSApplication.shared.appearance = nil
    }
  }
}
