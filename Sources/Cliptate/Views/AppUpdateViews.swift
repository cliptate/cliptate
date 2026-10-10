import SwiftUI

struct CheckForAppUpdatesButton: View {
  @ObservedObject private var updates = AppUpdateManager.shared

  var body: some View {
    if updates.isAvailable {
      Button("Check for Updates…", action: updates.checkForUpdates)
        .disabled(!updates.canCheckForUpdates || updates.isCheckingFeed)
    }
  }
}

struct AppUpdateSettingsView: View {
  @ObservedObject private var updates = AppUpdateManager.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if updates.isAvailable {
        Toggle("Automatically check for updates", isOn: Binding(
          get: { updates.automaticallyChecksForUpdates },
          set: { updates.setAutomaticallyChecksForUpdates($0) }))
        CheckForAppUpdatesButton()
      } else {
        Text("Updates are unavailable in this build.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}
