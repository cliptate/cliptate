import CliptateCore
import SwiftUI

struct EditorPresetDraft: Identifiable {
  let id = UUID()
  let preset: ConfigPreset?
  let makeDefault: Bool
}

struct EditorPresetSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var makeDefault: Bool
  let draft: EditorPresetDraft
  let onSave: (String, Bool) -> Void

  init(draft: EditorPresetDraft, onSave: @escaping (String, Bool) -> Void) {
    self.draft = draft
    self.onSave = onSave
    _name = State(initialValue: draft.preset?.name ?? "")
    _makeDefault = State(initialValue: draft.makeDefault)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(draft.preset == nil ? String(localized: "New Preset") : String(localized: "Rename Preset"))
        .font(.headline)
      Form {
        TextField("Preset Name", text: $name)
          .textFieldStyle(.roundedBorder)
        if draft.preset == nil {
          Toggle("Set as Default", isOn: $makeDefault)
        }
      }
      HStack {
        Spacer()
        Button("Cancel") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Save") {
          onSave(name, makeDefault)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(24)
    .frame(width: 400)
  }
}
