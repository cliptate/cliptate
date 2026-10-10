import Foundation

public struct SegmentTranslation: Codable, Equatable, Sendable {
  public var text: String
  public var language: Language
  public var translatedAt: Date

  public init(text: String, language: Language, translatedAt: Date = Date()) {
    self.text = text
    self.language = language
    self.translatedAt = translatedAt
  }

  public var isEmpty: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}
