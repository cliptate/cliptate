import Foundation
import MLXAudioVAD
import Testing

@testable import Cliptate

@Suite("SileroVADSegmenter")
struct SileroVADSegmenterTests {

  @Test("default batch tuning uses less aggressive silence splitting")
  func defaultBatchTuningUsesLessAggressiveSilenceSplitting() {
    let tuning = SileroVADSegmentationOptions.defaultBatch

    #expect(tuning.threshold == 0.5)
    #expect(tuning.minSpeechDurationMs == 250)
    #expect(tuning.minSilenceDurationMs == 350)
    #expect(tuning.speechPadMs == 80)
  }

  @Test("detectSpeechSegments passes configured tuning to generator")
  func detectSpeechSegmentsPassesConfiguredTuningToGenerator() throws {
    let expectedTuning = SileroVADSegmentationOptions(
      threshold: 0.62,
      minSpeechDurationMs: 250,
      minSilenceDurationMs: 480,
      speechPadMs: 90
    )
    nonisolated(unsafe) var capturedTuning: SileroVADSegmentationOptions?

    let segmenter = SileroVADSegmenter(
      generator: { _, _, tuning in
        capturedTuning = tuning
        return [SileroVADTimestamp(start: 1_600, end: 8_000)]
      },
      options: expectedTuning
    )

    let ranges = try segmenter.detectSpeechSegments(
      audioSamples: Array(repeating: Float(0.1), count: 16_000)
    )

    #expect(capturedTuning == expectedTuning)
    #expect(ranges == [AudioTimeRange(startTime: 0.1, endTime: 0.5, speakerId: nil)])
  }
}
