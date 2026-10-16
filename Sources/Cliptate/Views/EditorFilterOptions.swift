import CliptateCore
import SwiftUI

struct EditorFilterOptions: View {
  @EnvironmentObject private var config: AppConfiguration
  @State private var fillerWordsDraft = ""
  @FocusState private var isFillerWordEditorFocused: Bool

  var body: some View {
    let filterPunctuationBinding = Binding<Bool>(
      get: { !config.keepPunctuationOnExport },
      set: { config.keepPunctuationOnExport = !$0 }
    )

    return VStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 8) {
        Toggle(isOn: $config.effectFilterFillerWords) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Filter Filler Words")
              .font(.caption)
            Text("Remove speech fillers (e.g., uh, um, 嗯) from highlight analysis and keywords.")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
        .appFeatureSwitch()
      }
      .padding(8)
      .background(
        AppSurface.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )

      VStack(alignment: .leading, spacing: 6) {
        Toggle(isOn: filterPunctuationBinding) {
          VStack(alignment: .leading, spacing: 2) {
            Text("Filter punctuation")
              .font(.caption)
            Text("Only applied during export. When on, punctuation is removed in exported text.")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
        .appFeatureSwitch()
      }
      .padding(8)
      .background(
        AppSurface.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )

      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text("Filler Word List")
            .font(.caption)
          Spacer()
          Button("Reset") {
            config.effectFillerWords = SegmentEffectConfiguration.defaultFillerWords
            syncFillerWordsDraftFromConfig()
          }
          .buttonStyle(.borderless)
          .font(.caption2)
        }

        TextEditor(text: $fillerWordsDraft)
          .frame(minHeight: 76, idealHeight: 96)
          .font(.caption)
          .focused($isFillerWordEditorFocused)
          .padding(6)
          .scrollContentBackground(.hidden)
          .appInputSurface(isFocused: isFillerWordEditorFocused)
          .onAppear {
            syncFillerWordsDraftFromConfig()
          }
          .onChange(of: isFillerWordEditorFocused) { wasFocused, isFocused in
            if wasFocused && !isFocused {
              commitFillerWordsDraft()
            }
          }
          .onDisappear {
            commitFillerWordsDraft()
          }

        Text("Separate words by comma, space, or newline. Matching is case-insensitive.")
          .font(.caption2)
          .foregroundColor(.secondary)
      }
      .padding(8)
      .background(
        AppSurface.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
      .disabled(!config.effectFilterFillerWords)
    }
  }
  private func syncFillerWordsDraftFromConfig() {
    let current = config.effectFillerWords.joined(separator: "\n")
    if fillerWordsDraft != current {
      fillerWordsDraft = current
    }
  }
  private func commitFillerWordsDraft() {
    let parsed = SegmentEffectConfiguration.parseFillerWords(from: fillerWordsDraft)
    if parsed != config.effectFillerWords {
      config.effectFillerWords = parsed
    }
    let normalizedDraft = config.effectFillerWords.joined(separator: "\n")
    if fillerWordsDraft != normalizedDraft {
      fillerWordsDraft = normalizedDraft
    }
  }
}
