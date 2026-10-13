import SwiftUI

struct AICutLandingView: View {
  var onImportURLs: ([URL]) -> Void
  var onTap: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      DropAreaView(
        title: String(localized: "Drop videos here"),
        onDropURLs: onImportURLs,
        style: .hero,
        onTap: onTap
      )
      .frame(maxWidth: 680)

      Text("Supports MP4, MOV, AVI, MKV and more")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
    .padding(28)
  }
}
