import Foundation
import Testing

@testable import Cliptate

@Suite("Plain ASR path preserves Sortformer/VAD speaker IDs")
struct PlainASRSpeakerPropagationTests {
  @Test("returns segments unchanged when selected VAD model does not support diarization")
  func annotateSkipsWhenSelectedVADDoesNotSupportDiarization() async throws {
    enum TestError: Error { case shouldNotRun }

    let original = [
      Segment(startTime: 0.0, endTime: 1.0, text: "hello"),
      Segment(startTime: 1.0, endTime: 2.0, text: "world")
    ]

    let propagation = PlainASRSpeakerPropagation(
      vadModel: .sileroVAD,
      loadAudioSamples: { _ in throw TestError.shouldNotRun },
      detectSpeakerRanges: { _, _ in throw TestError.shouldNotRun }
    )

    let annotated = try await propagation.annotate(
      original,
      for: URL(fileURLWithPath: "/fake/path.wav")
    )

    #expect(annotated == original)
  }

  @Test("annotates plain ASR segments with Sortformer speaker ranges")
  func annotateUsesDetectedSpeakerRanges() async throws {
    let propagation = PlainASRSpeakerPropagation(
      vadModel: .sortformerOffline,
      loadAudioSamples: { _ in [Float](repeating: 0.1, count: 32_000) },
      detectSpeakerRanges: { _, _ in
        [
          AudioTimeRange(startTime: 0.0, endTime: 1.2, speakerId: 0),
          AudioTimeRange(startTime: 1.2, endTime: 2.5, speakerId: 1)
        ]
      }
    )

    let annotatedSegments = try await propagation.annotate(
      [
        Segment(startTime: 0.5, endTime: 1.0, text: "hello"),
        Segment(startTime: 1.5, endTime: 2.0, text: "world")
      ],
      for: URL(fileURLWithPath: "/fake/path.wav")
    )

    #expect(annotatedSegments.count == 2)
    #expect(annotatedSegments[0].speakerId == 0)
    #expect(annotatedSegments[1].speakerId == 1)
  }

  @Test("returns existing speaker IDs unchanged without loading audio again")
  func annotateSkipsWhenSpeakerIdsAlreadyExist() async throws {
    enum TestError: Error { case shouldNotRun }

    let propagation = PlainASRSpeakerPropagation(
      vadModel: .sortformerOffline,
      loadAudioSamples: { _ in throw TestError.shouldNotRun },
      detectSpeakerRanges: { _, _ in throw TestError.shouldNotRun }
    )

    let existing = [
      Segment(startTime: 0.0, endTime: 1.0, text: "hello", speakerId: 4)
    ]

    let annotated = try await propagation.annotate(
      existing,
      for: URL(fileURLWithPath: "/fake/path.wav")
    )

    #expect(annotated == existing)
  }

  @Test("propagates speaker detection failures")
  func annotateThrowsWhenSpeakerDetectionFails() async {
    enum TestError: Error { case detectionFailed }

    let propagation = PlainASRSpeakerPropagation(
      vadModel: .sortformerOffline,
      loadAudioSamples: { _ in [Float](repeating: 0.1, count: 16_000) },
      detectSpeakerRanges: { _, _ in throw TestError.detectionFailed }
    )

    await #expect(throws: TestError.self) {
      _ = try await propagation.annotate(
        [Segment(startTime: 0.0, endTime: 1.0, text: "hello")],
        for: URL(fileURLWithPath: "/fake/path.wav")
      )
    }
  }

  @Test("propagates audio loading failures")
  func annotateThrowsWhenAudioLoadingFails() async {
    enum TestError: Error { case loadFailed }

    let propagation = PlainASRSpeakerPropagation(
      vadModel: .sortformerOffline,
      loadAudioSamples: { _ in throw TestError.loadFailed },
      detectSpeakerRanges: { _, _ in [] }
    )

    await #expect(throws: TestError.self) {
      _ = try await propagation.annotate(
        [Segment(startTime: 0.0, endTime: 1.0, text: "hello")],
        for: URL(fileURLWithPath: "/fake/path.wav")
      )
    }
  }
}
