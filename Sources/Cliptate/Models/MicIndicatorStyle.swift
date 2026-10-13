import Foundation
import SwiftUI

/// Complete appearances for the dictation overlay. Raw values remain stable in saved settings.
enum MicIndicatorStyle: String, CaseIterable, Identifiable, Codable, Sendable {
  case graphite
  case pulseBlue
  case matrixGreen
  case voidPurple

  var id: String { rawValue }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)
    self = Self(rawValue: value) ?? .pulseBlue
  }

  var displayName: String {
    switch self {
    case .graphite: return String(localized: "Minimal Graphite")
    case .pulseBlue: return String(localized: "Ice Blue Pulse")
    case .matrixGreen: return String(localized: "Matrix Green")
    case .voidPurple: return String(localized: "Cosmic Purple")
    }
  }

  var summary: String {
    switch self {
    case .graphite: return String(localized: "Quiet, neutral, and focused")
    case .pulseBlue: return String(localized: "Cool glow with a crisp waveform")
    case .matrixGreen: return String(localized: "Phosphor glow inspired by terminals")
    case .voidPurple: return String(localized: "Deep violet with a soft neon glow")
    }
  }

  var usesTechDecoration: Bool { self != .graphite }
}

extension MicIndicatorStyle {
  var panelTopColor: Color {
    switch self {
    case .graphite: return Color(red: 0.15, green: 0.16, blue: 0.18, opacity: 0.94)
    case .pulseBlue: return Color(red: 0.03, green: 0.04, blue: 0.08, opacity: 0.82)
    case .matrixGreen: return Color(red: 0.02, green: 0.05, blue: 0.02, opacity: 0.82)
    case .voidPurple: return Color(red: 0.05, green: 0.02, blue: 0.09, opacity: 0.82)
    }
  }

  var panelBottomColor: Color {
    switch self {
    case .graphite: return Color(red: 0.07, green: 0.08, blue: 0.10, opacity: 0.96)
    case .pulseBlue: return Color(red: 0.005, green: 0.005, blue: 0.012, opacity: 0.87)
    case .matrixGreen: return Color(red: 0.005, green: 0.008, blue: 0.003, opacity: 0.87)
    case .voidPurple: return Color(red: 0.008, green: 0.003, blue: 0.015, opacity: 0.87)
    }
  }

  var borderTopColor: Color {
    switch self {
    case .graphite: return Color.white.opacity(0.24)
    case .pulseBlue: return Color(red: 0.30, green: 0.88, blue: 1.00).opacity(0.68)
    case .matrixGreen: return Color(red: 0.08, green: 1.00, blue: 0.38).opacity(0.60)
    case .voidPurple: return Color(red: 0.72, green: 0.22, blue: 1.00).opacity(0.65)
    }
  }

  var borderMidColor: Color {
    switch self {
    case .graphite: return Color.white.opacity(0.10)
    case .pulseBlue: return Color(red: 0.18, green: 0.52, blue: 1.00).opacity(0.26)
    case .matrixGreen: return Color(red: 0.08, green: 0.62, blue: 0.28).opacity(0.24)
    case .voidPurple: return Color(red: 0.45, green: 0.12, blue: 0.82).opacity(0.26)
    }
  }

  var radialHighlightColor: Color {
    switch self {
    case .graphite: return Color.clear
    case .pulseBlue: return Color(red: 0.22, green: 0.72, blue: 1.00).opacity(0.44)
    case .matrixGreen: return Color(red: 0.10, green: 0.90, blue: 0.35).opacity(0.36)
    case .voidPurple: return Color(red: 0.68, green: 0.16, blue: 0.98).opacity(0.46)
    }
  }

  var waveformTopColor: Color {
    switch self {
    case .graphite: return Color(red: 0.84, green: 0.87, blue: 0.92)
    case .pulseBlue:
      return Color(red: 0.48, green: 0.90, blue: 1.00)
    case .matrixGreen:
      return Color(red: 0.18, green: 1.00, blue: 0.42)
    case .voidPurple:
      return Color(red: 0.80, green: 0.22, blue: 1.00)
    }
  }

  var waveformBottomColor: Color {
    switch self {
    case .graphite: return Color(red: 0.52, green: 0.58, blue: 0.66)
    case .pulseBlue:
      return Color(red: 0.19, green: 0.57, blue: 0.95)
    case .matrixGreen:
      return Color(red: 0.06, green: 0.62, blue: 0.22)
    case .voidPurple:
      return Color(red: 0.32, green: 0.08, blue: 0.88)
    }
  }

  var timeTextColor: Color {
    switch self {
    case .graphite: return Color(red: 0.88, green: 0.90, blue: 0.94)
    case .pulseBlue: return Color(red: 0.68, green: 0.94, blue: 1.00)
    case .matrixGreen: return Color(red: 0.40, green: 1.00, blue: 0.58)
    case .voidPurple: return Color(red: 0.82, green: 0.66, blue: 1.00)
    }
  }

  var cornerAccentColor: Color {
    switch self {
    case .graphite: return Color.clear
    case .pulseBlue: return Color(red: 0.30, green: 0.88, blue: 1.00).opacity(0.55)
    case .matrixGreen: return Color(red: 0.12, green: 0.95, blue: 0.38).opacity(0.50)
    case .voidPurple: return Color(red: 0.70, green: 0.20, blue: 1.00).opacity(0.58)
    }
  }

}
