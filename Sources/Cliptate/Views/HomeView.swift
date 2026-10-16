import CliptateCore
import SwiftUI

struct HomeView: View {
  @EnvironmentObject private var config: AppConfiguration
  @ObservedObject private var historyRuntime = HistoryRuntime.shared
  @State private var contentWidth: CGFloat = 0

  private var summaryColumns: [GridItem] {
    let count = contentWidth >= 744 ? 3 : (contentWidth >= 492 ? 2 : 1)
    return Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: count)
  }

  private var usage: VoiceUsageStats {
    VoiceUsageStats(
      totalDuration: config.voiceToTextUsageTotalDuration,
      sessionCount: config.voiceToTextUsageSessionCount,
      totalCharacters: config.voiceToTextUsageTotalCharacters,
      totalWords: config.voiceToTextUsageTotalWords
    )
  }

  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      let activity = HistoryActivity(records: historyRuntime.activityRecords, now: context.date)
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          VStack(alignment: .leading, spacing: 12) {
            Text("All-time dictation")
              .font(.headline)
              .accessibilityAddTraits(.isHeader)
            usageOverview
          }

          HistoryActivityView(records: historyRuntime.activityRecords)

          VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
              Text("Records by source")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
              Spacer()
              Text("Last 12 months")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: summaryColumns, spacing: 12) {
              sourceCount("Voice Dictation", icon: "mic", count: activity.recordCount(for: .voiceDictation))
              sourceCount("File Transcription", icon: "doc.text", count: activity.recordCount(for: .fileTranscription))
              sourceCount("Voice Generation", icon: "waveform", count: activity.recordCount(for: .ttsSynthesis))
            }
          }
        }
        .frame(maxWidth: 1040, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { proxy in
          proxy.size.width
        } action: { contentWidth = $0 }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .topLeading)
      }
    }
    .background(AppSurface.contentBackground)
    .appPageHeader {
      AppPageHeader(.home, background: AppSurface.contentBackground)
    }
  }

  private var usageOverview: some View {
    let stats = usage
    return LazyVGrid(columns: summaryColumns, spacing: 12) {
      metric(
        "Total Voice Input", icon: "mic", value: duration(stats.totalDuration),
        detail: String(localized: "\(stats.sessionCount.formatted()) sessions"))
      metric(
        "Generated Text", icon: "text.alignleft", value: String(localized: "\(stats.totalWords.formatted()) words"),
        detail: stats.averageWordsPerMinute > 0
          ? String(localized: "Avg. ~\(Int(stats.averageWordsPerMinute.rounded()).formatted()) words/min")
          : String(localized: "Avg. speed pending"))
      metric(
        "Time Saved", icon: "clock", value: duration(stats.savedSeconds),
        detail: String(localized: "Estimated 20 words/min composition typing"))
    }
  }

  private func metric(_ title: LocalizedStringKey, icon: String, value: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(title, systemImage: icon)
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
      Text(value)
        .font(.title.weight(.semibold))
        .monospacedDigit()
      Text(detail)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(16)
    .background(AppSurface.settingsBackground, in: RoundedRectangle(cornerRadius: 10))
    .accessibilityElement(children: .combine)
  }

  private func sourceCount(_ title: LocalizedStringKey, icon: String, count: Int) -> some View {
    HStack(spacing: 12) {
      Label(title, systemImage: icon)
        .foregroundStyle(.secondary)
      Spacer(minLength: 8)
      Text(count, format: .number)
        .font(.title2.weight(.semibold))
        .monospacedDigit()
    }
    .padding(16)
    .background(AppSurface.settingsBackground, in: RoundedRectangle(cornerRadius: 10))
    .accessibilityElement(children: .combine)
  }

  private func duration(_ seconds: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.unitsStyle = .abbreviated
    formatter.maximumUnitCount = 2
    return formatter.string(from: max(0, seconds)) ?? String(localized: "0 seconds")
  }
}
