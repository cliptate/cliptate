import Foundation
import MLXAudioVAD
import Testing

@testable import Cliptate

private let liveMLXInferenceEnabled =
  ProcessInfo.processInfo.environment["CLIPTATE_ENABLE_LIVE_MLX_TESTS"] == "1"

// MARK: - AudioTimeRange Tests

@Suite("AudioTimeRange")
struct AudioTimeRangeTests {

  @Test("speakerId defaults to nil when not provided")
  func speakerIdDefaultsToNil() {
    let range = AudioTimeRange(startTime: 0.0, endTime: 1.0)
    #expect(range.speakerId == nil)
  }

  @Test("speakerId is preserved when provided")
  func speakerIdIsPreserved() {
    let range = AudioTimeRange(startTime: 1.0, endTime: 3.0, speakerId: 2)
    #expect(range.speakerId == 2)
  }

  @Test("two ranges with same times but different speakerIds are not equal")
  func rangesWithDifferentSpeakerIdsAreNotEqual() {
    let a = AudioTimeRange(startTime: 0.0, endTime: 2.0, speakerId: 0)
    let b = AudioTimeRange(startTime: 0.0, endTime: 2.0, speakerId: 1)
    #expect(a != b)
  }
}

// MARK: - SortformerVADSegmenter Tests

@Suite("SortformerVADSegmenter")
struct SortformerVADSegmenterTests {

  // MARK: - Pure conversion: segments(from:totalDuration:)

  @Test("empty diarization output produces no ranges")
  func emptyOutputProducesNoRanges() {
    let output = DiarizationOutput(segments: [])
    let ranges = SortformerVADSegmenter.segments(from: output, totalDuration: 10.0)
    #expect(ranges.isEmpty)
  }

  @Test("single speech segment is converted to AudioTimeRange")
  func singleSegmentIsConverted() {
    let output = DiarizationOutput(segments: [
      DiarizationSegment(start: 1.0, end: 3.0, speaker: 0)
    ])
    let ranges = SortformerVADSegmenter.segments(from: output, totalDuration: 10.0)
    #expect(ranges.count == 1)
    #expect(ranges[0].startTime == 1.0)
    #expect(ranges[0].endTime == 3.0)
  }

  @Test("segments from multiple speakers are merged into speech ranges")
  func multiSpeakerSegmentsMergedToSpeechRanges() {
    // Two speakers talking at the same time should produce merged ranges
    let output = DiarizationOutput(segments: [
      DiarizationSegment(start: 0.0, end: 2.0, speaker: 0),
      DiarizationSegment(start: 1.5, end: 4.0, speaker: 1),
    ])
    let ranges = SortformerVADSegmenter.segments(from: output, totalDuration: 10.0)
    #expect(ranges.count == 1)
    #expect(ranges[0].startTime == 0.0)
    #expect(abs(ranges[0].endTime - 4.0) < 0.01)
  }

  @Test("non-overlapping segments from different speakers produce separate ranges")
  func separateSpeakerSegmentsProduceSeparateRanges() {
    let output = DiarizationOutput(segments: [
      DiarizationSegment(start: 0.0, end: 2.0, speaker: 0),
      DiarizationSegment(start: 5.0, end: 7.0, speaker: 1),
    ])
    let ranges = SortformerVADSegmenter.segments(from: output, totalDuration: 10.0)
    #expect(ranges.count == 2)
    #expect(ranges[0].startTime == 0.0)
    #expect(ranges[1].startTime == 5.0)
  }

  @Test("segments are clamped to totalDuration")
  func segmentsClampedToTotalDuration() {
    let output = DiarizationOutput(segments: [
      DiarizationSegment(start: 8.0, end: 15.0, speaker: 0)  // end exceeds duration
    ])
    let ranges = SortformerVADSegmenter.segments(from: output, totalDuration: 10.0)
    #expect(ranges.count == 1)
    #expect(ranges[0].endTime <= 10.0)
  }

  @Test(
    "detectSpeechSegments calls generator with correct MLXArray",
    .disabled(if: !liveMLXInferenceEnabled, "Requires opt-in live MLX Metal runtime.")
  )
  func detectSpeechSegmentsCallsGenerator() async throws {
    let expectedSampleCount = 16_000 * 3  // 3 seconds at 16kHz
    nonisolated(unsafe) var capturedSampleCount: Int = 0

    let segmenter = SortformerVADSegmenter(
      generator: { audio, _ in
        capturedSampleCount = audio.dim(0)
        return DiarizationOutput(segments: [
          DiarizationSegment(start: 0.5, end: 2.5, speaker: 0)
        ])
      }
    )

    let samples = [Float](repeating: 0.1, count: expectedSampleCount)
    let ranges = try await segmenter.detectSpeechSegments(audioSamples: samples)
    #expect(capturedSampleCount == expectedSampleCount)
    #expect(ranges.count == 1)
  }

  @Test(
    "detectSpeechSegments with no speech returns empty array",
    .disabled(if: !liveMLXInferenceEnabled, "Requires opt-in live MLX Metal runtime.")
  )
  func noSpeechReturnsEmpty() async throws {
    let segmenter = SortformerVADSegmenter(
      generator: { _, _ in DiarizationOutput(segments: []) }
    )
    let samples = [Float](repeating: 0.0, count: 16_000)
    let ranges = try await segmenter.detectSpeechSegments(audioSamples: samples)
    #expect(ranges.isEmpty)
  }

  // MARK: - segmentsWithSpeakers Tests

  @Test("single speaker segment carries speakerId")
  func singleSpeakerSegmentCarriesSpeakerId() {
    let output = DiarizationOutput(segments: [
      DiarizationSegment(start: 0.0, end: 2.0, speaker: 3)
    ])
    let ranges = SortformerVADSegmenter.segmentsWithSpeakers(from: output, totalDuration: 10.0)
    #expect(ranges.count == 1)
    #expect(ranges[0].speakerId == 3)
    #expect(ranges[0].startTime == 0.0)
    #expect(ranges[0].endTime == 2.0)
  }

  @Test("segments from different speakers are kept separate in segmentsWithSpeakers")
  func differentSpeakersAreKeptSeparate() {
    let output = DiarizationOutput(segments: [
      DiarizationSegment(start: 0.0, end: 2.0, speaker: 0),
      DiarizationSegment(start: 3.0, end: 5.0, speaker: 1),
    ])
    let ranges = SortformerVADSegmenter.segmentsWithSpeakers(from: output, totalDuration: 10.0)
    #expect(ranges.count == 2)
    #expect(ranges[0].speakerId == 0)
    #expect(ranges[1].speakerId == 1)
  }

  @Test("overlapping segments from same speaker are merged and speakerId preserved")
  func sameSpeakerOverlappingSegmentsMerged() {
    let output = DiarizationOutput(segments: [
      DiarizationSegment(start: 0.0, end: 2.0, speaker: 1),
      DiarizationSegment(start: 1.5, end: 4.0, speaker: 1),
    ])
    let ranges = SortformerVADSegmenter.segmentsWithSpeakers(from: output, totalDuration: 10.0)
    #expect(ranges.count == 1)
    #expect(ranges[0].speakerId == 1)
    #expect(ranges[0].startTime == 0.0)
    #expect(abs(ranges[0].endTime - 4.0) < 0.01)
  }

  @Test("interleaved speakers produce alternating ranges with correct speakerIds")
  func interleavedSpeakersProduceCorrectRanges() {
    let output = DiarizationOutput(segments: [
      DiarizationSegment(start: 0.0, end: 2.0, speaker: 0),
      DiarizationSegment(start: 2.5, end: 4.0, speaker: 1),
      DiarizationSegment(start: 5.0, end: 6.0, speaker: 0),
    ])
    let ranges = SortformerVADSegmenter.segmentsWithSpeakers(
      from: output, totalDuration: 10.0
    ).sorted { $0.startTime < $1.startTime }
    #expect(ranges.count == 3)
    #expect(ranges[0].speakerId == 0)
    #expect(ranges[1].speakerId == 1)
    #expect(ranges[2].speakerId == 0)
  }

  // MARK: - detectAllSpeechSegments logic (via static helpers, no MLX runtime required)

  @Test("detectAllSpeechSegments returns merged ranges (no speaker) and speaker-annotated ranges")
  func detectAllSpeechSegmentsReturnsBothStyles() {
    // Simulate the same DiarizationOutput that the generator would produce.
    let output = DiarizationOutput(segments: [
      DiarizationSegment(start: 0.0, end: 2.0, speaker: 0),
      DiarizationSegment(start: 3.0, end: 5.0, speaker: 1),
    ])
    let duration = 10.0

    // This mirrors exactly what detectAllSpeechSegments does internally:
    let merged = SortformerVADSegmenter.segments(from: output, totalDuration: duration)
    let withSpeakers = SortformerVADSegmenter.segmentsWithSpeakers(from: output, totalDuration: duration)

    // merged: speaker info is dropped
    #expect(merged.count == 2)
    #expect(merged.allSatisfy { $0.speakerId == nil })

    // withSpeakers: speaker identity is preserved
    #expect(withSpeakers.count == 2)
    #expect(withSpeakers.contains { $0.speakerId == 0 })
    #expect(withSpeakers.contains { $0.speakerId == 1 })
  }

  @Test("detectAllSpeechSegments: merged and withSpeakers share the same time boundaries")
  func detectAllMergedAndSpeakerRangesShareTimes() {
    let output = DiarizationOutput(segments: [
      DiarizationSegment(start: 1.0, end: 3.0, speaker: 0),
      DiarizationSegment(start: 5.0, end: 7.0, speaker: 1),
    ])
    let duration = 10.0
    let merged = SortformerVADSegmenter.segments(from: output, totalDuration: duration)
    let withSpeakers = SortformerVADSegmenter.segmentsWithSpeakers(from: output, totalDuration: duration)

    let mergedTimes = merged.map { ($0.startTime, $0.endTime) }
    let speakerTimes = withSpeakers.map { ($0.startTime, $0.endTime) }
    #expect(mergedTimes.count == speakerTimes.count)
    for (m, s) in zip(mergedTimes, speakerTimes) {
      #expect(m.0 == s.0)
      #expect(m.1 == s.1)
    }
  }
  @Test(
    "real audio file produces non-empty speech segments",
    .disabled(if: !liveMLXInferenceEnabled, "Requires opt-in live MLX Metal runtime.")
  )
  func realAudioProducesSpeechSegments() async throws {
    guard let audioURL = Bundle.module.url(forResource: "vad_example", withExtension: "wav") else {
      throw TestError.resourceNotFound("vad_example.wav not found in test bundle")
    }

    let segmenter = try await SortformerVADSegmenter.makeWithModel(variant: .sortformerOffline)

    let audioSamples = try loadWAVSamples(from: audioURL)
    let ranges = try await segmenter.detectSpeechSegments(audioSamples: audioSamples)

    #expect(!ranges.isEmpty, "Expected at least one speech segment in vad_example.wav")
    for range in ranges {
      #expect(range.startTime >= 0.0)
      #expect(range.duration > 0.0)
    }
  }
}

// MARK: - Helpers

private enum TestError: Error {
  case resourceNotFound(String)
}

private func loadWAVSamples(from url: URL) throws -> [Float] {
  let data = try Data(contentsOf: url)
  guard data.count > 44 else { throw NSError(domain: "TestHelper", code: 1) }
  let audioData = data.dropFirst(44)
  let sampleCount = audioData.count / 2
  var samples = [Float](repeating: 0, count: sampleCount)
  audioData.withUnsafeBytes { ptr in
    let int16Ptr = ptr.bindMemory(to: Int16.self)
    for i in 0..<sampleCount {
      samples[i] = Float(int16Ptr[i]) / 32768.0
    }
  }
  return samples
}
