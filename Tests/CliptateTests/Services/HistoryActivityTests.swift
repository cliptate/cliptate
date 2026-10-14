import Foundation
import Testing

@testable import Cliptate

@Suite("History activity")
struct HistoryActivityTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return calendar
  }

  private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
  }

  @Test("The rolling year includes leap day, excludes future dates, and aligns Sunday rows")
  func rollingYear() {
    let today = date(2024, 3, 2)
    let activity = HistoryActivity(
      records: [
        HistoryActivityRecord(id: UUID(), startTime: date(2023, 3, 2), source: .voiceDictation),
        HistoryActivityRecord(id: UUID(), startTime: date(2023, 3, 3), source: .fileTranscription),
        HistoryActivityRecord(id: UUID(), startTime: date(2024, 2, 29), source: .ttsSynthesis),
        HistoryActivityRecord(id: UUID(), startTime: date(2024, 3, 3), source: .voiceDictation),
      ], now: today, calendar: calendar)

    #expect(activity.totalCount == 2)
    #expect(activity.activeDayCount == 2)
    #expect(activity.weeks.allSatisfy { $0.days.count == 7 })
    #expect(activity.weeks.allSatisfy { calendar.component(.weekday, from: $0.id) == 1 })
    let days = activity.weeks.flatMap(\.days).filter(\.isInRange)
    #expect(days.count == 366)
    #expect(days.first?.date == calendar.startOfDay(for: date(2023, 3, 3)))
    #expect(days.last?.date == calendar.startOfDay(for: today))
    #expect(days.first(where: { calendar.isDate($0.date, inSameDayAs: date(2024, 2, 29)) })?.count == 1)
  }

  @Test("Records group by local calendar day across daylight saving")
  func localDays() {
    let records = [1, 3, 23].map { hour in
      HistoryActivityRecord(id: UUID(), startTime: date(2024, 3, 10, hour: hour), source: .voiceDictation)
    }
    let activity = HistoryActivity(records: records, now: date(2024, 3, 11), calendar: calendar)
    #expect(activity.totalCount == 3)
    #expect(activity.activeDayCount == 1)
    #expect(activity.weeks.flatMap(\.days).first(where: { $0.count > 0 })?.count == 3)
  }

  @Test("Empty years have no activity and intensity increases with record count")
  func emptyAndIntensity() {
    let activity = HistoryActivity(records: [], now: date(2026, 10, 14), calendar: calendar)
    #expect(activity.totalCount == 0)
    #expect(activity.activeDayCount == 0)
    #expect([0, 1, 3, 6, 10, 100].map(HistoryActivity.intensity) == [0, 1, 2, 3, 4, 4])
  }

  @Test("Activity survives transcript expiry and reload without double-counting edits")
  @MainActor
  func persistsBeyondRetention() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("history.json")
    let store = TranscriptHistoryStore(historyURL: url)
    var session = TranscriptSession(startTime: Date().addingTimeInterval(-3 * 86_400))
    session.append(text: "Old dictation", at: 0)
    store.add(session)
    #expect(store.sessions.isEmpty)
    #expect(store.activityRecords.count == 1)
    store.add(session)
    #expect(store.activityRecords.count == 1)

    let reloaded = TranscriptHistoryStore(historyURL: url)
    #expect(reloaded.sessions.isEmpty)
    #expect(reloaded.activityRecords.first?.id == session.id)
    reloaded.removeAll(source: .voiceDictation)
    #expect(TranscriptHistoryStore(historyURL: url).activityRecords.isEmpty)
  }

  @Test("Legacy history seeds activity before expiry; deleting records updates persisted totals")
  @MainActor
  func migrationAndDeletion() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("history.json")
    var expired = TranscriptSession(startTime: Date().addingTimeInterval(-3 * 86_400))
    expired.append(text: "Expired dictation", at: 0)
    var retained = TranscriptSession(startTime: Date(), source: .fileTranscription)
    retained.append(text: "File transcript", at: 0)
    var tooOld = TranscriptSession(startTime: Date().addingTimeInterval(-400 * 86_400))
    tooOld.append(text: "Too old", at: 0)
    try JSONEncoder().encode([expired, retained, tooOld]).write(to: url)

    let store = TranscriptHistoryStore(historyURL: url)
    #expect(store.sessions.map(\.id) == [retained.id])
    #expect(Set(store.activityRecords.map(\.id)) == [expired.id, retained.id])
    retained.append(text: "Edited", at: 1)
    store.replace(retained)
    #expect(store.activityRecords.count == 2)
    store.remove(id: retained.id)
    #expect(TranscriptHistoryStore(historyURL: url).activityRecords.map(\.id) == [expired.id])
    store.removeAll()
    #expect(TranscriptHistoryStore(historyURL: url).activityRecords.isEmpty)
  }
}
