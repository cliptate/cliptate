import CliptateCore
import SwiftUI

struct EditorTranscriptionOptions: View {
  @EnvironmentObject private var config: AppConfiguration

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Transcription model selection is managed from the Models page.")
        .font(.caption2)
        .foregroundColor(.secondary)

      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("\(config.transcriberType.displayName) • \(config.modelVariant.displayName)")
            .font(.subheadline.weight(.medium))
          Spacer()
          Button {
            NotificationCenter.default.post(name: .openModelsLibrary, object: nil)
          } label: {
            Label("Open Models", systemImage: "square.and.arrow.up")
              .font(.caption)
          }
          .buttonStyle(.bordered)
          .accessibilityLabel("Open Models page")
        }

        Text("Language: \(config.language.displayName)")
          .font(.caption)
          .foregroundColor(.secondary)

        if let alignModel = config.alignModelVariant {
          Text("Align model: \(alignModel.displayName)")
            .font(.caption)
            .foregroundColor(.secondary)
        } else {
          Text(
            "Align model: \(String(localized: "Disabled", comment: "Align model state when not selected"))"
          )
          .font(.caption)
          .foregroundColor(.secondary)
        }
      }
      .padding(10)
      .background(
        AppSurface.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )

      ModelAwareLanguageSelectionView(
        title: String(localized: "Transcription Language", comment: "Label for selecting transcription language"),
        selectedLanguage: $config.language,
        contextProvider: {
          .asr(type: config.transcriberType, model: config.modelVariant)
        },
        helpText: String(localized: "Available languages are filtered by the active ASR model.", comment: "Help text for transcription language")
      )
    }
  }
}

struct EditorTranslationOptions: View {
  @EnvironmentObject private var config: AppConfiguration

  var body: some View {
    VStack(spacing: 12) {
      Text("Configure source and target languages for translation, plus subtitle placement.")
        .font(.caption2)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Source Language")
            .font(.caption)
            .foregroundColor(.secondary)

          Picker("Source Language", selection: $config.translationSourceLanguage) {
            ForEach(Language.translationSupported) { language in
              Text(language.displayName).tag(language)
            }
          }
          .pickerStyle(.menu)
        }
        .padding(8)
        .background(
          AppSurface.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )

        VStack(alignment: .leading, spacing: 8) {
          Text("Target Language")
            .font(.caption)
            .foregroundColor(.secondary)

          Picker("Target Language", selection: $config.translationTargetLanguage) {
            ForEach(Language.translationSupported) { language in
              Text(language.displayName).tag(language)
            }
          }
          .pickerStyle(.menu)
        }
        .padding(8)
        .background(
          AppSurface.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
      }

      VStack(alignment: .leading, spacing: 8) {
        Text("Placement")
          .font(.caption)
          .foregroundColor(.secondary)

        Picker("Placement", selection: $config.translationPlacement) {
          ForEach(SubtitleTranslationPlacement.allCases) { placement in
            Text(placement.displayName).tag(placement)
          }
        }
        .pickerStyle(.segmented)
      }
      .padding(8)
      .background(
        AppSurface.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )

      Text("Translations appear when enabled during export or playback overlays.")
        .font(.caption2)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
