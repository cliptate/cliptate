import SwiftUI

// MARK: - Speaker badge display helpers

/// Returns the display label for a speaker (1-indexed: speakerId 0 → "S1").
func speakerBadgeText(id: Int) -> String {
  "S\(id + 1)"
}

/// Fixed palette of 8 distinct colors for speaker identities; cycles for id ≥ 8.
private let speakerPalette: [Color] = [
  Color(red: 0.27, green: 0.52, blue: 0.93),  // blue
  Color(red: 0.20, green: 0.73, blue: 0.55),  // teal
  Color(red: 0.93, green: 0.56, blue: 0.23),  // orange
  Color(red: 0.78, green: 0.28, blue: 0.64),  // purple
  Color(red: 0.85, green: 0.33, blue: 0.33),  // red
  Color(red: 0.95, green: 0.76, blue: 0.18),  // yellow
  Color(red: 0.44, green: 0.68, blue: 0.33),  // green
  Color(red: 0.40, green: 0.69, blue: 0.82),  // sky
]

/// Returns a deterministic color for a speaker id; cycles through the 8-color palette.
func speakerBadgeColor(id: Int) -> Color {
  speakerPalette[id % speakerPalette.count]
}
