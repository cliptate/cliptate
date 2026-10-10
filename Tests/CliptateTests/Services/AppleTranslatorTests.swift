import Foundation
import Testing
import Translation

@testable import Cliptate

@Suite("AppleTranslator")
struct AppleTranslatorTests {
  @Test("translateSegments maps results by segment id and reports progress")
  func translateSegmentsMapsResultsAndProgress() async throws {
    guard #available(macOS 15.0, *) else { return }
    try await assertTranslateSegmentsMapsResultsAndProgress()
  }

  @available(macOS 15.0, *)
  @MainActor
  private func assertTranslateSegmentsMapsResultsAndProgress() async throws {
    let segments = [
      Segment(startTime: 0, endTime: 1, text: "Hello"),
      Segment(startTime: 1, endTime: 2, text: "World"),
    ]
    let session = StubTranslationSession(
      responses: [
        TranslationSession.Response(
          sourceLanguage: Locale.Language(identifier: "en"),
          targetLanguage: Locale.Language(identifier: "zh-Hans"),
          sourceText: "Hello",
          targetText: "你好",
          clientIdentifier: "0"
        ),
        TranslationSession.Response(
          sourceLanguage: Locale.Language(identifier: "en"),
          targetLanguage: Locale.Language(identifier: "zh-Hans"),
          sourceText: "World",
          targetText: "世界",
          clientIdentifier: "1"
        ),
      ]
    )

    var reportedProgress: [(Int, Int)] = []
    let translations = try await AppleTranslator.translateSegments(
      segments,
      using: session,
      from: .english,
      to: .chinese,
      progress: { completed, total in
        reportedProgress.append((completed, total))
      }
    )

    #expect(session.prepareCallCount == 1)
    #expect(translations[segments[0].id]?.text == "你好")
    #expect(translations[segments[0].id]?.language == .chinese)
    #expect(translations[segments[1].id]?.text == "世界")
    #expect(translations[segments[1].id]?.language == .chinese)
    #expect(reportedProgress.count == 2)
    #expect(reportedProgress[0].0 == 1)
    #expect(reportedProgress[0].1 == 2)
    #expect(reportedProgress[1].0 == 2)
    #expect(reportedProgress[1].1 == 2)
  }
}

@available(macOS 15.0, *)
@MainActor
private final class StubTranslationSession: AppleTranslationSessionHandling {
  let responses: [TranslationSession.Response]
  private(set) var prepareCallCount = 0

  init(responses: [TranslationSession.Response]) {
    self.responses = responses
  }

  func prepareTranslation() async throws {
    prepareCallCount += 1
  }

  func translateBatchResponses(_ requests: [TranslationSession.Request]) async throws -> [TranslationSession.Response] {
    responses
  }
}
