## 1. Research upstream API

- [x] 1.1 Clone or inspect `Blaizzy/mlx-audio-swift` `main` source to determine the exact `SpeechGenerationModel.generate` method signature (parameters, types, return type)
- [x] 1.2 Confirm whether `TTSModelUtils.loadModel(modelRepo:)` is still the correct entry point or if it has been renamed/moved
- [x] 1.3 Confirm whether `loadAudioArray(from:)` free function signature has changed in `MLXAudioCore`
- [x] 1.4 Confirm whether `ModelUtils.resolveOrDownloadModel` API used in `MLXTTSDownloadManager` has changed

## 2. Update package dependency

- [x] 2.1 In `Package.swift`, change the `mlx-audio-swift` dependency URL from `https://github.com/intrusive-memory/mlx-audio-swift.git` to `https://github.com/Blaizzy/mlx-audio-swift.git` and change `branch: "development"` to `branch: "main"` (or `from: "0.1.0"` if the tag is confirmed stable)
- [x] 2.2 Delete `Package.resolved` to force fresh resolution
- [x] 2.3 Run `swift package resolve` and confirm it resolves without errors
- [x] 2.4 Remove the TODO comment referencing the fork

## 3. Fix MLXTTSService — API adaptation

- [x] 3.1 Update `import` statements if module names have changed in the upstream
- [x] 3.2 Update `model.generate(...)` call in `synthesize` to match the upstream `SpeechGenerationModel` protocol signature (adapt `voice:`, `refAudio:`, `refText:`, `language:` parameters to whatever the upstream accepts)
- [x] 3.3 Remove `nonisolated(unsafe)` from `currentModel` — keep it as a plain actor-isolated `var`; fix any resulting compiler errors
- [x] 3.4 Update `TTSModelUtils.loadModel(modelRepo:)` call if the upstream API changed (rename or new parameter labels)
- [x] 3.5 Update `loadAudioArray(from:)` call if the upstream API changed
- [x] 3.6 Verify the `createWAVData` helper still compiles and works correctly

## 4. Fix MLXTTSDownloadManager — API adaptation

- [x] 4.1 Update `ModelUtils.resolveOrDownloadModel(repoID:requiredExtension:)` call if signature changed
- [x] 4.2 Confirm cache directory logic is still compatible (path derivation from repo ID)

## 5. Fix default language

- [x] 5.1 In `AppConfiguration.swift`, change the default value of `ttsLanguage` from `"zh"` to `"en"`
- [x] 5.2 Verify the `AppConfiguration.Snapshot` default is also updated if it has its own default value

## 6. Replace print with structured logging

- [x] 6.1 Add `import os` to `MLXTTSService.swift` and create a private `Logger` instance: `private let logger = Logger(subsystem: "com.voiceflowpro.tts", category: "MLXTTSService")`
- [x] 6.2 Replace all `print("🔍 ...")`  calls with `logger.debug(...)` in `MLXTTSService.swift`
- [x] 6.3 Replace all `print("✅ ...")`  calls with `logger.debug(...)` in `MLXTTSService.swift`
- [x] 6.4 Replace all `print("❌ ...")`  calls with `logger.error(...)` in `MLXTTSService.swift`
- [x] 6.5 Replace all `print("⚠️ ...")`  calls with `logger.warning(...)` in `MLXTTSService.swift`
- [x] 6.6 Add `import os` and a `Logger` instance to `MLXTTSDownloadManager.swift`; replace any `print` calls there too

## 7. Build verification

- [x] 7.1 Run `xcodebuild build -project VoiceFlowPro.xcodeproj -scheme VoiceFlowPro` and confirm exit code 0, zero errors
- [x] 7.2 Fix any remaining compiler warnings related to concurrency or deprecated API usage

## 8. Tests

- [x] 8.1 Update `MLXTTSDownloadManagerTests.swift` if any public API changed
- [x] 8.2 Create `Sources/VoiceFlowProTests/Services/MLXTTSServiceTests.swift` with unit tests for:
  - `createWAVData(from:sampleRate:)` with valid samples
  - `createWAVData(from:sampleRate:)` with empty samples
  - `synthesize` throws `MLXTTSError.emptyInput` when given blank text
  - `synthesize` throws `MLXTTSError.modelNotLoaded` when model is nil (mock or partial actor)
- [x] 8.3 Update `TextToSpeechModelsTests.swift` if model count or IDs changed
- [x] 8.4 Run `xcodebuild test -project VoiceFlowPro.xcodeproj -scheme VoiceFlowProTests` and confirm all tests pass
