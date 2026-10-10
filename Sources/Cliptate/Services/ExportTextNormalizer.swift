import Foundation

enum ExportTextNormalizer {
  static func normalize(text: String, keepPunctuation: Bool) -> String {
    guard !keepPunctuation else {
      return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    let stripped = String(text.unicodeScalars.filter { !CharacterSet.punctuationCharacters.contains($0) })
    return stripped
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func normalize(segments: [Segment], keepPunctuation: Bool) -> [Segment] {
    guard !keepPunctuation else { return segments }
    return segments.map { segment in
      var normalizedTranslation: SegmentTranslation? = nil
      if let t = segment.translation {
        normalizedTranslation = SegmentTranslation(
          text: normalize(text: t.text, keepPunctuation: keepPunctuation),
          language: t.language,
          translatedAt: t.translatedAt
        )
      }
      return Segment(
        id: segment.id,
        startTime: segment.startTime,
        endTime: segment.endTime,
        text: normalize(text: segment.text, keepPunctuation: keepPunctuation),
        words: segment.words,
        confidence: segment.confidence,
        speakerId: segment.speakerId,
        translation: normalizedTranslation
      )
    }
  }

  static func normalize(
    translations: [String: SegmentTranslation],
    keepPunctuation: Bool
  ) -> [String: SegmentTranslation] {
    guard !keepPunctuation else { return translations }
    return translations.mapValues { translation in
      SegmentTranslation(
        text: normalize(text: translation.text, keepPunctuation: keepPunctuation),
        language: translation.language,
        translatedAt: translation.translatedAt
      )
    }
  }
}
