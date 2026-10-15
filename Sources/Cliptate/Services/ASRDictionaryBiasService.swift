import CliptateCore
import Foundation

enum ASRDictionaryBiasService {
  static func dictionaryContext(from entries: [String], maxCharacters: Int = 2000) -> String? {
    guard maxCharacters > 0 else { return nil }
    let normalized = AppConfiguration.normalizeDictionaryEntries(entries)
    guard !normalized.isEmpty else { return nil }

    var accepted: [String] = []
    accepted.reserveCapacity(normalized.count)
    var currentLength = 0

    for entry in normalized {
      let extra = accepted.isEmpty ? entry.count : entry.count + 1
      if currentLength + extra > maxCharacters { break }
      accepted.append(entry)
      currentLength += extra
    }

    guard !accepted.isEmpty else { return nil }
    return accepted.joined(separator: "\n")
  }

  static func apply(to text: String, dictionaryEntries: [String], maxCharacters: Int = 2000) -> String {
    guard !text.isEmpty else { return text }
    guard let context = dictionaryContext(from: dictionaryEntries, maxCharacters: maxCharacters) else {
      return text
    }

    let entries = context
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .sorted { $0.count > $1.count }

    var biased = text
    for entry in entries {
      for variant in replacementCandidates(for: entry) where !variant.isEmpty {
        biased = biased.replacingOccurrences(
          of: variant,
          with: entry,
          options: [.caseInsensitive, .diacriticInsensitive]
        )
      }
    }
    return biased
  }

  static func apply(to segments: [Segment], dictionaryEntries: [String], maxCharacters: Int = 2000)
    -> [Segment]
  {
    guard !segments.isEmpty else { return segments }
    return segments.map { segment in
      Segment(
        id: segment.id,
        startTime: segment.startTime,
        endTime: segment.endTime,
        text: apply(
          to: segment.text,
          dictionaryEntries: dictionaryEntries,
          maxCharacters: maxCharacters
        ),
        words: segment.words,
        confidence: segment.confidence,
        speakerId: segment.speakerId,
        translation: segment.translation
      )
    }
  }

  private static func replacementCandidates(for entry: String) -> [String] {
    var candidates: [String] = []
    candidates.append(entry)

    let normalizedSpaces = entry.replacingOccurrences(
      of: "\\s+",
      with: " ",
      options: .regularExpression
    )
    if normalizedSpaces != entry { candidates.append(normalizedSpaces) }

    if entry.contains(" ") {
      let collapsed = entry.replacingOccurrences(of: " ", with: "")
      if !collapsed.isEmpty { candidates.append(collapsed) }
    } else {
      let splitCamel = entry.replacingOccurrences(
        of: "([a-z0-9])([A-Z])",
        with: "$1 $2",
        options: .regularExpression
      )
      if splitCamel != entry { candidates.append(splitCamel) }
    }

    var unique: [String] = []
    var seen: Set<String> = []
    for candidate in candidates {
      let key = candidate.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
      if seen.insert(key).inserted {
        unique.append(candidate)
      }
    }
    return unique
  }
}
