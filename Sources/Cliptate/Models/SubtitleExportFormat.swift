import Foundation

public enum SubtitleExportFormat: String, CaseIterable, Identifiable, Codable, Sendable {
  case srt
  case ass
  case txt

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .srt: return "SRT"
    case .ass: return "ASS"
    case .txt: return "TXT"
    }
  }

  public var fileExtension: String {
    switch self {
    case .srt: return "srt"
    case .ass: return "ass"
    case .txt: return "txt"
    }
  }

  public var description: String {
    switch self {
    case .srt:
      return String(localized: "Standard subtitle format compatible with most players.", comment: "SRT subtitle format description")
    case .ass:
      return String(localized: "Advanced SubStation Alpha with styling support.", comment: "ASS subtitle format description")
    case .txt:
      return String(localized: "Plain text transcript with timestamps.", comment: "TXT subtitle format description")
    }
  }
}
