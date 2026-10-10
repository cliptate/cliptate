import Foundation
import Testing

@testable import Cliptate

@Suite("Translation display pipeline")
@MainActor
struct TranslationDisplayPipelineTests {

  // MARK: - VideoState.processedTranslations storage

  @Test("applyTranslations stores by segment UUID")
  func applyTranslationsStoresBySegmentId() {
    let raw = [
      Segment(startTime: 0, endTime: 1, text: "Hello"),
      Segment(startTime: 1, endTime: 2, text: "World"),
    ]
    let state = VideoState(segments: raw)
    let processed = [
      Segment(startTime: 0, endTime: 1, text: "Hello"),
      Segment(startTime: 1, endTime: 2, text: "World"),
    ]
    let translations: [String: SegmentTranslation] = [
      processed[0].id: SegmentTranslation(text: "你好", language: .chinese),
      processed[1].id: SegmentTranslation(text: "世界", language: .chinese),
    ]

    state.applyTranslations(translations, for: processed)

    #expect(state.processedTranslations[processed[0].id]?.text == "你好")
    #expect(state.processedTranslations[processed[1].id]?.text == "世界")
  }

  @Test("clearTranslations removes processedTranslations")
  func clearTranslationsRemovesProcessedTranslations() {
    let raw = [Segment(startTime: 0, endTime: 1, text: "Hello")]
    let state = VideoState(segments: raw)
    let processed = [Segment(startTime: 0, endTime: 1, text: "Hello")]
    let translations: [String: SegmentTranslation] = [
      processed[0].id: SegmentTranslation(text: "你好", language: .chinese),
    ]
    state.applyTranslations(translations, for: processed)
    #expect(!state.processedTranslations.isEmpty)

    state.clearTranslations()

    #expect(state.processedTranslations.isEmpty)
    #expect(state.translationSignature == nil)
    #expect(state.lastTranslatedLanguage == nil)
  }

  @Test("setting new segments clears processedTranslations")
  func settingSegmentsClearsProcessedTranslations() {
    let raw = [Segment(startTime: 0, endTime: 1, text: "Hello")]
    let state = VideoState(segments: raw)
    let processed = [Segment(startTime: 0, endTime: 1, text: "Hello")]
    state.applyTranslations(
      [processed[0].id: SegmentTranslation(text: "你好", language: .chinese)],
      for: processed
    )
    #expect(!state.processedTranslations.isEmpty)

    // Setting new segments should clear translations
    state.segments = [Segment(startTime: 0, endTime: 2, text: "Different")]

    #expect(state.processedTranslations.isEmpty)
  }

  // MARK: - Translation injection after processing

  @Test("translations injected into segments by UUID match")
  func translationsInjectedByUUID() {
    let seg1 = Segment(id: "s1", startTime: 0, endTime: 1, text: "Hello")
    let seg2 = Segment(id: "s2", startTime: 1, endTime: 2, text: "World")
    let translations: [String: SegmentTranslation] = [
      "s1": SegmentTranslation(text: "你好", language: .chinese),
      "s2": SegmentTranslation(text: "世界", language: .chinese),
    ]

    let injected = VideoState.injectTranslations(translations, into: [seg1, seg2])

    #expect(injected[0].translation?.text == "你好")
    #expect(injected[1].translation?.text == "世界")
  }

  @Test("translations survive reprocessing when UUIDs preserved")
  func translationsSurviveReprocessingWithUUID() {
    let words: [WordTiming] = [
      WordTiming(word: "Hello", startTime: 0.0, endTime: 0.5),
      WordTiming(word: "World", startTime: 0.6, endTime: 1.0),
    ]
    let raw = [Segment(id: "stable-id", startTime: 0, endTime: 1.0, text: "Hello World", words: words)]
    let ops: [SegmentProcess.Operation] = [
      .splitBySilence(.init(splitThreshold: 2.0)),
      .padding(leftMs: 100, rightMs: 100),
    ]

    let first = SegmentProcess.process(segments: raw, totalDuration: 2.0, operations: ops)
    #expect(first.count == 1)
    #expect(first[0].id == "stable-id", "UUID should be preserved")

    let translations: [String: SegmentTranslation] = [
      "stable-id": SegmentTranslation(text: "你好世界", language: .chinese),
    ]

    let second = SegmentProcess.process(segments: raw, totalDuration: 2.0, operations: ops)
    let injected = VideoState.injectTranslations(translations, into: second)

    #expect(injected[0].translation?.text == "你好世界")
  }

  @Test("Split operations preserve UUID when segment is not actually split")
  func splitPreservesUUIDWhenNoSplit() {
    let words: [WordTiming] = [
      WordTiming(word: "Hello", startTime: 0.0, endTime: 0.3),
      WordTiming(word: "World", startTime: 0.4, endTime: 0.8),
    ]
    let original = Segment(id: "original-id", startTime: 0, endTime: 0.8, text: "Hello World", words: words)

    // SplitBySilence with high threshold — should NOT split
    let silenceResult = SegmentSplitBySilence.apply(segments: [original], options: .init(splitThreshold: 2.0))
    #expect(silenceResult.count == 1)
    #expect(silenceResult[0].id == "original-id", "SplitBySilence should preserve UUID when not splitting")

    // SplitBySentence — no sentence punctuation → should NOT split
    let sentenceResult = SegmentSplitBySentence.apply(segments: [original])
    #expect(sentenceResult.count == 1)
    #expect(sentenceResult[0].id == "original-id", "SplitBySentence should preserve UUID when not splitting")

    // SplitByNatural with large maxChars — should NOT split
    let naturalResult = SegmentSplitByNatural.apply(segments: [original], options: .init(maxChars: 1000))
    #expect(naturalResult.count == 1)
    #expect(naturalResult[0].id == "original-id", "SplitByNatural should preserve UUID when not splitting")

    // SegmentSplit (split by gap) with high threshold — should NOT split
    let gapResult = SegmentSplit.apply(segments: [original], options: .init(splitThreshold: 2.0))
    #expect(gapResult.count == 1)
    #expect(gapResult[0].id == "original-id", "SegmentSplit should preserve UUID when not splitting")
  }

  @Test("Split operations assign deterministic IDs when segment is actually split")
  func splitAssignsDeterministicIdsWhenSplitting() {
    let words: [WordTiming] = [
      WordTiming(word: "Hello", startTime: 0.0, endTime: 0.5),
      WordTiming(word: "World", startTime: 2.0, endTime: 2.5),
    ]
    let original = Segment(id: "original-id", startTime: 0, endTime: 2.5, text: "Hello World", words: words)

    let silenceResult = SegmentSplitBySilence.apply(segments: [original], options: .init(splitThreshold: 0.3))
    #expect(silenceResult.count == 2)
    #expect(silenceResult[0].id != "original-id", "Split fragments should get new IDs")
    #expect(silenceResult[1].id != "original-id", "Split fragments should get new IDs")

    // Run pipeline again — IDs must be identical (deterministic)
    let secondRun = SegmentSplitBySilence.apply(segments: [original], options: .init(splitThreshold: 0.3))
    #expect(secondRun.count == 2)
    #expect(secondRun[0].id == silenceResult[0].id, "Split IDs must be deterministic across runs")
    #expect(secondRun[1].id == silenceResult[1].id, "Split IDs must be deterministic across runs")
  }

  @Test("SplitBySentence produces deterministic IDs across runs")
  func sentenceSplitDeterministicIds() {
    let words: [WordTiming] = [
      WordTiming(word: "Hello.", startTime: 0.0, endTime: 0.5),
      WordTiming(word: "World", startTime: 0.6, endTime: 1.0),
    ]
    let original = Segment(id: "parent-id", startTime: 0, endTime: 1.0, text: "Hello. World", words: words)

    let first = SegmentSplitBySentence.apply(segments: [original])
    #expect(first.count == 2)

    let second = SegmentSplitBySentence.apply(segments: [original])
    #expect(second.count == 2)
    #expect(first[0].id == second[0].id, "Sentence split IDs must be deterministic")
    #expect(first[1].id == second[1].id, "Sentence split IDs must be deterministic")
  }

  @Test("SplitByNatural produces deterministic IDs across runs")
  func naturalSplitDeterministicIds() {
    let words: [WordTiming] = [
      WordTiming(word: "The", startTime: 0.0, endTime: 0.2),
      WordTiming(word: "quick", startTime: 0.2, endTime: 0.4),
      WordTiming(word: "brown", startTime: 0.4, endTime: 0.6),
      WordTiming(word: "fox", startTime: 0.6, endTime: 0.8),
      WordTiming(word: "jumps", startTime: 0.8, endTime: 1.0),
      WordTiming(word: "over", startTime: 1.0, endTime: 1.2),
      WordTiming(word: "the", startTime: 1.2, endTime: 1.4),
      WordTiming(word: "lazy", startTime: 1.4, endTime: 1.6),
      WordTiming(word: "dog", startTime: 1.6, endTime: 1.8),
    ]
    let original = Segment(
      id: "nat-parent", startTime: 0, endTime: 1.8,
      text: "The quick brown fox jumps over the lazy dog", words: words)

    let first = SegmentSplitByNatural.apply(segments: [original], options: .init(maxChars: 20))
    #expect(first.count > 1)

    let second = SegmentSplitByNatural.apply(segments: [original], options: .init(maxChars: 20))
    #expect(second.count == first.count)
    for i in 0..<first.count {
      #expect(first[i].id == second[i].id, "Natural split IDs must be deterministic at index \(i)")
    }
  }

  @Test("SplitByCharCount produces deterministic IDs across runs")
  func charCountSplitDeterministicIds() {
    let words: [WordTiming] = [
      WordTiming(word: "The", startTime: 0.0, endTime: 0.2),
      WordTiming(word: "quick", startTime: 0.2, endTime: 0.4),
      WordTiming(word: "brown", startTime: 0.4, endTime: 0.6),
      WordTiming(word: "fox", startTime: 0.6, endTime: 0.8),
      WordTiming(word: "jumps", startTime: 0.8, endTime: 1.0),
    ]
    let original = Segment(
      id: "cc-parent", startTime: 0, endTime: 1.0,
      text: "The quick brown fox jumps", words: words)

    let first = SegmentSplitByCharCount.apply(segments: [original], options: .init(maxChars: 15))
    #expect(first.count > 1)

    let second = SegmentSplitByCharCount.apply(segments: [original], options: .init(maxChars: 15))
    #expect(second.count == first.count)
    for i in 0..<first.count {
      #expect(first[i].id == second[i].id, "CharCount split IDs must be deterministic at index \(i)")
    }
  }

  @Test("Translations survive full pipeline reprocessing with splits")
  func translationsSurviveFullPipelineReprocessing() {
    let words: [WordTiming] = [
      WordTiming(word: "Hello.", startTime: 0.0, endTime: 0.5),
      WordTiming(word: "World", startTime: 0.6, endTime: 1.0),
    ]
    let raw = [Segment(id: "stable", startTime: 0, endTime: 1.0, text: "Hello. World", words: words)]
    let ops: [SegmentProcess.Operation] = [
      .splitBySentence,
      .padding(leftMs: 100, rightMs: 100),
    ]

    // First run: get processed segments and create translations
    let first = SegmentProcess.process(segments: raw, totalDuration: 2.0, operations: ops)
    #expect(first.count == 2, "Should split into 2 segments")

    var translations: [String: SegmentTranslation] = [:]
    for seg in first {
      translations[seg.id] = SegmentTranslation(text: "translated_\(seg.text)", language: .chinese)
    }

    // Second run: reprocess and inject translations
    let second = SegmentProcess.process(segments: raw, totalDuration: 2.0, operations: ops)
    let injected = VideoState.injectTranslations(translations, into: second)

    #expect(injected[0].translation != nil, "Translation must survive reprocessing for first segment")
    #expect(injected[1].translation != nil, "Translation must survive reprocessing for second segment")
    #expect(injected[0].translation?.text == "translated_\(first[0].text)")
    #expect(injected[1].translation?.text == "translated_\(first[1].text)")
  }

}
