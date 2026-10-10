import Foundation

/// Composes multiple time-aligned audio clips into a single continuous audio buffer.
public struct AudioComposer {

    /// A single audio clip positioned on the output timeline.
    public struct TimedClip {
        public let samples: [Float]
        public let startTime: TimeInterval
        public let duration: TimeInterval

        public init(samples: [Float], startTime: TimeInterval, duration: TimeInterval) {
            self.samples = samples
            self.startTime = startTime
            self.duration = duration
        }
    }

    /// Default crossfade duration (in seconds) applied at overlap boundaries.
    public static let defaultCrossfadeDuration: TimeInterval = 0.15

    /// Default fade-out duration (in seconds) applied when a clip is truncated.
    public static let defaultFadeOutDuration: TimeInterval = 0.10

    /// Maximum allowed overflow (in seconds) that a clip can extend past the next segment's start.
    /// Beyond this, the clip is truncated with a fade-out.
    public static let defaultMaxOverflow: TimeInterval = 0.30

    /// Compose clips into a single audio buffer at the given sample rate.
    ///
    /// Allows clips to overflow into the next segment by up to `maxOverflow` seconds.
    /// Overflow regions are blended with a crossfade. Clips exceeding maxOverflow are
    /// truncated with a fade-out ramp.
    public static func compose(
        clips: [TimedClip],
        totalDuration: TimeInterval,
        sampleRate: Int,
        crossfadeDuration: TimeInterval = AudioComposer.defaultCrossfadeDuration,
        fadeOutDuration: TimeInterval = AudioComposer.defaultFadeOutDuration,
        maxOverflow: TimeInterval = AudioComposer.defaultMaxOverflow
    ) -> [Float] {
        let totalSamples = Int(totalDuration * Double(sampleRate))
        var output = [Float](repeating: 0.0, count: totalSamples)

        let sorted = clips.sorted { $0.startTime < $1.startTime }
        let crossfadeSamples = max(1, Int(crossfadeDuration * Double(sampleRate)))
        let fadeOutSamples = max(1, Int(fadeOutDuration * Double(sampleRate)))
        let maxOverflowSamples = Int(maxOverflow * Double(sampleRate))

        for (idx, clip) in sorted.enumerated() {
            let startSample = Int(clip.startTime * Double(sampleRate))
            guard startSample >= 0, startSample < totalSamples else { continue }

            let maxByBuffer = totalSamples - startSample
            var usable = min(clip.samples.count, maxByBuffer)
            guard usable > 0 else { continue }

            // Determine allowed end position: next clip start + maxOverflow
            var applyFadeOut = (startSample + clip.samples.count) > totalSamples
            if idx + 1 < sorted.count {
                let nextStart = Int(sorted[idx + 1].startTime * Double(sampleRate))
                let allowedEnd = nextStart + maxOverflowSamples
                if startSample + usable > allowedEnd {
                    usable = max(0, allowedEnd - startSample)
                    applyFadeOut = true
                }
            }
            guard usable > 0 else { continue }

            // Write clip samples with optional fade-out at the tail
            let actualFadeOut = min(fadeOutSamples, usable)
            if applyFadeOut && actualFadeOut > 1 {
                let fadeStart = usable - actualFadeOut
                for i in 0..<fadeStart {
                    output[startSample + i] += clip.samples[i]
                }
                for i in fadeStart..<usable {
                    let gain = 1.0 - Float(i - fadeStart) / Float(actualFadeOut)
                    output[startSample + i] += clip.samples[i] * gain
                }
            } else {
                for i in 0..<usable {
                    output[startSample + i] += clip.samples[i]
                }
            }
        }

        // Second pass: apply crossfade (fade-in) at the start of each clip that overlaps
        // with the previous clip's overflow region
        for (idx, clip) in sorted.enumerated() {
            guard idx > 0 else { continue }
            let startSample = Int(clip.startTime * Double(sampleRate))
            guard startSample >= 0, startSample < totalSamples else { continue }

            let prevClip = sorted[idx - 1]
            let prevStart = Int(prevClip.startTime * Double(sampleRate))
            let prevRawEnd = prevStart + prevClip.samples.count
            // Only crossfade if previous clip's raw audio extends past our start
            guard prevRawEnd > startSample else { continue }

            let overlapLen = min(prevRawEnd - startSample, maxOverflowSamples)
            let fadeLen = min(crossfadeSamples, overlapLen, totalSamples - startSample)
            guard fadeLen > 1 else { continue }

            // In the overlap region, the output already has both clips summed.
            // Apply equal-power crossfade by scaling the summed values.
            for i in 0..<fadeLen {
                let t = Float(i) / Float(fadeLen)
                // Previous clip fades out, current clip fades in (equal power)
                let prevGain = cosf(t * .pi / 2.0)
                let currGain = sinf(t * .pi / 2.0)
                // We have: output = prevSample + currSample (both added in first pass)
                // We want: output = prevSample * prevGain + currSample * currGain
                // Approximate: since both are already there, scale the sum
                let combinedGain = (prevGain + currGain) / 2.0
                output[startSample + i] *= combinedGain
            }
        }

        // Clamp to [-1, 1]
        for i in 0..<totalSamples {
            output[i] = max(-1.0, min(1.0, output[i]))
        }

        return output
    }
}
