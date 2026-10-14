import Foundation

/// Minimal activity metadata, independent of transcript and audio retention.
struct HistoryActivityRecord: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let startTime: Date
  let source: SessionSource

  init(id: UUID, startTime: Date, source: SessionSource) {
    self.id = id
    self.startTime = startTime
    self.source = source
  }

  init(session: TranscriptSession) {
    self.init(id: session.id, startTime: session.startTime, source: session.source ?? .voiceDictation)
  }
}

/// Calendar-day projection for a GitHub-style rolling-year activity grid.
struct HistoryActivity {
  struct Day: Identifiable {
    var id: Date { date }
    let date: Date
    let count: Int
    let isInRange: Bool
    var intensity: Int { HistoryActivity.intensity(count) }
  }

  struct Week: Identifiable {
    let id: Date
    let days: [Day]
    let monthLabelDate: Date?
  }

  let weeks: [Week]
  let totalCount: Int
  let activeDayCount: Int

  static func rangeStart(now: Date, calendar: Calendar) -> Date {
    let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
    return calendar.date(byAdding: .year, value: -1, to: tomorrow)!
  }

  init(records: [HistoryActivityRecord], now: Date = Date(), calendar: Calendar = .current) {
    let today = calendar.startOfDay(for: now)
    let start = Self.rangeStart(now: now, calendar: calendar)
    let counts = Dictionary(grouping: records.filter {
      $0.startTime >= start && calendar.startOfDay(for: $0.startTime) <= today
    }, by: { calendar.startOfDay(for: $0.startTime) }).mapValues(\.count)
    totalCount = counts.values.reduce(0, +)
    activeDayCount = counts.count

    // Sunday at the top, matching the reference regardless of locale's first weekday.
    let leadingDays = calendar.component(.weekday, from: start) - 1
    var weekStart = calendar.date(byAdding: .day, value: -leadingDays, to: start)!
    var result: [Week] = []
    while weekStart <= today {
      let days = (0..<7).map { offset in
        let date = calendar.date(byAdding: .day, value: offset, to: weekStart)!
        return Day(date: date, count: counts[date, default: 0], isInRange: date >= start && date <= today)
      }
      let visibleDays = days.filter(\.isInRange)
      let monthDate = result.isEmpty
        ? visibleDays.first?.date
        : visibleDays.first(where: { calendar.component(.day, from: $0.date) == 1 })?.date
      result.append(Week(id: weekStart, days: days, monthLabelDate: monthDate))
      weekStart = calendar.date(byAdding: .day, value: 7, to: weekStart)!
    }
    weeks = result
  }

  static func intensity(_ count: Int) -> Int {
    switch count {
    case ...0: return 0
    case 1...2: return 1
    case 3...5: return 2
    case 6...9: return 3
    default: return 4
    }
  }
}
