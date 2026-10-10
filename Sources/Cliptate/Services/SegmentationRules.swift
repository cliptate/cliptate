import Foundation

enum SegmentationRules {
  private static let sentenceEnders: CharacterSet = {
    var set = CharacterSet()
    for scalar in "。！？.!?…⋯".unicodeScalars {
      set.insert(scalar)
    }
    return set
  }()

  private static let commaSeparators: CharacterSet = {
    var set = CharacterSet()
    for scalar in "，,、".unicodeScalars {
      set.insert(scalar)
    }
    return set
  }()

  private static func isSplitPunctuation(_ scalar: UnicodeScalar) -> Bool {
    sentenceEnders.contains(scalar) || commaSeparators.contains(scalar)
  }

  private static func isSentenceEnder(_ scalar: UnicodeScalar) -> Bool {
    sentenceEnders.contains(scalar)
  }

  private static func isCommaSeparator(_ scalar: UnicodeScalar) -> Bool {
    commaSeparators.contains(scalar)
  }

  static func shouldSplitAfter(word: WordTiming) -> Bool {
    if word.punctuation.unicodeScalars.contains(where: isSplitPunctuation) {
      return true
    }
    guard let last = word.word.unicodeScalars.last else { return false }
    return isSplitPunctuation(last)
  }

  static func shouldSplitAfterToken(_ token: String) -> Bool {
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let last = trimmed.unicodeScalars.last else { return false }
    return isSplitPunctuation(last)
  }

  static func tokenEndsWithCommaSeparator(_ token: String) -> Bool {
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let last = trimmed.unicodeScalars.last else { return false }
    return isCommaSeparator(last)
  }

  static func tokenEndsWithSentenceEnder(_ token: String) -> Bool {
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let last = trimmed.unicodeScalars.last else { return false }
    return isSentenceEnder(last)
  }
}
