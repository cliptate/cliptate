import Foundation

/// Deterministic bar‐weight pattern for the waveform visualizer.
/// The 5‐element pattern forms a natural center-high / sides-low envelope.
enum WaveformBarWeights {
  /// Base weight pattern: center is tallest, sides taper.
  static let pattern: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]

  /// Envelope smoothing: how fast bars rise toward a louder target (0–1).
  static let attackFactor: CGFloat = 0.4
  /// Envelope smoothing: how fast bars fall toward a quieter target (0–1).
  static let releaseFactor: CGFloat = 0.15

  /// Tile the pattern across `barCount` bars (simple modulo mapping).
  static func weights(forBarCount count: Int) -> [CGFloat] {
    (0..<count).map { pattern[$0 % pattern.count] }
  }

  /// Center-weighted mapping: blends the tiled pattern with a center-emphasis
  /// curve so that bars near the middle are taller regardless of tile position.
  static func centerWeighted(forBarCount count: Int) -> [CGFloat] {
    guard count > 0 else { return [] }
    let center = CGFloat(count - 1) / 2.0
    return (0..<count).map { i in
      let base = pattern[i % pattern.count]
      let distance = abs(CGFloat(i) - center)
      let emphasis = 1 - (distance / max(center, 1)) * 0.65
      return base * emphasis
    }
  }

  /// Apply ±4 % random jitter to a base value.
  static func applyJitter(to value: CGFloat) -> CGFloat {
    value * CGFloat.random(in: 0.96...1.04)
  }

  /// Smooth a bar height using attack/release envelope.
  /// Uses `attackFactor` when target > current (rising), `releaseFactor` when falling.
  static func envelopeSmooth(current: CGFloat, target: CGFloat) -> CGFloat {
    let factor = target >= current ? attackFactor : releaseFactor
    return current * (1 - factor) + target * factor
  }
}
