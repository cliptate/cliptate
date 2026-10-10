//
//  CliptateApp.swift
//  Cliptate
//
//  Created by 大可 on 2025/8/9.
//

import KeyboardShortcuts
import SwiftUI
import os.log

@main
struct CliptateApp: App {
  @StateObject private var config: AppConfiguration
  @StateObject private var presetStore: ConfigPresetStore
  @StateObject private var downloadStateStore: ModelDownloadStateStore
  @StateObject private var lightweightManager = LightweightModeManager.shared
  private let appliedStoredSnapshot: Bool
  private let configurationRuntime: ConfigurationRuntime

  @AppStorage("appLanguageCode") private var appLanguageCode: String = ""
  @AppStorage("appAppearanceMode") private var appAppearanceMode: String = ""

  private var appLocale: Locale {
    appLanguageCode.isEmpty ? .autoupdatingCurrent : Locale(identifier: appLanguageCode)
  }

  init() {
    ModelDownloadManager.configureSharedHubCacheEnvironment()

    let sharedConfig = AppConfiguration.shared
    let sharedPresetStore = ConfigPresetStore.shared
    let sharedConfigurationRuntime = ConfigurationRuntime.shared
    _config = StateObject(wrappedValue: sharedConfig)
    _presetStore = StateObject(wrappedValue: sharedPresetStore)
    _downloadStateStore = StateObject(wrappedValue: ModelDownloadStateStore.shared)
    configurationRuntime = sharedConfigurationRuntime

    let bootstrapResult = sharedConfigurationRuntime.bootstrap(using: sharedConfig)
    appliedStoredSnapshot = bootstrapResult.appliedStoredSnapshot

    // Set accessory policy at launch if lightweight mode is active.
    // Deferred because NSApp may not yet be initialized during App.init().
    if LightweightModeManager.shared.isActive {
      DispatchQueue.main.async {
        NSApp?.setActivationPolicy(.accessory)
      }
    }

    KeyboardShortcutManager.shared.registerDefaultShortcuts()

    // Apply persisted appearance mode before first window appears
    let storedMode = UserDefaults.standard.string(forKey: "appAppearanceMode") ?? "system"
    AppearanceManager.apply(mode: storedMode)

    // Apply persisted language override so Bundle.main uses the correct language immediately
    let storedLang = UserDefaults.standard.string(forKey: "appLanguageCode") ?? ""
    if storedLang.isEmpty {
      UserDefaults.standard.removeObject(forKey: "AppleLanguages")
    } else {
      UserDefaults.standard.set([storedLang], forKey: "AppleLanguages")
    }

    if !RuntimeEnvironment.isRunningTests {
      // App Store billing is optional; direct builds never initialize the SDK.
      if SubscriptionPolicy.isBillingEnabled,
        let apiKey = (ProcessInfo.processInfo.environment["CLIPTATE_REVENUECAT_API_KEY"]
        ?? Bundle.main.object(forInfoDictionaryKey: "CliptateRevenueCatAPIKey") as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !apiKey.isEmpty, !apiKey.hasPrefix("$(")
      {
        Task {
          do {
            try await RevenueCatManager.shared.initialize(apiKey: apiKey)
            Logger(subsystem: "com.Cliptate", category: "App").info(
              "RevenueCat initialized successfully")
          } catch {
            Logger(subsystem: "com.Cliptate", category: "App").error(
              "Failed to initialize RevenueCat: \(error.localizedDescription)")
          }
        }
      }

      DispatchQueue.main.async {
        AppUpdateManager.shared.start()
      }

      _ = sharedConfigurationRuntime
    }
  }

  var body: some Scene {
    WindowGroup {
      Group {
        if lightweightManager.isActive {
          // Empty placeholder — no view hierarchy allocated in lightweight mode
          Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
              // Close the auto-opened window immediately in lightweight mode
              DispatchQueue.main.async {
                for window in NSApp.windows
                where (window.isKeyWindow || window.isMainWindow) {
                  window.close()
                }
              }
            }
        } else {
          GeometryReader { _ in
            ContentView()
              .environmentObject(config)
              .environmentObject(downloadStateStore)
              .environment(\.locale, appLocale)
              .frame(minHeight: 500)
          }
        }
      }
    }
    .commands {
      CommandGroup(after: .appInfo) {
        CheckForAppUpdatesButton()
      }
    }
    .defaultSize(width: 1280, height: 800)
    .windowResizability(.automatic)

    MenuBarExtra {
      LightweightMenuView()
        .environmentObject(config)
        .environmentObject(lightweightManager)
    } label: {
      if let appIcon = NSImage(named: "AppIcon") {
        Image(nsImage: MenuBarIconRenderer.makeImage(from: appIcon))
      } else {
        Image(systemName: "mic.fill")
      }
    }
    .menuBarExtraStyle(.menu)
  }
}
