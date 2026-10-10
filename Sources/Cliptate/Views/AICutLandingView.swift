import SwiftUI

struct AICutLandingView: View {
  var onImportURLs: ([URL]) -> Void
  var onTap: () -> Void

  var body: some View {
    VStack(spacing: 24) {
      ZStack {
        Circle()
          .fill(Color.accentColor.opacity(0.1))
          .frame(width: 120, height: 120)

        Image(systemName: "video.fill")
          .font(.system(size: 48))
          .foregroundColor(.accentColor)
      }

      VStack(spacing: 12) {
        Text("Start Your Video Editing Journey")
          .font(.title2)
          .fontWeight(.semibold)
          .foregroundStyle(.primary)

        Text("Import one or more videos to transcribe, edit, and export.")
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }

      DropAreaView(
        title: String(localized: "Drop videos here or click to browse"),
        onDropURLs: onImportURLs,
        style: .hero,
        onTap: onTap
      )
      .frame(maxWidth: 680)

      VStack(spacing: 4) {
        Text("Supported Formats")
          .font(.caption)
          .fontWeight(.medium)
          .foregroundStyle(.secondary)

        Text("MP4, MOV, AVI, MKV and other common video formats")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 8)
      .background(.thinMaterial, in: Capsule())
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(32)
    .background(.regularMaterial)
  }
}
