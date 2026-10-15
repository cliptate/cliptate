import CliptateCore
import Testing

@testable import Cliptate

@Suite("SegmentSpeakerAnnotator")
struct SegmentSpeakerAnnotatorTests {
  @Test("assigns the speaker with the largest overlap")
  func assignsLargestOverlapSpeaker() {
    let segments = [
      Segment(startTime: 0.0, endTime: 1.0, text: "hello"),
      Segment(startTime: 1.0, endTime: 2.0, text: "world")
    ]

    let vadRanges = [
      AudioTimeRange(startTime: 0.0, endTime: 0.8, speakerId: 3),
      AudioTimeRange(startTime: 1.2, endTime: 1.9, speakerId: 7)
    ]

    let annotated = SegmentSpeakerAnnotator.annotate(segments, withSpeakers: vadRanges)

    #expect(annotated[0].speakerId == 3)
    #expect(annotated[1].speakerId == 7)
  }

  @Test("keeps nil speakerId when no VAD speaker overlaps")
  func keepsNilWithoutOverlap() {
    let segments = [Segment(startTime: 4.0, endTime: 5.0, text: "late")]
    let vadRanges = [AudioTimeRange(startTime: 0.0, endTime: 1.0, speakerId: 1)]

    let annotated = SegmentSpeakerAnnotator.annotate(segments, withSpeakers: vadRanges)

    #expect(annotated[0].speakerId == nil)
  }

  @Test("ignores overlapping VAD ranges that do not carry a speakerId")
  func ignoresOverlappingRangeWithoutSpeakerId() {
    let segments = [Segment(startTime: 0.0, endTime: 1.0, text: "hello")]
    let vadRanges = [AudioTimeRange(startTime: 0.0, endTime: 1.0, speakerId: nil)]

    let annotated = SegmentSpeakerAnnotator.annotate(segments, withSpeakers: vadRanges)

    #expect(annotated[0].speakerId == nil)
  }
}
