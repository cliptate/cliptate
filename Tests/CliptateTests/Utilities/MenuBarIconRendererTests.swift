import AppKit
import Testing

@testable import Cliptate

@MainActor
@Suite("MenuBarIconRenderer")
struct MenuBarIconRendererTests {
  @Test("renders an 18pt non-template menu bar icon")
  func renders18PointMenuBarIcon() {
    let source = NSImage(size: NSSize(width: 128, height: 128))

    let rendered = MenuBarIconRenderer.makeImage(from: source)

    #expect(rendered.size == NSSize(width: 18, height: 18))
    #expect(rendered.isTemplate == false)
  }
}
