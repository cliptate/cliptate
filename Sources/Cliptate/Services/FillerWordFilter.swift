import Foundation

@MainActor
enum FillerWordFilter {
  private static let regexCache = NSCache<NSString, NSRegularExpression>()

  static func filterSegments(_ segments: [Segment], fillerWords: Set<String>) -> [Segment] {
    guard !segments.isEmpty, !fillerWords.isEmpty,
      let regex = makeRegex(for: fillerWords)
    else {
      return segments
    }

    return segments.compactMap { segment in
      let sanitized = filter(text: segment.text, using: regex)
      let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return nil }
      return Segment(
        id: segment.id,
        startTime: segment.startTime,
        endTime: segment.endTime,
        text: trimmed,
        words: segment.words,
        confidence: segment.confidence,
        speakerId: segment.speakerId,
        translation: segment.translation
      )
    }
  }

  static func filter(text: String, fillerWords: Set<String>) -> String {
    guard !text.isEmpty, !fillerWords.isEmpty,
      let regex = makeRegex(for: fillerWords)
    else {
      return text
    }
    return filter(text: text, using: regex)
  }

  private static func filter(text: String, using regex: NSRegularExpression) -> String {
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    let replaced = regex.stringByReplacingMatches(
      in: text, options: [], range: range, withTemplate: " ")
    return cleanupWhitespaceAndPunctuation(replaced)
  }

  private static func makeRegex(for fillerWords: Set<String>) -> NSRegularExpression? {
    guard !fillerWords.isEmpty else { return nil }
    let key = cacheKey(for: fillerWords)
    if let key,
      let cached = regexCache.object(forKey: key)
    {
      return cached
    }

    var patterns: [String] = []
    patterns.reserveCapacity(fillerWords.count)
    let punctuationClass = "[,，、\\.。!！?？…~～]*"
    let alphanumerics = CharacterSet.alphanumerics

    for word in fillerWords {
      guard !word.isEmpty else { continue }
      let escaped = NSRegularExpression.escapedPattern(for: word)
      let hasAlphaNumeric = word.rangeOfCharacter(from: alphanumerics) != nil
      if hasAlphaNumeric {
        patterns.append("\\b" + escaped + "\\b" + punctuationClass)
      } else {
        patterns.append(escaped + punctuationClass)
      }
    }

    guard !patterns.isEmpty else { return nil }
    let pattern = patterns.joined(separator: "|")
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return nil
    }
    if let key {
      regexCache.setObject(regex, forKey: key)
    }
    return regex
  }

  private static func cacheKey(for fillerWords: Set<String>) -> NSString? {
    guard !fillerWords.isEmpty else { return nil }
    let joined =
      fillerWords
      .map { $0.lowercased() }
      .sorted()
      .joined(separator: "\u{1F}")
    return NSString(string: joined)
  }

  private static func cleanupWhitespaceAndPunctuation(_ text: String) -> String {
    let components = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
    guard !components.isEmpty else { return "" }
    var collapsed = components.joined(separator: " ")
    let punctuationToTighten = [
      ",", "，", ".", "。", "!", "！", "?", "？", ";", "；", ":", "：", "…", "、",
    ]
    for punctuation in punctuationToTighten {
      let spaced = " \(punctuation)"
      collapsed = collapsed.replacingOccurrences(of: spaced, with: punctuation)
    }
    return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
