//
//  CustomPromptDialog.swift
//  Cliptate
//
//  AI correction custom prompt input dialog
//

import SwiftUI

struct CustomPromptDialog: View {
  @Binding var isPresented: Bool
  @State private var promptText: String = ""
  @FocusState private var isPromptFocused: Bool
  let onConfirm: (String?) -> Void
  let onCancel: (() -> Void)?

  init(
    isPresented: Binding<Bool>, onCancel: (() -> Void)? = nil,
    onConfirm: @escaping (String?) -> Void
  ) {
    self._isPresented = isPresented
    self.onCancel = onCancel
    self.onConfirm = onConfirm
  }

  var body: some View {
    VStack(spacing: 20) {
      Text("Custom Correction Prompt")
        .font(.headline)

      Text(
        "You can provide a custom prompt to guide the AI in correcting the transcription. This can include specific instructions or context to improve accuracy. Leave it blank to apply the default instructions."
      )
      .font(.subheadline)
      .foregroundStyle(.secondary)

      TextEditor(text: $promptText)
        .frame(minHeight: 120)
        .scrollContentBackground(.hidden)
        .padding(8)
        .focused($isPromptFocused)
        .appInputSurface(isFocused: isPromptFocused)

      HStack(spacing: 12) {
        Spacer()
        Button("Cancel") {
          isPresented = false
          onCancel?()
        }
        .keyboardShortcut(.cancelAction)

        Button("Confirm") {
          isPresented = false
          let trimmed = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
          onConfirm(trimmed.isEmpty ? nil : trimmed)
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(24)
    .frame(width: 500)
    .background(AppSurface.pageBackground)
  }
}

#Preview {
  @Previewable @State var isPresented = true

  CustomPromptDialog(
    isPresented: $isPresented,
    onCancel: {
      print("User cancelled")
    }
  ) { prompt in
    print("Confirmed with prompt: \(prompt ?? "nil")")
  }
}
