import Testing

@testable import Cliptate

@Suite("ModelCacheManager Language Filtering")
struct ModelCacheManagerLanguageTests {
  @Test
  func asrLanguageFilteringUsesModelCapabilities() async {
    await ModelCacheManager.shared.invalidateLanguageSupportCache()
    let languages = await ModelCacheManager.shared.filteredLanguages(
      for: .asr(type: .parakeet, model: .parakeetV2)
    )

    #expect(languages == [.english])
  }

  @Test
  func alignLanguageFilteringUsesAlignModelCapabilities() async {
    await ModelCacheManager.shared.invalidateLanguageSupportCache()
    let languages = await ModelCacheManager.shared.filteredLanguages(
      for: .align(model: .qwen3ForcedAligner)
    )

    #expect(languages.contains(.english))
    #expect(languages.contains(.chinese))
    #expect(!languages.contains(.auto))
  }

  @Test
  func ttsLanguageFilteringMatchesSelectedTTSEngine() async {
    await ModelCacheManager.shared.invalidateLanguageSupportCache()
    let languages = await ModelCacheManager.shared.filteredLanguages(
      for: .tts(
        engine: .qwen3TTS,
        modelID: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"
      )
    )

    #expect(languages.contains(.english))
    #expect(languages.contains(.chinese))
    #expect(languages.contains(.japanese))
    #expect(languages.contains(.korean))
  }
}
