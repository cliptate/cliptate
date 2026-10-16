import Foundation
import Testing
@testable import Cliptate

@MainActor
struct AnalyticsPreferenceTests {
  @Test func optOutSurvivesPresetRoundTrip() throws {
    let config = AppConfiguration()
    config.analyticsCollectionEnabled = false
    let store = ConfigPresetStore.shared
    let encoded = try JSONEncoder().encode(store.payload(from: config))
    let payload = try JSONDecoder().decode(ConfigPreset.Payload.self, from: encoded)
    let restored = AppConfiguration()
    store.applyPayload(payload, to: restored)
    #expect(!restored.analyticsCollectionEnabled)
  }

  @Test func collectionDefaultsOnAndOptOutSurvivesSavingAndRestoring() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let persistence = AppConfigurationPersistence(fileURL: directory.appendingPathComponent("settings.json"))
    let config = AppConfiguration()
    #expect(config.analyticsCollectionEnabled)
    config.analyticsCollectionEnabled = false
    try persistence.flush(using: config)
    let restored = AppConfiguration()
    restored.applySnapshot(try #require(persistence.loadSnapshot()))
    #expect(!restored.analyticsCollectionEnabled)
  }
}
