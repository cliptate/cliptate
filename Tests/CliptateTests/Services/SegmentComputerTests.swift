import CliptateCore
import Foundation
import Testing

@testable import Cliptate

@Suite("SegmentComputer")
@MainActor
struct SegmentComputerTests {

  // MARK: - Basic computation

  @Test("computes segments with padding applied")
  func computeWithPadding() {
    let raw = [Segment(id: "s1", startTime: 1.0, endTime: 2.0, text: "Hello")]
    let input = SegmentComputer.Input(
      segments: raw,
      totalDuration: 5.0,
      filterSilent: false,
      splitBySentence: false,
      maxCharsPerSegment: 0,
      leftPadMs: 200,
      rightPadMs: 200,
      effectFilterFillerWords: false,
      fillerWords: [],
      dictionaryEntries: [] as [String],
      removedSegmentIDs: [],
      processedTranslations: [:]
    )
    let result = SegmentComputer.compute(input)
    #expect(result.count == 1)
    #expect(result[0].startTime < 1.0, "Left padding should extend start time")
    #expect(result[0].endTime > 2.0, "Right padding should extend end time")
  }

  // MARK: - Translation injection

  @Test("injects translations from processedTranslations")
  func injectTranslations() {
    let raw = [Segment(id: "s1", startTime: 0, endTime: 1, text: "Hello")]
    let translation = SegmentTranslation(text: "你好", language: .chinese)
    let input = SegmentComputer.Input(
      segments: raw,
      totalDuration: 2.0,
      filterSilent: false,
      splitBySentence: false,
      maxCharsPerSegment: 0,
      leftPadMs: 0,
      rightPadMs: 0,
      effectFilterFillerWords: false,
      fillerWords: [],
      dictionaryEntries: [] as [String],
      removedSegmentIDs: [],
      processedTranslations: ["s1": translation]
    )
    let result = SegmentComputer.compute(input)
    #expect(result[0].translation?.text == "你好")
  }

  @Test("translations survive splitBySentence reprocessing")
  func translationsSurviveSplit() {
    let words: [WordTiming] = [
      WordTiming(word: "Hello.", startTime: 0.0, endTime: 0.5),
      WordTiming(word: "World", startTime: 0.6, endTime: 1.0),
    ]
    let raw = [Segment(id: "parent", startTime: 0, endTime: 1.0, text: "Hello. World", words: words)]

    // First compute with split to get IDs
    let input1 = SegmentComputer.Input(
      segments: raw, totalDuration: 2.0, filterSilent: false, splitBySentence: true,
      maxCharsPerSegment: 0, leftPadMs: 0, rightPadMs: 0,
      effectFilterFillerWords: false, fillerWords: [], dictionaryEntries: [] as [String],
      removedSegmentIDs: [], processedTranslations: [:]
    )
    let firstRun = SegmentComputer.compute(input1)
    #expect(firstRun.count > 1, "Split should produce multiple segments")

    // Create translations for split segments
    var translations: [String: SegmentTranslation] = [:]
    for seg in firstRun {
      translations[seg.id] = SegmentTranslation(text: "translated_\(seg.text)", language: .chinese)
    }

    // Recompute with different padding but same split + translations
    let input2 = SegmentComputer.Input(
      segments: raw, totalDuration: 2.0, filterSilent: false, splitBySentence: true,
      maxCharsPerSegment: 0, leftPadMs: 100, rightPadMs: 100,
      effectFilterFillerWords: false, fillerWords: [], dictionaryEntries: [] as [String],
      removedSegmentIDs: [], processedTranslations: translations
    )
    let secondRun = SegmentComputer.compute(input2)
    for seg in secondRun {
      #expect(seg.translation != nil, "Translation should survive reprocessing for: \(seg.text)")
    }
  }

  // MARK: - Config reactivity

  @Test("splitBySentence produces more segments")
  func splitBySentenceEffect() {
    let words: [WordTiming] = [
      WordTiming(word: "Hello.", startTime: 0.0, endTime: 0.5),
      WordTiming(word: "World", startTime: 0.6, endTime: 1.0),
    ]
    let raw = [Segment(id: "s1", startTime: 0, endTime: 1.0, text: "Hello. World", words: words)]

    let withoutSplit = SegmentComputer.Input(
      segments: raw, totalDuration: 2.0, filterSilent: false, splitBySentence: false,
      maxCharsPerSegment: 0, leftPadMs: 0, rightPadMs: 0,
      effectFilterFillerWords: false, fillerWords: [], dictionaryEntries: [] as [String],
      removedSegmentIDs: [], processedTranslations: [:]
    )
    let withSplit = SegmentComputer.Input(
      segments: raw, totalDuration: 2.0, filterSilent: false, splitBySentence: true,
      maxCharsPerSegment: 0, leftPadMs: 0, rightPadMs: 0,
      effectFilterFillerWords: false, fillerWords: [], dictionaryEntries: [] as [String],
      removedSegmentIDs: [], processedTranslations: [:]
    )

    let a = SegmentComputer.compute(withoutSplit)
    let b = SegmentComputer.compute(withSplit)
    #expect(b.count > a.count)
  }

  @Test("filterSilent removes empty segments")
  func filterSilentEffect() {
    let raw = [
      Segment(id: "s1", startTime: 0, endTime: 1, text: "Hello"),
      Segment(id: "s2", startTime: 1, endTime: 2, text: "   "),
      Segment(id: "s3", startTime: 2, endTime: 3, text: "..."),
    ]
    let input = SegmentComputer.Input(
      segments: raw, totalDuration: 4.0, filterSilent: true, splitBySentence: false,
      maxCharsPerSegment: 0, leftPadMs: 0, rightPadMs: 0,
      effectFilterFillerWords: false, fillerWords: [], dictionaryEntries: [] as [String],
      removedSegmentIDs: [], processedTranslations: [:]
    )
    let result = SegmentComputer.compute(input)
    #expect(result.count == 1, "Only 'Hello' should survive silent filtering")
  }

  @Test("removedSegmentIDs excludes segments")
  func removedSegmentsExcluded() {
    let raw = [
      Segment(id: "s1", startTime: 0, endTime: 1, text: "Keep"),
      Segment(id: "s2", startTime: 1, endTime: 2, text: "Remove"),
    ]
    let removeID = SegmentIdentifier(segment: raw[1])
    let input = SegmentComputer.Input(
      segments: raw, totalDuration: 3.0, filterSilent: false, splitBySentence: false,
      maxCharsPerSegment: 0, leftPadMs: 0, rightPadMs: 0,
      effectFilterFillerWords: false, fillerWords: [], dictionaryEntries: [] as [String],
      removedSegmentIDs: [removeID], processedTranslations: [:]
    )
    let result = SegmentComputer.compute(input)
    #expect(result.count == 1)
    #expect(result[0].text == "Keep")
  }
}
