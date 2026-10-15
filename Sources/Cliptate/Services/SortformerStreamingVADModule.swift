import CliptateCore
import Foundation
import MLX
import MLXAudioVAD
import os.log

struct SortformerSpeechActivity: Sendable {
  /// Nil means ranges refer to the input chunk. Fixed-frame VAD may return buffered samples.
  var samples: [Float]? = nil
  let speechSampleRanges: [Range<Int>]
}

actor SortformerStreamingVADModule {
  struct Configuration: Sendable {
    let sampleRate: Int
    let threshold: Float
  }

  private let logger: Logger
  private let configuration: Configuration

  private var model: SortformerModel?
  private var streamingState: StreamingState?
  private var loadedVariant: ModelVariant?

  init(
    logger: Logger,
    configuration: Configuration = Configuration(sampleRate: 16_000, threshold: 0.5)
  ) {
    self.logger = logger
    self.configuration = configuration
  }

  func start(model variant: ModelVariant) async throws {
    guard variant.isSortformerVADModel else {
      throw NSError(
        domain: "SortformerStreamingVADModule",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: "\(variant.displayName) is not a Sortformer VAD model."
        ]
      )
    }

    if loadedVariant != variant || model == nil {
      logger.notice("🎤 Loading Sortformer VAD model: \(variant.displayName)")
      model = try await SortformerModel.fromPretrained(variant.huggingFaceRepoId)
      loadedVariant = variant
    }

    ModelArtifactStatusNotifier.postChange(for: variant)
    streamingState = model?.initStreamingState()
  }

  func stop() {
    streamingState = nil
  }

  func feed(samples: [Float]) async throws -> SortformerSpeechActivity {
    guard !samples.isEmpty else {
      return SortformerSpeechActivity(speechSampleRanges: [])
    }

    guard let model, let state = streamingState else {
      throw NSError(
        domain: "SortformerStreamingVADModule",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Sortformer streaming VAD has not been started."]
      )
    }

    // Upstream offsets segments by encoded frames; 0.5s input chunks may round to
    // 0.56s of frames. Using raw sample time here would drift on every feed.
    let processor = model.config.processorConfig
    let frameDuration = Double(processor.hopLength * model.config.fcEncoderConfig.subsamplingFactor)
      / Double(processor.samplingRate)
    let chunkStartTime = Double(state.framesProcessed) * frameDuration

    nonisolated(unsafe) let capturedModel = model
    let (output, newState) = try await capturedModel.feed(
      chunk: MLXArray(samples),
      state: state,
      sampleRate: configuration.sampleRate,
      threshold: configuration.threshold
    )

    streamingState = newState

    let ranges = Self.speechSampleRanges(
      segmentTimes: output.segments.map { (Double($0.start), Double($0.end)) },
      chunkStartTime: chunkStartTime,
      sampleCount: samples.count,
      sampleRate: configuration.sampleRate
    )

    return SortformerSpeechActivity(speechSampleRanges: ranges)
  }

  nonisolated static func speechSampleRanges(
    segmentTimes: [(start: Double, end: Double)],
    chunkStartTime: Double,
    sampleCount: Int,
    sampleRate: Int
  ) -> [Range<Int>] {
    let chunkEndTime = chunkStartTime + Double(sampleCount) / Double(sampleRate)
    return mergedRanges(
      segmentTimes.compactMap { segment in
        let startTime = max(segment.start, chunkStartTime)
        let endTime = min(segment.end, chunkEndTime)
        guard endTime > startTime else { return nil }

        let lowerBound = max(
          0,
          min(
            sampleCount,
            Int(((startTime - chunkStartTime) * Double(sampleRate)).rounded(.down))
          )
        )
        let upperBound = max(
          lowerBound,
          min(
            sampleCount,
            Int(((endTime - chunkStartTime) * Double(sampleRate)).rounded(.up))
          )
        )
        guard lowerBound < upperBound else { return nil }
        return lowerBound..<upperBound
      }
    )
  }

  private nonisolated static func mergedRanges(_ ranges: [Range<Int>]) -> [Range<Int>] {
    guard !ranges.isEmpty else { return [] }

    let sortedRanges = ranges.sorted { lhs, rhs in
      if lhs.lowerBound == rhs.lowerBound {
        return lhs.upperBound < rhs.upperBound
      }
      return lhs.lowerBound < rhs.lowerBound
    }

    var merged: [Range<Int>] = []
    for range in sortedRanges {
      guard let last = merged.last else {
        merged.append(range)
        continue
      }

      if range.lowerBound <= last.upperBound {
        merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
      } else {
        merged.append(range)
      }
    }

    return merged
  }
}
