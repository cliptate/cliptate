import Foundation
import Testing
@testable import Cliptate

@Suite("AppConfiguration TTS Properties Tests")
@MainActor
struct AppConfigurationTTSTests {

    @Test("Default snapshot has correct MLX TTS defaults")
    func testDefaultMLXTTSValues() {
        let snap = AppConfiguration.defaultSnapshot
        #expect(snap.ttsMLXModelId == "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit")
        #expect(snap.ttsVoiceDescription == "A young female speaker with a clear and gentle voice")
        #expect(snap.ttsReferenceAudioPath == "")
        #expect(snap.ttsReferenceText == "")
        #expect(snap.ttsLanguage == "en")
    }

    @Test("Default snapshot has ttsEmotionPrompt as empty string")
    func testDefaultEmotionPrompt() {
        let snap = AppConfiguration.defaultSnapshot
        #expect(snap.ttsEmotionPrompt == "")
    }

    @Test("ttsEmotionPrompt round-trips through makeSnapshot and applySnapshot")
    func testEmotionPromptSnapshotRoundTrip() {
        let original = AppConfiguration.shared.makeSnapshot()
        defer { AppConfiguration.shared.applySnapshot(original) }

        AppConfiguration.shared.ttsEmotionPrompt = "very happy and excited"
        let snap = AppConfiguration.shared.makeSnapshot()
        #expect(snap.ttsEmotionPrompt == "very happy and excited")

        AppConfiguration.shared.ttsEmotionPrompt = ""
        AppConfiguration.shared.applySnapshot(snap)
        #expect(AppConfiguration.shared.ttsEmotionPrompt == "very happy and excited")
    }

    @Test("ttsEmotionPrompt Snapshot encodes and decodes as JSON")
    func testEmotionPromptJSONRoundTrip() throws {
        let original = AppConfiguration.shared.makeSnapshot()
        defer { AppConfiguration.shared.applySnapshot(original) }

        AppConfiguration.shared.ttsEmotionPrompt = "calm and professional"
        let snap = AppConfiguration.shared.makeSnapshot()
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(AppConfiguration.Snapshot.self, from: data)
        #expect(decoded.ttsEmotionPrompt == "calm and professional")
    }

    @Test("Snapshot missing ttsEmotionPrompt decodes as empty string (backward compat)")
    func testEmotionPromptBackwardCompat() throws {
        let snap = AppConfiguration.shared.makeSnapshot()
        var dict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snap)) as! [String: Any]
        dict.removeValue(forKey: "ttsEmotionPrompt")
        let data = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(AppConfiguration.Snapshot.self, from: data)
        #expect(decoded.ttsEmotionPrompt == "")
    }
}
