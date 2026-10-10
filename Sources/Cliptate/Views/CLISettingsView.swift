import AppKit
import SwiftUI

struct CLISettingsView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var installed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(
        installed ? String(localized: "CLI installed") : String(localized: "CLI not installed"),
        systemImage: installed ? "checkmark.circle" : "terminal")
      if CLIInstallation.isAvailable {
        Text(
          "Run the copied command in Terminal. Add ~/.local/bin to your shell PATH to use cliptate."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        HStack {
          Button("Copy Install Command") { copy(CLIInstallation.installCommand) }
          Button("Copy Uninstall Command") { copy(CLIInstallation.uninstallCommand) }
          Button("Copy PATH Command") { copy(CLIInstallation.pathCommand) }
          Button("Refresh Status") { refresh() }
        }
        Text("cliptate transcribe recording.mp3 --format json")
          .font(.caption.monospaced())
          .textSelection(.enabled)
      } else {
        Text("The CLI helper is unavailable in this build.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .onAppear(perform: refresh)
    .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
  }

  private func refresh() { installed = CLIInstallation.isInstalled }
  private func copy(_ command: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(command, forType: .string)
  }
}
