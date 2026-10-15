import Foundation

/// Builds display text from word timings while preserving per-word punctuation.
public enum WordTimingTextComposer {
  public static func composeText(from words: [WordTiming]) -> String {
    var text = ""
    var lastToken = ""

    for word in words {
      let token = word.word.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !token.isEmpty else { continue }

      if needsSpace(lastToken, token) {
        text += " "
      }

      text += token
      if !word.punctuation.isEmpty {
        text += word.punctuation
      }
      lastToken = token
    }

    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public static func endsWithSentencePunctuation(_ word: WordTiming) -> Bool {
    SegmentationRules.shouldSplitAfter(word: word)
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
