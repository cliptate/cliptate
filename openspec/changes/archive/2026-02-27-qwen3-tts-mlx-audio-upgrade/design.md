## Context

VoiceFlowPro currently depends on a private fork of `mlx-audio-swift` (`intrusive-memory/mlx-audio-swift`, `development` branch) because the upstream `Blaizzy/mlx-audio-swift` did not previously have Qwen3-TTS support. That PR has now merged and the upstream `main` branch fully supports Qwen3-TTS including voice cloning.

The fork is stale, creates supply-chain risk, and will not receive upstream bug fixes or new model support. The integration code in `MLXTTSService.swift` was written against the fork's API; the upstream `SpeechGenerationModel` protocol and `TTSModelUtils` may have diverged.

Additional technical debt exists:
- `private nonisolated(unsafe) var currentModel` — breaks Swift 6 actor isolation guarantees
- Default language `"zh"` in `AppConfiguration` is wrong for English-first users
- ~40 `print` statements pollute production logs; they need to be replaced with structured `Logger` calls

## Goals / Non-Goals

**Goals:**
- Switch to `Blaizzy/mlx-audio-swift` `main` branch
- Adapt `MLXTTSService` to the upstream `SpeechGenerationModel.generate` API (whatever signature it uses)
- Fix the `nonisolated(unsafe)` actor isolation violation
- Change the default `ttsLanguage` from `"zh"` to `"en"`
- Replace all `print` statements in TTS services with `os.Logger` at `.debug` level
- Verify all three model families (Base/voice-clone, CustomVoice, VoiceDesign) dispatch correctly
- Add missing `MLXTTSServiceTests.swift`

**Non-Goals:**
- Adding new TTS models beyond what already exists in `TextToSpeechModels.swift`
- Changing the TTS UI (TTSSynthesisView, ModelsView)
- Modifying the Kokoro TTS path
- Migrating MLXAudioSTT usage (Whisper STT stays on WhisperKit)

## Decisions

### 1. Switch to upstream `main` without a version pin

**Decision**: Use `.branch("main")` initially; file a GitHub issue to switch to a tagged release once one exists (v0.1.0 was just cut on Feb 23, 2026).

**Alternatives considered**:
- Pin to `v0.1.0` tag immediately — preferred long-term, but `from: "0.1.0"` requires the tag to match the exact repo path which must be verified
- Keep fork — rejected; fork is unmaintained

**Rationale**: The upstream just cut v0.1.0. We use `.branch("main")` first to verify the API, then switch to the tagged release once confirmed.

### 2. Actor isolation fix for `currentModel`

**Decision**: Remove `nonisolated(unsafe)`. Keep `currentModel` as a plain `var` inside the actor; it is already protected by actor isolation. The `nonisolated(unsafe)` was added as a workaround for a compiler error that likely arose from incorrect import annotations (`@preconcurrency`).

**Alternatives considered**:
- `nonisolated(unsafe)` — rejected; defeats Swift 6 safety guarantees
- Move to a `@MainActor` class — rejected; TTS generation must run off the main thread

### 3. Upstream API adaptation strategy

**Decision**: Before writing code, inspect the upstream `SpeechGenerationModel` protocol and `TTSModelUtils.loadModel` source to determine the exact generate signature. Adapt the call site accordingly. If the upstream's `generate` signature is identical to the fork's, no change needed beyond the dependency URL.

**Rationale**: The README example `model.generate(text:parameters:)` suggests the upstream may have simplified the signature. The exact delta must be confirmed before coding.

### 4. Logging

**Decision**: Replace all `print` calls with `os.Logger` using subsystem `com.voiceflowpro.tts`. Use `.debug` for verbose traces, `.error` for failures. Debug-level messages are stripped by the system in production unless explicitly enabled via Console.app.

**Alternatives considered**:
- Remove print calls entirely — loses debugging ability during development
- Keep `print` — pollutes production logs

### 5. Default language

**Decision**: Change `AppConfiguration.ttsLanguage` default from `"zh"` to `"en"`. Existing presets that explicitly saved `"zh"` will be respected (Snapshot restore path).

## Risks / Trade-offs

- **API break risk**: The upstream `generate` signature may differ significantly from the fork. → Mitigation: Read upstream source before coding (task 1 of implementation)
- **Package resolution**: Switching from a fork URL to upstream may require deleting `Package.resolved` if SPM caches the old resolution. → Mitigation: Document resolution step in task
- **Snapshot compatibility**: Changing the default language from `"zh"` to `"en"` may surprise users who upgraded and don't have saved presets. → Acceptable: affects only the default value, not saved presets
- **Test coverage gap**: `MLXTTSService.generate` cannot be integration-tested without a downloaded model. → Mitigation: Test the `createWAVData` helper and error-path logic as unit tests; mark integration tests as `@available` with skip conditions

## Migration Plan

1. Update `Package.swift` URL + branch
2. Delete `Package.resolved` and re-resolve via `swift package resolve`
3. Fix compilation errors in `MLXTTSService` and `MLXTTSDownloadManager` caused by API changes
4. Fix `nonisolated(unsafe)` and logging
5. Change default language in `AppConfiguration`
6. Run `xcodebuild build` to confirm zero errors
7. Manually test one synthesis call per family (Base, CustomVoice, VoiceDesign)

**Rollback**: Revert `Package.swift` to the fork URL; the rest of the code is backward-compatible.

## Open Questions

- Does the upstream `SpeechGenerationModel.generate` still accept `voice:refAudio:refText:language:` parameters, or have they been consolidated into `GenerateParameters`?
- Is `TTSModelUtils.loadModel(modelRepo:)` still the correct entry point, or has it been renamed/moved?
- Should we switch to the `v0.1.0` tag immediately rather than tracking `main`?
