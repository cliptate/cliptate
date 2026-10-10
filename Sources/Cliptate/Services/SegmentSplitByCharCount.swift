import Foundation

/// Splits segments that exceed a character count limit using word-level timings.
///
/// Logic: greedily accumulate words until adding the next word would exceed
/// `maxChars`. When the limit is reached, emit the current group as a new segment
/// and start a new group.
///
/// Segments without word timings are passed through unchanged.
enum SegmentSplitByCharCount {

  struct Options: Sendable {
    /// Maximum character count per segment. Values <= 0 disable splitting.
    var maxChars: Int = 50

    init(maxChars: Int = 50) {
      self.maxChars = maxChars
    }
  }

  // MARK: - Public API

  /// Apply character-count-based splitting to a list of segments.
  static func apply(segments: [Segment], options: Options) -> [Segment] {
    guard !segments.isEmpty else { return [] }
    guard options.maxChars > 0 else { return segments }
    var result: [Segment] = []
    result.reserveCapacity(segments.count)
    for segment in segments.sorted(by: { $0.startTime < $1.startTime }) {
      if let words = segment.words, words.count > 1,
        segment.text.count > options.maxChars
      {
        let split = splitByCharCount(segment: segment, words: words, maxChars: options.maxChars)
        result.append(contentsOf: split)
      } else {
        result.append(segment)
      }
    }
    return result
  }

  // MARK: - Core Splitting Logic

  private static func splitByCharCount(
    segment: Segment,
    words: [WordTiming],
    maxChars: Int
  ) -> [Segment] {
    var segments: [Segment] = []
    var currentWords: [WordTiming] = []
    var currentLength = 0

    for w in words {
      let token = w.word.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !token.isEmpty else { continue }
      let renderedToken = token + w.punctuation

      let addedLength =
        currentWords.isEmpty
        ? renderedToken.count
        : renderedToken.count + (needsSpace(currentWords.last?.word ?? "", token) ? 1 : 0)

      // If adding this word would exceed limit and we have tokens, split first
      if !currentWords.isEmpty && currentLength + addedLength > maxChars {
        emitSegment(
          from: currentWords, into: &segments,
          segmentConfidence: segment.confidence,
          parentId: segment.id)
        currentWords.removeAll()
        currentLength = 0
      }

      let spacePenalty =
        currentWords.isEmpty ? 0 : (needsSpace(currentWords.last?.word ?? "", token) ? 1 : 0)
      currentWords.append(w)
      currentLength += renderedToken.count + spacePenalty
    }

    // Emit remaining tokens
    if !currentWords.isEmpty {
      emitSegment(
        from: currentWords, into: &segments,
        segmentConfidence: segment.confidence,
        parentId: segment.id)
    }

    return segments.isEmpty ? [segment] : segments
  }

  // MARK: - Helpers

  private static func needsSpace(_ prev: String, _ next: String) -> Bool {
    guard !prev.isEmpty else { return false }
    return containsASCII(next)
  }

  private static func containsASCII(_ text: String) -> Bool {
    for scalar in text.unicodeScalars {
      let v = scalar.value
      if (48...57).contains(v) || (65...90).contains(v) || (97...122).contains(v) {
        return true
      }
    }
    return false
  }

  private static func emitSegment(
    from words: [WordTiming],
    into segments: inout [Segment],
    segmentConfidence: Float?,
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
        confidence: segmentConfidence
      ))
  }
}
