# Previously unselected tests

These 12 Swift files are archived outside the active SwiftPM package and Xcode
unit-test target.
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
