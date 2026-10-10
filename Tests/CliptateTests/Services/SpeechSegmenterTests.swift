import Foundation
import Testing

@testable import Cliptate

@Suite("SpeechSegmenter")
struct SpeechSegmenterTests {
  @Test("clamps segment bounds and drops invalid ranges")
  func clampsAndFiltersRanges() async throws {
    let segmenter = SpeechSegmenter(
      segmentSpeech: { _, totalDuration in
        [
          AudioTimeRange(startTime: -1, endTime: 2),
          AudioTimeRange(startTime: 3, endTime: 3),
          AudioTimeRange(startTime: 9, endTime: 15),
        ].compactMap { seg -> AudioTimeRange? in
          let clamped = AudioTimeRange(
            startTime: max(seg.startTime, 0),
            endTime: min(seg.endTime, totalDuration)
          )
          return clamped.endTime > clamped.startTime ? clamped : nil
        }
      }
    )

    let segments = try await segmenter.segmentSpeech(
      audioSamples: Array(repeating: 0, count: 16000 * 12),
      totalDuration: 10
    )

    #expect(segments.count == 2)
    #expect(segments[0].startTime == 0)
    #expect(segments[0].endTime == 2)
    #expect(segments[1].startTime == 9)
    #expect(segments[1].endTime == 10)
  }
}
