import CliptateCore
import Testing

@testable import Cliptate

@Suite("Dubbing Batch Synthesis")
struct DubbingBatchSynthesisTests {

  // MARK: - Batch Creation

  @Test("single segment produces one batch")
  func singleSegmentOneBatch() {
    let segments = [
      Segment(
        startTime: 0, endTime: 2, text: "Hello",
        translation: SegmentTranslation(text: "你好", language: .chinese))
    ]
    let batches = DubbingService.createBatches(from: segments, maxCharsPerBatch: 500)
    #expect(batches.count == 1)
    #expect(batches[0].count == 1)
  }

  @Test("consecutive segments within char limit stay in one batch")
  func consecutiveSegmentsOneBatch() {
    let segments = [
      Segment(
        startTime: 0, endTime: 1, text: "Hello",
        translation: SegmentTranslation(text: "你好", language: .chinese)),
      Segment(
        startTime: 1, endTime: 2, text: "World",
        translation: SegmentTranslation(text: "世界", language: .chinese)),
      Segment(
        startTime: 2, endTime: 3, text: "Test",
        translation: SegmentTranslation(text: "测试", language: .chinese)),
    ]
    let batches = DubbingService.createBatches(from: segments, maxCharsPerBatch: 500)
    #expect(batches.count == 1)
    #expect(batches[0].count == 3)
  }

  @Test("large time gap splits into separate batches")
  func largeGapSplitsBatch() {
    let segments = [
      Segment(
        startTime: 0, endTime: 1, text: "Hello",
        translation: SegmentTranslation(text: "你好", language: .chinese)),
      Segment(
        startTime: 10, endTime: 11, text: "World",
        translation: SegmentTranslation(text: "世界", language: .chinese)),
    ]
    let batches = DubbingService.createBatches(from: segments, maxCharsPerBatch: 500)
    #expect(batches.count == 2)
    #expect(batches[0].count == 1)
    #expect(batches[1].count == 1)
  }

  @Test("exceeding char limit splits when combined duration exceeds threshold")
  func charLimitSplitsBatch() {
    let longText = String(repeating: "a", count: 300)
    // Each segment is 3s — combined 9s exceeds the 5s minBatchDuration threshold,
    // so char limit (500) triggers splitting after first segment.
    let segments = [
      Segment(
        startTime: 0, endTime: 3, text: "A",
        translation: SegmentTranslation(text: longText, language: .english)),
      Segment(
        startTime: 3, endTime: 6, text: "B",
        translation: SegmentTranslation(text: longText, language: .english)),
      Segment(
        startTime: 6, endTime: 9, text: "C",
        translation: SegmentTranslation(text: longText, language: .english)),
    ]
    let batches = DubbingService.createBatches(from: segments, maxCharsPerBatch: 500)
    // First segment (3s) is alone since adding second (600 chars > 500) after 3s < 5s...
    // Actually: first+second=6s >=5s and 600>500 → split.
    // First batch = [A], then second (3s) alone, add third (600>500, 3s<5s) → still merged
    // Let's trace: A added (300, 3s). B: currentDur=3<5 || chars=600>500 → exceedsLimit=false (3<5). Merged.
    // Now current=[A,B] 600chars 6s. C: currentDur=6>=5 && 900>500 → split.
    // Batch1=[A,B], current=[C]
    #expect(batches.count == 2)
    #expect(batches[0].count == 2)
    #expect(batches[1].count == 1)
  }

  @Test("short segments are merged for better prosody")
  func shortSegmentsMerged() {
    let segments = [
      Segment(
        startTime: 0, endTime: 1, text: "A",
        translation: SegmentTranslation(text: "Hello", language: .english)),
      Segment(
        startTime: 1, endTime: 2, text: "B",
        translation: SegmentTranslation(text: "World", language: .english)),
      Segment(
        startTime: 2, endTime: 3, text: "C",
        translation: SegmentTranslation(text: "Today", language: .english)),
    ]
    // All short (3s total < 5s), should stay in one batch
    let batches = DubbingService.createBatches(from: segments, maxCharsPerBatch: 200)
    #expect(batches.count == 1)
    #expect(batches[0].count == 3)
  }

  @Test("empty segments produce no batches")
  func emptySegmentsNoBatches() {
    let batches = DubbingService.createBatches(from: [], maxCharsPerBatch: 500)
    #expect(batches.isEmpty)
  }

  // MARK: - Sentence Separator

  @Test("Chinese uses Chinese period separator")
  func chineseSeparator() {
    #expect(DubbingService.sentenceSeparator(for: "zh") == "。")
  }

  @Test("Japanese uses Chinese period separator")
  func japaneseSeparator() {
    #expect(DubbingService.sentenceSeparator(for: "ja") == "。")
  }

  @Test("English uses period-space separator")
  func englishSeparator() {
    #expect(DubbingService.sentenceSeparator(for: "en") == ". ")
  }

  // MARK: - Energy-Based Splitting

  @Test("single segment returns all samples unsplit")
  func singleSegmentNoSplit() {
    let samples: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
    let result = DubbingService.splitAudioByEnergyBoundaries(
      samples: samples, sampleRate: 24000,
      segmentTexts: ["hello"], segmentDurations: [1.0]
    )
    #expect(result.count == 1)
    #expect(result[0] == samples)
  }

  @Test("two segments split at energy minimum")
  func twoSegmentsSplitAtEnergyMinimum() {
    // Create audio with a clear silence gap in the middle
    var samples = [Float](repeating: 0.0, count: 24000)
    // First half: speech-like values
    for i in 0..<10000 { samples[i] = Float.random(in: 0.3...0.8) }
    // Silence gap around 10000-14000
    // Second half: speech-like values
    for i in 14000..<24000 { samples[i] = Float.random(in: 0.3...0.8) }

    let result = DubbingService.splitAudioByEnergyBoundaries(
      samples: samples, sampleRate: 24000,
      segmentTexts: ["hello", "world"], segmentDurations: [0.5, 0.5]
    )
    #expect(result.count == 2)
    #expect(!result[0].isEmpty)
    #expect(!result[1].isEmpty)
    #expect(result[0].count + result[1].count == samples.count)

    // The split should happen in the silent region (10000-14000)
    #expect(result[0].count >= 9000)
    #expect(result[0].count <= 15000)
  }

  @Test("findMinEnergySample finds silence in noisy signal")
  func findMinEnergyInNoisySignal() {
    var samples = [Float](repeating: 0.0, count: 1000)
    for i in 0..<1000 { samples[i] = Float.random(in: 0.5...1.0) }
    // Insert silence at position 500-520
    for i in 500..<520 { samples[i] = 0.0 }

    let idx = DubbingService.findMinEnergySample(
      in: samples, from: 400, to: 600, windowSize: 20
    )
    // Should find index near the silence
    #expect(idx >= 490)
    #expect(idx <= 530)
  }
}
