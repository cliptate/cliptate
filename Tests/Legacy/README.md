# Previously unselected tests

These files are archived outside the active SwiftPM test target.
Some use retired test hooks, old model catalog expectations, or pre-Swift-6 isolation
assumptions (the Paywall view test fails strict concurrency compilation).

Update and validate a suite against the current implementation before moving it to
`Tests/CliptateTests`, where it will be discovered automatically. Shared test utilities
for archived suites are retained alongside them.

Archived paths:

- `CliptateTests.swift`
- `Integration/PurchaseFlowTests.swift`
- `Models/AppConfigurationTTSBookmarkTests.swift`
- `Models/MLXTTSModelMetricsTests.swift`
- `Models/TextToSpeechModelsTests.swift`
- `Services/ASRDictionaryBiasServiceTests.swift`
- `Services/PaywallManagerTests.swift`
- `Services/Qwen3PerSegmentAlignTests.swift`
- `Services/RevenueCatManagerPurchaseTests.swift`
- `Services/RevenueCatManagerTests.swift`
- `TestSupport/SubscriptionTestUtilities.swift`
- `Views/PaywallViewTests.swift`

`UITests/` preserves two Xcode UI test placeholders from the removed application
project. They require an XCUITest runner and are not run by SwiftPM. Use
`./scripts/build-and-run.sh --verify` for the current bundled-app launch check.
