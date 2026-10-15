import CliptateCore
import Foundation

struct PlainASRSpeakerPropagation {
  let vadModel: ModelVariant
  let loadAudioSamples: @Sendable (URL) async throws -> [Float]
  let detectSpeakerRanges: @Sendable ([Float], ModelVariant) async throws -> [AudioTimeRange]

  init(
    vadModel: ModelVariant,
    loadAudioSamples: @escaping @Sendable (URL) async throws -> [Float] = { url in
      try await AudioProcessor.loadAndConvertAudio(url: url)
    },
    detectSpeakerRanges: @escaping @Sendable ([Float], ModelVariant) async throws -> [AudioTimeRange] = {
      samples, vadModel in
      let segmenter = try await ModelCacheManager.shared.getVADSegmenter(model: vadModel)
      return try await segmenter.detectSpeechSegmentsWithSpeakers(audioSamples: samples)
    }
  ) {
    self.vadModel = vadModel
    self.loadAudioSamples = loadAudioSamples
    self.detectSpeakerRanges = detectSpeakerRanges
  }

  /// Annotates plain ASR segments with Sortformer/VAD speaker ranges when needed.
  /// Segments that already carry speaker IDs are returned unchanged.
  func annotate(_ segments: [Segment], for sourceURL: URL) async throws -> [Segment] {
    guard vadModel.isSortformerVADModel else { return segments }
    guard segments.allSatisfy({ $0.speakerId == nil }) else { return segments }
    let audioSamples = try await loadAudioSamples(sourceURL)
    return try await annotate(segments, samples: audioSamples)
  }

  func annotate(_ segments: [Segment], samples audioSamples: [Float]) async throws -> [Segment] {
    guard vadModel.isSortformerVADModel else { return segments }
    guard segments.allSatisfy({ $0.speakerId == nil }) else { return segments }
    let speakerRanges = try await detectSpeakerRanges(audioSamples, vadModel)
    return SegmentSpeakerAnnotator.annotate(segments, withSpeakers: speakerRanges)
  }
}
