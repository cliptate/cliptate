import Foundation

/// Parses and clamps numeric text for FCPXML speed and frame rate fields.
enum FCPXMLSpeedParser {

  /// Parse a user-typed string into a Double, tolerating trailing dots, leading dots, and comma separators.
  static func parse(_ text: String) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }

    // Normalize comma to dot for locale tolerance
    let normalized = trimmed.replacingOccurrences(of: ",", with: ".")

    return Double(normalized)
  }

  /// Clamp speed to valid range [0.1, 10.0].
  static func clamp(_ value: Double) -> Double {
    min(max(value, 0.1), 10.0)
  }

  /// Clamp frame rate to valid range [1.0, 240.0].
  static func clampFrameRate(_ value: Double) -> Double {
    min(max(value, 1.0), 240.0)
  }
}
