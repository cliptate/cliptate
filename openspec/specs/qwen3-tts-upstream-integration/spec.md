## ADDED Requirements

### Requirement: Upstream library dependency
The project SHALL depend on `Blaizzy/mlx-audio-swift` `main` branch (or the `v0.1.0` tagged release once verified) rather than any private fork.

#### Scenario: Fresh build resolves upstream package
- **WHEN** a developer clones the repository and runs `swift package resolve`
- **THEN** SPM downloads `mlx-audio-swift` from `https://github.com/Blaizzy/mlx-audio-swift.git` with no errors

#### Scenario: No fork reference in Package.swift
- **WHEN** `Package.swift` is inspected
- **THEN** there is no reference to `intrusive-memory/mlx-audio-swift`

### Requirement: Correct generate API call
`MLXTTSService` SHALL call the upstream `SpeechGenerationModel.generate` method using the exact signature exposed by `Blaizzy/mlx-audio-swift` `main`.

#### Scenario: Voice-clone synthesis dispatches correctly
- **WHEN** `synthesize` is called with a `referenceAudioURL` and `referenceText` for a Base-family model
- **THEN** the loaded `Qwen3TTSModel` receives the reference audio array and reference text, and returns a non-empty audio array

#### Scenario: VoiceDesign synthesis dispatches correctly
- **WHEN** `synthesize` is called with a non-nil `voiceDescription` for a VoiceDesign-family model
- **THEN** the loaded model receives the voice description string and returns a non-empty audio array

#### Scenario: Compilation succeeds
- **WHEN** `xcodebuild build -scheme VoiceFlowPro` is run after updating the dependency
- **THEN** it exits 0 with no compiler errors

### Requirement: Actor isolation is sound
`MLXTTSService.currentModel` SHALL be a normal actor-isolated property with no `nonisolated(unsafe)` annotation.

#### Scenario: No unsafe concurrency annotation
- **WHEN** `MLXTTSService.swift` is inspected
- **THEN** there is no `nonisolated(unsafe)` keyword on any stored property

#### Scenario: Concurrent access from two callers
- **WHEN** two concurrent `synthesize` calls arrive for the same model repo
- **THEN** both complete successfully without data races (only one model load occurs)

### Requirement: Structured logging replaces print
All TTS service logging SHALL use `os.Logger` (subsystem `com.voiceflowpro.tts`) instead of `print`.

#### Scenario: No bare print calls in TTS services
- **WHEN** `MLXTTSService.swift` and `MLXTTSDownloadManager.swift` are inspected
- **THEN** there are zero calls to `print(` in those files

#### Scenario: Debug logs are suppressed in release builds by default
- **WHEN** the app runs in release configuration without Console.app log streaming
- **THEN** no TTS debug messages appear in the system log

### Requirement: Default TTS language is English
`AppConfiguration.ttsLanguage` SHALL default to `"en"` for new installs where no saved preference exists.

#### Scenario: Fresh install defaults to English
- **WHEN** a user launches the app for the first time with no saved configuration
- **THEN** `AppConfiguration.ttsLanguage` is `"en"`

#### Scenario: Existing saved language preference is preserved
- **WHEN** a user has a saved preset with `ttsLanguage = "zh"`
- **THEN** applying that preset sets `ttsLanguage` to `"zh"`, not `"en"`

### Requirement: Download manager is compatible with upstream
`MLXTTSDownloadManager` SHALL use the correct `ModelUtils` API from `Blaizzy/mlx-audio-swift` `main` with no deprecation warnings.

#### Scenario: Model download succeeds
- **WHEN** `downloadModel(definition:)` is called for a valid HuggingFace repo
- **THEN** the model files are resolved to the local cache directory without errors

#### Scenario: Cache detection works
- **WHEN** a model has previously been downloaded
- **THEN** `isModelCached(definition:)` returns `true`
