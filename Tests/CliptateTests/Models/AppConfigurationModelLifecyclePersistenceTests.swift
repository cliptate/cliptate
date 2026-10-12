import Foundation
import Testing

@testable import Cliptate

@Suite("AppConfiguration model lifecycle persistence")
@MainActor
struct AppConfigurationModelLifecyclePersistenceTests {
  @Test("voice to text active ASR selection follows shared model selection")
  func voiceToTextActiveSelectionTracksSharedASRConfiguration() throws {
    let original = AppConfiguration.shared.makeSnapshot()
    defer {
      AppConfiguration.shared.applySnapshot(original)
    }

    var changed = original
    changed.transcriberType = .qwen3
    changed.modelVariant = .qwen3ASR
    changed.voiceToTextTranscriberType = .parakeet
    changed.voiceToTextModelVariant = .parakeetV3

    AppConfiguration.shared.applySnapshot(changed)

    #expect(AppConfiguration.shared.activeVoiceToTextTranscriberType == .qwen3)
    #expect(AppConfiguration.shared.activeVoiceToTextModelVariant == .qwen3ASR)
  }

  @Test("model lifecycle settings round-trip across snapshot persistence")
  func snapshotPersistenceRoundTripForModelLifecycleSettings() throws {
    let original = AppConfiguration.shared.makeSnapshot()
    defer {
      AppConfiguration.shared.applySnapshot(original)
    }

    var changed = original
    changed.alignModelVariant = .qwen3ForcedAligner
    changed.vadModelVariant = .sortformerStreaming
    changed.modelCleanupTimeoutSeconds = 1234
    changed.asrIdleTimeoutSeconds = 789
    changed.ttsEngine = .qwen3TTS
    changed.ttsMLXModelId = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"
    changed.voiceToTextTranscriberType = .parakeet
    changed.voiceToTextModelVariant = .parakeetV2

    let encoded = try JSONEncoder().encode(changed)
    let decoded = try JSONDecoder().decode(AppConfiguration.Snapshot.self, from: encoded)

    AppConfiguration.shared.applySnapshot(decoded)
    let reloaded = AppConfiguration.shared.makeSnapshot()

    #expect(reloaded.alignModelVariant == .qwen3ForcedAligner)
    #expect(reloaded.vadModelVariant == .sortformerStreaming)
    #expect(reloaded.modelCleanupTimeoutSeconds == 1234)
    #expect(reloaded.asrIdleTimeoutSeconds == 789)
    #expect(reloaded.ttsEngine == .qwen3TTS)
    #expect(reloaded.ttsMLXModelId == "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit")
    #expect(reloaded.voiceToTextTranscriberType == reloaded.transcriberType)
    #expect(reloaded.voiceToTextModelVariant == reloaded.modelVariant)
  }

  @Test("Whisper selection and explicit languages survive snapshot restoration")
  func whisperSnapshotRoundTrip() throws {
    let configuration = AppConfiguration.shared
    let original = configuration.makeSnapshot()
    defer { configuration.applySnapshot(original) }
    var changed = original
    changed.transcriberType = .whisper
    changed.modelVariant = .whisperSmall
    changed.language = .chinese
    changed.voiceToTextLanguage = .japanese
    let decoded = try JSONDecoder().decode(
      AppConfiguration.Snapshot.self, from: JSONEncoder().encode(changed)
    )
    configuration.applySnapshot(decoded)
    #expect(configuration.modelVariant == .whisperSmall)
    #expect(configuration.activeVoiceToTextTranscriberType == .whisper)
    #expect(configuration.activeVoiceToTextModelVariant == .whisperSmall)
    #expect(configuration.language == .chinese)
    #expect(configuration.voiceToTextLanguage == .japanese)
  }

  @Test("Legacy Whisper redirects restore to Turbo with supported languages")
  func legacyWhisperSnapshot() {
    let configuration = AppConfiguration.shared
    let original = configuration.makeSnapshot()
    defer { configuration.applySnapshot(original) }
    var changed = original
    changed.transcriberType = .whisper
    changed.modelVariant = .parakeetV3
    changed.language = .auto
    changed.voiceToTextLanguage = .auto
    configuration.applySnapshot(changed)
    #expect(configuration.modelVariant == .whisperLargeV3Turbo)
    #expect(configuration.activeVoiceToTextModelVariant == .whisperLargeV3Turbo)
    #expect(configuration.language == .english)
    #expect(configuration.voiceToTextLanguage == .english)
  }

  @Test("Nemotron snapshot and preset selections restore for AI Cut and dictation")
  func nemotronSnapshotRoundTrip() throws {
    let configuration = AppConfiguration.shared
    let original = configuration.makeSnapshot()
    defer { configuration.applySnapshot(original) }
    var changed = original
    changed.transcriberType = .nemotron
    changed.modelVariant = .nemotronASR35bf16
    changed.language = .chinese
    changed.voiceToTextLanguage = .japanese
    let decoded = try JSONDecoder().decode(AppConfiguration.Snapshot.self, from: JSONEncoder().encode(changed))
    configuration.applySnapshot(decoded)
    #expect(configuration.modelVariant == .nemotronASR35bf16)
    #expect(configuration.activeVoiceToTextTranscriberType == .nemotron)
    #expect(configuration.activeVoiceToTextModelVariant == .nemotronASR35bf16)
    #expect(configuration.language == .chinese)
    #expect(configuration.voiceToTextLanguage == .japanese)

    changed.modelVariant = .nemotronASREnglish8bit
    configuration.applySnapshot(changed)
    #expect(configuration.language == .english)
    #expect(configuration.voiceToTextLanguage == .english)
    changed.modelVariant = .parakeetV3
    configuration.applySnapshot(changed)
    #expect(configuration.modelVariant == .nemotronASR358bit)
    #expect(configuration.activeVoiceToTextModelVariant == .nemotronASR358bit)
  }

  @Test("saved sortformerOffline selection migrates to sileroVAD")
  func migratesOfflineVADSelection() throws {
    let original = AppConfiguration.shared.makeSnapshot()
    defer {
      AppConfiguration.shared.applySnapshot(original)
    }

    var changed = original
    changed.vadModelVariant = .sortformerOffline

    AppConfiguration.shared.applySnapshot(changed)

    #expect(AppConfiguration.shared.vadModelVariant == .sileroVAD)
  }

  @Test("invalid align selection falls back to visible align model")
  func invalidAlignSelectionFallsBackOnSnapshotRestore() throws {
    let original = AppConfiguration.shared.makeSnapshot()
    defer {
      AppConfiguration.shared.applySnapshot(original)
    }

    var changed = original
    changed.alignModelVariant = .parakeetV3

    AppConfiguration.shared.applySnapshot(changed)

    #expect(AppConfiguration.shared.alignModelVariant == ModelVariant.alignerModels.first)
  }
}
