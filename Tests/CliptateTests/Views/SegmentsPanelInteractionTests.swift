import Foundation
import SwiftUI
import Testing

@testable import Cliptate

@Suite("Segments panel header controls")
struct SegmentsPanelInteractionTests {
  @Test("time toggle keeps a valid symbol and flips emphasis with state")
  func timeToggleKeepsValidSymbolAndFlipsEmphasis() {
    let visible = SegmentsPanelHeaderControlState(
      hasSegments: true,
      showTimes: true
    )
    #expect(visible.timeSymbolName == "clock")
    #expect(visible.isTimeHighlighted)
    #expect(visible.controlSize.width >= 28)
    #expect(visible.controlSize.height >= 28)

    let hidden = SegmentsPanelHeaderControlState(
      hasSegments: true,
      showTimes: false
    )
    #expect(hidden.timeSymbolName == "clock")
    #expect(hidden.isTimeHighlighted == false)
    #expect(hidden.controlSize == visible.controlSize)
  }

  @Test("row translations respect translationPlacement config for above and below")
  func rowTranslationsRespectPlacementConfig() throws {
    let root = projectRoot()
    let path = root.appendingPathComponent("Sources/Cliptate/Views/SegmentsPanelView.swift")
    let content = try String(contentsOf: path, encoding: .utf8)

    // SegmentRowView must read config via @EnvironmentObject to access translationPlacement
    #expect(content.contains("@EnvironmentObject") && content.contains("config"))

    // Must render translation conditionally above original text
    #expect(content.contains("config.translationPlacement == .above"))
    // Must render translation conditionally below original text
    #expect(content.contains("config.translationPlacement == .below"))
    // Must contain the translationEditor call
    #expect(content.contains("translationEditor(for: resolvedTranslation)"))
  }

  private func projectRoot() -> URL {
    let fileURL = URL(fileURLWithPath: #filePath)
    return fileURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }
}
