import CliptateCore
import SwiftUI

struct AICutProgressView: View {
  let presentation: AICutProgressPresentation
  let batch: AICutBatchContext?
  let modelDownloadProgress: ModelDownloadProgress?
  let isInitializingModel: Bool
  var onCancel: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 8) {
        Text(presentation.title)
          .font(.title2)
          .fontWeight(.semibold)
        Text(presentation.detail)
          .foregroundStyle(.secondary)

        if let currentFileName = presentation.currentFileName, currentFileName != presentation.detail {
          Label(currentFileName, systemImage: "doc.text")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      // Single unified progress bar
      VStack(alignment: .leading, spacing: 6) {
        StyledProgressBar(value: presentation.displayFraction)
      }

      if let batch, !batch.items.isEmpty {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(batch.items) { item in
            HStack(spacing: 10) {
              Image(systemName: icon(for: item.status))
                .foregroundStyle(color(for: item.status))
              Text(item.url.lastPathComponent)
                .lineLimit(1)
              Spacer()
              Text(label(for: item.status))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
        .padding(16)
        .background(AppSurface.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      }

      HStack {
        Spacer()
        Button("Cancel") {
          onCancel()
        }
      }
    }
    .padding(24)
    .frame(minWidth: 420, idealWidth: 460)
    .background(AppSurface.pageBackground)
  }

  private func label(for status: AICutBatchItem.Status) -> String {
    switch status {
    case .pending:
      return String(localized: "Waiting", comment: "Batch item status: waiting to start")
    case .running:
      return String(localized: "Processing", comment: "Batch item status: in progress")
    case .succeeded:
      return String(localized: "Done", comment: "Batch item status: completed successfully")
    case .failed:
      return String(localized: "Failed", comment: "Batch item status: completed with error")
    }
  }

  private func icon(for status: AICutBatchItem.Status) -> String {
    switch status {
    case .pending:
      return "circle.dashed"
    case .running:
      return "waveform.circle.fill"
    case .succeeded:
      return "checkmark.circle.fill"
    case .failed:
      return "xmark.octagon.fill"
    }
  }

  private func color(for status: AICutBatchItem.Status) -> Color {
    switch status {
    case .pending:
      return .secondary
    case .running:
      return .accentColor
    case .succeeded:
      return .green
    case .failed:
      return .red
    }
  }
}

// MARK: - Styled Progress Bar

private struct StyledProgressBar: View {
  let value: Double

  private let barHeight: CGFloat = 8

  var body: some View {
    HStack(spacing: 10) {
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule()
            .fill(AppSurface.subtleFill)

          Capsule()
            .fill(Color.accentColor)
            .frame(width: max(geo.size.width * CGFloat(value), 0))
            .animation(.easeInOut(duration: 0.3), value: value)
        }
      }
      .frame(height: barHeight)
      .clipShape(Capsule())

      Text("\(Int(value * 100))%")
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(width: 36, alignment: .trailing)
    }
    .accessibilityValue("\(Int(value * 100)) percent")
  }
}
