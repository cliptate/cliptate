import Foundation

import CliptateCore
import os

@MainActor
final class TranscriptHistoryStore: ObservableObject {
  static let shared = TranscriptHistoryStore()

  @Published private(set) var sessions: [TranscriptSession] = []
  @Published private(set) var activityRecords: [HistoryActivityRecord] = []

  private let historyURL: URL
  private let activityURL: URL
  private let logger = Logger(subsystem: "com.Cliptate", category: "TranscriptHistory")
  /// How long to retain live-dictation sessions (and their associated audio recordings).
  private let dictationRetentionInterval: TimeInterval = 60 * 60 * 24  // 24 hours
  /// How long to retain file-transcription sessions (text only, no audio ownership).
  private let fileTranscriptionRetentionInterval: TimeInterval = 60 * 60 * 24 * 30  // 30 days

  init(historyURL: URL? = nil) {
    self.historyURL = historyURL ?? Self.makeHistoryURL()
    self.activityURL = self.historyURL.deletingPathExtension().appendingPathExtension("activity.json")
    load()
    loadActivity()
    // Seed legacy sessions before the normal retention policy removes their content.
    var recordsByID = Dictionary(activityRecords.map { ($0.id, $0) }, uniquingKeysWith: { _, newer in newer })
    for session in sessions { recordsByID[session.id] = HistoryActivityRecord(session: session) }
    activityRecords = Array(recordsByID.values)
    pruneActivity()
    saveActivity()
    purgeExpiredSessions()
  }

  /// Recent dictation sessions (last 24 h), used by the Voice To Text sidebar.
  var recentDictationSessions: [TranscriptSession] {
    let cutoff = Date().addingTimeInterval(-dictationRetentionInterval)
    return sessions
      .filter { ($0.source ?? .voiceDictation) == .voiceDictation && $0.startTime >= cutoff }
      .sorted { $0.startTime > $1.startTime }
  }

  /// All retained sessions sorted newest-first, for the dedicated History page.
  var allSortedSessions: [TranscriptSession] {
    sessions.sorted { $0.startTime > $1.startTime }
  }

  func add(_ session: TranscriptSession, replacingTranscription: Bool = false) {
    guard !session.combinedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return
    }

    var normalized = session
    if normalized.endTime == nil {
      normalized.finish()
    }
    if let existingIndex = sessions.firstIndex(where: { $0.id == normalized.id }) {
      let existing = sessions.remove(at: existingIndex)
      normalized = Self.preservingEvidence(in: normalized, from: existing, replacingTranscription: replacingTranscription)
      if existing.recordingURL != normalized.recordingURL {
        deleteOwnedRecording(for: existing)
      }
    }
    sessions.append(normalized)
    updateActivity(for: normalized)
    purgeExpiredSessions()
    save()
  }

  func replace(_ session: TranscriptSession) {
    guard let index = sessions.firstIndex(where: { $0.id == session.id }) else {
      add(session)
      return
    }
    var updated = session
    if updated.endTime == nil {
      updated.finish()
    }

    let previous = sessions[index]
    updated = Self.preservingEvidence(in: updated, from: previous)
    if previous.recordingURL != updated.recordingURL {
      deleteOwnedRecording(for: previous)
    }

    sessions[index] = updated
    updateActivity(for: updated)
    purgeExpiredSessions()
    save()
  }

  func existingFileTranscriptionSessionID(forSourceURL url: URL) -> UUID? {
    let normalizedURL = url.standardizedFileURL
    return sessions.first { session in
      guard (session.source ?? .voiceDictation) == .fileTranscription else { return false }
      guard let bookmarkData = session.sourceURLBookmark else { return false }

      var isStale = false
      guard
        let resolvedURL = try? URL(
          resolvingBookmarkData: bookmarkData,
          options: .withSecurityScope,
          relativeTo: nil,
          bookmarkDataIsStale: &isStale
        ),
        !isStale
      else {
        return false
      }

      let needsStop = resolvedURL.startAccessingSecurityScopedResource()
      defer {
        if needsStop {
          resolvedURL.stopAccessingSecurityScopedResource()
        }
      }
      return resolvedURL.standardizedFileURL == normalizedURL
    }?.id
  }

  func sourceURLBookmark(for sessionID: UUID?) -> Data? {
    guard let sessionID else { return nil }
    return sessions.first(where: { $0.id == sessionID })?.sourceURLBookmark
  }

  func remove(id: UUID) {
    let removedSessions = sessions.filter { $0.id == id }
    removedSessions.forEach { deleteOwnedRecording(for: $0) }
    sessions.removeAll { $0.id == id }
    activityRecords.removeAll { $0.id == id }
    save()
  }

  /// Removes all sessions of a given source, or all sessions when `source` is nil.
  func removeAll(source: SessionSource? = nil) {
    if let source {
      let toRemove = sessions.filter { ($0.source ?? .voiceDictation) == source }
      toRemove.forEach { deleteOwnedRecording(for: $0) }
      sessions.removeAll { ($0.source ?? .voiceDictation) == source }
      activityRecords.removeAll { $0.source == source }
    } else {
      sessions.forEach { deleteOwnedRecording(for: $0) }
      sessions.removeAll()
      activityRecords.removeAll()
    }
    save()
  }

  /// Fresh editing snapshots must not discard audit events or replace their newer status.
  private static func preservingEvidence(
    in incoming: TranscriptSession, from existing: TranscriptSession, replacingTranscription: Bool = false
  ) -> TranscriptSession {
    var result = incoming
    var events = existing.corrections ?? []
    var ids = Set(events.map(\.id))
    events.append(contentsOf: (incoming.corrections ?? []).filter { ids.insert($0.id).inserted })
    let replacedTranscription: Bool
    if let old = existing.aiCutSegments, let new = incoming.aiCutSegments {
      replacedTranscription = !old.isEmpty && !new.isEmpty
        && Set(old.map(\.id)).isDisjoint(with: Set(new.map(\.id)))
    } else {
      replacedTranscription = !existing.lines.isEmpty && !incoming.lines.isEmpty
        && Set(existing.lines.map(\.id)).isDisjoint(with: Set(incoming.lines.map(\.id)))
    }
    if replacedTranscription || replacingTranscription {
      for index in events.indices where events[index].status == .applied {
        events[index].status = .superseded
        events[index].statusChangedAt = Date()
      }
    }
    result.corrections = events.isEmpty ? nil : events
    if result.aiCutOriginalSegments == nil {
      result.aiCutOriginalSegments = existing.aiCutOriginalSegments
    }
    return result
  }

  /// Persist audit changes atomically before publishing them to readers.
  func recordCorrections(_ events: [TranscriptCorrection], for sessionIDs: [UUID]) throws {
    var updated = sessions
    for index in updated.indices where sessionIDs.contains(updated[index].id) {
      var stored = updated[index].corrections ?? []
      var ids = Set(stored.map(\.id))
      stored.append(contentsOf: events.filter { ids.insert($0.id).inserted })
      updated[index].corrections = stored.isEmpty ? nil : stored
    }
    try persist(updated)
    sessions = updated
  }

  func markCorrections(for sessionID: UUID, status: TranscriptCorrection.Status) throws {
    var updated = sessions
    guard let index = updated.firstIndex(where: { $0.id == sessionID }),
      var events = updated[index].corrections else { return }
    for eventIndex in events.indices where events[eventIndex].status == .applied {
      events[eventIndex].status = status
      events[eventIndex].statusChangedAt = Date()
    }
    updated[index].corrections = events
    try persist(updated)
    sessions = updated
  }

  private func persist(_ updated: [TranscriptSession]) throws {
    try JSONEncoder().encode(updated).write(to: historyURL, options: .atomic)
  }

  private func purgeExpiredSessions() {
    let dictationCutoff = Date().addingTimeInterval(-dictationRetentionInterval)
    let fileCutoff = Date().addingTimeInterval(-fileTranscriptionRetentionInterval)

    let expired = sessions.filter { session in
      switch session.source ?? .voiceDictation {
      case .voiceDictation: return session.startTime < dictationCutoff
      case .fileTranscription, .ttsSynthesis: return session.startTime < fileCutoff
      }
    }
    expired.forEach { deleteOwnedRecording(for: $0) }
    sessions.removeAll { session in
      switch session.source ?? .voiceDictation {
      case .voiceDictation: return session.startTime < dictationCutoff
      case .fileTranscription, .ttsSynthesis: return session.startTime < fileCutoff
      }
    }
  }

  private func load() {
    do {
      let data = try Data(contentsOf: historyURL)
      let decoded = try JSONDecoder().decode([TranscriptSession].self, from: data)
      sessions = decoded
    } catch {
      if (error as NSError).code != NSFileReadNoSuchFileError {
        logger.error("Failed to load transcript history: \(error.localizedDescription)")
      }
      sessions = []
    }
  }

  private func save() {
    do {
      let data = try JSONEncoder().encode(sessions)
      try data.write(to: historyURL, options: [.atomic])
    } catch {
      logger.error("Failed to persist transcript history: \(error.localizedDescription)")
    }
    saveActivity()
  }

  private func updateActivity(for session: TranscriptSession) {
    let record = HistoryActivityRecord(session: session)
    if let index = activityRecords.firstIndex(where: { $0.id == session.id }) {
      activityRecords[index] = record
    } else {
      activityRecords.append(record)
    }
    pruneActivity()
  }

  private func pruneActivity() {
    let cutoff = HistoryActivity.rangeStart(now: Date(), calendar: .current)
    activityRecords.removeAll { $0.startTime < cutoff }
  }

  private func loadActivity() {
    do {
      activityRecords = try JSONDecoder().decode([HistoryActivityRecord].self, from: Data(contentsOf: activityURL))
    } catch {
      if (error as NSError).code != NSFileReadNoSuchFileError {
        logger.error("Failed to load history activity: \(error.localizedDescription)")
      }
    }
  }

  private func saveActivity() {
    do {
      let data = try JSONEncoder().encode(activityRecords.sorted { $0.startTime < $1.startTime })
      try data.write(to: activityURL, options: .atomic)
    } catch {
      logger.error("Failed to persist history activity: \(error.localizedDescription)")
    }
  }

  private static func makeHistoryURL() -> URL {
    historyBaseDirectory().appendingPathComponent("transcript-history.json")
  }

  /// Directory where auto-saved TTS audio files are stored.
  static func ttsAudioDirectory() -> URL {
    let dir = historyBaseDirectory().appendingPathComponent("tts-audio", isDirectory: true)
    if !FileManager.default.fileExists(atPath: dir.path) {
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    return dir
  }

  private static func historyBaseDirectory() -> URL {
    let fileManager = FileManager.default
    let directory = AppIdentity.current.applicationSupportDirectory(fileManager: fileManager)

    if !fileManager.fileExists(atPath: directory.path) {
      try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    return directory
  }

  /// Deletes owned audio recordings for dictation sessions and auto-saved TTS audio files.
  private func deleteOwnedRecording(for session: TranscriptSession) {
    let source = session.source ?? .voiceDictation
    switch source {
    case .voiceDictation:
      guard let url = session.recordingURL else { return }
      do {
        try FileManager.default.removeItem(at: url)
      } catch {
        logger.error("Failed to remove dictation recording: \(error.localizedDescription)")
      }
    case .ttsSynthesis:
      guard let bookmarkData = session.ttsAudioBookmark else { return }
      var isStale = false
      guard
        let url = try? URL(
          resolvingBookmarkData: bookmarkData,
          options: .withSecurityScope,
          relativeTo: nil,
          bookmarkDataIsStale: &isStale
        ), !isStale
      else { return }
      let needsStop = url.startAccessingSecurityScopedResource()
      defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
      do {
        try FileManager.default.removeItem(at: url)
      } catch {
        logger.error("Failed to remove TTS audio file: \(error.localizedDescription)")
      }
    case .fileTranscription:
      break
    }
  }
}
