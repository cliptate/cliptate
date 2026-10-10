import SwiftUI

/// A string-backed text field for decimal input that doesn't reformat mid-typing.
/// Parses and clamps the value only on commit (Enter or focus loss).
struct DecimalTextField: View {
  @Binding var value: Double
  var clamp: (Double) -> Double = { $0 }

  @State private var draft: String = ""
  @FocusState private var isFocused: Bool

  var body: some View {
    TextField("", text: $draft)
      .textFieldStyle(.roundedBorder)
      .multilineTextAlignment(.trailing)
      .focused($isFocused)
      .onAppear { draft = formatValue(value) }
      .onChange(of: value) { _, newValue in
        if !isFocused {
          draft = formatValue(newValue)
        }
      }
      .onChange(of: isFocused) { _, focused in
        if !focused { commitDraft() }
      }
      .onSubmit { commitDraft() }
  }

  private func commitDraft() {
    if let parsed = FCPXMLSpeedParser.parse(draft) {
      let clamped = clamp(parsed)
      value = clamped
      draft = formatValue(clamped)
    } else {
      draft = formatValue(value)
    }
  }

  private func formatValue(_ v: Double) -> String {
    if v == v.rounded() {
      return String(format: "%.0f", v)
    }
    return String(format: "%.2g", v)
  }
}
