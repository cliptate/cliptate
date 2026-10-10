import Foundation
import Testing

@testable import Cliptate

private let liveMLXInferenceEnabled =
  ProcessInfo.processInfo.environment["CLIPTATE_ENABLE_LIVE_MLX_TESTS"] == "1"

@Suite("MLXParakeetTranscriber")
struct MLXParakeetTranscriberTests {

  @Test("transcriber initializes without model ready")
  func initializesWithoutModelReady() async {
    let transcriber = MLXParakeetTranscriber(model: .parakeetV3)
    let ready = transcriber.isModelReady
    #expect(!ready)
  }

  @Test("transcribeChunk throws when model not ready")
  func transcribeChunkThrowsWhenNotReady() async {
    let transcriber = MLXParakeetTranscriber(model: .parakeetV3)
    let silence = [Float](repeating: 0, count: 160)
    await #expect(throws: Error.self) {
      _ = try await transcriber.transcribeChunk(samples: silence, language: .english)
    }
  }

  @Test("transcribeWithProgress throws when model not ready")
  func transcribeWithProgressThrowsWhenNotReady() async {
    let transcriber = MLXParakeetTranscriber(model: .parakeetV3)
    await #expect(throws: Error.self) {
      _ = try await transcriber.transcribeWithProgress(
        audioPath: "/nonexistent.wav",
        language: .english,
        progressHandler: { _ in }
      )
    }
  }

  @Test(
    "warmUp and transcribe real audio",
    .disabled(if: !liveMLXInferenceEnabled, "Requires opt-in live MLX Metal runtime.")
  )
  func warmUpAndTranscribeRealAudio() async throws {
    let bundle = Bundle.module
    guard let audioURL = bundle.url(forResource: "vad_example", withExtension: "wav") else {
      throw TestError.resourceNotFound("vad_example.wav not found in test bundle")
    }

    let transcriber = MLXParakeetTranscriber(model: .parakeetV3)
    try await transcriber.warmUpModelWithProgress { _ in }

    let ready = transcriber.isModelReady
    #expect(ready)

    let result = try await transcriber.transcribeWithProgress(
      audioPath: audioURL.path,
      language: .english,
      progressHandler: { _ in }
    )

    #expect(result.totalDuration > 0)
    let allText = result.segments.map(\.text).joined(separator: " ")
    #expect(!allText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  @Test(
    "chunk transcription returns non-empty text for speech audio",
    .disabled(if: !liveMLXInferenceEnabled, "Requires opt-in live MLX Metal runtime.")
  )
  func chunkTranscriptionReturnsSpeech() async throws {
    let bundle = Bundle.module
    guard let audioURL = bundle.url(forResource: "vad_example", withExtension: "wav") else {
      throw TestError.resourceNotFound("vad_example.wav not found in test bundle")
    }

    let transcriber = MLXParakeetTranscriber(model: .parakeetV3)
    try await transcriber.warmUpModelWithProgress { _ in }

    // Use first 5 seconds as a chunk
    let data = try Data(contentsOf: audioURL)
    let audioBytes = data.dropFirst(44)  // skip WAV header
    let sampleCount = min(audioBytes.count / 2, 16_000 * 5)
    var samples = [Float](repeating: 0, count: sampleCount)
    audioBytes.withUnsafeBytes { ptr in
      let int16Ptr = ptr.bindMemory(to: Int16.self)
      for i in 0..<sampleCount {
        samples[i] = Float(int16Ptr[i]) / 32_768.0
      }
    }

    let text = try await transcriber.transcribeChunk(samples: samples, language: .english)
    #expect(!text.isEmpty)
  }
}

private enum TestError: Error {
  case resourceNotFound(String)
}
