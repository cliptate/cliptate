import SwiftUI

struct StatusView: View {
  var statusText: String
  var modelDownloadProgress: ModelDownloadProgress?
  var isInitializingModel: Bool
  var batchTranscriptionProgress: (current: Int, total: Int)?
  var onDismiss: (() -> Void)? = nil
  var onShow: (() -> Void)? = nil
  var isVisible: Bool = true

  var body: some View {
    Group {
      if isVisible {
        VStack(alignment: .leading, spacing: 12) {
          HStack(spacing: 8) {
            Label("Status", systemImage: "text.bubble")
              .font(.headline)
              .foregroundStyle(.primary)

            Spacer()

            if let onDismiss {
              Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                  .foregroundStyle(.secondary)
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Hide status")
            }
          }

          Text(statusText)
            .font(.callout)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)

          if let batchProgress = batchTranscriptionProgress {
            VStack(spacing: 8) {
              ProgressView(value: Double(batchProgress.current), total: Double(batchProgress.total))
                .progressViewStyle(.linear)

              HStack {
                Text("File \(batchProgress.current) of \(batchProgress.total)")
                  .font(.caption)
                  .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(Double(batchProgress.current) / Double(batchProgress.total) * 100))%")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            }
          } else if isInitializingModel, let progress = modelDownloadProgress {
            VStack(spacing: 8) {
              ProgressView(value: progress.progress)
                .progressViewStyle(.linear)

              HStack {
                Text("\(Int(progress.progress * 100))%")
                  .font(.caption)
                  .foregroundStyle(.secondary)

                Spacer()

                if progress.maxAttempts > 1 {
                  Text("Attempt \(progress.attemptNumber)/\(progress.maxAttempts)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }

              if let estimatedTime = progress.estimatedTimeRemaining, estimatedTime > 0 {
                let minutes = Int(estimatedTime) / 60
                let seconds = Int(estimatedTime) % 60
                Text("ETA: \(minutes)m \(seconds)s")
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      } else if let onShow {
        Button(action: onShow) {
          Label("Show Status", systemImage: "text.bubble")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderless)
      }
    }
  }
}
