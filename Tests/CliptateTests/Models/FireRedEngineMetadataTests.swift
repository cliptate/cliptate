import Testing

@testable import Cliptate

@Suite("FireRed engine metadata")
struct FireRedEngineMetadataTests {
  @Test("FireRed appears as a distinct ASR engine")
  func fireRedEngineExists() {
    // These English assertions intentionally match the current NSLocalizedString fallback keys.
    #expect(TranscriberType.allCases.contains(.fireRed))
    #expect(TranscriberType.fireRed.displayName == "FireRed")
  }

  @Test("FireRed exposes only FireRed models")
  func fireRedSupportedModels() {
    #expect(TranscriberType.fireRed.supportedModels == [.fireRedASR2])
    #expect(ModelVariant.fireRedASR2.isFireRedASRModel)
    #expect(ModelVariant.fireRedASR2.provider == .fireRed)
    #expect(!ModelVariant.fireRedASR2.isQwen3ASRModel)
    #expect(!ModelVariant.fireRedASR2.isParakeetModel)
  }

  @Test("Sortformer offline is removed from user-visible VAD models")
  func sortformerOfflineRemovedFromVisibleVADModels() {
    #expect(!ModelVariant.vadModels.contains(.sortformerOffline))
    #expect(ModelVariant.vadModels.contains(.sortformerStreaming))
  }

  @Test("FireRed capability metadata reflects product requirements")
  func fireRedCapabilities() {
    // These expectations intentionally match the English NSLocalizedString keys.
    #expect(ModelVariant.fireRedASR2.languageSummary == "Chinese dialects, English, mixed speech, lyrics")
    #expect(ModelVariant.fireRedASR2.featureHighlights.contains("Mandarin + 20+ dialects / accents"))
    #expect(ModelVariant.fireRedASR2.featureHighlights.contains("Chinese-English mixed speech"))
    #expect(ModelVariant.fireRedASR2.featureHighlights.contains("Lyrics recognition"))
  }

  @Test("FireRed localized metadata preserves visible copy")
  func fireRedLocalizedMetadataPreservesVisibleCopy() {
    #expect(TranscriberType.fireRed.displayName == "FireRed")
    #expect(
      TranscriberType.fireRed.description
        == "FireRed ASR for Mandarin dialects, English, mixed speech, and lyrics recognition"
    )
    #expect(ModelVariant.fireRedASR2.displayName == "FireRed ASR 2")
    #expect(
      ModelVariant.fireRedASR2.summary
        == "FireRed ASR 2 optimized for Mandarin dialects, English, mixed speech, and lyrics recognition."
    )
    #expect(ModelVariant.fireRedASR2.languageSummary == "Chinese dialects, English, mixed speech, lyrics")
    #expect(
      ModelVariant.fireRedASR2.featureHighlights == [
        "Mandarin + 20+ dialects / accents",
        "Chinese-English mixed speech",
        "Lyrics recognition",
      ])
  }

  @Test("Sortformer streaming localized copy preserves visible copy")
  func sortformerStreamingLocalizedCopyPreservesVisibleCopy() {
    #expect(ModelsView.ASRProvider.fireRed.displayName == "FireRed")
    #expect(ModelVariant.sortformerStreaming.displayName == "Sortformer Streaming")
    #expect(
      ModelVariant.sortformerStreaming.summary
        == "Streaming diarization and speech activity detection optimized for low-latency MLX pipelines."
    )
    #expect(ModelVariant.sortformerStreaming.languageSummary == "Language independent")
    #expect(
      ModelVariant.sortformerStreaming.featureHighlights == [
        "Streaming diarization",
        "MLX optimized",
        "Low-latency VAD",
      ])
  }

  @Test("FireRed engine now creates the dedicated transcriber")
  func fireRedCreatesDedicatedTranscriber() {
    let transcriber = TranscriberType.fireRed.createTranscriber(model: .fireRedASR2)
    #expect(transcriber is FireRedASRTranscriber)
  }
}
