import Foundation
import Testing
@testable import Cliptate

@Suite("Qwen3 Per-Segment Alignment")
struct Qwen3PerSegmentAlignTests {

  @Test("rebases local word timings by segment offset")
  func rebasesWordTimingsBySegmentOffset() {
    let asrSegment = Segment(
      startTime: 10.0,
      endTime: 13.0,
      text: "hello world",
      words: nil,
      confidence: nil
    )
    let localWords = [
      WordTiming(word: "hello", startTime: 0.1, endTime: 0.5, confidence: nil, punctuation: ""),
      WordTiming(word: "world", startTime: 0.6, endTime: 1.0, confidence: nil, punctuation: ""),
    ]
    let result = Qwen3ForcedAlignerTranscriber.rebaseAndBuildSegment(
      asrSegment: asrSegment,
      localWords: localWords
    )
    #expect(result != nil)
    #expect(result?.startTime == 10.1)
    #expect(result?.endTime == 11.0)
    #expect(result?.words?.count == 2)
    #expect(result?.words?[0].startTime == 10.1)
    #expect(result?.words?[1].startTime == 10.6)
  }

  @Test("returns nil for empty word timings")
  func returnsNilForEmptyWords() {
    let asrSegment = Segment(
      startTime: 5.0, endTime: 8.0, text: "silence", words: nil, confidence: nil)
    let result = Qwen3ForcedAlignerTranscriber.rebaseAndBuildSegment(
      asrSegment: asrSegment,
      localWords: []
    )
    #expect(result == nil)
  }

  @Test("preserves original ASR segment confidence in output segment")
  func preservesConfidence() {
    let asrSegment = Segment(
      startTime: 0.0, endTime: 2.0, text: "hi", words: nil, confidence: 0.9)
    let localWords = [
      WordTiming(word: "hi", startTime: 0.1, endTime: 0.4, confidence: nil, punctuation: ""),
    ]
    let result = Qwen3ForcedAlignerTranscriber.rebaseAndBuildSegment(
      asrSegment: asrSegment,
      localWords: localWords
    )
    #expect(result?.confidence == 0.9)
  }

  @Test("multiple segments produce monotonically increasing start times after rebasing")
  func multipleSegmentsMonotonicTimestamps() {
    let segments = [
      Segment(startTime: 0.0, endTime: 2.0, text: "hello", words: nil, confidence: nil),
      Segment(startTime: 5.0, endTime: 7.0, text: "world", words: nil, confidence: nil),
    ]
    let localWordsPerSegment: [[WordTiming]] = [
      [WordTiming(word: "hello", startTime: 0.1, endTime: 0.4, confidence: nil, punctuation: "")],
      [WordTiming(word: "world", startTime: 0.2, endTime: 0.6, confidence: nil, punctuation: "")],
    ]

    let results = zip(segments, localWordsPerSegment).compactMap { (seg, words) in
      Qwen3ForcedAlignerTranscriber.rebaseAndBuildSegment(asrSegment: seg, localWords: words)
    }

    #expect(results.count == 2)
    #expect(results[0].startTime < results[1].startTime)
    #expect(results[0].endTime <= results[1].startTime)
    // Verify exact rebased values: segmentOffset + localWordStartTime
    #expect(results[0].startTime == 0.1)   // 0.0 + 0.1
    #expect(results[0].endTime == 0.4)     // 0.0 + 0.4
    #expect(results[1].startTime == 5.2)   // 5.0 + 0.2
    #expect(results[1].endTime == 5.6)     // 5.0 + 0.6
  }

  @Test("empty localWords returns nil (whitespace-only segment skipped by caller)")
  func nilForEmptyLocalWords() {
    // Caller trims and guards before calling rebaseAndBuildSegment;
    // empty localWords represent a segment that produced no alignable words.
    let seg = Segment(startTime: 1.0, endTime: 3.0, text: "   ", words: nil, confidence: nil)
    let result = Qwen3ForcedAlignerTranscriber.rebaseAndBuildSegment(asrSegment: seg, localWords: [])
    #expect(result == nil)
  }
}
