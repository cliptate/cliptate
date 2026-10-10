import Foundation
import Testing

@testable import Cliptate

@Suite("Qwen3 streaming speech accumulator")
struct Qwen3StreamingSpeechAccumulatorTests {
  @Test("speech ranges are accumulated until silence closes the segment")
  func accumulatesSpeechUntilSilence() {
    var accumulator = StreamingSpeechAccumulator(maxBufferedSamples: 12)

    let firstEmission = accumulator.ingest(
      chunk: [0, 1, 2, 3, 4, 5],
      speechSampleRanges: [0..<2, 4..<6]
    )
    #expect(firstEmission == nil)

    let secondEmission = accumulator.ingest(
      chunk: [6, 7, 8, 9],
      speechSampleRanges: []
    )
    #expect(secondEmission == [0, 1, 4, 5])
  }

  @Test("buffer flushes automatically once the speech window reaches its cap")
  func emitsWhenSpeechWindowReachesCap() {
    var accumulator = StreamingSpeechAccumulator(maxBufferedSamples: 4)

    let emission = accumulator.ingest(
      chunk: [10, 11, 12, 13, 14, 15],
      speechSampleRanges: [1..<5]
    )

    #expect(emission == [11, 12, 13, 14])
    #expect(accumulator.hasPendingSpeech == false)
  }

  @Test("flush returns trailing buffered speech on stop")
  func flushReturnsTrailingSpeech() {
    var accumulator = StreamingSpeechAccumulator(maxBufferedSamples: 10)

    _ = accumulator.ingest(
      chunk: [20, 21, 22, 23],
      speechSampleRanges: [1..<4]
    )

    #expect(accumulator.flush() == [21, 22, 23])
    #expect(accumulator.flush() == nil)
  }

  @Test("requires three silent chunks before flushing buffered speech")
  func requiresThreeSilentChunksBeforeFlush() {
    var accumulator = StreamingSpeechAccumulator(
      maxBufferedSamples: 12,
      requiredConsecutiveSilentChunks: 3
    )

    _ = accumulator.ingest(
      chunk: [0, 1, 2, 3],
      speechSampleRanges: [0..<4]
    )

    #expect(accumulator.ingest(chunk: [4, 5], speechSampleRanges: []) == nil)
    #expect(accumulator.ingest(chunk: [6, 7], speechSampleRanges: []) == nil)
    #expect(accumulator.ingest(chunk: [8, 9], speechSampleRanges: []) == [0, 1, 2, 3])
  }

  @Test("speech after a short pause resets the silent chunk counter")
  func speechAfterShortPauseResetsSilentCounter() {
    var accumulator = StreamingSpeechAccumulator(
      maxBufferedSamples: 20,
      requiredConsecutiveSilentChunks: 3
    )

    _ = accumulator.ingest(chunk: [0, 1], speechSampleRanges: [0..<2])
    #expect(accumulator.ingest(chunk: [2, 3], speechSampleRanges: []) == nil)

    _ = accumulator.ingest(chunk: [4, 5], speechSampleRanges: [0..<2])
    #expect(accumulator.ingest(chunk: [6, 7], speechSampleRanges: []) == nil)
    #expect(accumulator.ingest(chunk: [8, 9], speechSampleRanges: []) == nil)
    #expect(accumulator.ingest(chunk: [10, 11], speechSampleRanges: []) == [0, 1, 4, 5])
  }
}
