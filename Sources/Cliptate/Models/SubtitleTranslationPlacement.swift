import Foundation

public enum SubtitleTranslationPlacement: String, CaseIterable, Identifiable, Codable, Sendable {
  case above
  case below

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .above: return String(localized: "Above Original", comment: "Subtitle translation placement: above the original line")
    case .below: return String(localized: "Below Original", comment: "Subtitle translation placement: below the original line")
    }
  }
}
