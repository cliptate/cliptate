import Foundation

/// Abstracts the ASR (automatic speech recognition) stage: transcribes a
/// pre-segmented audio chunk (16 kHz mono Float32 samples) to plain text.
protocol ASRChunkProvider: Sendable {
  func transcribe(samples: [Float], language: Language) async throws -> String
}

/// ASR provider backed by MLXParakeetTranscriber.
struct ParakeetASRChunkProvider: ASRChunkProvider {
  let transcriber: MLXParakeetTranscriber

  func transcribe(samples: [Float], language: Language) async throws -> String {
    try await transcriber.transcribeChunk(samples: samples, language: language)
  }
}

/// ASR provider backed by Qwen3ASRTranscriber.
/// Captures an optional dictionary context for custom vocabulary biasing.
struct Qwen3ASRChunkProvider: ASRChunkProvider {
  let transcriber: Qwen3ASRTranscriber
  let dictionaryContext: String?

  func transcribe(samples: [Float], language: Language) async throws -> String {
    try await transcriber.transcribeChunk(
      samples: samples,
      language: language,
      dictionaryContext: dictionaryContext
    )
  }
}

/// Generic fallback ASR provider for any Transcriber not implementing
/// ChunkTranscriber. Prefers the ChunkTranscriber fast path when available;
/// otherwise falls back to file-based transcription.
struct FallbackASRChunkProvider: ASRChunkProvider {
  let transcriber: any Transcriber

  func transcribe(samples: [Float], language: Language) async throws -> String {
    if let chunkTranscriber = transcriber as? ChunkTranscriber {
      return try await chunkTranscriber.transcribeChunk(samples: samples, language: language)
    }
    let url = try AudioProcessor.saveSegmentToTemporaryFile(samples: samples)
    defer { try? FileManager.default.removeItem(at: url) }
    let result = try await transcriber.transcribeWithProgress(
      audioPath: url.path,
      language: language
    ) { _ in }
    return result.segments.map(\.text)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
