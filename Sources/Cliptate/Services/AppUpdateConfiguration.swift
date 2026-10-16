import Foundation

import CliptateCore

/// Validates updater configuration for production direct downloads.
struct AppUpdateConfiguration {
  let isEnabled: Bool

  init(info: [String: Any]) {
    let enabled = (info["CliptateUpdatesEnabled"] as? Bool)
      ?? (info["CliptateUpdatesEnabled"] as? String).map { $0 == "YES" || $0 == "1" }
      ?? false
    let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:))
    let key = (info["SUPublicEDKey"] as? String).flatMap { Data(base64Encoded: $0) }
    let identity = AppIdentity(bundleIdentifier: info["CFBundleIdentifier"] as? String)
    isEnabled = enabled && identity != .development
      && feed?.scheme == "https" && feed?.host?.isEmpty == false && key?.count == 32
  }

  init(bundle: Bundle) {
    self.init(info: bundle.infoDictionary ?? [:])
  }

  static var current: AppUpdateConfiguration {
    AppUpdateConfiguration(bundle: .main)
  }
}
