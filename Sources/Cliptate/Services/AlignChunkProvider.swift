import Foundation

/// Abstracts the forced-alignment stage: maps an existing text transcript
/// onto fine-grained word-level timestamps for a pre-segmented audio chunk
/// (16 kHz mono Float32 samples, 0-based offsets).
protocol AlignChunkProvider: Sendable {
  func align(samples: [Float], text: String, language: Language) async throws -> [WordTiming]
}

/// Align provider backed by Qwen3ForcedAlignerTranscriber's forced-aligner model.
struct Qwen3AlignChunkProvider: AlignChunkProvider {
  let aligner: Qwen3ForcedAlignerTranscriber

  func align(samples: [Float], text: String, language: Language) async throws -> [WordTiming] {
    try aligner.alignChunk(samples: samples, text: text, language: language)
  }
}
