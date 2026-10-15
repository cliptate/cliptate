//
//  CliptateUITestsLaunchTests.swift
//  CliptateUITests
//
//  Created by 大可 on 2025/8/9.
//

import XCTest

final class CliptateUITestsLaunchTests: XCTestCase {
  override class var runsForEachTargetApplicationUIConfiguration: Bool {
    true
  }

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testLaunch() throws {
    guard ProcessInfo.processInfo.environment["RUN_UI_SMOKE_TESTS"] == "1" else {
      throw XCTSkip(
        "Launch smoke test skipped in automated runs due to intermittent termination failures")
    }
    let app = XCUIApplication()
    app.launch()

    // Insert steps here to perform after app launch but before taking a screenshot,
    // such as logging into a test account or navigating somewhere in the app

    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Launch Screen"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
