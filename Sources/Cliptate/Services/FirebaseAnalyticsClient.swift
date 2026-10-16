import FirebaseAnalytics
import FirebaseCore
import Foundation
import os

@MainActor
final class FirebaseAnalyticsClient {
  private var configured = false
  private let logger = Logger(subsystem: "com.Cliptate", category: "Analytics")

  func setCollectionEnabled(_ enabled: Bool) {
    guard !RuntimeEnvironment.isRunningTests else { return }
    if enabled && !configured {
      guard
        Bundle.main.bundleURL.pathExtension == "app",
        let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
        let options = FirebaseOptions(contentsOfFile: path),
        options.bundleID == Bundle.main.bundleIdentifier
      else {
        logger.notice("Analytics unavailable: no matching bundled Firebase configuration")
        return
      }
      FirebaseApp.configure(options: options)
      configured = true
    }
    guard configured else { return }
    if enabled {
      Analytics.setConsent([
        .analyticsStorage: .granted,
        .adStorage: .denied,
        .adUserData: .denied,
        .adPersonalization: .denied,
      ])
      let distribution = "direct"
      #if DEBUG
      let environment = "development"
      #else
      let environment = "production"
      #endif
      Analytics.setDefaultEventParameters([
        "distribution": distribution,
        "build_environment": environment,
        "app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
      ])
    }
    Analytics.setAnalyticsCollectionEnabled(enabled)
    if !enabled {
      Analytics.resetAnalyticsData()
    }
  }

  func record(_ event: AnalyticsEvent) {
    guard configured else { return }
    Analytics.logEvent(event.name, parameters: event.parameters)
  }
}
