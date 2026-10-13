import Foundation
import Testing

@testable import Cliptate

@Suite("Dictation indicator visibility")
@MainActor
struct MicIndicatorVisibilityTests {
  @Test("A failed dictation indicator disappears after one second without an extra dismissal delay")
  func warningExpiresAfterOneSecond() async throws {
    let overlay = MicIndicatorOverlay(configuration: AppConfiguration())
    defer { overlay.stopTracking() }
    overlay.showInputWarning("No text recognized")
    #expect(overlay.testPanelIsVisible)
    try await Task.sleep(for: .milliseconds(1150))
    #expect(!overlay.testPanelIsVisible)
    #expect(!overlay.testIsActive)
    #expect(overlay.testInputWarning == nil)
  }

  @Test("Repeated error notifications do not extend the one-second display limit")
  func repeatedWarningKeepsOriginalDeadline() async throws {
    let overlay = MicIndicatorOverlay(configuration: AppConfiguration())
    defer { overlay.stopTracking() }
    overlay.showInputWarning("No text recognized")
    try await Task.sleep(for: .milliseconds(400))
    overlay.showInputWarning("No text recognized")
    try await Task.sleep(for: .milliseconds(750))
    #expect(!overlay.testPanelIsVisible)
    #expect(!overlay.testIsActive)
  }

  @Test("The one-second error timeout cannot dismiss a newer dictation")
  func warningTimeoutPreservesNextSession() async throws {
    let overlay = MicIndicatorOverlay(configuration: AppConfiguration())
    defer { overlay.stopTracking() }
    overlay.showInputWarning("No text recognized")
    overlay.startTracking()
    try await Task.sleep(for: .milliseconds(1150))
    #expect(overlay.testPanelIsVisible)
    #expect(overlay.testIsActive)
    #expect(overlay.testOverlayStatus == .listening)
  }

  @Test("Legacy disabled settings cannot leave the indicator hidden after removing the switch")
  func legacyDisabledSettings() throws {
    let config = AppConfiguration()
    config.micIndicatorStyle = .graphite
    let snapshotData = try withLegacyDisabledSetting(
      JSONEncoder().encode(config.makeSnapshot()))
    let restored = AppConfiguration()
    restored.applySnapshot(try JSONDecoder().decode(
      AppConfiguration.Snapshot.self, from: snapshotData))
    let snapshotOverlay = MicIndicatorOverlay(configuration: restored)
    defer { snapshotOverlay.stopTracking() }
    snapshotOverlay.startTracking()
    #expect(snapshotOverlay.testPanelIsVisible)
    #expect(restored.micIndicatorStyle == .graphite)
    snapshotOverlay.stopTracking()

    let payloadData = try withLegacyDisabledSetting(
      JSONEncoder().encode(ConfigPresetStore.shared.payload(from: config)))
    ConfigPresetStore.shared.applyPayload(
      try JSONDecoder().decode(ConfigPreset.Payload.self, from: payloadData), to: restored)
    let presetOverlay = MicIndicatorOverlay(configuration: restored)
    defer { presetOverlay.stopTracking() }
    presetOverlay.startTracking()
    #expect(presetOverlay.testPanelIsVisible)
    #expect(restored.micIndicatorStyle == .graphite)
  }

  private func withLegacyDisabledSetting(_ data: Data) throws -> Data {
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["micIndicatorEnabled"] = false
    return try JSONSerialization.data(withJSONObject: object)
  }
}
