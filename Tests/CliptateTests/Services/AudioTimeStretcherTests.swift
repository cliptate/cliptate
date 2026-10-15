import CliptateCore
import Foundation
import Testing

@testable import Cliptate

@Suite("AudioTimeStretcher – time compression")
struct AudioTimeStretcherTests {

    @Test("audio shorter than target is returned unchanged")
    func noStretchNeeded() {
        let sampleRate = 24000
        let samples = [Float](repeating: 0.5, count: sampleRate)  // 1 second
        let result = AudioTimeStretcher.stretchToFit(
            samples: samples,
            sampleRate: sampleRate,
            targetDuration: 2.0  // plenty of room
        )
        #expect(result.count == samples.count)
    }

    @Test("audio longer than target is compressed")
    func stretchCompresses() {
        let sampleRate = 24000
        // 2 seconds of audio
        let samples = [Float](repeating: 0.5, count: 2 * sampleRate)
        let result = AudioTimeStretcher.stretchToFit(
            samples: samples,
            sampleRate: sampleRate,
            targetDuration: 1.5  // need ~1.33x compression
        )
        // Result should be shorter than input
        #expect(result.count < samples.count)
        // Result should be approximately targetDuration * sampleRate (within 10%)
        let expectedCount = Int(1.5 * Double(sampleRate))
        let tolerance = Int(0.15 * Double(expectedCount))
        #expect(abs(result.count - expectedCount) < tolerance)
    }

    @Test("compression capped at maxSpeedupFactor with fade-out trim")
    func maxSpeedupCap() {
        let sampleRate = 24000
        // 3 seconds of audio that must fit in 1 second (3x compression needed)
        let samples = [Float](repeating: 0.5, count: 3 * sampleRate)
        let result = AudioTimeStretcher.stretchToFit(
            samples: samples,
            sampleRate: sampleRate,
            targetDuration: 1.0
        )
        // Since max speedup is 1.3x, SOLA compresses to ~2.3s, then fade-out trim to target (1.0s)
        let targetSamples = Int(1.0 * Double(sampleRate))
        #expect(result.count == targetSamples)
        // Should still be shorter than input
        #expect(result.count < samples.count)
        // Last sample should be faded to near-zero (fade-out applied)
        #expect(abs(result.last ?? 1.0) < 0.01)
    }

    @Test("empty samples returns empty")
    func emptyInput() {
        let result = AudioTimeStretcher.stretchToFit(
            samples: [],
            sampleRate: 24000,
            targetDuration: 1.0
        )
        #expect(result.isEmpty)
    }

    @Test("very short audio below minimum is passed through")
    func veryShortPassthrough() {
        let sampleRate = 24000
        // 50ms of audio (below minimumInputDuration of 100ms)
        let samples = [Float](repeating: 0.5, count: Int(0.05 * Double(sampleRate)))
        let result = AudioTimeStretcher.stretchToFit(
            samples: samples,
            sampleRate: sampleRate,
            targetDuration: 0.01
        )
        #expect(result.count == samples.count)
    }
}

@Suite("AudioComposer – fade behavior")
struct AudioComposerFadeTests {

    @Test("overlapping clips blend smoothly with crossfade")
    func crossfadeOnOverlap() {
        let sampleRate = 8000
        // clip1: 2 seconds of audio starting at 0, clip2 starts at 1s
        // Clip1's tail is allowed to overflow into clip2's region with crossfade
        let clip1 = AudioComposer.TimedClip(
            samples: [Float](repeating: 1.0, count: 2 * sampleRate),
            startTime: 0.0,
            duration: 2.0
        )
        let clip2 = AudioComposer.TimedClip(
            samples: [Float](repeating: 0.8, count: sampleRate),
            startTime: 1.0,
            duration: 1.0
        )

        let result = AudioComposer.compose(
            clips: [clip1, clip2],
            totalDuration: 3.0,
            sampleRate: sampleRate,
            crossfadeDuration: 0.15,
            fadeOutDuration: 0.1,
            maxOverflow: 0.3
        )

        // Before overlap (0.5s): only clip1
        #expect(result[sampleRate / 2] == 1.0)

        // In overlap region (1.0s): both clips contribute (crossfade blended)
        // The value should be positive (not silent) — smooth transition
        let overlapMid = sampleRate + sampleRate / 4  // 1.25s
        #expect(result[overlapMid] > 0.5)

        // After overlap ends (1.5s): only clip2
        #expect(abs(result[Int(1.5 * Double(sampleRate))] - 0.8) < 0.1)

        // After clip2 ends (2.5s): silence
        #expect(result[Int(2.5 * Double(sampleRate))] == 0.0)
    }

    @Test("non-overlapping clips have no fade-in applied")
    func noFadeInWithoutOverlap() {
        let sampleRate = 8000
        let clip1 = AudioComposer.TimedClip(
            samples: [Float](repeating: 1.0, count: sampleRate / 2),
            startTime: 0.0,
            duration: 0.5
        )
        let clip2 = AudioComposer.TimedClip(
            samples: [Float](repeating: 0.8, count: sampleRate / 2),
            startTime: 1.0,  // well after clip1 ends
            duration: 0.5
        )

        let result = AudioComposer.compose(
            clips: [clip1, clip2],
            totalDuration: 2.0,
            sampleRate: sampleRate
        )

        // clip2 starts at full amplitude (no fade-in needed)
        #expect(result[sampleRate] == 0.8)
    }

    @Test("clip truncated by totalDuration gets fade-out")
    func fadeOutAtEnd() {
        let sampleRate = 8000
        let fadeOutDuration: TimeInterval = 0.05
        let fadeOutSamples = Int(fadeOutDuration * Double(sampleRate))

        // 2 seconds of audio, but totalDuration is only 1 second
        let clip = AudioComposer.TimedClip(
            samples: [Float](repeating: 1.0, count: 2 * sampleRate),
            startTime: 0.0,
            duration: 2.0
        )

        let result = AudioComposer.compose(
            clips: [clip],
            totalDuration: 1.0,
            sampleRate: sampleRate,
            fadeOutDuration: fadeOutDuration
        )

        #expect(result.count == sampleRate)
        // Last sample should be near zero (faded out)
        #expect(result[sampleRate - 1] < 0.1)
        // Sample before fade region should be full amplitude
        #expect(result[sampleRate - fadeOutSamples - 1] == 1.0)
    }
}

@Suite("DubbingService – time window computation")
struct DubbingTimeWindowTests {

    @Test("available windows computed correctly")
    func computeWindows() {
        let segments = [
            makeSegment(start: 0.0, end: 1.0),
            makeSegment(start: 1.5, end: 2.5),
            makeSegment(start: 3.0, end: 4.0),
        ]
        let windows = DubbingService.computeAvailableWindows(
            segments: segments,
            totalDuration: 5.0
        )
        #expect(windows.count == 3)
        // First segment: from 0.0 to next start at 1.5
        #expect(abs(windows[0] - 1.5) < 0.001)
        // Second segment: from 1.5 to next start at 3.0
        #expect(abs(windows[1] - 1.5) < 0.001)
        // Last segment: from 3.0 to totalDuration 5.0
        #expect(abs(windows[2] - 2.0) < 0.001)
    }

    @Test("fitSamplesToWindow passes through short audio")
    func fitPassthrough() {
        let sampleRate = 24000
        let samples = [Float](repeating: 0.5, count: sampleRate)  // 1s
        let result = DubbingService.fitSamplesToWindow(
            samples: samples,
            sampleRate: sampleRate,
            availableWindow: 2.0
        )
        #expect(result.count == samples.count)
    }

    @Test("fitSamplesToWindow compresses overflow audio")
    func fitCompresses() {
        let sampleRate = 24000
        // 3 seconds needs to fit in 1.0s window (overflow allowance is 0.3s, so total 1.3s is threshold)
        // 3s > 1.0 + 0.3 = 1.3, so compression will trigger
        let samples = [Float](repeating: 0.5, count: 3 * sampleRate)
        let result = DubbingService.fitSamplesToWindow(
            samples: samples,
            sampleRate: sampleRate,
            availableWindow: 1.0
        )
        #expect(result.count < samples.count)
    }

    // Helper
    private func makeSegment(start: TimeInterval, end: TimeInterval) -> Segment {
        Segment(startTime: start, endTime: end, text: "test")
    }
}
