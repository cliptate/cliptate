# Previously unselected tests

These files are archived outside the active SwiftPM test target.
Some use retired test hooks, old model catalog expectations, or pre-Swift-6 isolation
assumptions.

Update and validate a suite against the current implementation before moving it to
`Tests/CliptateTests`, where it will be discovered automatically. Shared test utilities
for archived suites are retained alongside them.

Archived paths:

- `CliptateTests.swift`
- `Models/AppConfigurationTTSBookmarkTests.swift`
- `Models/MLXTTSModelMetricsTests.swift`
- `Models/TextToSpeechModelsTests.swift`
- `Services/ASRDictionaryBiasServiceTests.swift`
- `Services/Qwen3PerSegmentAlignTests.swift`

`UITests/` preserves two Xcode UI test placeholders from the removed application
project. They require an XCUITest runner and are not run by SwiftPM. Use
`./scripts/build-and-run.sh --verify` for the current bundled-app launch check.
