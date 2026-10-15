import CliptateCore
import Foundation
import MLX
import MLXAudioVAD
import os.log

public struct SileroVADSegmentationOptions: Sendable, Equatable {
  public let threshold: Float
  public let minSpeechDurationMs: Int
  public let minSilenceDurationMs: Int
  public let speechPadMs: Int

  public init(
    threshold: Float,
    minSpeechDurationMs: Int,
    minSilenceDurationMs: Int,
    speechPadMs: Int
  ) {
    self.threshold = threshold
    self.minSpeechDurationMs = minSpeechDurationMs
    self.minSilenceDurationMs = minSilenceDurationMs
    self.speechPadMs = speechPadMs
  }

  public static let defaultBatch = SileroVADSegmentationOptions(
    threshold: 0.5,
    minSpeechDurationMs: 250,
    minSilenceDurationMs: 350,
    speechPadMs: 80
  )
}

/// Wraps SileroVAD for VAD-based speech segmentation (no speaker diarization).
///
/// **Offline batch**: call `detectSpeechSegments(audioSamples:)` which uses
/// `SileroVAD.getSpeechTimestamps()` on the full audio at once.
///
/// **Real-time streaming**: use `SileroStreamingVADModule` which wraps
/// `SileroVAD.feed()` for chunk-by-chunk processing.
public struct SileroVADSegmenter: Sendable {

  public typealias TimestampGenerator = @Sendable ([Float], Int, SileroVADSegmentationOptions) throws
    -> [SileroVADTimestamp]

  public let generator: TimestampGenerator
  public let sampleRate: Int
  let options: SileroVADSegmentationOptions

  public init(
    generator: @escaping TimestampGenerator,
    sampleRate: Int = 16_000,
    options: SileroVADSegmentationOptions = .defaultBatch
  ) {
    self.generator = generator
    self.sampleRate = sampleRate
    self.options = options
  }

  // MARK: - Offline batch segmentation

  /// Detect speech segments in the full audio. All segments have `speakerId: nil`.
  public func detectSpeechSegments(
    audioSamples: [Float],
    sampleRate overrideSampleRate: Int? = nil
  ) throws -> [AudioTimeRange] {
    guard !audioSamples.isEmpty else { return [] }
    let sr = overrideSampleRate ?? sampleRate
    let timestamps = try generator(audioSamples, sr, options)
    return Self.segments(from: timestamps, sampleRate: sr)
  }

  // MARK: - Pure conversion (testable without model)

  /// Convert SileroVADTimestamp array to AudioTimeRange segments (speakerId: nil).
  public static func segments(
    from timestamps: [SileroVADTimestamp],
    sampleRate: Int
  ) -> [AudioTimeRange] {
    timestamps.map { ts in
      AudioTimeRange(
        startTime: Double(ts.start) / Double(sampleRate),
        endTime: Double(ts.end) / Double(sampleRate),
        speakerId: nil
      )
    }
  }

  // MARK: - Factory

  /// A no-op segmenter (returns empty array).
  public static func makePassthrough() -> SileroVADSegmenter {
    SileroVADSegmenter(generator: { _, _, _ in [] })
  }

  /// Load a SileroVAD model from HuggingFace and return a configured segmenter.
  public static func makeWithModel(
    variant: ModelVariant = .sileroVAD,
    sampleRate: Int = 16_000,
    logger: Logger = Logger(subsystem: "com.cliptate.app", category: "SileroVAD"),
    options: SileroVADSegmentationOptions = .defaultBatch
  ) async throws -> SileroVADSegmenter {
    logger.notice("🎤 Loading Silero VAD model: \(variant.rawValue)")
    let model = try await SileroVAD.fromPretrained(variant.huggingFaceRepoId)
    logger.notice("✅ Silero VAD model loaded")
    nonisolated(unsafe) let capturedModel = model
    return SileroVADSegmenter(
      generator: { samples, sr, tuning in
        let audio = MLXArray(samples)
        return try capturedModel.getSpeechTimestamps(
          audio,
          sampleRate: sr,
          threshold: tuning.threshold,
          minSpeechDurationMs: tuning.minSpeechDurationMs,
          minSilenceDurationMs: tuning.minSilenceDurationMs,
          speechPadMs: tuning.speechPadMs
        )
      },
      sampleRate: sampleRate,
      options: options
    )
  }
}
