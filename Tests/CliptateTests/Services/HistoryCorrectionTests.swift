import Foundation
import Testing
import CliptateCore

@testable import Cliptate

@Suite("AI correction history")
@MainActor
struct HistoryCorrectionTests {
  @Test func appliedEvidenceRejectsInvalidAndNoOpProposals() {
    let result = AICorrector.applyCorrectionsWithEvidence([
      .init(index: 0, original: "wrong", corrected: "right"),
      .init(index: Int.min, original: "wrong", corrected: "right"),
      .init(index: 1, original: "missing", corrected: "right"),
      .init(index: 1, original: "", corrected: "right"),
      .init(index: 1, original: "wrong", corrected: " "),
      .init(index: 1, original: "wrong", corrected: "wrong"),
      .init(index: 1, original: "wrong", corrected: "right"),
      .init(index: 1, original: "wrong", corrected: "right"),
    ], to: ["a wrong word"])
    #expect(result.correctedTexts == ["a right word"])
    #expect(result.corrections.count == 1)
    #expect(result.corrections.first?.original == "wrong")
  }

  @Test func eventsSurviveFreshSessionSavesAndRestart() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("history.json")
    let store = TranscriptHistoryStore(historyURL: url)
    let runtime = HistoryRuntime(store: store)
    let id = UUID()
    let segment = Segment(id: "seg", startTime: 0, endTime: 1, text: "right")
    var session = TranscriptSession(id: id, source: .fileTranscription, aiCutSegments: [segment])
    session.append(text: "right", at: 0)
    runtime.add(session)
    let event = TranscriptCorrection(
      kind: .phrase, original: "wrong", corrected: "right", originalContext: "wrong",
      correctedContext: "right", targetID: "seg", provider: "openai", model: "test", language: "en")
    try runtime.recordCorrections([event], for: id)
    runtime.add(session) // An editor constructed this session before the audit event existed.
    #expect(runtime.sessions.first?.corrections?.count == 1)
    try runtime.markCorrections(for: id, status: .reverted)
    runtime.add(session)
    let reloaded = TranscriptHistoryStore(historyURL: url)
    #expect(reloaded.sessions.first?.corrections?.first?.status == .reverted)
    #expect(reloaded.sessions.first?.corrections?.first?.original == "wrong")
  }

  @Test func dictationAttributionUsesCapturedSessionIDsAndDeduplicatesQueries() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let runtime = HistoryRuntime(store: TranscriptHistoryStore(historyURL: directory.appendingPathComponent("history.json")))
    let state = VoiceShortcutState()
    state.activateMode(.dictation)
    var first = TranscriptSession(source: .voiceDictation)
    first.append(text: "one", at: 0)
    var second = TranscriptSession(source: .voiceDictation)
    second.append(text: "two", at: 0)
    runtime.add(first)
    runtime.add(second)
    state.absorbSessionTextOnce(sessionID: first.id, text: "one")
    state.absorbSessionTextOnce(sessionID: first.id, text: "one")
    state.absorbSessionTextOnce(sessionID: second.id, text: "two")
    let result = try #require(state.endSession())
    #expect(result.sessionIDs == [first.id, second.id])
    try runtime.recordDictationCorrection(
      sessionIDs: result.sessionIDs, original: result.transcript, corrected: "one two",
      provider: "openai", model: "test", language: "en")
    #expect(runtime.sessions.allSatisfy { $0.corrections?.count == 1 })
    let page = try runtime.query(CLIHistoryQuery(action: .corrections))
    #expect(page.corrections.count == 1)
    #expect(page.corrections.first?.relatedSessionIDs.count == 2)
  }

  @Test func historyCursorSurvivesNewEntriesAndRejectsChangedFilters() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let runtime = HistoryRuntime(store: TranscriptHistoryStore(historyURL: directory.appendingPathComponent("history.json")))
    for index in 0..<3 {
      var session = TranscriptSession(startTime: Date().addingTimeInterval(Double(index)), source: .fileTranscription)
      session.append(text: "record \(index)", at: 0)
      runtime.add(session)
    }
    var query = CLIHistoryQuery(action: .list, limit: 1)
    let first = try runtime.query(query)
    guard let cursor = first.nextCursor else {
      Issue.record("Expected a cursor for the remaining history entries")
      return
    }
    query.cursor = cursor
    var newSession = TranscriptSession(startTime: Date().addingTimeInterval(10), source: .fileTranscription)
    newSession.append(text: "newer", at: 0)
    runtime.add(newSession)
    let second = try runtime.query(query)
    #expect(second.sessions.count == 1)
    #expect(second.sessions.first?.id != first.sessions.first?.id)
    #expect(second.sessions.first?.id != newSession.id.uuidString)
    query.search = "other"
    #expect(throws: (any Error).self) { try runtime.query(query) }
  }

  @Test func parserValidatesHistoryQueries() throws {
    guard case .history(let query) = try CLICommand.parse([
      "history", "corrections", "--source", "fileTranscription", "--since", "2026-10-01T00:00:00Z",
      "--search", "Cliptate", "--limit", "10", "--format", "json",
    ]) else { Issue.record("Expected history command"); return }
    #expect(query.limit == 10)
    #expect(query.search == "Cliptate")
    for arguments in [["history", "delete"], ["history", "show", "bad-id"],
      ["history", "list", "--limit", "0"], ["history", "list", "--limit", "201"],
      ["history", "list", "--since", "yesterday"], ["history", "list", "--source", "invalid"]] {
      #expect(throws: (any Error).self) { try CLICommand.parse(arguments) }
    }
  }

  @Test func explicitRetranscriptionSupersedesEvidenceEvenWhenSegmentIDsStayStable() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let runtime = HistoryRuntime(store: TranscriptHistoryStore(historyURL: directory.appendingPathComponent("history.json")))
    let original = Segment(id: "stable", startTime: 0, endTime: 1, text: "Clip date")
    let corrected = Segment(id: "stable", startTime: 0, endTime: 1, text: "Cliptate")
    var session = TranscriptSession(source: .fileTranscription,
      aiCutSegments: [corrected], aiCutOriginalSegments: [original])
    session.append(text: corrected.text, at: 0)
    runtime.add(session)
    try runtime.recordFileCorrections([.init(index: 1, original: "Clip date", corrected: "Cliptate")],
      segments: [original], for: session.id, provider: "openai", model: "test", language: "en")
    runtime.add(session, replacingTranscription: true)
    let record = try #require(runtime.sessions.first)
    #expect(record.corrections?.first?.status == .superseded)
    #expect(record.aiCutOriginalSegments?.first?.text == "Clip date")
    #expect(record.corrections?.first?.targetID == "stable")
    #expect(record.corrections?.first?.originalContext == "Clip date")
    #expect(AICorrector.buildDictionaryAnalysisText(from: [record]).contains("AI correction") == false)
  }

  @Test func correctionTimeFiltersRetentionAndShowPagination() throws {
    let now = Date()
    var oldFile = TranscriptSession(startTime: now.addingTimeInterval(-172_800), source: .fileTranscription)
    oldFile.append(text: "first", at: 0)
    oldFile.append(text: "second", at: 1)
    oldFile.corrections = [TranscriptCorrection(recordedAt: now, kind: .phrase,
      original: "Clip date", corrected: "Cliptate", originalContext: "Clip date",
      correctedContext: "Cliptate", provider: "openai", model: "test", language: "en")]
    var expiredDictation = TranscriptSession(startTime: now.addingTimeInterval(-172_800), source: .voiceDictation)
    expiredDictation.append(text: "expired", at: 0)
    expiredDictation.corrections = oldFile.corrections
    let query = CLIHistoryQuery(action: .corrections, since: HistoryQuery.date(now.addingTimeInterval(-60)), search: "Cliptate")
    let filtered = try HistoryQuery.page(query, sessions: [oldFile, expiredDictation], now: now)
    #expect(filtered.corrections.count == 1)
    #expect(filtered.corrections.first?.source == "fileTranscription")
    #expect(try HistoryQuery.page(CLIHistoryQuery(action: .list, since: query.since),
      sessions: [oldFile], now: now).sessions.isEmpty)
    var show = CLIHistoryQuery(action: .show, sessionID: oldFile.id.uuidString, limit: 1)
    var texts: [String] = []
    var corrections: [String] = []
    repeat {
      let page = try HistoryQuery.page(show, sessions: [oldFile], now: now)
      #expect(page.sessions.count == 1)
      texts += page.lines.map(\.text)
      corrections += page.corrections.map(\.corrected)
      show.cursor = page.nextCursor
    } while show.cursor != nil
    #expect(texts == ["first", "second"])
    #expect(corrections == ["Cliptate"])
    show.cursor = try HistoryQuery.page(show, sessions: [oldFile], now: now).nextCursor
    oldFile.append(text: "changed", at: 2)
    #expect(throws: (any Error).self) { try HistoryQuery.page(show, sessions: [oldFile], now: now) }
  }

  @Test func byteBudgetPagesRatherThanTruncatesTextAndFailsForOneOversizeRecord() throws {
    var session = TranscriptSession(source: .fileTranscription)
    session.append(text: String(repeating: "甲", count: 200), at: 0)
    session.append(text: String(repeating: "乙", count: 200), at: 1)
    var query = CLIHistoryQuery(action: .show, sessionID: session.id.uuidString)
    let page = try HistoryQuery.page(query, sessions: [session], maximumBytes: 1_900)
    #expect(page.lines.count == 1)
    #expect(page.lines.first?.text == session.lines.first?.text)
    guard let cursor = page.nextCursor else {
      Issue.record("Expected a cursor for the remaining history lines")
      return
    }
    query.cursor = cursor
    #expect(try HistoryQuery.page(query, sessions: [session], maximumBytes: 1_900).lines.first?.text == session.lines.last?.text)
    #expect(throws: (any Error).self) {
      try HistoryQuery.page(CLIHistoryQuery(action: .show, sessionID: session.id.uuidString),
        sessions: [session], maximumBytes: 500)
    }
  }

  @Test func failedAuditWriteDoesNotPublishSuccessInMemory() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let runtime = HistoryRuntime(store: TranscriptHistoryStore(historyURL: directory.appendingPathComponent("history.json")))
    var session = TranscriptSession(source: .voiceDictation)
    session.append(text: "wrong", at: 0)
    runtime.add(session)
    try FileManager.default.removeItem(at: directory)
    #expect(throws: (any Error).self) {
      try runtime.recordDictationCorrection(sessionIDs: [session.id], original: "wrong", corrected: "right",
        provider: "openai", model: "test", language: "en")
    }
    #expect(runtime.sessions.first?.corrections == nil)
  }

  @Test func handlerEnablesDictionaryLearningWithoutInferenceOrLeakingInternalFields() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let runtime = HistoryRuntime(store: TranscriptHistoryStore(historyURL: directory.appendingPathComponent("history.json")))
    var session = TranscriptSession(recordingURL: URL(fileURLWithPath: "/private/recording.wav"),
      source: .fileTranscription, sourceURLBookmark: Data([1, 2, 3]))
    session.append(text: "Cliptate", at: 0)
    runtime.add(session)
    try runtime.recordFileCorrections([.init(index: 1, original: "Clip date", corrected: "Cliptate")],
      segments: [Segment(id: "seg", startTime: 0, endTime: 1, text: "Clip date")],
      for: session.id, provider: "openai", model: "test", language: "en")
    let config = AppConfiguration()
    var persisted: [String] = []
    let handler = CLIRequestHandler(config: config, history: runtime, persist: { persisted = $0.voiceToTextCustomDictionary },
      transcribe: { _, _ in Issue.record("History must not infer"); throw CancellationError() },
      ensureModel: { _, _, _ in Issue.record("History must not load models") })
    let event = try await handler.execute(CLIRequest(operation: .history, history: .init(action: .corrections)))
    let page = try #require(event.history)
    let data = try CLIOutput.encode(page)
    let json = String(decoding: data, as: UTF8.self)
    #expect(json.contains("/private") == false)
    #expect(json.contains("Bookmark") == false)
    let terms = page.corrections.filter { $0.kind == "phrase" && $0.status == "applied" }.map(\.corrected)
    let response = try await handler.execute(CLIRequest(operation: .dictionaryAdd, entries: terms))
    #expect(response.entries?.contains("Cliptate") == true)
    #expect(persisted.contains("Cliptate"))
    #expect(persisted.contains("Clip date") == false)
  }
}
