import Foundation

import CliptateCore

/// Distribution configuration is separate from the APP_STORE accessibility capability gate.
struct AppUpdateConfiguration {
  let isEnabled: Bool

  init(info: [String: Any], hasAppStoreReceipt: Bool) {
    let enabled = (info["CliptateUpdatesEnabled"] as? Bool)
      ?? (info["CliptateUpdatesEnabled"] as? String).map { $0 == "YES" || $0 == "1" }
      ?? false
    let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:))
    let key = (info["SUPublicEDKey"] as? String).flatMap { Data(base64Encoded: $0) }
    let identity = AppIdentity(bundleIdentifier: info["CFBundleIdentifier"] as? String)
    isEnabled = enabled && !hasAppStoreReceipt && identity != .development
      && feed?.scheme == "https" && feed?.host?.isEmpty == false && key?.count == 32
  }

  init(bundle: Bundle) {
    // Only inspect local macOS distribution metadata; this is not purchase validation.
    let receipt = bundle.bundleURL.appendingPathComponent("Contents/_MASReceipt/receipt")
    let hasReceipt = FileManager.default.fileExists(atPath: receipt.path)
    self.init(info: bundle.infoDictionary ?? [:], hasAppStoreReceipt: hasReceipt)
  }

  static var current: AppUpdateConfiguration {
    AppUpdateConfiguration(bundle: .main)
  }
}
