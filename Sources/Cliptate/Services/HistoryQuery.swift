import CryptoKit
import Foundation
#if canImport(CliptateCLIKit)
  import CliptateCLIKit
#endif

/// Pure projection and pagination of retained sessions. No inference or file access.
enum HistoryQuery {
  private struct Cursor: Codable {
    let filters: String
    let snapshot: String?
    let time: Double
    let id: String
  }

  private struct Row {
    let time: Double
    let id: String
    var session: CLIHistorySession?
    var line: CLIHistoryLine?
    var correction: CLIHistoryCorrection?
  }

  static func page(
    _ query: CLIHistoryQuery, sessions: [TranscriptSession], now: Date = Date(),
    maximumBytes: Int = 8 * 1024 * 1024
  ) throws -> CLIHistoryPage {
    try query.validate()
    let retained = sessions.filter { session in
      let source = session.source ?? .voiceDictation
      let retention: TimeInterval = source == .voiceDictation ? 86_400 : 2_592_000
      return session.startTime >= now.addingTimeInterval(-retention)
        && (query.source == nil || query.source == source.rawValue)
        && (query.sessionID == nil || UUID(uuidString: query.sessionID!) == session.id)
    }.sorted { $0.startTime == $1.startTime ? $0.id.uuidString > $1.id.uuidString : $0.startTime > $1.startTime }
    let since = query.since.flatMap(CLIHistoryQuery.date)
    let until = query.until.flatMap(CLIHistoryQuery.date)
    func inRange(_ date: Date) -> Bool {
      (since == nil || date >= since!) && (until == nil || date <= until!)
    }
    func matches(_ text: String) -> Bool {
      query.search.map { text.localizedStandardContains($0) } ?? true
    }
    var rows: [Row] = []
    var result = CLIHistoryPage()
    switch query.action {
    case .list:
      rows = retained.filter {
        inRange($0.startTime) && (!query.correctionsOnly || !($0.corrections ?? []).isEmpty)
          && matches($0.combinedText + "\n" + ($0.sourceFileName ?? "") + "\n"
            + ($0.corrections ?? []).map { $0.original + "\n" + $0.corrected }.joined(separator: "\n"))
      }.map { Row(time: $0.startTime.timeIntervalSince1970, id: $0.id.uuidString, session: summary($0)) }
    case .corrections:
      var events: [UUID: (TranscriptSession, TranscriptCorrection)] = [:]
      for session in retained {
        for event in session.corrections ?? [] {
          // Shared dictation evidence is emitted once. Any later non-applied status wins.
          if let existing = events[event.id], existing.1.status != .applied { continue }
          events[event.id] = (session, event)
        }
      }
      rows = events.values.filter { session, event in
        inRange(event.recordedAt) && matches([
          event.original, event.corrected, event.originalContext, event.correctedContext,
          session.sourceFileName ?? "",
        ].joined(separator: "\n"))
      }.map { session, event in
        Row(time: event.recordedAt.timeIntervalSince1970, id: event.id.uuidString,
          correction: correction(event, session: session))
      }
    case .show:
      guard let session = retained.first else {
        throw CLIError(String(localized: "History session was not found or has expired."))
      }
      result.sessions = [summary(session)]
      rows = session.lines.map {
        Row(time: 0, id: $0.id.uuidString,
          line: CLIHistoryLine(id: $0.id.uuidString, timestamp: $0.timestamp, text: $0.text, speakerId: $0.speakerId))
      }
      rows += (session.corrections ?? []).map {
        Row(time: 0, id: $0.id.uuidString, correction: correction($0, session: session))
      }
      rows = rows.enumerated().map { index, row in
        Row(time: -Double(index), id: row.id, line: row.line, correction: row.correction)
      }
    }
    rows.sort { $0.time == $1.time ? $0.id > $1.id : $0.time > $1.time }
    var normalized = query
    normalized.cursor = nil
    normalized.limit = 50
    let filters = digest(try stableEncoding(normalized))
    // Show cursors are tied to the text snapshot: editing during pagination requires a restart.
    let snapshot: String?
    if query.action == .show {
      var full = result
      for row in rows { append(row, to: &full) }
      snapshot = digest(try stableEncoding(full))
    } else { snapshot = nil }
    if let raw = query.cursor {
      guard let data = Data(base64Encoded: raw),
        let cursor = try? JSONDecoder().decode(Cursor.self, from: data),
        cursor.filters == filters, cursor.snapshot == snapshot, cursor.time.isFinite
      else { throw CLIHistoryQuery.invalidArguments() }
      rows.removeAll { $0.time > cursor.time || ($0.time == cursor.time && $0.id >= cursor.id) }
    }
    var consumed = 0
    for row in rows.prefix(query.limit) {
      var candidate = result
      append(row, to: &candidate)
      if try JSONEncoder().encode(candidate).count > maximumBytes {
        guard consumed > 0 else {
          throw CLIError(String(localized: "A history record exceeds the CLI response size limit."))
        }
        break
      }
      result = candidate
      consumed += 1
    }
    if consumed < rows.count, let last = rows.prefix(consumed).last {
      result.nextCursor = try JSONEncoder().encode(Cursor(
        filters: filters, snapshot: snapshot, time: last.time, id: last.id)).base64EncodedString()
    }
    return result
  }

  private static func append(_ row: Row, to page: inout CLIHistoryPage) {
    if let value = row.session { page.sessions.append(value) }
    if let value = row.line { page.lines.append(value) }
    if let value = row.correction { page.corrections.append(value) }
  }

  private static func stableEncoding<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
  }

  private static func digest(_ data: Data) -> String {
    Data(SHA256.hash(data: data)).base64EncodedString()
  }

  static func date(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  private static func summary(_ session: TranscriptSession) -> CLIHistorySession {
    CLIHistorySession(id: session.id.uuidString, startTime: date(session.startTime),
      endTime: session.endTime.map(date), source: (session.source ?? .voiceDictation).rawValue,
      sourceFileName: session.sourceFileName, language: session.language?.rawValue,
      model: session.modelVariant?.rawValue, lineCount: session.lines.count,
      correctionCount: session.corrections?.count ?? 0, preview: String(session.combinedText.prefix(160)))
  }

  private static func correction(
    _ event: TranscriptCorrection, session: TranscriptSession
  ) -> CLIHistoryCorrection {
    CLIHistoryCorrection(id: event.id.uuidString, batchID: event.batchID.uuidString,
      sessionID: session.id.uuidString, relatedSessionIDs: event.relatedSessionIDs.map(\.uuidString),
      source: (session.source ?? .voiceDictation).rawValue, sourceFileName: session.sourceFileName,
      recordedAt: date(event.recordedAt), kind: event.kind.rawValue, status: event.status.rawValue,
      statusChangedAt: event.statusChangedAt.map(date), original: event.original, corrected: event.corrected,
      originalContext: event.originalContext, correctedContext: event.correctedContext,
      targetID: event.targetID, timestamp: event.timestamp, provider: event.provider,
      model: event.model, language: event.language)
  }
}
