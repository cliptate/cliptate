import CliptateCore
import Foundation
import Testing

@Suite("Core segment processing")
struct SegmentProcessingTests {
  @Test func splittingPreservesTimingAndSpeakerWithStableIdentifiers() throws {
    let words = [
      WordTiming(word: "Hello", startTime: 0, endTime: 0.5, punctuation: "."),
      WordTiming(word: "World", startTime: 1, endTime: 1.5, punctuation: "."),
    ]
    let original = Segment(
      id: "parent", startTime: 0, endTime: 1.5, text: "Hello. World.",
      words: words, confidence: 0.9, speakerId: 2)

    let segments = SegmentProcess.process(
      segments: [original], totalDuration: 2, operations: [.splitBySentence])

    #expect(segments.count == 2)
    #expect(segments.map(\.id) == ["parent:0-500", "parent:1000-1500"])
    #expect(segments.map(\.speakerId) == [2, 2])
    #expect(segments.compactMap(\.words).flatMap { $0 } == words)

    let encoded = try JSONEncoder().encode(segments)
    let restored = try JSONDecoder().decode([Segment].self, from: encoded)
    #expect(restored == segments)
    #expect(restored.map(\.id) == segments.map(\.id))
  }

  @Test func compressionAndTextNormalizationPreserveTranslationAndIdentity() throws {
    let translation = SegmentTranslation(text: "你好！", language: .chinese)
    let original = Segment(
      id: "translated", startTime: 3, endTime: 4, text: "Hello!", speakerId: 1,
      translation: translation)
    let normalized = ExportTextNormalizer.normalize(
      segments: [original], keepPunctuation: false)
    let compressed = SegmentCompressor.compress(normalized)
    let segment = try #require(compressed.compressedSegments.first)

    #expect(segment.id == original.id)
    #expect(segment.startTime == 0)
    #expect(segment.endTime == 1)
    #expect(segment.text == "Hello")
    #expect(segment.translation?.text == "你好")
    #expect(segment.translation?.language == .chinese)
    #expect(segment.speakerId == 1)
    #expect(compressed.expandTime(0.5) == 3.5)
  }
}
