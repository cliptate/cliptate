import CliptateCore
import SwiftUI

struct EditorPresetsView: View {
  @EnvironmentObject private var config: AppConfiguration
  @ObservedObject private var presetStore = ConfigPresetStore.shared
  private let configurationRuntime = ConfigurationRuntime.shared
  @State private var selectedPresetID: UUID?
  @State private var isApplyingPreset = false
  @State private var presetDraft: EditorPresetDraft?
  @State private var autoSyncTask: Task<Void, Never>?

  var body: some View {
    presetPicker
      .sheet(item: $presetDraft) { draft in
        EditorPresetSheet(draft: draft) { name, makeDefault in
          savePreset(draft, name: name, makeDefault: makeDefault)
        }
      }
      .onReceive(config.objectWillChange) { _ in schedulePresetSync() }
      .onDisappear {
        autoSyncTask?.cancel()
        autoSyncPreset()
      }
  }

  private func schedulePresetSync() {
    autoSyncTask?.cancel()
    autoSyncTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(500))
      guard !Task.isCancelled else { return }
      autoSyncPreset()
    }
  }
  private var presetPicker: some View {
    HStack(spacing: 8) {
      Text("Presets")
        .foregroundStyle(.secondary)
      if presetStore.presets.isEmpty {
        HStack(spacing: 8) {
          Image(systemName: "bookmark.slash")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text("No presets")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          Button {
            captureNewPreset(makeDefault: true)
          } label: {
            Label("Save", systemImage: "plus")
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
      } else {
        HStack(spacing: 8) {
          Picker(
            "Presets",
            selection: Binding(
              get: {
                selectedPresetID ?? presetStore.presets.first(where: { $0.isDefault })?.id
              },
              set: { newVal in
                selectedPresetID = newVal
                if let id = newVal {
                  isApplyingPreset = true
                  try? configurationRuntime.applyPreset(id: id, to: config)
                  DispatchQueue.main.async { isApplyingPreset = false }
                }
              }
            )
          ) {
            ForEach(presetStore.presets) { p in
              Label(p.name, systemImage: p.isDefault ? "star" : "bookmark")
                .tag(Optional.some(p.id))
            }
          }
          .labelsHidden()
          .frame(maxWidth: .infinity, alignment: .leading)
          .animation(.spring(response: 0.35, dampingFraction: 0.8), value: selectedPresetID)

          Menu {
            if let id = selectedPresetID,
              let preset = presetStore.presets.first(where: { $0.id == id })
            {
              Button {
                captureNewPreset(makeDefault: false)
              } label: {
                Label("New Preset", systemImage: "plus")
              }
              Divider()
              Button {
                beginRename(preset)
              } label: {
                Label("Rename", systemImage: "pencil")
              }
              Button {
                duplicatePreset(preset)
              } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
              }
              Button {
                try? presetStore.setDefault(id: preset.id)
              } label: {
                Label("Set Default", systemImage: "star.fill")
              }
              Divider()
              Button {
                configurationRuntime.resetToDefaults(using: config)
                selectedPresetID = presetStore.presets.first(where: { $0.isDefault })?.id
              } label: {
                Label("Reset to Factory Defaults", systemImage: "arrow.counterclockwise")
              }
              Divider()
              Button(role: .destructive) {
                deletePreset(preset)
              } label: {
                Label("Delete", systemImage: "trash")
              }
            } else {
              Button {
                captureNewPreset(makeDefault: true)
              } label: {
                Label("New Preset", systemImage: "plus")
              }
            }
          } label: {
            Image(systemName: "ellipsis.circle")
              .imageScale(.medium)
          }
          .menuIndicator(.hidden)
          .fixedSize()
          .help("Presets")
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .onAppear {
      if presetStore.presets.isEmpty { try? presetStore.load() }
      if let createdOrDefault = try? presetStore.ensureDefaultPreset(using: config) {
        if selectedPresetID == nil { selectedPresetID = createdOrDefault.id }
      }
    }
    .controlSize(.small)
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
  }
  // MARK: - Actions
  private func captureNewPreset(makeDefault: Bool) {
    presetDraft = EditorPresetDraft(preset: nil, makeDefault: makeDefault)
  }

  private func beginRename(_ preset: ConfigPreset) {
    presetDraft = EditorPresetDraft(preset: preset, makeDefault: false)
  }

  private func savePreset(_ draft: EditorPresetDraft, name: String, makeDefault: Bool) {
    if let preset = draft.preset {
      try? presetStore.update(id: preset.id) { $0.name = name }
    } else if let preset = try? presetStore.create(from: config, name: name, makeDefault: makeDefault) {
      selectedPresetID = preset.id
    }
  }

  private func duplicatePreset(_ preset: ConfigPreset) {
    do {
      _ = try presetStore.create(from: config, name: preset.name, makeDefault: false)
    } catch {}
  }

  private func deletePreset(_ preset: ConfigPreset) {
    do {
      try presetStore.delete(id: preset.id)
      if selectedPresetID == preset.id { selectedPresetID = presetStore.presets.first?.id }
    } catch {}
  }

  // MARK: - Auto Sync Selected Preset
  private func autoSyncPreset() {
    guard !isApplyingPreset else { return }

    // 如果没有选中预设，尝试使用 Default 预设
    let targetID = selectedPresetID ?? presetStore.presets.first(where: { $0.isDefault })?.id

    guard let id = targetID,
      presetStore.presets.first(where: { $0.id == id }) != nil
    else { return }

    do {
      try presetStore.update(id: id) { p in
        p.payload = presetStore.payload(from: config)
      }
    } catch {
      print("⚠️ Failed to auto-sync preset: \(error.localizedDescription)")
    }
  }

}
