import Foundation
import Testing

@testable import Cliptate

@Suite("Segment speaker propagation pipeline")
struct SegmentSpeakerPropagationPipelineTests {
  @Test("padding keeps speakerId")
  func paddingKeepsSpeakerId() {
    let segments = [
      Segment(startTime: 1.0, endTime: 2.0, text: "hello", speakerId: 7),
      Segment(startTime: 3.0, endTime: 4.0, text: "world")
    ]

    let result = SegmentProcess.process(
      segments: segments,
      totalDuration: 5.0,
      operations: [.padding(leftMs: 100, rightMs: 200)]
    )

    #expect(result.count == 2)
    #expect(result.first?.speakerId == 7)
    #expect(result.last?.speakerId == nil)
  }

  @Test("compression keeps speakerId")
  func compressionKeepsSpeakerId() {
    let segments = [
      Segment(startTime: 2.0, endTime: 3.5, text: "hello", speakerId: 4),
      Segment(startTime: 5.0, endTime: 6.0, text: "world")
    ]

    let result = SegmentCompressor.compress(segments).compressedSegments

    #expect(result.count == 2)
    #expect(result.first?.speakerId == 4)
    #expect(result.last?.speakerId == nil)
  }

  @MainActor
  @Test("filler filter keeps speakerId")
  func fillerFilterKeepsSpeakerId() {
    let segments = [
      Segment(startTime: 0.0, endTime: 1.0, text: "um hello", speakerId: 2),
      Segment(startTime: 1.5, endTime: 2.5, text: "um world")
    ]

    let result = FillerWordFilter.filterSegments(segments, fillerWords: ["um"])

    #expect(result.count == 2)
    #expect(result.first?.text == "hello")
    #expect(result.first?.speakerId == 2)
    #expect(result.last?.text == "world")
    #expect(result.last?.speakerId == nil)
  }

  @Test("dictionary bias keeps speakerId")
  func dictionaryBiasKeepsSpeakerId() {
    let segments = [
      Segment(startTime: 0.0, endTime: 1.0, text: "whisper cut pro", speakerId: 1),
      Segment(startTime: 1.5, endTime: 2.5, text: "whisper cut pro")
    ]

    let result = ASRDictionaryBiasService.apply(
      to: segments,
      dictionaryEntries: ["Whisper Cut Pro"]
    )

    #expect(result.count == 2)
    #expect(result.first?.text == "Whisper Cut Pro")
    #expect(result.first?.speakerId == 1)
    #expect(result.last?.text == "Whisper Cut Pro")
    #expect(result.last?.speakerId == nil)
  }

  @Test("silence split keeps speakerId on emitted segments")
  func silenceSplitKeepsSpeakerId() {
    let segment = Segment(
      startTime: 0.0,
      endTime: 2.4,
      text: "hello world again",
      words: [
        word("hello", 0.0, 0.3),
        word("world", 0.35, 0.6),
        word("again", 1.5, 1.8)
      ],
      speakerId: 9
    )

    let result = SegmentSplitBySilence.apply(
      segments: [segment],
      options: .init(splitThreshold: 0.5)
    )

    #expect(result.count == 2)
    #expect(result.allSatisfy { $0.speakerId == 9 })
  }

  @Test("silence split keeps nil speakerId on emitted segments")
  func silenceSplitKeepsNilSpeakerId() {
    let segment = Segment(
      startTime: 0.0,
      endTime: 2.4,
      text: "hello world again",
      words: [
        word("hello", 0.0, 0.3),
        word("world", 0.35, 0.6),
        word("again", 1.5, 1.8)
      ]
    )

    let result = SegmentSplitBySilence.apply(
      segments: [segment],
      options: .init(splitThreshold: 0.5)
    )

    #expect(result.count == 2)
    #expect(result.allSatisfy { $0.speakerId == nil })
  }

  @Test("sentence split keeps speakerId on emitted segments")
  func sentenceSplitKeepsSpeakerId() {
    let segment = Segment(
      startTime: 0.0,
      endTime: 1.4,
      text: "Hello world. Again now.",
      words: [
        word("Hello", 0.0, 0.2),
        word("world", 0.2, 0.5, punctuation: "."),
        word("Again", 0.7, 0.9),
        word("now", 0.9, 1.2, punctuation: ".")
      ],
      speakerId: 5
    )

    let result = SegmentSplitBySentence.apply(segments: [segment])

    #expect(result.count == 2)
    #expect(result.allSatisfy { $0.speakerId == 5 })
  }

  @Test("sentence split keeps nil speakerId on emitted segments")
  func sentenceSplitKeepsNilSpeakerId() {
    let segment = Segment(
      startTime: 0.0,
      endTime: 1.4,
      text: "Hello world. Again now.",
      words: [
        word("Hello", 0.0, 0.2),
        word("world", 0.2, 0.5, punctuation: "."),
        word("Again", 0.7, 0.9),
        word("now", 0.9, 1.2, punctuation: ".")
      ]
    )

    let result = SegmentSplitBySentence.apply(segments: [segment])

    #expect(result.count == 2)
    #expect(result.allSatisfy { $0.speakerId == nil })
  }

  @Test("natural split keeps speakerId on both halves with words")
  func naturalSplitKeepsSpeakerIdWithWords() {
    let segment = Segment(
      startTime: 0.0,
      endTime: 1.2,
      text: "alpha beta gamma",
      words: [
        word("alpha", 0.0, 0.2),
        word("beta", 0.25, 0.45),
        word("gamma", 0.5, 0.8)
      ],
      speakerId: 3
    )

    let result = SegmentSplitByNatural.apply(
      segments: [segment],
      options: .init(maxChars: 10)
    )

    #expect(result.count == 2)
    #expect(result.allSatisfy { $0.speakerId == 3 })
  }

  @Test("natural split keeps speakerId on both halves without words")
  func naturalSplitKeepsSpeakerIdWithoutWords() {
    let segment = Segment(
      startTime: 0.0,
      endTime: 1.2,
      text: "alpha beta gamma",
      speakerId: 6
    )

    let result = SegmentSplitByNatural.apply(
      segments: [segment],
      options: .init(maxChars: 10)
    )

    #expect(result.count == 2)
    #expect(result.allSatisfy { $0.speakerId == 6 })
  }

  @Test("natural split keeps nil speakerId on both halves without words")
  func naturalSplitKeepsNilSpeakerIdWithoutWords() {
    let segment = Segment(
      startTime: 0.0,
      endTime: 1.2,
      text: "alpha beta gamma"
    )

    let result = SegmentSplitByNatural.apply(
      segments: [segment],
      options: .init(maxChars: 10)
    )

    #expect(result.count == 2)
    #expect(result.allSatisfy { $0.speakerId == nil })
  }

  @Test("legacy split helper keeps speakerId")
  func legacySplitKeepsSpeakerId() {
    let segment = Segment(
      startTime: 0.0,
      endTime: 1.8,
      text: "hello world again",
      words: [
        word("hello", 0.0, 0.2),
        word("world", 0.25, 0.5),
        word("again", 1.1, 1.4)
      ],
      speakerId: 8
    )

    let result = SegmentSplit.apply(
      segments: [segment],
      options: .init(splitThreshold: 0.5)
    )

    #expect(result.count == 2)
    #expect(result.allSatisfy { $0.speakerId == 8 })
  }

  @Test("legacy split helper keeps nil speakerId")
  func legacySplitKeepsNilSpeakerId() {
    let segment = Segment(
      startTime: 0.0,
      endTime: 1.8,
      text: "hello world again",
      words: [
        word("hello", 0.0, 0.2),
        word("world", 0.25, 0.5),
        word("again", 1.1, 1.4)
      ]
    )

    let result = SegmentSplit.apply(
      segments: [segment],
      options: .init(splitThreshold: 0.5)
    )

    #expect(result.count == 2)
    #expect(result.allSatisfy { $0.speakerId == nil })
  }

  private func word(
    _ word: String,
    _ startTime: TimeInterval,
    _ endTime: TimeInterval,
    punctuation: String = ""
  ) -> WordTiming {
    WordTiming(
      word: word,
      startTime: startTime,
      endTime: endTime,
      punctuation: punctuation
    )
  }
}
