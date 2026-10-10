import Foundation
import Testing

@testable import Cliptate

@Suite("Translation display & config reactivity")
@MainActor
struct TranslationAndConfigReactivityTests {

  // MARK: - Bug 1: Translations must be injected into segments via paddedSegments pipeline

  @Test("injectTranslations embeds translations into segments by UUID")
  func injectTranslationsMatchesByUUID() {
    let seg = Segment(id: "seg-1", startTime: 0, endTime: 1, text: "Hello")
    let translation = SegmentTranslation(text: "你好", language: .chinese)
    let translations: [String: SegmentTranslation] = ["seg-1": translation]

    let result = VideoState.injectTranslations(translations, into: [seg])
    #expect(result[0].translation?.text == "你好")
  }

  @Test("injectTranslations leaves segments without matching translations unchanged")
  func injectTranslationsNoMatch() {
    let seg = Segment(id: "seg-1", startTime: 0, endTime: 1, text: "Hello")
    let result = VideoState.injectTranslations([:], into: [seg])
    #expect(result[0].translation == nil)
  }

  @Test("VideoState.applyTranslations stores translations in processedTranslations")
  func applyTranslationsUpdatesProcessedTranslations() {
    let state = VideoState()
    let seg = Segment(id: "seg-1", startTime: 0, endTime: 1, text: "Hello")
    let translation = SegmentTranslation(text: "你好", language: .chinese)

    state.applyTranslations(["seg-1": translation], for: [seg])
    #expect(state.processedTranslations["seg-1"]?.text == "你好")
  }

  // MARK: - Bug 2: Config changes must produce different processed segments

  @Test("Changing splitBySentence produces different segment output")
  func splitBySentenceConfigChange() {
    let words: [WordTiming] = [
      WordTiming(word: "Hello.", startTime: 0.0, endTime: 0.5),
      WordTiming(word: "World", startTime: 0.6, endTime: 1.0),
    ]
    let raw = [Segment(id: "s1", startTime: 0, endTime: 1.0, text: "Hello. World", words: words)]

    let opsWithout: [SegmentProcess.Operation] = [
      .padding(leftMs: 100, rightMs: 100),
    ]
    let withoutSplit = SegmentProcess.process(segments: raw, totalDuration: 2.0, operations: opsWithout)

    let opsWith: [SegmentProcess.Operation] = [
      .splitBySentence,
      .padding(leftMs: 100, rightMs: 100),
    ]
    let withSplit = SegmentProcess.process(segments: raw, totalDuration: 2.0, operations: opsWith)

    #expect(withSplit.count > withoutSplit.count, "splitBySentence should produce more segments")
  }

  @Test("Changing padding values produces different segment timing")
  func paddingConfigChange() {
    let raw = [
      Segment(id: "s1", startTime: 1.0, endTime: 2.0, text: "Hello"),
    ]

    let ops100: [SegmentProcess.Operation] = [.padding(leftMs: 100, rightMs: 100)]
    let result100 = SegmentProcess.process(segments: raw, totalDuration: 5.0, operations: ops100)

    let ops500: [SegmentProcess.Operation] = [.padding(leftMs: 500, rightMs: 500)]
    let result500 = SegmentProcess.process(segments: raw, totalDuration: 5.0, operations: ops500)

    #expect(result100[0].startTime != result500[0].startTime, "Different padding should produce different start times")
    #expect(result100[0].endTime != result500[0].endTime, "Different padding should produce different end times")
  }

  @Test("Translations survive config-triggered reprocessing when IDs are deterministic")
  func translationsSurviveConfigReprocessing() {
    let words: [WordTiming] = [
      WordTiming(word: "Hello.", startTime: 0.0, endTime: 0.5),
      WordTiming(word: "World", startTime: 0.6, endTime: 1.0),
    ]
    let raw = [Segment(id: "parent", startTime: 0, endTime: 1.0, text: "Hello. World", words: words)]

    let ops: [SegmentProcess.Operation] = [
      .splitBySentence,
      .padding(leftMs: 100, rightMs: 100),
    ]
    let firstRun = SegmentProcess.process(segments: raw, totalDuration: 2.0, operations: ops)

    var translations: [String: SegmentTranslation] = [:]
    for seg in firstRun {
      translations[seg.id] = SegmentTranslation(text: "translated_\(seg.text)", language: .chinese)
    }

    // Change padding (config change) and reprocess
    let newOps: [SegmentProcess.Operation] = [
      .splitBySentence,
      .padding(leftMs: 200, rightMs: 200),
    ]
    let secondRun = SegmentProcess.process(segments: raw, totalDuration: 2.0, operations: newOps)

    // IDs should be deterministic, so translations should still match
    let injected = VideoState.injectTranslations(translations, into: secondRun)
    for seg in injected {
      #expect(seg.translation != nil, "Translation should survive config-triggered reprocessing for segment: \(seg.text)")
    }
  }

  // MARK: - Persistence: translations round-trip through segments

  @Test("extractTranslationsFromSegments populates processedTranslations")
  func extractTranslationsPopulatesDict() {
    let translation = SegmentTranslation(text: "你好", language: .chinese)
    let seg = Segment(
      id: "s1", startTime: 0, endTime: 1, text: "Hello",
      words: nil, confidence: nil, speakerId: nil, translation: translation
    )
    let state = VideoState(segments: [seg])
    #expect(state.processedTranslations.isEmpty, "Init should not auto-extract")
    state.extractTranslationsFromSegments()
    #expect(state.processedTranslations["s1"]?.text == "你好")
  }

  @Test("translations round-trip: embed → save → restore → extract")
  func translationsRoundTrip() {
    // Simulate: translate → embed → save as segments → restore → extract
    let rawSeg = Segment(id: "s1", startTime: 0, endTime: 1, text: "Hello")
    let translation = SegmentTranslation(text: "你好", language: .chinese)
    let translations = ["s1": translation]

    // Embed translations (simulates what markTranslationsChanged now does)
    let withTranslations = VideoState.injectTranslations(translations, into: [rawSeg])
    #expect(withTranslations[0].translation?.text == "你好")

    // Restore from history (simulates VideoState(segments: savedSegments))
    let restored = VideoState(segments: withTranslations)
    restored.extractTranslationsFromSegments()
    #expect(restored.processedTranslations["s1"]?.text == "你好")
  }

  @Test("VideoPlayerView prefers processed segments for subtitle rendering")
  func videoPlayerViewPrefersProcessedSegments() {
    let stale = [Segment(id: "s1", startTime: 0, endTime: 1, text: "old")]
    let processed = [Segment(id: "s1", startTime: 0, endTime: 1, text: "new")]

    let result = VideoPlayerView.resolvedDisplayedSegments(
      passedSegments: stale,
      processedSegments: processed
    )

    #expect(result == processed)
  }

  @Test("VideoPlayerView falls back to passed segments when processed segments are empty")
  func videoPlayerViewFallsBackToPassedSegments() {
    let stale = [Segment(id: "s1", startTime: 0, endTime: 1, text: "old")]

    let result = VideoPlayerView.resolvedDisplayedSegments(
      passedSegments: stale,
      processedSegments: []
    )

    #expect(result == stale)
  }
}
