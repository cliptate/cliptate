import Foundation

/// Abstracts the Voice Activity Detection stage of the transcription pipeline.
/// Implementations detect speech segments from raw audio samples.
protocol VADProvider: Sendable {
  func detectSpeech(samples: [Float], totalDuration: Double) async throws -> [AudioTimeRange]
}

/// Default VAD provider backed by SortformerVADSegmenter via SpeechSegmenter.
struct SortformerVADProvider: VADProvider {
  let segmenter: SpeechSegmenter

  init(segmenter: SpeechSegmenter = SpeechSegmenter()) {
    self.segmenter = segmenter
  }

  func detectSpeech(samples: [Float], totalDuration: Double) async throws -> [AudioTimeRange] {
    try await segmenter.segmentSpeech(audioSamples: samples, totalDuration: totalDuration)
  }
}

/// Lightweight VAD provider backed by SileroVAD. No speaker diarization.
struct SileroVADProvider: VADProvider {
  let model: ModelVariant

  init(model: ModelVariant = .sileroVAD) {
    self.model = model
  }

  func detectSpeech(samples: [Float], totalDuration: Double) async throws -> [AudioTimeRange] {
    let segmenter = try await ModelCacheManager.shared.getSileroVADSegmenter(model: model)
    return try segmenter.detectSpeechSegments(audioSamples: samples)
  }
}
