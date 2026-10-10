import Testing

@testable import Cliptate

@Suite("Dubbing Export Fallback")
struct DubbingExportFallbackTests {

  // MARK: - Voice Clone Model Resolution

  @Test("resolves voice-clone model when selected model already supports it")
  func resolvesDirectMatchForVoiceCloneModel() {
    let baseModelRepo = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"
    let resolved = DubbingModelResolver.resolveVoiceCloneModel(
      preferredRepo: baseModelRepo
    )
    #expect(resolved != nil)
    #expect(resolved?.huggingFaceRepo == baseModelRepo)
    #expect(resolved?.supportsVoiceClone == true)
  }

  @Test("resolves voice-clone model when selected model is CustomVoice")
  func resolvesVoiceCloneModelForCustomVoice() {
    let customVoiceRepo = "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit"
    let resolved = DubbingModelResolver.resolveVoiceCloneModel(
      preferredRepo: customVoiceRepo
    )
    #expect(resolved != nil)
    #expect(resolved?.supportsVoiceClone == true)
    // Should prefer same parameter size and quantization
    #expect(resolved?.parameterSize == "0.6B")
    #expect(resolved?.quantization == "8-bit")
  }

  @Test("resolves voice-clone model when selected model is VoiceDesign")
  func resolvesVoiceCloneModelForVoiceDesign() {
    let voiceDesignRepo = "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-4bit"
    let resolved = DubbingModelResolver.resolveVoiceCloneModel(
      preferredRepo: voiceDesignRepo
    )
    #expect(resolved != nil)
    #expect(resolved?.supportsVoiceClone == true)
    // Should prefer same parameter size and quantization
    #expect(resolved?.parameterSize == "1.7B")
    #expect(resolved?.quantization == "4-bit")
  }

  @Test("resolves any voice-clone model when no matching size/quantization found")
  func resolvesAnyVoiceCloneModelAsFallback() {
    // Use a completely unknown repo
    let unknownRepo = "mlx-community/Unknown-Model"
    let resolved = DubbingModelResolver.resolveVoiceCloneModel(
      preferredRepo: unknownRepo
    )
    #expect(resolved != nil)
    #expect(resolved?.supportsVoiceClone == true)
  }

  // MARK: - Dubbing Precondition Checks

  @Test("canPerformDubbing returns false when no translations exist")
  func cannotDubWithoutTranslations() {
    let segments = [
      Segment(startTime: 0, endTime: 1, text: "Hello"),
      Segment(startTime: 1, endTime: 2, text: "World"),
    ]
    let result = DubbingModelResolver.canPerformDubbing(
      segments: segments,
      ttsLanguage: "en"
    )
    #expect(result == false)
  }

  @Test("canPerformDubbing returns true when translations exist")
  func canDubWithTranslations() {
    let segments = [
      Segment(
        startTime: 0, endTime: 1, text: "你好",
        translation: SegmentTranslation(text: "Hello", language: .english)),
      Segment(startTime: 1, endTime: 2, text: "世界"),
    ]
    let result = DubbingModelResolver.canPerformDubbing(
      segments: segments,
      ttsLanguage: "en"
    )
    #expect(result == true)
  }

  @Test("canPerformDubbing returns false for unsupported language")
  func cannotDubUnsupportedLanguage() {
    let segments = [
      Segment(
        startTime: 0, endTime: 1, text: "Hello",
        translation: SegmentTranslation(text: "Bonjour", language: .french)),
    ]
    let result = DubbingModelResolver.canPerformDubbing(
      segments: segments,
      ttsLanguage: "fr"
    )
    #expect(result == false)
  }

  @Test("canPerformDubbing returns false for empty segments")
  func cannotDubEmptySegments() {
    let result = DubbingModelResolver.canPerformDubbing(
      segments: [],
      ttsLanguage: "en"
    )
    #expect(result == false)
  }
}
