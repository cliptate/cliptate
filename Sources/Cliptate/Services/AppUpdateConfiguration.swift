import Foundation

/// Distribution configuration is separate from the APP_STORE accessibility capability gate.
struct AppUpdateConfiguration {
  let isEnabled: Bool

  init(info: [String: Any], hasAppStoreReceipt: Bool) {
    let enabled = (info["CliptateUpdatesEnabled"] as? Bool)
      ?? (info["CliptateUpdatesEnabled"] as? String).map { $0 == "YES" || $0 == "1" }
      ?? false
    let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:))
    let key = (info["SUPublicEDKey"] as? String).flatMap { Data(base64Encoded: $0) }
    isEnabled = enabled && !hasAppStoreReceipt
      && feed?.scheme == "https" && feed?.host?.isEmpty == false && key?.count == 32
  }

  static var current: AppUpdateConfiguration {
    let bundle = Bundle.main
    let hasReceipt = bundle.appStoreReceiptURL.map {
      FileManager.default.fileExists(atPath: $0.path)
    } ?? false
    return AppUpdateConfiguration(info: bundle.infoDictionary ?? [:], hasAppStoreReceipt: hasReceipt)
  }
}
