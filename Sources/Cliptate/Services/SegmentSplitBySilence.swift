import Foundation

/// Splits segments by detecting silence gaps between word-level timings.
///
/// Logic: when the gap between two consecutive words exceeds `splitThreshold`,
/// split into separate segments at that point.
///
/// This is the reusable version of the logic originally in `Qwen3ASRTranscriber.buildSegmentsFromWordTimings`.
enum SegmentSplitBySilence {
  struct Options: Sendable {
    /// Gap threshold in seconds. Gaps above this force a split between words.
    var splitThreshold: Double = 0.3

    init(splitThreshold: Double = 0.3) {
      self.splitThreshold = splitThreshold
    }
  }

  // MARK: - Public API

  /// Apply silence-based splitting to a list of segments.
  ///
  /// Each input segment's word-level timings are used to detect silence gaps.
  /// Segments without word timings are passed through unchanged.
  static func apply(segments: [Segment], options: Options) -> [Segment] {
    guard !segments.isEmpty else { return [] }
    var result: [Segment] = []
    result.reserveCapacity(segments.count)
    for segment in segments.sorted(by: { $0.startTime < $1.startTime }) {
      if let words = segment.words, words.count > 1 {
        let split = splitByWordGaps(segment: segment, words: words, options: options)
        result.append(contentsOf: split)
      } else {
        result.append(segment)
      }
    }
    return result
  }

  // MARK: - Core Splitting Logic

  /// Split a single segment into sub-segments based on word-level gaps.
  private static func splitByWordGaps(
    segment: Segment,
    words: [WordTiming],
    options: Options
  ) -> [Segment] {
    var segments: [Segment] = []
    var currentWords: [WordTiming] = []
    var lastEnd: Double? = nil

    for w in words {
      let token = w.word.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !token.isEmpty else { continue }
      let start = w.startTime
      let end = w.endTime

      // If gap exceeds threshold, split here
      if !currentWords.isEmpty, let le = lastEnd {
        let gap = start - le
        if gap > options.splitThreshold {
          emitSegment(
            from: currentWords, into: &segments,
            segmentConfidence: segment.confidence,
            speakerId: segment.speakerId,
            parentId: segment.id)
          currentWords.removeAll()
        }
      }

      currentWords.append(w)
      lastEnd = end
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

  /// Emit a segment from tokens, matching word timings for the segment.
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
