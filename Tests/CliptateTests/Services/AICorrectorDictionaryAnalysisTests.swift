import CliptateCore
import Foundation
import Testing

@testable import Cliptate

@Suite("AICorrector dictionary analysis")
struct AICorrectorDictionaryAnalysisTests {

  // MARK: - buildDictionaryAnalysisText

  @Test("empty session list produces empty string")
  func emptySessionsProducesEmptyText() {
    let result = AICorrector.buildDictionaryAnalysisText(from: [])
    #expect(result.isEmpty)
  }

  @Test("sessions are assembled newest-first")
  func sessionsOrderedNewestFirst() {
    let old = TranscriptSession(
      startTime: Date(timeIntervalSinceNow: -3600),
      lines: [TranscriptLine(timestamp: 0, text: "old text")]
    )
    let recent = TranscriptSession(
      startTime: Date(timeIntervalSinceNow: -60),
      lines: [TranscriptLine(timestamp: 0, text: "recent text")]
    )
    let result = AICorrector.buildDictionaryAnalysisText(from: [old, recent])
    #expect(result.hasPrefix("recent text"))
    #expect(result.contains("old text"))
  }

  @Test("text is capped at maxLength characters")
  func textCappedAtMaxLength() {
    let longText = String(repeating: "a", count: 8000)
    let session = TranscriptSession(
      startTime: Date(),
      lines: [TranscriptLine(timestamp: 0, text: longText)]
    )
    let result = AICorrector.buildDictionaryAnalysisText(from: [session], maxLength: 5000)
    #expect(result.count <= 5000)
  }

  @Test("sessions beyond maxLength are omitted in full, partial text is taken from last fitting session")
  func laterSessionsOmittedWhenBudgetExceeded() {
    let first = TranscriptSession(
      startTime: Date(timeIntervalSinceNow: -10),
      lines: [TranscriptLine(timestamp: 0, text: String(repeating: "x", count: 900))]
    )
    let second = TranscriptSession(
      startTime: Date(timeIntervalSinceNow: -20),
      lines: [TranscriptLine(timestamp: 0, text: "should be partial or omitted")]
    )
    let result = AICorrector.buildDictionaryAnalysisText(from: [first, second], maxLength: 1000)
    #expect(result.count <= 1000)
    #expect(result.contains(String(repeating: "x", count: 900)))
  }

  @Test("sessions with empty combinedText are skipped")
  func emptySessionsSkipped() {
    let empty = TranscriptSession(startTime: Date(timeIntervalSinceNow: -5), lines: [])
    let withText = TranscriptSession(
      startTime: Date(timeIntervalSinceNow: -10),
      lines: [TranscriptLine(timestamp: 0, text: "hello world")]
    )
    let result = AICorrector.buildDictionaryAnalysisText(from: [empty, withText])
    #expect(result == "hello world")
  }

  @Test("multiple sessions are separated by divider")
  func multipleSessionsSeparatedByDivider() {
    let s1 = TranscriptSession(
      startTime: Date(timeIntervalSinceNow: -10),
      lines: [TranscriptLine(timestamp: 0, text: "alpha")]
    )
    let s2 = TranscriptSession(
      startTime: Date(timeIntervalSinceNow: -20),
      lines: [TranscriptLine(timestamp: 0, text: "beta")]
    )
    let result = AICorrector.buildDictionaryAnalysisText(from: [s1, s2])
    #expect(result.contains("---"))
    #expect(result.contains("alpha"))
    #expect(result.contains("beta"))
  }

  // MARK: - parseDictionaryTermsResponse

  @Test("parses clean JSON array")
  func parsesCleanJSONArray() {
    let response = #"["SwiftUI", "CoreML", "Parakeet"]"#
    let terms = AICorrector.parseDictionaryTermsResponse(response, maxTerms: 30)
    #expect(terms == ["SwiftUI", "CoreML", "Parakeet"])
  }

  @Test("parses JSON inside markdown code fence")
  func parsesJSONInCodeFence() {
    let response = "```json\n[\"Whisper\", \"LLaMA\"]\n```"
    let terms = AICorrector.parseDictionaryTermsResponse(response, maxTerms: 30)
    #expect(terms.contains("Whisper"))
    #expect(terms.contains("LLaMA"))
  }

  @Test("extracts JSON array embedded in prose")
  func extractsJSONEmbeddedInProse() {
    let response = #"Here are the terms: ["Tokyo", "OpenAI"] as requested."#
    let terms = AICorrector.parseDictionaryTermsResponse(response, maxTerms: 30)
    #expect(terms.contains("Tokyo"))
    #expect(terms.contains("OpenAI"))
  }

  @Test("respects maxTerms cap")
  func respectsMaxTermsCap() {
    let many = (1...50).map { "Term\($0)" }
    let json = try! String(data: JSONSerialization.data(withJSONObject: many), encoding: .utf8)!
    let terms = AICorrector.parseDictionaryTermsResponse(json, maxTerms: 10)
    #expect(terms.count <= 10)
  }

  @Test("returns empty array for empty response")
  func emptyResponseReturnsEmpty() {
    let terms = AICorrector.parseDictionaryTermsResponse("", maxTerms: 30)
    #expect(terms.isEmpty)
  }

  @Test("falls back to line extraction when JSON is invalid")
  func fallsBackToLineExtraction() {
    let response = "- SwiftUI\n- CoreData\n- CloudKit"
    let terms = AICorrector.parseDictionaryTermsResponse(response, maxTerms: 30)
    #expect(terms.contains("SwiftUI"))
    #expect(terms.contains("CoreData"))
    #expect(terms.contains("CloudKit"))
  }
}
