import Foundation

/// Splits segments at punctuation boundaries using word-level timings.
///
/// Logic: when a word ends with sentence punctuation or comma (。！？.!?，,、 etc.),
/// split after that word to form a new segment boundary.
///
/// Segments without word timings are passed through unchanged.
enum SegmentSplitBySentence {
  // MARK: - Public API

  /// Apply sentence-based splitting to a list of segments.
  static func apply(segments: [Segment]) -> [Segment] {
    guard !segments.isEmpty else { return [] }
    var result: [Segment] = []
    result.reserveCapacity(segments.count)
    for segment in segments.sorted(by: { $0.startTime < $1.startTime }) {
      if let words = segment.words, words.count > 1 {
        let split = splitBySentence(segment: segment, words: words)
        result.append(contentsOf: split)
      } else {
        result.append(segment)
      }
    }
    return result
  }

  // MARK: - Core Splitting Logic

  private static func splitBySentence(
    segment: Segment,
    words: [WordTiming]
  ) -> [Segment] {
    var segments: [Segment] = []
    var currentWords: [WordTiming] = []

    for w in words {
      let token = w.word.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !token.isEmpty else { continue }

      currentWords.append(w)

      // Check if this word ends with sentence-ending punctuation
      if WordTimingTextComposer.endsWithSentencePunctuation(w) {
        emitSegment(
          from: currentWords, into: &segments,
          segmentConfidence: segment.confidence,
          speakerId: segment.speakerId,
          parentId: segment.id)
        currentWords.removeAll()
      }
    }

    if !currentWords.isEmpty {
      emitSegment(
        from: currentWords, into: &segments,
        segmentConfidence: segment.confidence,
        speakerId: segment.speakerId,
        parentId: segment.id)
    }

    if segments.isEmpty { return [segment] }
    if segments.count == 1 {
      let s = segments[0]
      return [Segment(id: segment.id, startTime: s.startTime, endTime: s.endTime,
                      text: s.text, words: s.words, confidence: s.confidence,
                      speakerId: s.speakerId, translation: s.translation)]
    }
    return segments
  }

  // MARK: - Helpers

  private static func emitSegment(
    from words: [WordTiming],
    into segments: inout [Segment],
    segmentConfidence: Float?,
    speakerId: Int?,
    parentId: String
  ) {
    guard !words.isEmpty else { return }
    let startTime = words.first!.startTime
    let endTime = words.last!.endTime
    let text = WordTimingTextComposer.composeText(from: words)
    guard !text.isEmpty else { return }

    segments.append(
      Segment(
        id: Segment.deterministicChildId(parentId: parentId, startTime: startTime, endTime: endTime),
        startTime: startTime,
        endTime: endTime,
        text: text,
        words: words,
        confidence: segmentConfidence,
        speakerId: speakerId
      ))
  }
}
