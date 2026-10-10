import Foundation
import Testing

@Suite("AI settings view source")
struct AISettingsViewSourceTests {
  @Test("display language picker includes German")
  func displayLanguagePickerIncludesGerman() throws {
    let content = try aiSettingsViewSource()

    #expect(content.contains(#".init(id: "de", label: "Deutsch")"#))
  }

  @Test("startup settings omit lightweight mode controls")
  func startupSettingsOmitLightweightModeControls() throws {
    let content = try aiSettingsViewSource()

    guard let sectionRange = content.range(of: "private var startupSection: some View {") else {
      Issue.record("startupSection definition not found")
      return
    }

    let startupSection = content[sectionRange.lowerBound...]
    #expect(startupSection.contains("LoginItemSettingsView()"))
    #expect(startupSection.contains("Lightweight Mode") == false)
    #expect(startupSection.contains("enterLightweightMode") == false)
    #expect(startupSection.contains("exitLightweightMode") == false)
  }

  private func aiSettingsViewSource() throws -> String {
    let fileURL = URL(fileURLWithPath: #filePath)
    let projectRoot = fileURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    let sourceURL = projectRoot.appendingPathComponent("Sources/Cliptate/Views/AISettingsView.swift")
    return try String(contentsOf: sourceURL, encoding: .utf8)
  }
}
