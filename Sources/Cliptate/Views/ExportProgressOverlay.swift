import SwiftUI

/// A floating overlay that shows real-time export progress for each phase.
struct ExportProgressOverlay: View {
  let exportProgress: ExportProgressState
  var onDismiss: (() -> Void)? = nil

  var body: some View {
    if exportProgress.isActive || hasRecentResults {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Image(systemName: "square.and.arrow.up")
            .font(.system(size: 14, weight: .semibold))
          Text("Exporting")
            .font(.headline)
          Spacer()
          if exportProgress.isActive {
            ProgressView()
              .controlSize(.small)
          } else if allCompleted {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(.green)
          } else if hasRecentResults {
            Image(systemName: "exclamationmark.circle.fill")
              .foregroundStyle(.orange)
          }
          if !exportProgress.isActive && hasRecentResults {
            Button {
              onDismiss?()
            } label: {
              Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Dismiss", comment: "Export progress overlay dismiss button tooltip"))
          }
        }

        // Overall progress
        VStack(alignment: .leading, spacing: 4) {
          ProgressView(value: exportProgress.overallProgress)
            .tint(.accentColor)
          Text(overallLabel)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Divider()

        // Per-phase progress rows
        ForEach(exportProgress.phases) { phase in
          ExportPhaseRow(phase: phase)
        }
      }
      .padding(16)
      .frame(width: 320)
      .background(.ultraThinMaterial)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .strokeBorder(.separator.opacity(0.3), lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
      .transition(.opacity.combined(with: .move(edge: .bottom)))
      .animation(.easeInOut(duration: 0.3), value: exportProgress)
    }
  }

  private var allCompleted: Bool {
    !exportProgress.phases.isEmpty
      && exportProgress.phases.allSatisfy { $0.status == .completed }
  }

  private var hasRecentResults: Bool {
    !exportProgress.phases.isEmpty
      && exportProgress.phases.allSatisfy { $0.status == .completed || $0.status == .failed }
  }

  private var overallLabel: String {
    let pct = Int(exportProgress.overallProgress * 100)
    if let current = exportProgress.currentPhaseLabel {
      return String(localized: "\(pct)% · \(current)", comment: "Export progress: percentage and current phase label")
    }
    if allCompleted {
      return String(localized: "Export completed", comment: "Export progress: all phases finished")
    }
    return "\(pct)%"
  }
}

/// A single row showing progress for one export phase.
private struct ExportPhaseRow: View {
  let phase: ExportPhase

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: phase.type.iconName)
        .font(.system(size: 13))
        .foregroundStyle(iconColor)
        .frame(width: 20)

      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Text(phase.type.displayName)
            .font(.subheadline.weight(.medium))
          Spacer()
          statusBadge
        }

        if phase.status == .inProgress {
          ProgressView(value: phase.progress)
            .tint(.accentColor)
        } else if phase.status == .failed, let msg = phase.failureMessage {
          Text(msg)
            .font(.caption2)
            .foregroundStyle(.red)
            .lineLimit(2)
        }
      }
    }
    .padding(.vertical, 2)
  }

  @ViewBuilder
  private var statusBadge: some View {
    switch phase.status {
    case .pending:
      Text("Pending")
        .font(.caption2)
        .foregroundStyle(.secondary)
    case .inProgress:
      Text("\(Int(phase.progress * 100))%")
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    case .completed:
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 12))
        .foregroundStyle(.green)
    case .failed:
      Image(systemName: "xmark.circle.fill")
        .font(.system(size: 12))
        .foregroundStyle(.red)
    }
  }

  private var iconColor: Color {
    switch phase.status {
    case .completed: return .green
    case .failed: return .red
    case .inProgress: return .accentColor
    case .pending: return .secondary
    }
  }
}
