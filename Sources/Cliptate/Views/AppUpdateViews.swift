import AppKit
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

struct VerifiedAppUpdateView: View {
  @ObservedObject var prompt: AppUpdateInstallationPrompt

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(spacing: 16) {
        Image(nsImage: NSApplication.shared.applicationIconImage)
          .resizable()
          .frame(width: 56, height: 56)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 6) {
          Text("Update available")
            .font(.title3.weight(.semibold))
          HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
              .foregroundStyle(.green)
              .accessibilityHidden(true)
            Text("Signature verified")
              .foregroundStyle(.secondary)
          }
          .font(.body)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(16)
      .background(.background, in: RoundedRectangle(cornerRadius: 16))
      .overlay {
        RoundedRectangle(cornerRadius: 16)
          .strokeBorder(.quaternary, lineWidth: 1)
      }
      .accessibilityElement(children: .combine)

      HStack {
        Button("Install on Quit") { prompt.respond(.dismiss) }
          .keyboardShortcut(.cancelAction)
        Spacer()
        Button("Install and Relaunch") { prompt.respond(.install) }
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.borderedProminent)
      }
      .disabled(!prompt.isActive)
    }
    .padding(24)
    .frame(width: 440)
  }
}
