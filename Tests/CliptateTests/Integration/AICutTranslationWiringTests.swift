import Foundation
import Testing

@Suite("AI Cut translation wiring")
struct AICutTranslationWiringTests {
  @Test("editor window content owns translationTask trigger")
  func editorWindowOwnsTranslationTask() throws {
    let root = projectRoot()
    let path = root.appendingPathComponent("Sources/Cliptate/Views/AICutView.swift")
    let content = try String(contentsOf: path, encoding: .utf8)

    #expect(content.contains("baseView.translationTask(") == false)

    guard let editorRange = content.range(of: "private var editorWindowContent: some View {") else {
      Issue.record("editorWindowContent definition not found")
      return
    }

    let editorSlice = content[editorRange.lowerBound...]
    #expect(editorSlice.contains(".translationTask("))
  }

  @Test("translation writes flow through one refresh and persistence hook")
  func translationWritesFlowThroughRefreshHook() throws {
    let root = projectRoot()
    let path = root.appendingPathComponent("Sources/Cliptate/Views/AICutView.swift")
    let content = try String(contentsOf: path, encoding: .utf8)

    #expect(content.contains("@State private var translationsVersion: Int = 0"))
    #expect(content.contains("private func markTranslationsChanged("))
    #expect(content.contains("translationsVersion &+= 1"))
    #expect(content.contains("markTranslationsChanged(for: request.url, state: state)"))
    #expect(content.contains("markTranslationsChanged(for: url, state: videoState)"))
  }

  @Test("paddedSegments uses SegmentComputer with translations")
  func paddedSegmentsUsesSegmentComputer() throws {
    let root = projectRoot()
    let path = root.appendingPathComponent("Sources/Cliptate/Views/AICutView.swift")
    let content = try String(contentsOf: path, encoding: .utf8)

    #expect(content.contains("SegmentComputer.Input("))
    #expect(content.contains("SegmentComputer.compute("))
  }

  @Test("markTranslationsChanged embeds translations for persistence")
  func markTranslationsChangedEmbeds() throws {
    let root = projectRoot()
    let path = root.appendingPathComponent("Sources/Cliptate/Views/AICutView.swift")
    let content = try String(contentsOf: path, encoding: .utf8)

    guard let funcRange = content.range(of: "private func markTranslationsChanged(") else {
      Issue.record("markTranslationsChanged not found")
      return
    }
    let slice = content[funcRange.lowerBound...]
    #expect(slice.contains("VideoState.injectTranslations("))
    #expect(slice.contains("segmentsWithTranslations"))
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
