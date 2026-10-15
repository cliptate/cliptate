import CliptateCore
import SwiftUI

/// Menu bar menu shown in lightweight mode (and always available as a status item).
struct LightweightMenuView: View {
  @EnvironmentObject private var config: AppConfiguration
  @EnvironmentObject private var lightweightManager: LightweightModeManager

  @State private var downloadedModels: Set<ModelVariant> = []
  #if !APP_STORE
  @StateObject private var cliLifecycle = CLIApplicationLifecycle.shared
  #endif

  private var needsFullAppWindow: Bool {
    #if APP_STORE
    lightweightManager.isActive
    #else
    lightweightManager.isActive || cliLifecycle.backgroundLaunch
    #endif
  }

  var body: some View {
    Group {
    // Language picker — filtered by the active model's supported languages
    Menu(String(localized: "Dictation Language", comment: "Menu bar: dictation language submenu")) {
      let supported = config.modelVariant.supportedLanguages
      ForEach(supported) { lang in
        Button {
          config.voiceToTextLanguage = lang
        } label: {
          if config.voiceToTextLanguage == lang {
            Text("✓ \(lang.displayName)")
          } else {
            Text("   \(lang.displayName)")
          }
        }
      }
    }

    // Model picker — only selectable engines, only downloaded models
    Menu(String(localized: "ASR Model", comment: "Menu bar: ASR model submenu")) {
      ForEach(TranscriberType.selectableCases) { engine in
        let available = engine.supportedModels.filter { downloadedModels.contains($0) }
        if available.isEmpty {
          Menu(engine.displayName) {
            Button {} label: {
              Text(String(localized: "No downloaded models", comment: "Menu bar: no models available for engine"))
            }
            .disabled(true)
          }
        } else {
          Menu(engine.displayName) {
            ForEach(available) { model in
              Button {
                config.transcriberType = engine
                config.modelVariant = model
              } label: {
                if config.transcriberType == engine && config.modelVariant == model {
                  Text("✓ \(model.displayName)")
                } else {
                  Text("   \(model.displayName)")
                }
              }
            }
          }
        }
      }
    }

    Divider()

    Button(action: openProSection) {
      Text(AppSection.pro.description)
    }

    if needsFullAppWindow {
      Button {
        openFullApplication()
      } label: {
        Text(String(localized: "Open Full App", comment: "Menu bar: open full application window"))
      }
    } else {
      Button {
        lightweightManager.enterLightweightMode()
      } label: {
        Text(
          String(
            localized: "Enter Lightweight Mode",
            comment: "Menu bar: enter lightweight mode to save memory"))
      }
    }

    Divider()

    CheckForAppUpdatesButton()

    Button {
      NSApplication.shared.terminate(nil)
    } label: {
      Text(String(localized: "Quit", comment: "Menu bar: quit application"))
    }
    .keyboardShortcut("q")
    }
    .task {
      await refreshDownloadStatuses()
    }
    .onReceive(NotificationCenter.default.publisher(for: .modelArtifactsDidChange)) { _ in
      Task { await refreshDownloadStatuses() }
    }
  }

  private func refreshDownloadStatuses() async {
    var downloaded = Set<ModelVariant>()
    for engine in TranscriberType.selectableCases {
      for model in engine.supportedModels {
        let hasArtifacts = await ModelDownloadManager.shared.hasLocalArtifacts(for: model)
        if hasArtifacts {
          downloaded.insert(model)
        }
      }
    }
    await MainActor.run {
      downloadedModels = downloaded
    }
  }

  private func openProSection() {
    AppNavigationRequestStore.store(.pro)
    if needsFullAppWindow {
      openFullApplication()
    }
    NotificationCenter.default.post(name: .openProSection, object: nil)
  }

  private func openFullApplication() {
    #if !APP_STORE
    cliLifecycle.backgroundLaunch = false
    #endif
    if lightweightManager.isActive {
      lightweightManager.exitLightweightMode()
    } else {
      lightweightManager.showMainWindow()
    }
  }
}
