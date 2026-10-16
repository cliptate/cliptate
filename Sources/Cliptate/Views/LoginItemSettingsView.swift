import AppKit
import SwiftUI

struct LoginItemSettingsView: View {
  @State private var settings = LoginItemSettings()

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Toggle(isOn: Binding(
        get: { settings.isEnabled },
        set: { enabled in
          Task { await settings.setEnabled(enabled) }
        }
      )) {
        Label("Launch at Login", systemImage: "power")
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .appFeatureSwitch()
      .disabled(!settings.hasLoaded || settings.isBusy)

      if let errorMessage = settings.errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .task { await settings.refresh() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) {
      _ in
      Task { await settings.refresh() }
    }
  }
}
