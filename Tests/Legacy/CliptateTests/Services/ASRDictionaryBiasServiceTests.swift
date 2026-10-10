import Testing

@testable import Cliptate

struct ASRDictionaryBiasServiceTests {
  @Test
  func dictionaryContextIsCappedAtTwoThousandCharacters() {
    let entries = (0..<600).map { "term-\($0)" }
    let context = ASRDictionaryBiasService.dictionaryContext(from: entries, maxCharacters: 2000)
    #expect((context?.count ?? 0) <= 2000)
  }

  @Test
  func appliesDictionaryEntryCaseInsensitively() {
    let result = ASRDictionaryBiasService.apply(
      to: "today we shipped whisper cut pro",
      dictionaryEntries: ["Whisper Cut Pro"]
    )
    #expect(result == "today we shipped Whisper Cut Pro")
  }

  @Test
  func appliesBiasToSegmentText() {
    let segments = [Segment(startTime: 0, endTime: 1, text: "we use whisper cut pro")]
    let result = ASRDictionaryBiasService.apply(
      to: segments,
      dictionaryEntries: ["Whisper Cut Pro"]
    )
    #expect(result.first?.text == "we use Whisper Cut Pro")
  }
}
