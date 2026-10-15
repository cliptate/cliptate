import SwiftUI

struct EditorSourceRow<Actions: View>: View {
  let url: URL
  let hasTranscription: Bool
  @ViewBuilder var actions: () -> Actions

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "video")
        .foregroundStyle(.secondary)
      Text(url.lastPathComponent)
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer(minLength: 4)
      if hasTranscription {
        Image(systemName: "checkmark.circle")
          .foregroundStyle(.secondary)
          .accessibilityLabel("Transcribed")
      }
      Menu(content: actions) {
        Image(systemName: "ellipsis")
      }
      .menuIndicator(.hidden)
      .menuStyle(.borderlessButton)
      .fixedSize()
      .help("Source")
    }
    .font(.callout)
    .padding(.vertical, 3)
    .help(url.lastPathComponent)
  }
}
