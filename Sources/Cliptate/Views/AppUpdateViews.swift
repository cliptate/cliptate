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
        Toggle(isOn: Binding(
          get: { updates.automaticallyChecksForUpdates },
          set: { updates.setAutomaticallyChecksForUpdates($0) }
        )) {
          Text("Automatically check for updates")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .appFeatureSwitch()
        CheckForAppUpdatesButton()
      } else {
        Text("Updates are unavailable in this build.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}

struct AvailableAppUpdateButton: View {
  let update: AppUpdateOffer
  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented = true
    } label: {
      Label {
        Text("Update: \(update.details.version)")
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      } icon: {
        Image(systemName: "shippingbox.fill")
      }
      .font(.caption.weight(.semibold))
      .foregroundStyle(.white)
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .background(Color.accentColor, in: Capsule())
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text("Update available: \(update.details.version)"))
    .help(Text("Update available: \(update.details.version)"))
    .popover(isPresented: $isPresented, arrowEdge: .trailing) {
      AvailableAppUpdateView(update: update)
    }
    .onChange(of: update.id) { _, _ in isPresented = false }
  }
}

struct AvailableAppUpdateView: View {
  private let details: AppUpdateDetails
  @ObservedObject private var prompt: AppUpdateInstallationPrompt

  init(update: AppUpdateOffer) {
    details = update.details
    prompt = update.prompt
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 16) {
        Text("Update available")
          .font(.title3.weight(.semibold))

        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
          GridRow {
            Text("Version:")
              .foregroundStyle(.secondary)
              .gridColumnAlignment(.trailing)
            Text(details.version)
          }
          if let size = details.formattedSize {
            GridRow {
              Text("Size:").foregroundStyle(.secondary)
              Text(size)
            }
          }
          if let date = details.releaseDate {
            GridRow {
              Text("Release date:").foregroundStyle(.secondary)
              Text(date, format: .dateTime.year().month(.wide).day())
            }
          }
        }
        .textSelection(.enabled)

        HStack(spacing: 8) {
          Button("Skip") { prompt.respond(.skip) }
          Button("Later") { prompt.respond(.dismiss) }
            .keyboardShortcut(.cancelAction)
          Spacer(minLength: 8)
          if details.isInformationOnly {
            Button("View Update") {
              NSWorkspace.shared.open(details.informationURL ?? details.notesURL)
              prompt.respond(.dismiss)
            }
            .buttonStyle(.borderedProminent)
          } else {
            Button("Install and Relaunch") { prompt.respond(.install) }
              .buttonStyle(.borderedProminent)
              .keyboardShortcut(.defaultAction)
          }
        }
        .buttonStyle(.bordered)
        .disabled(!prompt.isActive)
      }
      .padding(20)

      Divider()

      Link(destination: details.notesURL) {
        HStack(spacing: 10) {
          Label("View Release Notes", systemImage: "doc.text")
          Spacer()
          Image(systemName: "arrow.up.right")
            .accessibilityHidden(true)
        }
        .font(.body.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }
    .frame(width: 400)
    .background(AppSurface.pageBackground)
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
      .background(AppSurface.cardBackground, in: RoundedRectangle(cornerRadius: 16))
      .overlay {
        RoundedRectangle(cornerRadius: 16)
          .strokeBorder(AppSurface.border, lineWidth: 1)
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
    .background(AppSurface.pageBackground)
  }
}
