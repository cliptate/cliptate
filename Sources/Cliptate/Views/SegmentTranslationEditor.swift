import CliptateCore
import SwiftUI

struct SegmentTranslationEditor: View {
  let translation: SegmentTranslation
  @Binding var text: String
  let onCommit: () -> Void
  @FocusState private var isTranslationFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Image(systemName: "globe")
          .font(.caption2)
          .foregroundColor(.secondary)
        Text(translation.language.displayName)
          .font(.caption2)
          .foregroundColor(.secondary)
      }

      ZStack(alignment: .topLeading) {
        Text(text)
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.leading)
          .lineLimit(1...6)
          .fixedSize(horizontal: false, vertical: true)
          .opacity(isTranslationFocused ? 0 : 1)
          .onTapGesture { isTranslationFocused = true }

        TextField("Translation", text: $text, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .font(.callout)
          .focused($isTranslationFocused)
          .lineLimit(1...6)
          .opacity(isTranslationFocused ? 1 : 0)
          .allowsHitTesting(isTranslationFocused)
          .onSubmit { onCommit() }
      }
    }
    .padding(.vertical, 2)
    .onChange(of: isTranslationFocused) { _, focused in
      if !focused { onCommit() }
    }
  }
}
