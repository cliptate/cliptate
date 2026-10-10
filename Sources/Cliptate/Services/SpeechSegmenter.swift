import Foundation

/// Speech activity segmenter backed by the Sortformer model (post-processing / offline).
///
/// For real-time streaming, use SortformerStreamingVADModule instead.
struct SpeechSegmenter {
  typealias SegmentSpeechClosure = @Sendable ([Float], Double) async throws -> [AudioTimeRange]

  private let segmentSpeechClosure: SegmentSpeechClosure

  init(model: ModelVariant = .sortformerOffline) {
    self.segmentSpeechClosure = { audioSamples, totalDuration in
      try await SpeechSegmenter.defaultSegmentSpeech(
        audioSamples: audioSamples,
        totalDuration: totalDuration,
        model: model
      )
    }
  }

  init(segmentSpeech: @escaping SegmentSpeechClosure) {
    self.segmentSpeechClosure = segmentSpeech
  }

  func segmentSpeech(audioSamples: [Float], totalDuration: Double) async throws -> [AudioTimeRange] {
    return try await segmentSpeechClosure(audioSamples, totalDuration)
  }

  private static func defaultSegmentSpeech(
    audioSamples: [Float],
    totalDuration: Double,
    model: ModelVariant
  ) async throws -> [AudioTimeRange] {
    let segmenter = try await ModelCacheManager.shared.getVADSegmenter(model: model)
    return try await segmenter.detectSpeechSegments(audioSamples: audioSamples)
  }
}
