import Foundation
import Testing
@testable import Cliptate

@Suite("App update configuration")
struct AppUpdateConfigurationTests {
  private let valid: [String: Any] = [
    "CliptateUpdatesEnabled": "YES",
    "SUFeedURL": "https://github.com/cliptate/cliptate/releases/latest/download/appcast.xml",
    "SUPublicEDKey": Data(repeating: 1, count: 32).base64EncodedString(),
  ]

  @Test func configuredDirectBuildIsEnabled() {
    #expect(AppUpdateConfiguration(info: valid, hasAppStoreReceipt: false).isEnabled)
  }

  @Test func storeAndExplicitlyDisabledBuildsNeverEnableUpdates() {
    #expect(!AppUpdateConfiguration(info: valid, hasAppStoreReceipt: true).isEnabled)
    var info = valid
    info["CliptateUpdatesEnabled"] = "NO"
    #expect(!AppUpdateConfiguration(info: info, hasAppStoreReceipt: false).isEnabled)
    info["CliptateUpdatesEnabled"] = false
    #expect(!AppUpdateConfiguration(info: info, hasAppStoreReceipt: false).isEnabled)
  }

  @Test func missingOrInvalidSigningKeyDisablesUpdates() {
    for key in ["", "$(CLIPTATE_SPARKLE_PUBLIC_KEY)", "invalid", Data(repeating: 1, count: 31).base64EncodedString()] {
      var info = valid
      info["SUPublicEDKey"] = key
      #expect(!AppUpdateConfiguration(info: info, hasAppStoreReceipt: false).isEnabled)
    }
  }

  @Test func feedMustBeAnAbsoluteHTTPSURL() {
    for feed in ["", "http://example.com/appcast.xml", "file:///tmp/appcast.xml", "$(CLIPTATE_UPDATE_FEED_URL)", "https:appcast.xml"] {
      var info = valid
      info["SUFeedURL"] = feed
      #expect(!AppUpdateConfiguration(info: info, hasAppStoreReceipt: false).isEnabled)
    }
  }
}
