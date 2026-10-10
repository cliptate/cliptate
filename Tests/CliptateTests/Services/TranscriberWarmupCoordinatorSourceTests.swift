import Foundation
import Testing

@Suite("TranscriberWarmupCoordinator source")
struct TranscriberWarmupCoordinatorSourceTests {
  @Test("bootstrap preloads the configured VAD model")
  func bootstrapPreloadsConfiguredVADModel() throws {
    let content = try coordinatorSource()

    #expect(content.contains("scheduleVADWarmup(for: config.vadModelVariant, force: true)"))
  }

  @Test("configuration changes rewarm the selected VAD model")
  func configurationChangesRewarmSelectedVADModel() throws {
    let content = try coordinatorSource()

    #expect(content.contains("config.$vadModelVariant"))
    #expect(content.contains(".dropFirst()"))
    #expect(content.contains("self?.scheduleVADWarmup(for: vadModel)"))
  }

  private func coordinatorSource() throws -> String {
    let fileURL = URL(fileURLWithPath: #filePath)
    let projectRoot = fileURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    let sourceURL = projectRoot.appendingPathComponent(
      "Sources/Cliptate/Services/TranscriberWarmupCoordinator.swift"
    )
    return try String(contentsOf: sourceURL, encoding: .utf8)
  }
}
