import Combine
import Foundation
#if canImport(CliptateCLIKit)
  import CliptateCLIKit
#endif

@MainActor
final class HistoryRuntime: ObservableObject {
  static let shared = HistoryRuntime()

  private let store: TranscriptHistoryStore
  private var cancellable: AnyCancellable?

  init(store: TranscriptHistoryStore? = nil) {
    self.store = store ?? .shared
    cancellable = self.store.objectWillChange.sink { [weak self] _ in
      self?.objectWillChange.send()
    }
  }

  var recentDictationSessions: [TranscriptSession] {
    store.recentDictationSessions
  }

  var allSortedSessions: [TranscriptSession] {
    store.allSortedSessions
  }

  var sessions: [TranscriptSession] {
    store.sessions
  }

  var activityRecords: [HistoryActivityRecord] {
    store.activityRecords
  }

  func add(_ session: TranscriptSession, replacingTranscription: Bool = false) {
    store.add(session, replacingTranscription: replacingTranscription)
  }

  func replace(_ session: TranscriptSession) {
    store.replace(session)
  }

  func existingFileTranscriptionSessionID(forSourceURL url: URL) -> UUID? {
    store.existingFileTranscriptionSessionID(forSourceURL: url)
  }

  func sourceURLBookmark(for sessionID: UUID?) -> Data? {
    store.sourceURLBookmark(for: sessionID)
  }

  func remove(id: UUID) {
    store.remove(id: id)
  }

  func removeAll(source: SessionSource? = nil) {
    store.removeAll(source: source)
  }

  func recordCorrections(_ events: [TranscriptCorrection], for sessionID: UUID) throws {
    try store.recordCorrections(events, for: [sessionID])
  }

  func recordFileCorrections(
    _ proposals: [AICorrector.CorrectionItem], segments: [Segment], for sessionID: UUID,
    provider: String, model: String, language: String
  ) throws {
    let originalTexts = segments.map(\.text)
    let applied = AICorrector.applyCorrectionsWithEvidence(proposals, to: originalTexts)
    let batchID = UUID()
    let recordedAt = Date()
    var currentTexts = originalTexts
    var events: [TranscriptCorrection] = []
    for proposal in applied.corrections {
      let index = proposal.index - 1
      let before = currentTexts[index]
      let after = before.replacingOccurrences(of: proposal.original, with: proposal.corrected)
      currentTexts[index] = after
      var event = TranscriptCorrection(
        batchID: batchID, recordedAt: recordedAt, kind: .phrase,
        original: proposal.original, corrected: proposal.corrected,
        originalContext: before, correctedContext: after, targetID: segments[index].id,
        timestamp: segments[index].startTime, provider: provider, model: model, language: language,
        relatedSessionIDs: [sessionID])
      if !applied.correctedTexts[index].contains(proposal.corrected) {
        event.status = .superseded
        event.statusChangedAt = recordedAt
      }
      events.append(event)
    }
    guard !events.isEmpty else { return }
    try recordCorrections(events, for: sessionID)
  }

  func markCorrections(for sessionID: UUID, status: TranscriptCorrection.Status) throws {
    try store.markCorrections(for: sessionID, status: status)
  }

  func recordDictationCorrection(
    sessionIDs: [UUID], original: String, corrected: String,
    provider: String, model: String, language: String
  ) throws {
    guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !corrected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      original != corrected else { return }
    let ids = sessionIDs.filter { id in
      store.sessions.contains { $0.id == id && ($0.source ?? .voiceDictation) == .voiceDictation }
    }
    guard !ids.isEmpty else { return }
    var event = TranscriptCorrection(
      kind: .dictation, original: original, corrected: corrected,
      originalContext: original, correctedContext: corrected, provider: provider, model: model,
      language: language, relatedSessionIDs: sessionIDs)
    let retainedOriginal = sessionIDs.compactMap { id in
      store.sessions.first(where: { $0.id == id })?.combinedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }.joined()
    if retainedOriginal != original {
      event.status = .superseded
      event.statusChangedAt = Date()
    }
    try store.recordCorrections([event], for: ids)
  }

  func query(_ query: CLIHistoryQuery) throws -> CLIHistoryPage {
    try HistoryQuery.page(query, sessions: store.sessions)
  }
}
