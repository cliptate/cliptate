import CliptateCore
import Foundation
import Testing

@testable import Cliptate

/// Tests for ttsPresetSpeaker in AppConfiguration.Snapshot (round-trip, backward compat, defaults).
@Suite("AppConfiguration – TTS preset speaker")
@MainActor
struct TTSPresetSpeakerConfigTests {

    // MARK: - Round-trip via makeSnapshot / applySnapshot

    @Test("ttsPresetSpeaker round-trips through Snapshot encode/decode")
    func presetSpeakerSnapshotRoundTrip() throws {
        let original = AppConfiguration.shared.makeSnapshot()
        defer { AppConfiguration.shared.applySnapshot(original) }

        AppConfiguration.shared.ttsPresetSpeaker = "Vivian"
        let snap = AppConfiguration.shared.makeSnapshot()
        #expect(snap.ttsPresetSpeaker == "Vivian")

        AppConfiguration.shared.ttsPresetSpeaker = ""
        AppConfiguration.shared.applySnapshot(snap)
        #expect(AppConfiguration.shared.ttsPresetSpeaker == "Vivian")
    }

    @Test("ttsPresetSpeaker Snapshot encodes and decodes as JSON")
    func presetSpeakerSnapshotJSONRoundTrip() throws {
        let original = AppConfiguration.shared.makeSnapshot()
        defer { AppConfiguration.shared.applySnapshot(original) }

        AppConfiguration.shared.ttsPresetSpeaker = "Ryan"
        let snap = AppConfiguration.shared.makeSnapshot()
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(AppConfiguration.Snapshot.self, from: data)
        #expect(decoded.ttsPresetSpeaker == "Ryan")
    }

    @Test("Snapshot with missing ttsPresetSpeaker decodes as empty string (backward compat)")
    func backwardCompatMissingPresetSpeaker() throws {
        let snap = AppConfiguration.shared.makeSnapshot()
        var dict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snap)) as! [String: Any]
        dict.removeValue(forKey: "ttsPresetSpeaker")
        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(AppConfiguration.Snapshot.self, from: data)
        #expect(decoded.ttsPresetSpeaker == "")
    }

    @Test("Default ttsPresetSpeaker is empty string")
    func defaultPresetSpeakerIsEmpty() {
        #expect(AppConfiguration.defaultSnapshot.ttsPresetSpeaker == "")
    }

    @Test("TTSPresetSpeaker.all contains expected Chinese and English speakers")
    func presetSpeakerListContainsExpectedSpeakers() {
        let all = TTSPresetSpeaker.all
        let names = all.map(\.name)
        // Chinese speakers
        #expect(names.contains("Vivian"))
        #expect(names.contains("Serena"))
        #expect(names.contains("Uncle_Fu"))
        #expect(names.contains("Dylan"))
        #expect(names.contains("Eric"))
        // English speakers
        #expect(names.contains("Ryan"))
        #expect(names.contains("Aiden"))
    }
}
