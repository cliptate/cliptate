import AVFoundation
import Foundation
import os

private let logger = Logger(subsystem: "com.cliptate.audio", category: "AudioTimeStretcher")

/// Stretches or compresses audio samples to fit a target duration using AVAudioEngine's time-pitch unit.
public struct AudioTimeStretcher {

    /// Maximum speed-up factor allowed before we prefer fade-out truncation.
    public static let maxSpeedupFactor: Float = 1.3

    /// Minimum audio duration (seconds) worth stretching. Below this, just pass through.
    public static let minimumInputDuration: TimeInterval = 0.1

    /// Stretch (or compress) `samples` at `sampleRate` to fit within `targetDuration`.
    ///
    /// - If the samples already fit within `targetDuration`, they are returned unchanged.
    /// - If the required speed-up exceeds `maxSpeedupFactor`, the audio is sped up to
    ///   `maxSpeedupFactor` and the caller should truncate the remainder.
    ///
    /// - Returns: Time-stretched samples, or the original samples if no stretching is needed.
    public static func stretchToFit(
        samples: [Float],
        sampleRate: Int,
        targetDuration: TimeInterval,
        maxSpeedup: Float = maxSpeedupFactor
    ) -> [Float] {
        guard sampleRate > 0, !samples.isEmpty else { return samples }

        let inputDuration = Double(samples.count) / Double(sampleRate)
        guard inputDuration > minimumInputDuration else { return samples }

        // If audio already fits, no stretching needed
        guard inputDuration > targetDuration else { return samples }

        // Calculate required rate adjustment
        let requiredRate = Float(inputDuration / targetDuration)
        let effectiveRate = min(requiredRate, maxSpeedup)

        // Use SOLA-based time stretching for quality
        var result = solaTimeStretch(samples: samples, sampleRate: sampleRate, rate: effectiveRate)

        // If after stretching the result STILL exceeds targetDuration (cap was hit),
        // apply a graceful fade-out at the boundary instead of hard-cutting.
        let targetSampleCount = Int(targetDuration * Double(sampleRate))
        if result.count > targetSampleCount && targetSampleCount > 0 {
            let fadeOutSamples = min(Int(0.05 * Double(sampleRate)), targetSampleCount / 4)  // 50ms fade
            for i in 0..<fadeOutSamples {
                let idx = targetSampleCount - fadeOutSamples + i
                let gain = Float(fadeOutSamples - i) / Float(fadeOutSamples)
                result[idx] *= gain
            }
            result = Array(result.prefix(targetSampleCount))
        }

        return result
    }

    /// SOLA (Synchronous Overlap-Add) time stretching.
    /// Speeds up audio by `rate` factor while preserving pitch.
    static func solaTimeStretch(
        samples: [Float],
        sampleRate: Int,
        rate: Float
    ) -> [Float] {
        guard rate > 1.0 else { return samples }

        let frameSize = 1024
        let hopSize = frameSize / 4
        let outputHop = Int(Float(hopSize) / rate)

        let inputCount = samples.count
        let expectedOutputCount = Int(Float(inputCount) / rate)
        var output = [Float](repeating: 0.0, count: expectedOutputCount + frameSize)
        var windowFunc = [Float](repeating: 0.0, count: frameSize)
        // Hann window
        for i in 0..<frameSize {
            windowFunc[i] = 0.5 * (1.0 - cos(2.0 * .pi * Float(i) / Float(frameSize)))
        }

        var normalization = [Float](repeating: 0.0, count: output.count)
        var inputPos = 0
        var outputPos = 0

        while inputPos + frameSize <= inputCount && outputPos + frameSize <= output.count {
            // Apply window and overlap-add
            for i in 0..<frameSize {
                let sample = samples[inputPos + i] * windowFunc[i]
                output[outputPos + i] += sample
                normalization[outputPos + i] += windowFunc[i]
            }

            inputPos += hopSize
            outputPos += outputHop
        }

        // Normalize
        for i in 0..<min(expectedOutputCount, output.count) {
            if normalization[i] > 0.001 {
                output[i] /= normalization[i]
            }
        }

        return Array(output.prefix(expectedOutputCount))
    }
}
