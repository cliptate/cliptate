import CliptateCore
import Foundation

/// Orchestrates a complete VAD → ASR → Align batch transcription pipeline.
///
/// Each stage is backed by a swappable provider, enabling different model
/// implementations to be selected at runtime without changing this type.
/// Use `TranscriptionPipelineFactory` to create a correctly configured instance.
struct BatchTranscriptionPipeline: Sendable {
  let vad: any VADProvider
  let asr: any ASRChunkProvider
  let align: any AlignChunkProvider

  init(vad: any VADProvider, asr: any ASRChunkProvider, align: any AlignChunkProvider) {
    self.vad = vad
    self.asr = asr
    self.align = align
  }

  /// Runs the full pipeline on pre-loaded audio samples.
  ///
  /// 1. VAD detects speech segments.
  /// 2. For each segment, ASR transcribes the chunk to text.
  /// 3. For each segment, Align maps text to word-level timestamps.
  ///
  /// Progress is reported via `progressHandler` in [0, 1].
  func run(
    samples: [Float],
    totalDuration: Double,
    language: Language,
    modelUsed: String,
    progressHandler: @escaping @Sendable (TranscriptionProgress) -> Void
  ) async throws -> TranscriptionResult {
    let speechSegments = try await vad.detectSpeech(samples: samples, totalDuration: totalDuration)

    let capturedASR = asr
    let capturedAlign = align

    return try await SegmentedAlignmentPipeline().run(
      speechSegments: speechSegments,
      totalDuration: totalDuration,
      modelUsed: modelUsed,
      progressHandler: progressHandler,
      transcribe: { segment in
        let chunkSamples = AudioProcessor.extractSamples(
          samples: samples,
          startTime: segment.startTime,
          endTime: segment.endTime
        )
        guard !chunkSamples.isEmpty else { return "" }
        return try await capturedASR.transcribe(samples: chunkSamples, language: language)
      },
      align: { segment, text in
        let chunkSamples = AudioProcessor.extractSamples(
          samples: samples,
          startTime: segment.startTime,
          endTime: segment.endTime
        )
        guard !chunkSamples.isEmpty else { return [] }
        return try await capturedAlign.align(samples: chunkSamples, text: text, language: language)
      }
    )
  }
}
