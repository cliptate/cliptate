import CliptateCore
import Foundation
import Testing

@testable import Cliptate

@Suite("AI Cut translation executor")
@MainActor
struct AICutTranslationExecutorTests {
  @Test("applies translated text to video state and emits progress plus completion status")
  func appliesTranslatedTextToVideoState() async throws {
    let url = URL(fileURLWithPath: "/tmp/example.mov")
    let segments = [
      Segment(startTime: 0, endTime: 1, text: "Hello"),
      Segment(startTime: 1, endTime: 2, text: "World"),
    ]
    let translatedAt = Date(timeIntervalSince1970: 1_234)
    let expectedTranslations: [String: SegmentTranslation] = [
      segments[0].id: SegmentTranslation(text: "你好", language: .chinese, translatedAt: translatedAt),
      segments[1].id: SegmentTranslation(text: "世界", language: .chinese, translatedAt: translatedAt),
    ]
    let request = AICutTranslationRequest(
      url: url,
      segments: segments,
      sourceLanguage: Language.english,
      targetLanguage: Language.chinese
    )
    let state = VideoState(segments: segments)
    var statusUpdates: [String] = []

    let executor = AICutTranslationExecutor { incomingRequest, progress in
      #expect(incomingRequest == request)
      progress(1, 2)
      progress(2, 2)
      return expectedTranslations
    }

    try await executor.execute(request: request, state: state) { status in
      statusUpdates.append(status)
    }

    // Translations stored in processedTranslations keyed by segment UUID
    #expect(state.processedTranslations[segments[0].id] == expectedTranslations[segments[0].id])
    #expect(state.processedTranslations[segments[1].id] == expectedTranslations[segments[1].id])
    #expect(state.translationSignature == SegmentSignature.compute(for: segments))
    #expect(state.lastTranslatedLanguage == Language.chinese)
    #expect(
      statusUpdates == [
        AICutTranslationExecutor.progressMessage(completed: 1, total: 2),
        AICutTranslationExecutor.progressMessage(completed: 2, total: 2),
        AICutTranslationExecutor.completionMessage(
          translatedCount: 2,
          totalCount: 2,
          targetLanguage: Language.chinese
        ),
      ]
    )
  }
}
