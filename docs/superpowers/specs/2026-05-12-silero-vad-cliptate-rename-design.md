# Silero VAD Integration & Cliptate Rename

**Date**: 2026-05-12  
**Status**: Draft

## Problem Statement

1. The app currently only supports Sortformer for VAD (voice activity detection), which is ~850MB. A lightweight Silero VAD option (~2MB) would improve the first-run experience and serve users who don't need speaker diarization.
2. The app needs rebranding from "VoiceFlowPro" / "Voice Flow Pro" to "Cliptate" across all layers.

## Scope

### Part 1: Silero VAD Integration

**New `ModelVariant` case**: `sileroVADV6` pointing to `mlx-community/silero-vad-v6`.

**Key behavior**: When Silero is selected as VAD model, speaker diarization is skipped. All `speakerId` values are `nil`. When Sortformer is selected, existing diarization behavior is preserved.

**Default VAD**: Change from `sortformerStreaming` to `sileroVADV6` so new users get a ~2MB download instead of ~850MB.

#### New Files

1. **`SileroVADSegmenter.swift`** — Mirrors `SortformerVADSegmenter` for batch/offline VAD.
   - Wraps `SileroVAD.getSpeechTimestamps()` to produce `[AudioTimeRange]` with `speakerId: nil`.
   - `makeWithModel(variant:)` factory loads via `SileroVAD.fromPretrained()`.
   - `detectSpeechSegments(audioSamples:)` for offline batch use.
   - No `detectSpeechSegmentsWithSpeakers` or `detectAllSpeechSegments` — Silero doesn't do diarization.

2. **`SileroStreamingVADModule.swift`** — Mirrors `SortformerStreamingVADModule` for streaming VAD.
   - Actor conforming to `StreamingVADProvider`.
   - Uses `SileroVAD.feed(chunk:state:sampleRate:)` for streaming.
   - `feed()` returns `SortformerSpeechActivity` (reuse the same type, rename is unnecessary since it just carries `speechSampleRanges`).
   - Chunk size: 512 samples at 16kHz (Silero's required chunk size).

#### Modified Files

3. **`DataTypes.swift` / `ModelVariant`**:
   - Add `case sileroVADV6 = "silero-vad-v6"`.
   - Add `isSileroVADModel` computed property.
   - Add `isVADModel` computed property that returns `isSortformerVADModel || isSileroVADModel`.
   - Update `vadModels` to use `isVADModel` instead of `isSortformerVADModel`.
   - Update `displayName`, `summary`, `featureHighlights`, `languageSummary`, `fileSize`, `speedScore`, `accuracyScore`, `provider`, `accessLevel` for the new case.

4. **`Qwen3ASRTranscriber.swift` (ModelVariant extension)**:
   - Add `huggingFaceRepoId` for `sileroVADV6`: `"mlx-community/silero-vad-v6"`.

5. **`AppConfiguration.swift`**:
   - Change `defaultSnapshot.vadModelVariant` from `.sortformerStreaming` to `.sileroVADV6`.
   - Update `vadModelVariant` didSet guard: accept any model where `isVADModel` is true, but reject `sortformerOffline` for streaming (keep that restriction).

6. **`ModelCacheManager.swift`**:
   - Add `getSileroVADModel(model:)` method that loads and caches a `SileroVAD` instance.
   - Add a new `CachedResource` case `.sileroVAD(SileroVAD)` (or reuse an abstraction).
   - Update `getVADSegmenter()` to branch on model type — return `SortformerVADSegmenter` for Sortformer, or a new `SileroVADSegmenter` for Silero.

7. **`ModelDownloadManager.swift`**:
   - Add `case sileroVAD` to `DownloadBackend`.
   - Update `downloadBackend(for:)` to recognize Silero models.
   - Add download logic for Silero models using `SileroVAD.fromPretrained()`.

8. **`VADProvider.swift`**:
   - Add `SileroVADProvider` struct conforming to `VADProvider`.

9. **`StreamingVADProvider.swift`**:
   - Add conformance extension for `SileroStreamingVADModule`.

10. **`TranscriptionPipelineFactory.swift`**:
    - Update `makeVADProvider()` to accept a model type parameter and return Silero or Sortformer provider.
    - Update `makeStreamingProvider()` to create `SileroStreamingVADModule` when Silero is selected.

11. **`SpeechSegmenter.swift`**:
    - Update default closure to check `vadModelVariant` and use appropriate segmenter.

12. **`ModelsView.swift`**:
    - Update VAD section to show both Sortformer and Silero models.
    - Update `isVADSelection`, `onSetAsVAD` to use `isVADModel`.
    - Add note in VAD header that Silero = no speaker identification.

13. **`SortformerVADSegmenter.swift`**: No changes — keep as-is.

14. **Batch transcription pipeline** (`BatchTranscriptionPipeline`, `SpeechSegmenter`):
    - When Silero is the active VAD, `detectSpeechSegmentsWithSpeakers` should not be called. The pipeline should check whether the VAD supports diarization and skip speaker annotation if not.

#### Diarization Skip Logic

The key behavioral change: when `vadModelVariant.isSileroVADModel`:
- `SortformerVADSegmenter.detectAllSpeechSegments()` is NOT called.
- Instead, `SileroVADSegmenter.detectSpeechSegments()` is used, returning `[AudioTimeRange]` with `speakerId: nil`.
- Speaker propagation in `PlainASRSpeakerPropagation` will receive empty speaker ranges → no speaker assignment → all segments get `speakerId: nil`.
- This is the desired behavior: "selecting Silero means no speaker identification."

### Part 2: Rename to Cliptate

Systematic rename across all layers:

| Old | New |
|-----|-----|
| `VoiceFlowPro` (package/target) | `Cliptate` |
| `VoiceFlowProApp` (struct) | `CliptateApp` |
| `VoiceFlowProTests` | `CliptateTests` |
| `VoiceFlowProUITests` | `CliptateUITests` |
| `VoicePinkPro` (scheme) | `Cliptate` |
| `com.voiceflowpro.app` / `com.VoiceFlowPro` (loggers) | `com.cliptate.app` / `com.Cliptate` |
| `VoiceFlowPro.*` (notifications) | `Cliptate.*` |
| `VoiceFlowPro/` (App Support dir) | `Cliptate/` |
| "Voice Flow Pro" (UI text) | "Cliptate" |
| `VoiceFlowPro.xcodeproj` | `Cliptate.xcodeproj` |

**Migration note**: The Application Support directory rename needs a migration path — existing users have data in `~/Library/Application Support/VoiceFlowPro/`. Add a one-time migration that moves/symlinks the old directory.

#### Files to rename (filesystem):
- `Sources/VoiceFlowPro/` → `Sources/Cliptate/`
- `Sources/VoiceFlowProTests/` → `Sources/CliptateTests/`
- `Sources/VoiceFlowProUITests/` → `Sources/CliptateUITests/`
- `Sources/VoiceFlowPro.xcodeproj/` → `Sources/Cliptate.xcodeproj/`
- `Sources/VoiceFlowPro/VoiceFlowPro.swift` → `Sources/Cliptate/Cliptate.swift`
- `Sources/VoiceFlowPro/VoiceFlowPro.entitlements` → `Sources/Cliptate/Cliptate.entitlements`

## Testing Strategy (TDD)

### Silero VAD Tests

1. **`SileroVADSegmenterTests.swift`** — Unit tests for `SileroVADSegmenter`:
   - `timestampsToAudioTimeRanges` — verify conversion from `SileroVADTimestamp` to `AudioTimeRange`.
   - `emptyInputReturnsEmpty` — zero samples produces empty result.
   - `allSpeakerIdsAreNil` — verify no speaker IDs in output.

2. **`SileroStreamingVADModuleTests.swift`** — Streaming tests:
   - `feedReturnsActivityRanges` — verify chunk feeding produces sample ranges.
   - `startRejectsNonSileroModel` — rejects sortformer models.

3. **`VADProviderTests.swift`** — Update existing tests:
   - Add `SileroVADProvider` tests alongside existing `SortformerVADProvider` tests.

4. **`TranscriptionPipelineFactoryTests.swift`** — Update:
   - Test that factory creates Silero VAD when Silero model is selected.

5. **`ModelDownloadManagerTests.swift`** — Update:
   - Test `downloadBackend(for:)` returns `.sileroVAD` for Silero variant.

6. **`DataTypesTests.swift`** — Update:
   - Test `isVADModel`, `isSileroVADModel` properties.

7. **`AppConfigurationModelLifecyclePersistenceTests.swift`** — Update:
   - Test default VAD is now `sileroVADV6`.
   - Test that Silero variants are accepted by `vadModelVariant` setter.

### Rename Tests

8. Update all test file references and imports from `VoiceFlowPro` to `Cliptate`.

## Out of Scope

- Auto-resampling for non-16kHz audio (Silero rejects non-16k/8k rates; the app already normalizes to 16kHz).
- Silero VAD v5 support (only v6).
- Combining Silero VAD with Sortformer diarization in a hybrid mode.
