import Foundation
import Testing

@testable import Cliptate

@Suite("Waveform bar weights")
struct WaveformBarWeightTests {

  @Test("Weight pattern has 5 elements matching spec [0.5, 0.8, 1.0, 0.75, 0.55]")
  func weightPatternShape() {
    let weights = WaveformBarWeights.pattern
    #expect(weights.count == 5)
    #expect(weights == [0.5, 0.8, 1.0, 0.75, 0.55])
  }

  @Test("Weights tile across arbitrary bar count")
  func weightTiling() {
    let mapped = WaveformBarWeights.weights(forBarCount: 12)
    #expect(mapped.count == 12)
    // Index 0 maps to pattern[0]=0.5, index 2 maps to pattern[2]=1.0
    #expect(mapped[0] == 0.5)
    #expect(mapped[2] == 1.0)
    // Index 5 wraps → pattern[0]=0.5
    #expect(mapped[5] == 0.5)
    #expect(mapped[7] == 1.0)
  }

  @Test("Envelope smoothing: attack 40%, release 15%")
  func envelopeSmoothingFactors() {
    // Attack (rising) should use 0.4 factor
    #expect(WaveformBarWeights.attackFactor == 0.4)
    // Release (decaying) should use 0.15 factor
    #expect(WaveformBarWeights.releaseFactor == 0.15)
  }

  @Test("Envelope smooth applies attack on rising values")
  func envelopeAttack() {
    let current: CGFloat = 0.3
    let target: CGFloat = 0.8
    let result = WaveformBarWeights.envelopeSmooth(current: current, target: target)
    // attack: current * (1 - 0.4) + target * 0.4 = 0.3 * 0.6 + 0.8 * 0.4 = 0.18 + 0.32 = 0.5
    #expect(abs(result - 0.5) < 0.001)
  }

  @Test("Envelope smooth applies release on falling values")
  func envelopeRelease() {
    let current: CGFloat = 0.8
    let target: CGFloat = 0.3
    let result = WaveformBarWeights.envelopeSmooth(current: current, target: target)
    // release: current * (1 - 0.15) + target * 0.15 = 0.8 * 0.85 + 0.3 * 0.15 = 0.68 + 0.045 = 0.725
    #expect(abs(result - 0.725) < 0.001)
  }

  @Test("Jitter stays within ±4% bounds")
  func jitterBounds() {
    let base: CGFloat = 1.0
    // Run 1000 samples, all must be in [0.96, 1.04]
    for _ in 0..<1000 {
      let jittered = WaveformBarWeights.applyJitter(to: base)
      #expect(jittered >= 0.96 * base)
      #expect(jittered <= 1.04 * base)
    }
  }

  @Test("Center-weighted mapping produces pronounced center-high sides-low shape for 24 bars")
  func centerWeightedShape() {
    let mapped = WaveformBarWeights.centerWeighted(forBarCount: 24)
    #expect(mapped.count == 24)
    // Center bars (11, 12) should be significantly higher than edges
    let center = (mapped[11] + mapped[12]) / 2
    let edge = (mapped[0] + mapped[23]) / 2
    #expect(center > edge)
    // Center should be at least 1.5x the edge (pronounced shape)
    #expect(center / edge > 1.5)
  }
}
