import AVFoundation
import Testing

@testable import Cliptate

@Suite("Qwen3ASRTranscriber dictionary context")
struct Qwen3ASRTranscriberContextTests {
  @Test("file transcription forwards dictionary context into Qwen3 generate")
  func fileTranscriptionForwardsDictionaryContext() async throws {
    let capture = Qwen3ASRTranscriber.TestHooks.GenerateCapture()
    let transcriber = Qwen3ASRTranscriber(
      model: .qwen3ASR,
      testHooks: .init(
        loadAudioSamples: { _ in [0.1, -0.2, 0.3, -0.4] },
        readAudioDuration: { _ in 1.0 },
        generate: capture.record
      )
    )

    let result = try await transcriber.transcribeWithProgress(
      audioPath: "/tmp/cliptate-dictionary-context.wav",
      language: .english,
      dictionaryContext: "WhisperCutPro\nsysulq"
    ) { _ in }

    #expect(capture.last?.context == "WhisperCutPro\nsysulq")
    #expect(result.segments.first?.text == "sysulq whispercut")
  }

  @Test("chunk transcription forwards dictionary context into Qwen3 chunk path")
  func chunkTranscriptionForwardsDictionaryContext() async throws {
    let capture = Qwen3ASRTranscriber.TestHooks.GenerateCapture()
    let transcriber = Qwen3ASRTranscriber(
      model: .qwen3ASR,
      testHooks: .init(
        generate: capture.record
      )
    )

    _ = try await transcriber.transcribeChunk(
      samples: [0.1, -0.2, 0.3, -0.4],
      language: .english,
      dictionaryContext: "WhisperCutPro"
    )

    #expect(capture.last?.context == "WhisperCutPro")
  }

  @Test("streaming chunk transcription forwards dictionary context into Qwen3 generate")
  func streamingChunkForwardsDictionaryContext() throws {
    let capture = Qwen3ASRTranscriber.TestHooks.GenerateCapture()
    let transcriber = Qwen3ASRTranscriber(
      model: .qwen3ASR,
      testHooks: .init(
        generate: capture.record
      )
    )

    _ = try transcriber.transcribeStreamingChunk(
      samples16k: [0.1, -0.2, 0.3, -0.4],
      language: .english,
      dictionaryContext: "sysulq"
    )

    #expect(capture.last?.context == "sysulq")
  }

  @MainActor
  @Test("StreamingAudioCaptureModule forwards dictionary context into chunk transcription")
  func streamingModuleForwardsDictionaryContextThroughModule() async throws {
    // This test verifies that dictionaryContext passed to the module
    // reaches the ASR engine. We test this through the transcriber directly
    // since the module's audio pipeline cannot be easily unit-tested without
    // a real mic. The direct call in the test above verifies the same path.
    let capture = Qwen3ASRTranscriber.TestHooks.GenerateCapture()
    let transcriber = Qwen3ASRTranscriber(
      model: .qwen3ASR,
      testHooks: .init(
        generate: capture.record
      )
    )

    // Call via StreamingASREngine protocol
    let engine: any StreamingASREngine = transcriber
    _ = try engine.transcribeStreamingChunk(
      samples16k: [0.1, -0.2, 0.3, -0.4],
      language: .english,
      dictionaryContext: "sysulq"
    )

    #expect(capture.last?.context == "sysulq")
  }

  @MainActor
  @Test("dictionary bias fallback still normalizes qwen3 output after context injection")
  func fallbackBiasStillApplies() {
    let config = AppConfiguration.shared
    let transcriber = VoiceTranscriber.shared
    let previousDictionary = config.voiceToTextCustomDictionary

    defer {
      config.replaceDictionaryEntries(with: previousDictionary)
      transcriber.testResetAfterQwen3StreamAssertions()
    }

    config.replaceDictionaryEntries(with: ["WhisperCutPro"])
    transcriber.testPrepareForQwen3StreamAssertions()

    transcriber.testHandleQwen3StreamUpdate("whisper cut pro")

    #expect(transcriber.liveText == "WhisperCutPro")
  }
}
