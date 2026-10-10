import Foundation

/// Minimal protocol for any ASR model that can transcribe a chunk of 16kHz mono audio.
///
/// Conformers provide a synchronous transcription method. The streaming pipeline
/// handles mic capture, buffering, VAD, and resampling — engines only see
/// pre-processed 16kHz speech samples.
protocol StreamingASREngine: Sendable {
  /// Transcribe a chunk of 16kHz mono audio samples.
  /// - Parameters:
  ///   - samples16k: Pre-resampled 16kHz mono float samples.
  ///   - language: Target language for transcription.
  ///   - dictionaryContext: Optional custom dictionary bias context string.
  /// - Returns: Transcribed text for this chunk (may be empty).
  func transcribeStreamingChunk(
    samples16k: [Float],
    language: Language,
    dictionaryContext: String?
  ) throws -> String
}
