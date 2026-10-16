import SwiftUI

struct HistoryActivityView: View {
  @Environment(\.colorScheme) private var colorScheme
  @State private var gridWidth: CGFloat = 0
  @State private var hoveredDay: HistoryActivity.Day?
  @State private var hoverLocation: CGPoint = .zero
  let records: [HistoryActivityRecord]

  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      let activity = HistoryActivity(records: records, now: context.date)
      VStack(alignment: .leading, spacing: 12) {
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .firstTextBaseline) {
            title
            Spacer(minLength: 16)
            summary(activity)
          }
          VStack(alignment: .leading, spacing: 4) {
            title
            summary(activity)
          }
        }

        activityGrid(activity)
          .overlay(alignment: .topLeading) {
            if let day = hoveredDay {
              VStack(alignment: .leading, spacing: 4) {
                Text(day.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
                  .font(.caption.weight(.semibold))
                Text(day.count == 1 ? String(localized: "1 record") : String(localized: "\(day.count) records"))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              .padding(10)
              .frame(width: 200, alignment: .leading)
              .background(AppSurface.contentBackground, in: RoundedRectangle(cornerRadius: 8))
              .overlay {
                RoundedRectangle(cornerRadius: 8)
                  .strokeBorder(AppSurface.border, lineWidth: 1)
              }
              .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
              .offset(
                x: min(max(0, hoverLocation.x - 100), max(0, gridWidth - 200)),
                y: hoverLocation.y + 14
              )
              .allowsHitTesting(false)
              .accessibilityHidden(true)
            }
          }
          .zIndex(1)

        HStack(alignment: .top, spacing: 12) {
          Text("Daily counts remain after transcripts expire.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
          legend
        }
      }
      .padding(16)
      .background(AppSurface.settingsBackground, in: RoundedRectangle(cornerRadius: 10))
    }
    .onDisappear { hoveredDay = nil }
  }

  private var title: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text("Activity")
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
      Text("Last 12 months")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private func summary(_ activity: HistoryActivity) -> some View {
    Text("\(activity.totalCount) records · \(activity.activeDayCount) active days")
      .font(.caption)
      .foregroundStyle(.secondary)
      .monospacedDigit()
  }

  private func activityGrid(_ activity: HistoryActivity) -> some View {
    GeometryReader { proxy in
      let gap: CGFloat = 3
      let labelWidth: CGFloat = 32
      let columns = CGFloat(activity.weeks.count)
      let cellSize = gridCellSize(width: proxy.size.width, columns: columns)
      HStack(alignment: .top, spacing: gap) {
        weekdayLabels(cellSize: cellSize, gap: gap)
          .frame(width: labelWidth - gap)
        ScrollView(.horizontal) {
          HStack(alignment: .top, spacing: gap) {
            ForEach(activity.weeks) { week in
              VStack(spacing: gap) {
                Color.clear
                  .frame(width: cellSize, height: 18)
                  .overlay(alignment: .leading) {
                    if let date = week.monthLabelDate {
                      Text(date, format: .dateTime.month(.abbreviated))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                        .accessibilityHidden(true)
                    }
                  }
                ForEach(week.days) { day in
                  cell(day, size: cellSize)
                }
              }
              .accessibilityElement(children: .contain)
            }
          }
          .padding(.trailing, 24) // Room for the final month's label.
          .padding(.bottom, 4)
          .frame(minWidth: max(0, proxy.size.width - labelWidth), alignment: .leading)
        }
        .defaultScrollAnchor(.trailing)
      }
    }
    .frame(height: 55 + 7 * gridCellSize(width: gridWidth, columns: CGFloat(activity.weeks.count)))
    .onGeometryChange(for: CGFloat.self) { proxy in
      proxy.size.width
    } action: { width in
      gridWidth = width
    }
    .onContinuousHover(coordinateSpace: .local) { phase in
      switch phase {
      case .active(let location): hoverLocation = location
      case .ended: hoveredDay = nil
      }
    }
  }

  private func gridCellSize(width: CGFloat, columns: CGFloat) -> CGFloat {
    // Keep square days readable, allowing modest growth within the bounded card.
    min(18, max(10, (width - 32 - columns * 3 - 24) / columns))
  }

  private func weekdayLabels(cellSize: CGFloat, gap: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: gap) {
      Color.clear.frame(height: 18)
      ForEach(1...7, id: \.self) { weekday in
        Text([2, 4, 6].contains(weekday) ? Calendar.current.shortWeekdaySymbols[weekday - 1] : "")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .frame(height: cellSize)
          .accessibilityHidden(true)
      }
    }
  }

  @ViewBuilder
  private func cell(_ day: HistoryActivity.Day, size: CGFloat) -> some View {
    if day.isInRange {
      let label = String(
        localized: "\(day.date.formatted(date: .complete, time: .omitted)): \(day.count) records",
        comment: "History activity: daily count tooltip and accessibility label")
      RoundedRectangle(cornerRadius: 2)
        .fill(color(for: day.intensity))
        .overlay {
          RoundedRectangle(cornerRadius: 2)
            .strokeBorder(
              hoveredDay?.id == day.id ? Color.accentColor : .primary.opacity(0.05),
              lineWidth: hoveredDay?.id == day.id ? 1.5 : 0.5
            )
        }
        .frame(width: size, height: size)
        .onHover { hovering in
          if hovering {
            hoveredDay = day
          } else if hoveredDay?.id == day.id {
            hoveredDay = nil
          }
        }
        .accessibilityLabel(label)
    } else {
      Color.clear
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
  }

  private var legend: some View {
    HStack(spacing: 4) {
      Text("Less")
      ForEach(0...4, id: \.self) { level in
        RoundedRectangle(cornerRadius: 2)
          .fill(color(for: level))
          .frame(width: 10, height: 10)
          .accessibilityHidden(true)
      }
      Text("More")
    }
    .font(.caption2)
    .foregroundStyle(.secondary)
    .fixedSize()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(String(localized: "More intense green means more records."))
  }

  private func color(for level: Int) -> Color {
    if colorScheme == .dark {
      switch level {
      case 0: return .primary.opacity(0.06)
      case 1: return Color(red: 0.05, green: 0.27, blue: 0.16)
      case 2: return Color(red: 0.00, green: 0.43, blue: 0.20)
      case 3: return Color(red: 0.15, green: 0.65, blue: 0.25)
      default: return Color(red: 0.22, green: 0.83, blue: 0.33)
      }
    }
    switch level {
    case 0: return .primary.opacity(0.06)
    case 1: return Color(red: 0.61, green: 0.84, blue: 0.65)
    case 2: return Color(red: 0.30, green: 0.69, blue: 0.40)
    case 3: return Color(red: 0.16, green: 0.53, blue: 0.28)
    default: return Color(red: 0.09, green: 0.37, blue: 0.20)
    }
  }
}

#Preview("History activity") {
  HistoryActivityView(records: (0..<180).map { index in
    HistoryActivityRecord(
      id: UUID(), startTime: Calendar.current.date(byAdding: .day, value: -(index * index % 365), to: Date())!,
      source: .voiceDictation)
  })
  .padding()
  .frame(width: 960)
}
