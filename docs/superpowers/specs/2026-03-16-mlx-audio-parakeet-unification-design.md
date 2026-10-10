# MLX Audio Parakeet Unification Design

## Problem

`Parakeet` support currently diverges from the newer `MLX Audio` ASR path used by `Qwen3 ASR`.

Today the codebase mixes two implementation styles:

- `Qwen3` uses `MLXAudioCore` / `MLXAudioSTT` through `Qwen3ASRTranscriber`
- `Parakeet` still relies on `FluidAudio`-specific transcriber and streaming logic

This split increases maintenance cost across model loading, warmup, cache behavior, streaming dictation, and tests. The goal is to replace the `FluidAudio`-based `Parakeet` implementation with an `MLX Audio`-based one while preserving the existing product-facing engine choice of `TranscriberType.parakeet`.

## Goals

- Keep `TranscriberType.parakeet` and existing user-facing model choices
- Move `Parakeet` ASR execution onto the same `MLX Audio` engine flow used for `Qwen3`
- Unify model classification, cache loading, warmup, and download readiness checks for MLX-backed ASR models
- Replace live dictation / streaming for `Parakeet` with the same style of MLX pipeline used by `Qwen3`
- Drive the change with tests first

## Non-Goals

- Removing the `Parakeet` product concept from the UI
- Refactoring Whisper paths beyond incidental compatibility updates
- Introducing a large new abstraction hierarchy unless the TDD cycle proves it necessary
- Solving unrelated `FluidAudio` usages such as alignment helpers unless they block this migration

## Critical Prerequisite

This design assumes `Parakeet` can run on the MLX path used by this application, but the current local Swift code only proves direct `mlx-audio-swift` usage for `Qwen3` model classes.

At design time, the repository shows:

- local Swift imports and code paths for `Qwen3ASRModel` and `Qwen3ForcedAlignerModel`
- no checked-in Swift model class or example proving direct `Parakeet` support in `MLXAudioSTT`
- existing Parakeet runtime behavior implemented through `FluidAudio` types such as `AsrModels`, `StreamingAsrManager`, and `AsrModelVersion`

Therefore the migration must explicitly treat Parakeet-on-MLX as a verified prerequisite, not an assumed implementation detail.

Accepted implementation outcomes:

- `mlx-audio-swift` already supports Parakeet and the app adopts that support directly
- the dependency is updated to a revision that adds Parakeet support
- the project adds a local Swift bridge/wrapper to a Parakeet-capable MLX runtime while still converging the app onto the MLX execution flow

If none of these are true, the migration is blocked at the runtime capability level and should not proceed past the verification phase.

## Current State Summary

### Product and model selection

- `TranscriberType.parakeet` is still exposed as a first-class ASR engine
- `ModelVariant.parakeetV2` and `ModelVariant.parakeetV3` are classified as Parakeet-only models
- `ModelVariant.isMLXAudioModel` currently excludes Parakeet and only recognizes `Qwen3` and Sortformer variants

### Runtime implementation split

- `TranscriberType.createTranscriber(model:)` returns `FluidAudioTranscriber` for `.parakeet`
- `VoiceTranscriber` stores a `FluidAudioTranscriber` for Parakeet and uses a `ParakeetTranscriptionModule` built on `StreamingAsrManager`
- `Qwen3ASRTranscriber` already implements an `MLX Audio`-based offline ASR path
- `Qwen3StreamingModule` and `ParakeetTranscriptionModule` follow similar product needs but remain separate code paths

### Cache and warmup behavior

- `ModelCacheManager` and `TranscriberWarmupCoordinator` are the modern cache/warmup surfaces
- `TranscriberWarmupCoordinator` still contains explicit Parakeet streaming warmup behavior that depends on `FluidAudio` types and `AsrModelVersion`

## Proposed Architecture

### 1. Keep product engine identity, unify execution engine

`TranscriberType.parakeet` remains unchanged in settings, UI, and persisted configuration.

Internally, both `Parakeet` and `Qwen3` become `MLX Audio` ASR models. The execution pipeline should depend on model capabilities, not on a historical `FluidAudio` implementation branch.

### 2. Introduce a unified MLX-backed ASR transcriber path

Adopt one of these equivalent end states:

- generalize `Qwen3ASRTranscriber` into a shared `MLXAudioASRTranscriber`, then configure it by `ModelVariant`
- or keep `Qwen3ASRTranscriber` but extract shared MLX loading / transcription behavior into reusable helpers and add a sibling MLX Parakeet transcriber

The preferred direction is the first if the extraction remains small and readable during TDD.

The unified transcriber must support:

- model warmup with `ModelDownloadProgress`
- offline transcription with `TranscriptionProgress`
- chunk transcription for streaming reuse
- explicit validation of supported languages and model families
- model-family-specific loading for `Qwen3 ASR`, `Qwen3 ForcedAligner`, and `Parakeet`

### 3. Reclassify Parakeet as MLX-backed

Update `ModelVariant` helpers so that Parakeet participates in MLX-oriented branches:

- `isMLXAudioModel` should change from `isQwen3Model || isSortformerVADModel` to also include Parakeet ASR models
- add a narrower helper if needed, such as `isMLXAudioASRModel`
- keep `provider == .parakeet` so product identity remains stable

This allows selection, cache, and readiness logic to reason about Parakeet and Qwen3 consistently without changing the visible engine choice.

### 4. Unify live dictation / streaming structure

Replace the current Parakeet-specific runtime dependency on `FluidAudioTranscriber` with an MLX-backed streaming module that mirrors the operational shape of `Qwen3StreamingModule`.

Expected end state:

- `VoiceTranscriber` no longer stores `FluidAudioTranscriber` for Parakeet
- `VoiceTranscriber.configureEngine` receives an MLX-backed transcriber for Parakeet from `ModelCacheManager`
- the Parakeet streaming module uses the same chunking / callback / finalize conventions as the Qwen3 flow
- stop/final transcript behavior remains product-compatible

It is acceptable to keep separate `Parakeet` and `Qwen3` streaming modules if they share the same architectural pattern and MLX-backed dependencies. Full deduplication is optional in this change.

### 5. Unify cache, warmup, and download checks

Update these surfaces to treat Parakeet as part of the MLX-backed ASR family:

- `TranscriberType.createTranscriber(model:)`
- `ModelCacheManager.getASRTranscriber`
- `ModelDownloadManager.hasLocalArtifacts(for:)` and related mapping helpers
- `TranscriberWarmupCoordinator.scheduleWarmup` and `ensureStreamingWarmup`

The main rule is: the decision tree should be based on supported model families and capabilities, not on legacy engine-specific branches.

## Detailed Design

### Model classification

Add or adjust `ModelVariant` helpers:

- `isParakeetModel`
- `isQwen3ASRModel`
- `isQwen3AlignerModel`
- `isMLXAudioModel`
- optional: `isMLXAudioASRModel`

Recommended interpretation:

- `Parakeet` and `Qwen3 ASR` are MLX-backed ASR models
- `Qwen3 ForcedAligner` is MLX-backed but not a dictation model
- Sortformer remains MLX-backed VAD / diarization support

### Transcriber factory behavior

Change `TranscriberType.createTranscriber(model:)` so:

- `.whisper` still returns `WhisperTranscriber`
- `.parakeet` returns an MLX-backed Parakeet transcriber
- `.qwen3` returns an MLX-backed Qwen3 transcriber

If a shared `MLXAudioASRTranscriber` is introduced, the factory should simply validate and pass the chosen `ModelVariant`.

### VoiceTranscriber behavior

Update `VoiceTranscriber` so that Parakeet engine setup is no longer typed around `FluidAudioTranscriber`.

Required outcomes:

- cached transcriber acquisition for `.parakeet` succeeds through `ModelCacheManager`
- `configureEngine` and `startTranscriptionPipeline` only keep product-specific branching where user behavior differs
- `stop()` finalization for Parakeet still returns the latest stable text

### Warmup coordinator behavior

Current warmup keeps a dedicated Parakeet streaming warm path. After migration:

- warmup for `.parakeet` should preload the MLX-backed ASR transcriber just like `.qwen3`
- any remaining streaming warmup should operate on MLX-backed streaming prerequisites, not FluidAudio-only types
- if streaming warmup remains model-specific, the differentiation must be keyed by `ModelVariant`, not by `AsrModelVersion` or any other FluidAudio-only enum

### Download and readiness behavior

Model download checks should not treat Parakeet as a separate non-MLX runtime just because it was previously implemented with `FluidAudio`.

If Parakeet still requires model-specific artifact mapping, keep that mapping in `ModelVariant`/download manager helpers, but remove FluidAudio-specific assumptions from higher-level orchestration code.

## TDD Plan

Implementation should proceed in small red-green-refactor cycles.

### Phase 0: verify Parakeet runtime support on the MLX path

Before changing production code:

- verify whether the pinned `mlx-audio-swift` dependency can actually load and run Parakeet models
- identify the concrete runtime entry point for Parakeet on Swift; if no such type exists, document the required dependency upgrade or local bridge
- verify that at least one target Parakeet model artifact is available in a format consumable by the chosen MLX runtime path
- record the result in tests or implementation notes before proceeding

If verification fails, implementation must stop and the scope changes from migration to enabling Parakeet support in the MLX runtime itself.

### Phase 1: model classification and factory tests

Add or update tests to lock expected behavior for:

- Parakeet classified as MLX-backed where appropriate
- `TranscriberType.parakeet.supportedModels` remains unchanged
- `TranscriberType.createTranscriber(model:)` no longer creates `FluidAudioTranscriber`

Candidate test files:

- `Sources/VoiceFlowProTests/Models/DataTypesTests.swift`
- new or existing service-level factory tests

### Phase 2: cache and warmup tests

Add tests for:

- `ModelCacheManager` accepting Parakeet through the MLX-backed path
- `TranscriberWarmupCoordinator` not depending on FluidAudio-specific Parakeet branches
- streaming warmup state keyed by `ModelVariant` rather than `AsrModelVersion`
- language filtering remaining correct for `parakeet-v2` and `parakeet-v3`

Candidate files:

- `Sources/VoiceFlowProTests/Services/ModelCacheManagerLanguageTests.swift`
- new tests around cache/warmup selection logic

### Phase 3: streaming entry-point tests

Add focused tests around live-dictation entry points:

- `VoiceTranscriber` engine configuration for Parakeet no longer requires `FluidAudioTranscriber`
- Parakeet start/stop behavior still routes through the expected MLX-backed streaming module

Use seams or small helper extraction where needed to keep tests deterministic.

### Phase 4: implementation and cleanup

After tests fail for the right reason:

- add the MLX-backed Parakeet implementation
- switch factory/cache/warmup/runtime references
- remove obsolete `FluidAudio` Parakeet wiring
- leave unrelated `FluidAudio` consumers alone unless they break the build

## File Impact

Most likely files to change:

- `Sources/VoiceFlowPro/Models/DataTypes.swift`
- `Sources/VoiceFlowPro/Services/VoiceTranscriber.swift`
- `Sources/VoiceFlowPro/Services/ModelCacheManager.swift`
- `Sources/VoiceFlowPro/Services/ModelDownloadManager.swift`
- `Sources/VoiceFlowPro/Services/TranscriberWarmupCoordinator.swift`
- `Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift`
- possibly a new shared MLX ASR transcriber file
- selected test files under `Sources/VoiceFlowProTests/Models` and `Sources/VoiceFlowProTests/Services`

Files expected to become obsolete or reduced in responsibility:

- `Sources/VoiceFlowPro/Services/FluidAudioStreamModule.swift`
- `Sources/VoiceFlowPro/Services/FluidAudioTranscriptionModule.swift`

## Risks and Mitigations

### Risk: streaming behavior regresses

Mitigation:

- preserve existing callback semantics in `VoiceTranscriber`
- add streaming-focused tests before swapping implementation
- migrate stop/finalize behavior explicitly, not implicitly

### Risk: model readiness and download checks drift

Mitigation:

- centralize model-family classification in `ModelVariant`
- test factory/cache/warmup decisions directly

### Risk: forced aligner logic gets entangled

Mitigation:

- keep `Qwen3 ForcedAligner` support explicit and separate from dictation-capable MLX ASR models
- do not over-generalize alignment behavior into Parakeet unless the library actually supports it

### Risk: the Swift MLX dependency does not expose Parakeet

Mitigation:

- front-load runtime capability verification in Phase 0
- do not start refactoring app orchestration until a concrete Parakeet-on-MLX loading path is proven
- if support only exists in Python-side MLX projects, treat that as a separate enablement effort rather than silently stretching this migration

## Recommendation

Implement the migration using a unified MLX-backed ASR pipeline, but avoid a deep abstraction-first rewrite. Extract only the shared pieces that the tests force into existence.

This preserves delivery speed while still achieving the real goal: Parakeet stops being a legacy FluidAudio special case and becomes another model family on the MLX Audio engine path.
