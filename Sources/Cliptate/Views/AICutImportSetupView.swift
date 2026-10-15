import CliptateCore
import SwiftUI

struct AICutImportSetupView: View {
  let urls: [URL]
  @Binding var language: Language
  var onRemove: (URL) -> Void
  var onCancel: () -> Void
  var onStart: () -> Void
  var contextProvider: () -> ModelLanguageContext

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 8) {
        Text("Prepare Import")
          .font(.title2)
          .fontWeight(.semibold)

        Text("Review the files in this batch and choose the transcription language before starting.")
          .foregroundStyle(.secondary)
      }

      ScrollView {
        VStack(spacing: 10) {
          ForEach(urls, id: \.self) { url in
            HStack(spacing: 12) {
              Image(systemName: "film")
                .foregroundColor(.accentColor)

              VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                  .fontWeight(.medium)
                  .lineLimit(1)
                Text(url.path)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }

              Spacer()

              Button(role: .destructive) {
                onRemove(url)
              } label: {
                Image(systemName: "trash")
              }
              .buttonStyle(.borderless)
            }
            .padding(12)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
          }
        }
      }
      .frame(minHeight: 180)

      ModelAwareLanguageSelectionView(
        title: String(localized: "Transcription Language", comment: "Label for selecting transcription language"),
        selectedLanguage: $language,
        contextProvider: contextProvider,
        helpText: String(localized: "This selection applies to every file in the batch.", comment: "Help text for transcription language")
      )

      HStack {
        Button("Cancel", role: .cancel) {
          onCancel()
        }

        Spacer()

        Button("Start Transcription") {
          onStart()
        }
        .buttonStyle(.borderedProminent)
        .disabled(urls.isEmpty)
      }
    }
    .padding(24)
    .frame(minWidth: 520, idealWidth: 560, minHeight: 420)
  }
}
