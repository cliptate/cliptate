import Foundation

/// Status states displayed in the floating mic-indicator overlay.
public enum OverlayStatus: String, Sendable {
  case idle
  case listening
  case transcribing
  case aiEnhance
  case copiedToClipboard

  var label: String {
    switch self {
    case .idle: return "Idle"
    case .listening: return "Listening"
    case .transcribing: return "Transcribing"
    case .aiEnhance: return "AI Enhance"
    case .copiedToClipboard: return "Copied"
    }
  }

  var processingLabel: String? {
    switch self {
    case .transcribing:
      String(localized: "Transcribing", comment: "Mic overlay processing status")
    case .aiEnhance:
      String(localized: "Thinking", comment: "Mic overlay AI enhancement status")
    case .copiedToClipboard:
      String(localized: "Copied · ⌘V", comment: "Mic overlay clipboard-fallback status")
    case .idle, .listening:
      nil
    }
  }

  /// Whether to show a spinner animation for this state.
  var showsSpinner: Bool {
    switch self {
    case .transcribing, .aiEnhance: return true
    case .idle, .listening, .copiedToClipboard: return false
    }
  }
}
