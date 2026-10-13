import Foundation
import Testing

@testable import Cliptate

@Suite("Dictation indicator styles")
@MainActor
struct MicIndicatorStyleTests {
  @Test(
    "Every style survives snapshot and preset restoration", arguments: MicIndicatorStyle.allCases)
  func roundTrip(style: MicIndicatorStyle) throws {
    let configuration = AppConfiguration()
    configuration.micIndicatorStyle = style
    let snapshot = try JSONDecoder().decode(
      AppConfiguration.Snapshot.self, from: JSONEncoder().encode(configuration.makeSnapshot())
    )
    let restored = AppConfiguration()
    restored.applySnapshot(snapshot)
    #expect(restored.micIndicatorStyle == style)

    let store = ConfigPresetStore.shared
    let payload = try JSONDecoder().decode(
      ConfigPreset.Payload.self, from: JSONEncoder().encode(store.payload(from: configuration))
    )
    restored.micIndicatorStyle = .pulseBlue
    store.applyPayload(payload, to: restored)
    #expect(restored.micIndicatorStyle == style)
  }

  @Test(
    "Older and unknown style values preserve the existing blue appearance",
    arguments: [Optional<String>.none, "futureStyle"])
  func compatibleRestore(value: String?) throws {
    let configuration = AppConfiguration()
    let snapshotData = try replacingStyle(
      in: JSONEncoder().encode(configuration.makeSnapshot()), with: value)
    let snapshot = try JSONDecoder().decode(AppConfiguration.Snapshot.self, from: snapshotData)
    #expect(snapshot.micIndicatorStyle == .pulseBlue)

    let presetData = try replacingStyle(
      in: JSONEncoder().encode(ConfigPresetStore.shared.payload(from: configuration)), with: value)
    let preset = try JSONDecoder().decode(ConfigPreset.Payload.self, from: presetData)
    #expect(preset.micIndicatorStyle == .pulseBlue)
  }

  @Test("An existing overlay follows style changes without restarting")
  func liveStyleSelection() {
    let configuration = AppConfiguration()
    let overlay = MicIndicatorOverlay(configuration: configuration)
    overlay.startTracking()
    defer { overlay.stopTracking() }
    overlay.updateTranscript("Preview text stays visible during style changes.")
    overlay.updateStatus(.transcribing)
    let height = overlay.testCurrentPanelHeight
    for style in MicIndicatorStyle.allCases {
      configuration.micIndicatorStyle = style
      #expect(overlay.testIndicatorStyle == style)
      #expect(overlay.testIsActive)
      #expect(overlay.testHasTranscript)
      #expect(overlay.testOverlayStatus == .transcribing)
      #expect(overlay.testCurrentPanelHeight == height)
    }
    configuration.resetToDefaults()
    #expect(overlay.testIndicatorStyle == .pulseBlue)
  }

  private func replacingStyle(in data: Data, with value: String?) throws -> Data {
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["micIndicatorStyle"] = value
    return try JSONSerialization.data(withJSONObject: object)
  }
}
