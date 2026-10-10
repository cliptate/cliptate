import Foundation
import Testing
@testable import Cliptate

@Suite("TranscriptionPostProcessor")
struct TranscriptionPostProcessorTests {

  @Test func sileroSelectionSkipsSpeakerAnnotation() async {
    let segments = [
      Segment(startTime: 0.0, endTime: 1.0, text: "hello world"),
      Segment(startTime: 1.0, endTime: 2.0, text: "foo bar"),
    ]
    let asrResult = TranscriptionResult(
      segments: segments,
      totalDuration: 2.0,
      processingTime: 1.0,
      modelUsed: "test"
    )

    enum TestError: Error { case shouldNotRun }
    let propagation = PlainASRSpeakerPropagation(
      vadModel: .sileroVAD,
      loadAudioSamples: { _ in throw TestError.shouldNotRun },
      detectSpeakerRanges: { _, _ in throw TestError.shouldNotRun }
    )
    let processor = TranscriptionPostProcessor(speakerPropagation: propagation)

    let result = await processor.postProcess(
      asrResult: asrResult,
      sourceURL: URL(fileURLWithPath: "/tmp/test.wav"),
      dictionaryEntries: []
    )

    #expect(result.segments == segments)
    #expect(result.speakerAnnotationApplied == false)
  }

  @Test func happyPath_appliesBiasAndSpeakers() async {
    let segments = [
      Segment(startTime: 0.0, endTime: 1.0, text: "hello world"),
      Segment(startTime: 1.0, endTime: 2.0, text: "foo bar"),
    ]
    let asrResult = TranscriptionResult(
      segments: segments,
      totalDuration: 2.0,
      processingTime: 1.0,
      modelUsed: "test"
    )

    let speakerRanges: [AudioTimeRange] = [
      AudioTimeRange(startTime: 0.0, endTime: 1.2, speakerId: 0),
      AudioTimeRange(startTime: 1.2, endTime: 2.5, speakerId: 1),
    ]

    let propagation = PlainASRSpeakerPropagation(
      vadModel: .sortformerOffline,
      loadAudioSamples: { _ in [Float](repeating: 0, count: 16000) },
      detectSpeakerRanges: { _, _ in speakerRanges }
    )
    let processor = TranscriptionPostProcessor(speakerPropagation: propagation)

    let result = await processor.postProcess(
      asrResult: asrResult,
      sourceURL: URL(fileURLWithPath: "/tmp/test.wav"),
      dictionaryEntries: []
    )

    #expect(result.segments.count == 2)
    #expect(result.segments[0].speakerId == 0)
    #expect(result.segments[1].speakerId == 1)
    #expect(result.speakerAnnotationApplied == true)
    #expect(result.audioDuration == 2.0)
  }

  @Test func samplesBackedPostProcess_appliesSpeakers() async {
    let segments = [
      Segment(startTime: 0.0, endTime: 1.0, text: "hello world"),
      Segment(startTime: 1.0, endTime: 2.0, text: "foo bar"),
    ]
    let asrResult = TranscriptionResult(
      segments: segments,
      totalDuration: 2.0,
      processingTime: 1.0,
      modelUsed: "test"
    )

    let speakerRanges: [AudioTimeRange] = [
      AudioTimeRange(startTime: 0.0, endTime: 1.2, speakerId: 0),
      AudioTimeRange(startTime: 1.2, endTime: 2.5, speakerId: 1),
    ]

    let propagation = PlainASRSpeakerPropagation(
      vadModel: .sortformerOffline,
      loadAudioSamples: { _ in [] },
      detectSpeakerRanges: { _, _ in speakerRanges }
    )
    let processor = TranscriptionPostProcessor(speakerPropagation: propagation)

    let result = await processor.postProcess(
      asrResult: asrResult,
      audioSamples: [Float](repeating: 0, count: 32_000),
      dictionaryEntries: []
    )

    #expect(result.segments.count == 2)
    #expect(result.segments[0].speakerId == 0)
    #expect(result.segments[1].speakerId == 1)
    #expect(result.speakerAnnotationApplied == true)
  }

  @Test func speakerAnnotationFails_gracefulFallback() async {
    let segments = [
      Segment(startTime: 0.0, endTime: 1.0, text: "hello"),
    ]
    let asrResult = TranscriptionResult(
      segments: segments,
      totalDuration: 1.0,
      processingTime: 0.5,
      modelUsed: "test"
    )

    let propagation = PlainASRSpeakerPropagation(
      vadModel: .sortformerOffline,
      loadAudioSamples: { _ in throw NSError(domain: "test", code: 1) },
      detectSpeakerRanges: { _, _ in [] }
    )
    let processor = TranscriptionPostProcessor(speakerPropagation: propagation)

    let result = await processor.postProcess(
      asrResult: asrResult,
      sourceURL: URL(fileURLWithPath: "/tmp/test.wav"),
      dictionaryEntries: []
    )

    #expect(result.segments.count == 1)
    #expect(result.segments[0].speakerId == nil)
    #expect(result.speakerAnnotationApplied == false)
  }

  @Test func emptyASRResult_handlesGracefully() async {
    let asrResult = TranscriptionResult(
      segments: [],
      totalDuration: 0.0,
      processingTime: 0.0,
      modelUsed: "test"
    )

    let propagation = PlainASRSpeakerPropagation(
      vadModel: .sortformerOffline,
      loadAudioSamples: { _ in [] },
      detectSpeakerRanges: { _, _ in [] }
    )
    let processor = TranscriptionPostProcessor(speakerPropagation: propagation)

    let result = await processor.postProcess(
      asrResult: asrResult,
      sourceURL: URL(fileURLWithPath: "/tmp/test.wav"),
      dictionaryEntries: []
    )

    #expect(result.segments.isEmpty)
    #expect(result.speakerAnnotationApplied == false)
  }
}
