import Foundation
import NaturalLanguage

/// Splits segments using Apple's NaturalLanguage framework.
///
/// Uses NLTagger to assign POS-based weights to candidate break points,
/// scoring each by `nextTokenWeight / (1 + distanceFromCenter × 0.5)`.
/// The winning break point is mapped to the nearest word-timing boundary
/// when `words` is present; otherwise timing is interpolated by char ratio.
public enum SegmentSplitByNatural {

  public struct Options: Sendable {
    /// Maximum characters per segment. Values <= 0 disable splitting.
    public var maxChars: Int = 50

    public init(maxChars: Int = 50) {
      self.maxChars = maxChars
    }
  }

  // MARK: - Public API

  /// Apply NL-based splitting to a list of segments.
  /// Recursively splits any segment whose text exceeds `maxChars` until all
  /// segments are within the limit (or no further split point can be found).
  public static func apply(segments: [Segment], options: Options) -> [Segment] {
    guard !segments.isEmpty, options.maxChars > 0 else { return segments }
    var result: [Segment] = []
    result.reserveCapacity(segments.count)
    for segment in segments.sorted(by: { $0.startTime < $1.startTime }) {
      result.append(contentsOf: splitRecursive(segment, maxChars: options.maxChars))
    }
    return result
  }

  /// Recursively split a segment until its text fits within maxChars.
  private static func splitRecursive(_ segment: Segment, maxChars: Int) -> [Segment] {
    guard segment.text.count > maxChars else { return [segment] }
    let parts = splitSegment(segment)
    // If no split was possible, return as-is to avoid infinite loop
    guard parts.count > 1 else { return [segment] }
    return parts.flatMap { splitRecursive($0, maxChars: maxChars) }
  }

  // MARK: - Core Logic

  private static let tagWeights: [NLTag: Double] = [
    .punctuation: 10.0,
    .conjunction: 8.0,
    .preposition: 5.0,
    .verb: 3.0,
    .noun: 1.0,
  ]

  /// Returns 1 or 2 segments; returns the original segment unchanged if no
  /// suitable break point is found.
  private static func splitSegment(_ segment: Segment) -> [Segment] {
    let text = segment.text
    guard text.count >= 2 else { return [segment] }

    guard let splitIndex = bestSplitIndex(in: text) else { return [segment] }

    let firstText = String(text[..<splitIndex]).trimmingCharacters(in: .whitespaces)
    let secondText = String(text[splitIndex...]).trimmingCharacters(in: .whitespaces)
    guard !firstText.isEmpty, !secondText.isEmpty else { return [segment] }

    if let words = segment.words, words.count > 1 {
      return splitByWords(segment: segment, words: words, firstText: firstText, secondText: secondText)
    } else {
      return splitByCharRatio(segment: segment, firstText: firstText, secondText: secondText)
    }
  }

  // MARK: - NLTagger scoring

  private static func bestSplitIndex(in text: String) -> String.Index? {
    let tagger = NLTagger(tagSchemes: [.lexicalClass])
    tagger.string = text

    struct Token {
      let upperBound: String.Index
      let weight: Double
    }
    var tokens: [Token] = []

    tagger.enumerateTags(
      in: text.startIndex..<text.endIndex,
      unit: .word,
      scheme: .lexicalClass,
      options: [NLTagger.Options.omitWhitespace, .omitPunctuation]
    ) { tag, range in
      let weight = tag.flatMap { tagWeights[$0] } ?? 1.0
      tokens.append(Token(upperBound: range.upperBound, weight: weight))
      return true
    }

    guard tokens.count > 1 else { return nil }

    let centerOffset = text.count / 2
    var bestIndex: String.Index = text.index(text.startIndex, offsetBy: centerOffset)
    var maxScore = -1.0

    for i in 0..<(tokens.count - 1) {
      let splitPos = tokens[i].upperBound
      let distance = abs(text.distance(from: text.startIndex, to: splitPos) - centerOffset)
      let score = tokens[i + 1].weight / (1.0 + Double(distance) * 0.5)
      if score > maxScore {
        maxScore = score
        bestIndex = splitPos
      }
    }
    return bestIndex
  }

  // MARK: - Timing helpers

  /// Split by mapping firstText / secondText char counts to the nearest word boundary.
  private static func splitByWords(
    segment: Segment,
    words: [WordTiming],
    firstText: String,
    secondText: String
  ) -> [Segment] {
    // Reconstruct cumulative character offsets per word end
    var cumulative = 0
    var wordEndOffsets: [Int] = []
    var prevToken = ""
    for w in words {
      let token = (w.word + w.punctuation).trimmingCharacters(in: .whitespaces)
      guard !token.isEmpty else {
        wordEndOffsets.append(cumulative)
        continue
      }
      if needsSpace(prevToken, token) {
        cumulative += 1  // space between ASCII words
      }
      cumulative += token.count
      wordEndOffsets.append(cumulative)
      prevToken = token
    }

    let target = firstText.count
    var bestWordIdx = 0
    var bestDist = Int.max
    for (i, offset) in wordEndOffsets.enumerated() {
      let dist = abs(offset - target)
      if dist < bestDist {
        bestDist = dist
        bestWordIdx = i
      }
    }

    // Ensure at least one word in each half
    let splitWordIdx = max(0, min(bestWordIdx, words.count - 2))

    let firstWords = Array(words[0...splitWordIdx])
    let secondWords = Array(words[(splitWordIdx + 1)...])
    guard !firstWords.isEmpty, !secondWords.isEmpty else { return [segment] }

    let s1 = Segment(
      id: Segment.deterministicChildId(parentId: segment.id, startTime: firstWords.first!.startTime, endTime: firstWords.last!.endTime),
      startTime: firstWords.first!.startTime,
      endTime: firstWords.last!.endTime,
      text: WordTimingTextComposer.composeText(from: firstWords),
      words: firstWords,
      confidence: segment.confidence,
      speakerId: segment.speakerId
    )
    let s2 = Segment(
      id: Segment.deterministicChildId(parentId: segment.id, startTime: secondWords.first!.startTime, endTime: secondWords.last!.endTime),
      startTime: secondWords.first!.startTime,
      endTime: secondWords.last!.endTime,
      text: WordTimingTextComposer.composeText(from: secondWords),
      words: secondWords,
      confidence: segment.confidence,
      speakerId: segment.speakerId
    )
    return [s1, s2]
  }

  /// Fallback: interpolate timing by character ratio.
  private static func splitByCharRatio(
    segment: Segment,
    firstText: String,
    secondText: String
  ) -> [Segment] {
    let totalChars = firstText.count + secondText.count
    guard totalChars > 0 else { return [segment] }
    let ratio = Double(firstText.count) / Double(totalChars)
    let splitTime = segment.startTime + segment.duration * ratio
    let s1 = Segment(
      id: Segment.deterministicChildId(parentId: segment.id, startTime: segment.startTime, endTime: splitTime),
      startTime: segment.startTime, endTime: splitTime,
      text: firstText, words: nil, confidence: segment.confidence, speakerId: segment.speakerId)
    let s2 = Segment(
      id: Segment.deterministicChildId(parentId: segment.id, startTime: splitTime, endTime: segment.endTime),
      startTime: splitTime, endTime: segment.endTime,
      text: secondText, words: nil, confidence: segment.confidence, speakerId: segment.speakerId)
    return [s1, s2]
  }

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
}
