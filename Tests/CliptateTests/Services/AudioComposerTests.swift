import Foundation
import Testing

@testable import Cliptate

@Suite("AudioComposer – timeline composition")
struct AudioComposerTests {

    @Test("single clip placed at correct offset")
    func singleClipOffset() {
        let sampleRate = 16000
        let clip = AudioComposer.TimedClip(
            samples: [Float](repeating: 1.0, count: sampleRate),  // 1 second
            startTime: 2.0,
            duration: 1.0
        )

        let result = AudioComposer.compose(
            clips: [clip],
            totalDuration: 5.0,
            sampleRate: sampleRate
        )

        let expectedCount = 5 * sampleRate
        #expect(result.count == expectedCount)

        // Before clip: silence
        #expect(result[0] == 0.0)
        #expect(result[sampleRate - 1] == 0.0)

        // During clip (at 2.0s)
        #expect(result[2 * sampleRate] == 1.0)
        #expect(result[2 * sampleRate + sampleRate / 2] == 1.0)

        // After clip (at 3.0s+): silence
        #expect(result[3 * sampleRate] == 0.0)
    }

    @Test("multiple clips with gaps filled by silence")
    func multipleClipsWithGaps() {
        let sampleRate = 8000
        let clip1 = AudioComposer.TimedClip(
            samples: [Float](repeating: 0.5, count: sampleRate),  // 1s at t=0
            startTime: 0.0,
            duration: 1.0
        )
        let clip2 = AudioComposer.TimedClip(
            samples: [Float](repeating: 0.8, count: sampleRate),  // 1s at t=2
            startTime: 2.0,
            duration: 1.0
        )

        let result = AudioComposer.compose(
            clips: [clip1, clip2],
            totalDuration: 4.0,
            sampleRate: sampleRate
        )

        #expect(result.count == 4 * sampleRate)

        // clip1 region
        #expect(result[0] == 0.5)
        // gap between clips
        #expect(result[Int(1.5 * Double(sampleRate))] == 0.0)
        // clip2 region
        #expect(result[2 * sampleRate] == 0.8)
        // after clip2
        #expect(result[3 * sampleRate] == 0.0)
    }

    @Test("empty clips produces all silence")
    func emptyClips() {
        let sampleRate = 16000
        let result = AudioComposer.compose(
            clips: [],
            totalDuration: 2.0,
            sampleRate: sampleRate
        )

        #expect(result.count == 2 * sampleRate)
        #expect(result.allSatisfy { $0 == 0.0 })
    }

    @Test("total output duration matches expected")
    func totalDurationMatch() {
        let sampleRate = 44100
        let totalDuration = 10.0
        let clip = AudioComposer.TimedClip(
            samples: [Float](repeating: 0.3, count: 44100),
            startTime: 5.0,
            duration: 1.0
        )

        let result = AudioComposer.compose(
            clips: [clip],
            totalDuration: totalDuration,
            sampleRate: sampleRate
        )

        #expect(result.count == Int(totalDuration * Double(sampleRate)))
    }

    @Test("clip extending beyond totalDuration is truncated")
    func clipBeyondTotalDuration() {
        let sampleRate = 8000
        let clip = AudioComposer.TimedClip(
            samples: [Float](repeating: 1.0, count: 2 * sampleRate),  // 2 seconds
            startTime: 4.0,
            duration: 2.0
        )

        let result = AudioComposer.compose(
            clips: [clip],
            totalDuration: 5.0,  // Only 1 second of the 2s clip fits
            sampleRate: sampleRate
        )

        #expect(result.count == 5 * sampleRate)
        // The clip starts at 4.0s and only 1s fits before totalDuration
        #expect(result[4 * sampleRate] == 1.0)
    }

    @Test("clips are placed in order regardless of input order")
    func unorderedClips() {
        let sampleRate = 8000
        let clip1 = AudioComposer.TimedClip(
            samples: [Float](repeating: 0.3, count: sampleRate / 2),
            startTime: 2.0,
            duration: 0.5
        )
        let clip2 = AudioComposer.TimedClip(
            samples: [Float](repeating: 0.7, count: sampleRate / 2),
            startTime: 0.5,
            duration: 0.5
        )

        // Pass clip1 (later) before clip2 (earlier)
        let result = AudioComposer.compose(
            clips: [clip1, clip2],
            totalDuration: 3.0,
            sampleRate: sampleRate
        )

        // clip2 at 0.5s
        #expect(result[sampleRate / 2] == 0.7)
        // clip1 at 2.0s
        #expect(result[2 * sampleRate] == 0.3)
    }
}
