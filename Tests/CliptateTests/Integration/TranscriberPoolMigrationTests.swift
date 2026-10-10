import Foundation
import Testing

@Suite("TranscriberPool migration verification")
struct TranscriberPoolMigrationTests {
  @Test("active transcription workflows no longer reference TranscriberPool.shared")
  func noActiveWorkflowReferencesLegacyPool() throws {
    let root = projectRoot()
    let workflowFiles = [
      "Sources/Cliptate/Services/VoiceTranscriber.swift",
      "Sources/Cliptate/Services/TranscriberWarmupCoordinator.swift",
      "Sources/Cliptate/Views/AICutView.swift",
      "Sources/Cliptate/Views/VoiceToTextView.swift",
      "Sources/Cliptate/Views/ModelsView.swift",
    ]

    for relativePath in workflowFiles {
      let content = try String(
        contentsOf: root.appendingPathComponent(relativePath),
        encoding: .utf8
      )
      #expect(
        content.contains("TranscriberPool.shared") == false,
        "\(relativePath) still references TranscriberPool.shared"
      )
    }
  }

  @Test("legacy TranscriberPool remains explicitly deprecated")
  func legacyPoolIsDeprecated() throws {
    let root = projectRoot()
    let transcriberPoolPath = root.appendingPathComponent(
      "Sources/Cliptate/Services/TranscriberPool.swift"
    )
    let content = try String(contentsOf: transcriberPoolPath, encoding: .utf8)
    #expect(content.contains("@available(*, deprecated"))
    #expect(content.contains("Use ModelCacheManager.shared instead."))
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
