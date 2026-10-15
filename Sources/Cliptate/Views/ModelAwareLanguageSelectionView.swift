import CliptateCore
import SwiftUI

struct ModelAwareLanguageSelectionView: View {
  let title: String
  @Binding var selectedLanguage: Language
  let contextProvider: () -> ModelLanguageContext
  var helpText: String? = nil

  @State private var availableLanguages: [Language] = []
  @State private var isLoadingLanguages = false
  @State private var automaticChangeNotice: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(title)
          .font(.caption)
          .foregroundStyle(.secondary)
        if isLoadingLanguages {
          ProgressView()
            .controlSize(.small)
        }
      }

      Picker(title, selection: $selectedLanguage) {
        ForEach(availableLanguages, id: \.self) { language in
          Text(language.displayName).tag(language)
        }
      }
      .pickerStyle(.menu)
      .disabled(availableLanguages.isEmpty)

      if let helpText {
        Text(helpText)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      if let automaticChangeNotice {
        Label(automaticChangeNotice, systemImage: "info.circle")
          .font(.caption2)
          .foregroundStyle(.orange)
      }
    }
    .task(id: contextIdentity) {
      await refreshLanguages()
    }
  }

  private var contextIdentity: String {
    switch contextProvider() {
    case .asr(let type, let model):
      return "asr:\(type.rawValue):\(model.rawValue)"
    case .align(let model):
      return "align:\(model.rawValue)"
    case .tts(let engine, let modelID):
      return "tts:\(engine.rawValue):\(modelID ?? "default")"
    }
  }

  private func refreshLanguages() async {
    await MainActor.run {
      isLoadingLanguages = true
    }

    let context = contextProvider()
    let supportedLanguages = await ModelCacheManager.shared.filteredLanguages(for: context)
    let autoLanguages = supportedLanguages.filter { $0.isAuto }
    let rest = supportedLanguages.filter { !$0.isAuto }.sorted { $0.displayName < $1.displayName }
    let sorted = autoLanguages + rest

    await MainActor.run {
      availableLanguages = sorted
      isLoadingLanguages = false

      guard !sorted.isEmpty else { return }
      guard !sorted.contains(selectedLanguage) else {
        automaticChangeNotice = nil
        return
      }

      let previous = selectedLanguage
      let fallback = sorted.first ?? previous
      selectedLanguage = fallback
      automaticChangeNotice =
        "Language changed automatically from \(previous.displayName) to \(fallback.displayName)."
    }
  }
}
