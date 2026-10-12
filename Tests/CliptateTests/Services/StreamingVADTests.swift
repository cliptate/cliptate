import Testing

@testable import Cliptate

@Suite("Streaming VAD audio framing")
struct StreamingVADTests {
  @Test("Sortformer uses encoded frame time to map segments after many microphone feeds")
  func sortformerMapsFrameOffset() {
    // 100 half-second chunks encode to 7 frames each at 80ms per frame.
    let frameOffset = Double(100 * 7) * 0.08
    let ranges = SortformerStreamingVADModule.speechSampleRanges(
      segmentTimes: [(frameOffset, frameOffset + 0.56)],
      chunkStartTime: frameOffset,
      sampleCount: 8000,
      sampleRate: 16000
    )
    #expect(ranges == [0..<8000])
  }

  @Test("Overlapping Sortformer speakers contribute each speech sample once")
  func sortformerMergesOverlappingSpeakers() {
    let ranges = SortformerStreamingVADModule.speechSampleRanges(
      segmentTimes: [(1, 1.25), (1.125, 1.5), (0, 0.5), (2, 3)],
      chunkStartTime: 1,
      sampleCount: 8000,
      sampleRate: 16000
    )
    #expect(ranges == [0..<8000])
  }

  @Test("Silero carries incomplete frames across microphone chunks without losing samples")
  func sileroPreservesIncompleteFrames() {
    var buffer = SileroStreamingAudioBuffer()
    let input = (0..<16000).map(Float.init)
    let first = buffer.append(Array(input.prefix(8000)), frameSize: 512)
    #expect(first.count == 7680)
    #expect(buffer.pendingSamples == Array(input[7680..<8000]))
    let second = buffer.append(Array(input.suffix(8000)), frameSize: 512)
    #expect(first + second + buffer.pendingSamples == input)
    #expect(second.count.isMultiple(of: 512))
  }

  @Test("Sub-frame microphone feeds are buffered until Silero can evaluate them")
  func sileroBuffersShortFeeds() {
    var buffer = SileroStreamingAudioBuffer()
    #expect(buffer.append([0, 1], frameSize: 4).isEmpty)
    #expect(buffer.append([2, 3, 4], frameSize: 4) == [0, 1, 2, 3])
    #expect(buffer.pendingSamples == [4])
  }
}
