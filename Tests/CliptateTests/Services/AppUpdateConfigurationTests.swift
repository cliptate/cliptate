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

  @Test func developmentAppCannotUseTheProductionUpdater() {
    var info = valid
    info["CFBundleIdentifier"] = "com.cliptate.dev"
    #expect(!AppUpdateConfiguration(info: info, hasAppStoreReceipt: false).isEnabled)
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

  @Test func unpublishedFeedIsReportedBeforeStartingSparkle() async throws {
    let url = URL(string: "https://github.com/cliptate/cliptate/releases/latest/download/appcast.xml")!
    let missing = try await AppUpdateManager.isFeedMissing(url) { request in
      #expect(request.url == url)
      #expect(request.httpMethod == "HEAD")
      return HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
    }
    #expect(missing)
  }

  @Test func publishedFeedsAndServerFailuresContinueThroughSparkle() async throws {
    let url = URL(string: "https://example.com/appcast.xml")!
    for code in [200, 403, 500] {
      let missing = try await AppUpdateManager.isFeedMissing(url) { _ in
        HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!
      }
      #expect(!missing)
    }
    await #expect(throws: URLError(.notConnectedToInternet)) {
      try await AppUpdateManager.isFeedMissing(url) { _ in
        throw URLError(.notConnectedToInternet)
      }
    }
  }
}
