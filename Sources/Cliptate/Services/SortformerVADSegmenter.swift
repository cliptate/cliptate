import CliptateCore
import Foundation
import MLX
import MLXAudioVAD
import os.log

// MARK: - SortformerVADSegmenter

/// Wraps SortformerModel for VAD-based speech segmentation.
///
/// **Post-processing** (offline batch): call `detectSpeechSegments(audioSamples:)`
/// which uses SortformerModel.generate() on the full audio at once.
///
/// **Real-time streaming**: use `SortformerStreamingVADModule` which wraps
/// SortformerModel.feed() for chunk-by-chunk processing.
public struct SortformerVADSegmenter: Sendable {

  /// Closure type matching SortformerModel.generate() semantics.
  /// Takes ownership of the audio tensor along with its sample rate.
  public typealias Generator = @Sendable (sending MLXArray, Int) async throws -> DiarizationOutput

  public let generator: Generator
  public let sampleRate: Int
  public let threshold: Float
  public let minDuration: Float
  public let mergeGap: Float

  public init(
    generator: @escaping Generator,
    sampleRate: Int = 16_000,
    threshold: Float = 0.5,
    minDuration: Float = 0.2,
    mergeGap: Float = 0.3
  ) {
    self.generator = generator
    self.sampleRate = sampleRate
    self.threshold = threshold
    self.minDuration = minDuration
    self.mergeGap = mergeGap
  }

  // MARK: - Offline batch segmentation

  /// Detect speech segments in the full audio (post-processing / offline use).
  public func detectSpeechSegments(
    audioSamples: [Float],
    sampleRate overrideSampleRate: Int? = nil
  ) async throws -> [AudioTimeRange] {
    guard !audioSamples.isEmpty else { return [] }
    let sr = overrideSampleRate ?? sampleRate
    let audio = MLXArray(audioSamples)
    let output = try await generator(audio, sr)
    let totalDuration = Double(audioSamples.count) / Double(sr)
    return Self.segments(from: output, totalDuration: totalDuration)
  }

  /// Detect speech segments preserving per-speaker identity.
  /// Use this when you need to annotate transcription results with speaker IDs.
  public func detectSpeechSegmentsWithSpeakers(
    audioSamples: [Float],
    sampleRate overrideSampleRate: Int? = nil
  ) async throws -> [AudioTimeRange] {
    guard !audioSamples.isEmpty else { return [] }
    let sr = overrideSampleRate ?? sampleRate
    let audio = MLXArray(audioSamples)
    let output = try await generator(audio, sr)
    let totalDuration = Double(audioSamples.count) / Double(sr)
    return Self.segmentsWithSpeakers(from: output, totalDuration: totalDuration)
  }

  /// Run the model once and return both merged VAD ranges (for chunked transcription)
  /// and speaker-annotated ranges (for diarization annotation).
  /// Prefer this over calling `detectSpeechSegments` and `detectSpeechSegmentsWithSpeakers`
  /// separately when you need both — it invokes the underlying model only once.
  public func detectAllSpeechSegments(
    audioSamples: [Float],
    sampleRate overrideSampleRate: Int? = nil
  ) async throws -> (merged: [AudioTimeRange], withSpeakers: [AudioTimeRange]) {
    guard !audioSamples.isEmpty else { return ([], []) }
    let sr = overrideSampleRate ?? sampleRate
    let audio = MLXArray(audioSamples)
    let output = try await generator(audio, sr)
    let totalDuration = Double(audioSamples.count) / Double(sr)
    return (
      merged: Self.segments(from: output, totalDuration: totalDuration),
      withSpeakers: Self.segmentsWithSpeakers(from: output, totalDuration: totalDuration)
    )
  }

  // MARK: - Pure conversion (testable without model)

  /// Convert a DiarizationOutput to merged AudioTimeRange segments.
  /// Speaker identity is ignored — any speech activity from any speaker
  /// is treated as "speech" for VAD purposes.
  public static func segments(
    from output: DiarizationOutput,
    totalDuration: Double
  ) -> [AudioTimeRange] {
    guard !output.segments.isEmpty else { return [] }

    // Sort by start time, clamp to totalDuration
    let sorted = output.segments
      .map { AudioTimeRange(startTime: Double($0.start), endTime: min(Double($0.end), totalDuration)) }
      .filter { $0.duration > 0 }
      .sorted { $0.startTime < $1.startTime }

    guard !sorted.isEmpty else { return [] }

    // Merge overlapping / adjacent ranges
    var merged: [AudioTimeRange] = []
    for range in sorted {
      guard let last = merged.last else {
        merged.append(range)
        continue
      }
      if range.startTime <= last.endTime {
        // Overlapping: extend
        merged[merged.count - 1] = AudioTimeRange(
          startTime: last.startTime,
          endTime: max(last.endTime, range.endTime)
        )
      } else {
        merged.append(range)
      }
    }

    return merged
  }

  // MARK: - Speaker-preserving conversion

  /// Convert DiarizationOutput to per-speaker AudioTimeRange segments.
  /// Unlike `segments(from:)`, this preserves speaker identity — segments from
  /// different speakers are never merged. Adjacent/overlapping segments from the
  /// *same* speaker are merged within that speaker's track.
  public static func segmentsWithSpeakers(
    from output: DiarizationOutput,
    totalDuration: Double
  ) -> [AudioTimeRange] {
    guard !output.segments.isEmpty else { return [] }

    // Group by speaker
    var bySpeaker: [Int: [DiarizationSegment]] = [:]
    for seg in output.segments {
      bySpeaker[seg.speaker, default: []].append(seg)
    }

    var result: [AudioTimeRange] = []
    for (speakerId, segs) in bySpeaker {
      let sorted = segs
        .map { AudioTimeRange(
          startTime: Double($0.start),
          endTime: min(Double($0.end), totalDuration),
          speakerId: speakerId
        )}
        .filter { $0.duration > 0 }
        .sorted { $0.startTime < $1.startTime }

      // Merge overlapping within same speaker
      var merged: [AudioTimeRange] = []
      for range in sorted {
        if let last = merged.last, range.startTime <= last.endTime {
          merged[merged.count - 1] = AudioTimeRange(
            startTime: last.startTime,
            endTime: max(last.endTime, range.endTime),
            speakerId: speakerId
          )
        } else {
          merged.append(range)
        }
      }
      result.append(contentsOf: merged)
    }

    return result.sorted { $0.startTime < $1.startTime }
  }

  // MARK: - Factory

  /// A no-op segmenter used before the model is loaded (returns empty array).
  /// Replaced after warmup by makeWithModel().
  public static func makePassthrough() -> SortformerVADSegmenter {
    SortformerVADSegmenter(generator: { _, _ in DiarizationOutput(segments: []) })
  }

  /// Load a SortformerModel from HuggingFace and return a configured segmenter.
  public static func makeWithModel(
    variant: ModelVariant = .sortformerOffline,
    sampleRate: Int = 16_000,
    threshold: Float = 0.5,
    minDuration: Float = 0.2,
    mergeGap: Float = 0.3,
    logger: Logger = Logger(subsystem: "com.cliptate.app", category: "SortformerVAD")
  ) async throws -> SortformerVADSegmenter {
    logger.notice("🎤 Loading Sortformer VAD model: \(variant.rawValue)")
    let model = try await SortformerModel.fromPretrained(variant.huggingFaceRepoId)
    logger.notice("✅ Sortformer VAD model loaded")
    nonisolated(unsafe) let capturedModel = model
    let capturedThreshold = threshold
    let capturedMinDuration = minDuration
    let capturedMergeGap = mergeGap
    return SortformerVADSegmenter(
      generator: { audio, sr in
        try await capturedModel.generate(
          audio: audio,
          sampleRate: sr,
          threshold: capturedThreshold,
          minDuration: capturedMinDuration,
          mergeGap: capturedMergeGap
        )
      },
      sampleRate: sampleRate,
      threshold: threshold,
      minDuration: minDuration,
      mergeGap: mergeGap
    )
  }
}
