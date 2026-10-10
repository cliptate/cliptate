import Foundation
import Testing

@testable import Cliptate

@Suite("ConfigurationRuntime")
@MainActor
struct ConfigurationRuntimeTests {
  @Test("bootstrap prefers persisted configuration over the default preset")
  func bootstrapPrefersPersistedConfiguration() throws {
    let config = AppConfiguration.shared
    let original = config.makeSnapshot()
    defer { config.applySnapshot(original) }

    var storedSnapshot = AppConfiguration.defaultSnapshot
    storedSnapshot.transcriberType = .qwen3
    storedSnapshot.modelVariant = .qwen3ASR
    storedSnapshot.language = .japanese

    let persistence = FakePersistence(snapshot: storedSnapshot)
    let presetStore = FakePresetStore(
      presets: [
        ConfigPreset(
          id: UUID(),
          name: "Default",
          createdAt: .distantPast,
          updatedAt: .distantPast,
          isDefault: true,
          payload: .init(
            transcriberType: .parakeet,
            modelVariant: .parakeetV3,
            language: .english,
            leftPadMs: 100,
            rightPadMs: 100,
            splitBySentence: true,
            maxCharsPerSegment: 50,
            filterSilent: true,
            ttsEngine: .qwen3TTS,
            ttsVariantPreference: .automatic,
            ttsSpeakingRate: 1.0,
            fcpxmlProjectName: "Default",
            fcpxmlEnabled: true,
            fcpxmlFrameRate: 25.0,
            fcpxmlIncludeSubtitles: true,
            fcpxmlIsResolveCompatible: false,
            exportMode: .merge,
            videoExportEnabled: false,
            videoExportFormat: .mp4,
            videoExportBurnInSubtitles: true,
            keepPunctuationOnExport: true,
            videoExportQuality: .original,
            audioExportEnabled: false,
            audioExportFormat: .m4a,
            effectExtractHighlights: true,
            effectEnableScaling: true,
            effectScaleMultiplier: 1.2,
            effectEnableZoom: false,
            effectZoomMultiplier: 1.2,
            effectFilterFillerWords: true,
            effectFillerWords: SegmentEffectConfiguration.defaultFillerWords,
            translationPlacement: .below,
            translationTargetLanguage: .chinese,
            subtitleStyles: defaultSubtitleStyles,
            subtitleExportFormats: [],
            aiProviderKeys: [:],
            selectedAIProvider: .gemini,
            aiEnabled: false
          )
        )
      ]
    )
    let modelRuntime = FakeModelRuntime()
    var migrationCount = 0

    let runtime = ConfigurationRuntime(
      persistence: persistence,
      presetStore: presetStore,
      modelRuntime: modelRuntime,
      migrate: { _ in migrationCount += 1 }
    )

    let result = runtime.bootstrap(using: config)

    #expect(result.appliedStoredSnapshot == true)
    #expect(config.transcriberType == .qwen3)
    #expect(config.modelVariant == .qwen3ASR)
    #expect(config.language == .japanese)
    #expect(persistence.bindCallCount == 1)
    #expect(presetStore.loaded == true)
    #expect(presetStore.appliedPresetIDs.isEmpty)
    #expect(modelRuntime.prepareCallCount == 1)
    #expect(migrationCount == 1)
  }
}

@MainActor
private final class FakePersistence: ConfigurationSnapshotPersisting {
  func flush(using config: AppConfiguration) throws {}
  var snapshot: AppConfiguration.Snapshot?
  private(set) var bindCallCount = 0

  init(snapshot: AppConfiguration.Snapshot?) {
    self.snapshot = snapshot
  }

  func bind(to config: AppConfiguration) {
    bindCallCount += 1
  }

  func loadSnapshot() -> AppConfiguration.Snapshot? {
    snapshot
  }

  func clearSnapshot() {}
}

@MainActor
private final class FakePresetStore: ConfigurationPresetManaging {
  var presets: [ConfigPreset]
  private(set) var loaded = false
  private(set) var appliedPresetIDs: [UUID] = []

  init(presets: [ConfigPreset]) {
    self.presets = presets
  }

  func load() throws {
    loaded = true
  }

  func apply(id: UUID, to config: AppConfiguration) throws {
    appliedPresetIDs.append(id)
  }

  func ensureDefaultPreset(using config: AppConfiguration) throws -> ConfigPreset {
    try #require(presets.first)
  }
}

@MainActor
private final class FakeModelRuntime: ModelRuntimeControlling {
  private(set) var prepareCallCount = 0

  func prepare(using config: AppConfiguration) {
    prepareCallCount += 1
  }
}
