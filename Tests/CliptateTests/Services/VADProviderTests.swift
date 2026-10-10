import Foundation
import Testing

@testable import Cliptate

@Suite("VADProvider")
struct VADProviderTests {

  @Test("SortformerVADProvider delegates to injected SpeechSegmenter")
  func sortformerVADProviderDelegatesToSpeechSegmenter() async throws {
    let expected = [
      AudioTimeRange(startTime: 0, endTime: 1),
      AudioTimeRange(startTime: 3, endTime: 4),
    ]
    let stubSegmenter = SpeechSegmenter(segmentSpeech: { _, _ in expected })
    let provider = SortformerVADProvider(segmenter: stubSegmenter)

    let result = try await provider.detectSpeech(
      samples: Array(repeating: Float(0), count: 16000 * 5), totalDuration: 5)

    #expect(result == expected)
  }

  @Test("SortformerVADProvider propagates segmenter errors")
  func sortformerVADProviderPropagatesSegmenterErrors() async throws {
    struct SegmentError: Error, Equatable {}
    let stubSegmenter = SpeechSegmenter(segmentSpeech: { _, _ in throw SegmentError() })
    let provider = SortformerVADProvider(segmenter: stubSegmenter)

    await #expect(throws: SegmentError.self) {
      _ = try await provider.detectSpeech(samples: [0], totalDuration: 1)
    }
  }

  @Test("SortformerVADProvider default initializer constructs without crash")
  func sortformerVADProviderDefaultInit() {
    let provider = SortformerVADProvider()
    _ = provider  // conformance compile check
  }

  @Test("SileroVADProvider conforms to VADProvider")
  func sileroVADProviderConformance() {
    let provider = SileroVADProvider(model: .sileroVAD)
    #expect(provider is any VADProvider)
  }

  @Test("SileroVADProvider default init uses sileroVAD")
  func sileroVADProviderDefaultInit() {
    let provider = SileroVADProvider()
    #expect(provider.model == .sileroVAD)
  }
}
