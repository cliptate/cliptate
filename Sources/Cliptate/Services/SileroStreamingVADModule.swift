import CliptateCore
import Foundation
import MLX
import MLXAudioVAD
import os.log

/// Streaming voice activity detection backed by SileroVAD.
///
/// Feeds 512-sample chunks at 16 kHz and returns speech probability per chunk.
/// Conforms to `StreamingVADProvider` so it can be injected into the streaming
/// transcription pipeline as an alternative to `SortformerStreamingVADModule`.
actor SileroStreamingVADModule {
  struct Configuration: Sendable {
    let sampleRate: Int
    let threshold: Float
  }

  private let logger: Logger
  private let configuration: Configuration

  private var model: SileroVAD?
  private var streamingState: SileroVADStreamingState?
  private var loadedVariant: ModelVariant?
  private var audioBuffer = SileroStreamingAudioBuffer()

  /// Silero requires exactly 512 samples per chunk at 16 kHz (or 256 at 8 kHz).
  private var chunkSize: Int { configuration.sampleRate == 16_000 ? 512 : 256 }

  init(
    logger: Logger,
    configuration: Configuration = Configuration(sampleRate: 16_000, threshold: 0.5)
  ) {
    self.logger = logger
    self.configuration = configuration
  }

  func start(model variant: ModelVariant) async throws {
    guard variant.isSileroVADModel else {
      throw NSError(
        domain: "SileroStreamingVADModule",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: "\(variant.displayName) is not a Silero VAD model."
        ]
      )
    }

    if loadedVariant != variant || model == nil {
      logger.notice("🎤 Loading Silero VAD model: \(variant.displayName)")
      model = try await SileroVAD.fromPretrained(variant.huggingFaceRepoId)
      loadedVariant = variant
    }

    ModelArtifactStatusNotifier.postChange(for: variant)
    streamingState = try model?.initialState(sampleRate: configuration.sampleRate)
    audioBuffer = SileroStreamingAudioBuffer()
  }

  func stop() {
    streamingState = nil
    audioBuffer = SileroStreamingAudioBuffer()
  }

  func feed(samples: [Float]) async throws -> SortformerSpeechActivity {
    guard !samples.isEmpty else {
      return SortformerSpeechActivity(speechSampleRanges: [])
    }

    guard let model, var state = streamingState else {
      throw NSError(
        domain: "SileroStreamingVADModule",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Silero streaming VAD has not been started."]
      )
    }

    // Retain incomplete frames across microphone feeds rather than discarding
    // the tail of every 0.5s chunk (8000 is not a multiple of 512).
    let samples = audioBuffer.append(samples, frameSize: chunkSize)
    // Process input in fixed-size chunks (512 samples at 16 kHz)
    var speechRanges: [Range<Int>] = []
    var offset = 0

    while offset + chunkSize <= samples.count {
      let chunk = Array(samples[offset..<(offset + chunkSize)])
      let chunkArray = MLXArray(chunk)

      nonisolated(unsafe) let capturedModel = model
      let (prob, newState) = try capturedModel.feed(
        chunk: chunkArray,
        state: state,
        sampleRate: configuration.sampleRate
      )
      state = newState

      let probability = prob.item(Float.self)
      if probability >= configuration.threshold {
        speechRanges.append(offset..<(offset + chunkSize))
      }
      offset += chunkSize
    }

    streamingState = state
    return SortformerSpeechActivity(samples: samples, speechSampleRanges: mergedRanges(speechRanges))
  }

  private func mergedRanges(_ ranges: [Range<Int>]) -> [Range<Int>] {
    guard !ranges.isEmpty else { return [] }

    var merged: [Range<Int>] = []
    for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
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

extension SileroStreamingVADModule: StreamingVADProvider {}

struct SileroStreamingAudioBuffer: Sendable {
  private(set) var pendingSamples: [Float] = []

  mutating func append(_ samples: [Float], frameSize: Int) -> [Float] {
    pendingSamples.append(contentsOf: samples)
    let count = pendingSamples.count / frameSize * frameSize
    let completeFrames = Array(pendingSamples.prefix(count))
    pendingSamples.removeFirst(count)
    return completeFrames
  }
}
