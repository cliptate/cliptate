## Why

The upstream `Blaizzy/mlx-audio-swift` library has merged full Qwen3-TTS support (including voice cloning) into its `main` branch, making the project's temporary fork dependency (`intrusive-memory/mlx-audio-swift` on `development` branch) unnecessary and unmaintained. Migrating to the official upstream also exposes a richer, updated `SpeechGenerationModel` protocol that changes the `generate` call signature, so all integration code must be adapted. Additionally the existing implementation has known issues: a `nonisolated(unsafe)` concurrency workaround, the default language set to `zh` (confusing English-first users), and debug-level `print` statements polluting production logs.

## What Changes

- **Dependency**: Replace the fork (`intrusive-memory/mlx-audio-swift`, `development` branch) with the official upstream (`Blaizzy/mlx-audio-swift`, `main` branch) in `Package.swift`
- **API Adaptation**: Update `MLXTTSService.swift` to match the upstream `SpeechGenerationModel.generate` signature (the upstream uses `GenerateParameters` directly without separate `voice`/`refAudio`/`refText`/`language` top-level arguments — these are now encapsulated in model-specific parameter types or the `GenerateParameters` struct)
- **Voice Cloning**: Ensure the `Qwen3-TTS-12Hz-0.6B-Base-8bit` model's voice-cloning path (reference audio + reference text) works correctly against the official API
- **VoiceDesign & CustomVoice**: Verify all three model families (Base/voice-clone, CustomVoice, VoiceDesign) dispatch correctly
- **Concurrency Fix**: Remove `nonisolated(unsafe)` from `currentModel`; keep `currentModel` as a proper actor-isolated property
- **Default Language**: Change `ttsLanguage` default from `"zh"` to `"en"` in `AppConfiguration`
- **Logging Cleanup**: Replace verbose `print` calls with `Logger` (os.log) using `debug` level, so they are stripped from release builds
- **Download Manager**: Update `MLXTTSDownloadManager` if `ModelUtils.resolveOrDownloadModel` API changed upstream

## Capabilities

### New Capabilities
- `qwen3-tts-upstream-integration`: Migrate the Qwen3-TTS integration to use the official upstream mlx-audio-swift library with the correct API, enabling proper voice cloning, voice design, and custom-voice synthesis

### Modified Capabilities
- None — this is a dependency upgrade and bug-fix pass; the user-visible feature set stays the same

## Impact

- **`Package.swift`**: Dependency URL and branch change
- **`Sources/VoiceFlowPro/Services/MLXTTSService.swift`**: `generate` call signature update, concurrency fix, logging improvement
- **`Sources/VoiceFlowPro/Services/MLXTTSDownloadManager.swift`**: Potential API update for `ModelUtils`
- **`Sources/VoiceFlowPro/Models/AppConfiguration.swift`**: Default language change (`"zh"` → `"en"`)
- **Tests**: `MLXTTSDownloadManagerTests.swift` may need updates if download API changes; new `MLXTTSServiceTests.swift` to cover the generation path
- **No UI changes** required — the existing `TTSSynthesisView` and `ModelsView` remain compatible
