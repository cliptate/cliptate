import Foundation
import MLX
import MLXAudioVAD
import os.log

struct SortformerSpeechActivity: Sendable {
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
  private var processedSamples: Int = 0

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
    processedSamples = 0
  }

  func stop() {
    streamingState = nil
    processedSamples = 0
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

    let chunkStartTime = Double(processedSamples) / Double(configuration.sampleRate)
    let chunkDuration = Double(samples.count) / Double(configuration.sampleRate)
    let chunkEndTime = chunkStartTime + chunkDuration

    nonisolated(unsafe) let capturedModel = model
    let (output, newState) = try await capturedModel.feed(
      chunk: MLXArray(samples),
      state: state,
      sampleRate: configuration.sampleRate,
      threshold: configuration.threshold
    )

    streamingState = newState
    processedSamples += samples.count

    let ranges = mergedRanges(
      output.segments.compactMap { segment in
        let startTime = max(Double(segment.start), chunkStartTime)
        let endTime = min(Double(segment.end), chunkEndTime)
        guard endTime > startTime else { return nil }

        let lowerBound = max(
          0,
          min(
            samples.count,
            Int(((startTime - chunkStartTime) * Double(configuration.sampleRate)).rounded(.down))
          )
        )
        let upperBound = max(
          lowerBound,
          min(
            samples.count,
            Int(((endTime - chunkStartTime) * Double(configuration.sampleRate)).rounded(.up))
          )
        )
        guard lowerBound < upperBound else { return nil }
        return lowerBound..<upperBound
      }
    )

    return SortformerSpeechActivity(speechSampleRanges: ranges)
  }

  private func mergedRanges(_ ranges: [Range<Int>]) -> [Range<Int>] {
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
