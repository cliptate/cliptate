# Model Runtime Store Split Design

## Problem

`ModelCacheManager` currently mixes several responsibilities:

- ASR runtime loading and reuse
- Qwen3 aligner loading
- TTS runtime loading
- model lifecycle / preload / memory status for the Models page
- language support filtering
- cache eviction and warmup coordination

That centralization makes changes risky and harder to reason about. The recent VAD download issue also showed that download, cache-path, runtime-load, and UI-state concerns are already split conceptually, but are still partially coupled through one large actor.

## Goals

- Remove the monolithic `ModelCacheManager`.
- Preserve current preload and lifecycle UI in `ModelsView`.
- Keep runtime reuse and in-flight request deduplication.
- Keep clear boundaries between download, runtime loading, lifecycle state, and language support.
- Minimize behavior changes while refactoring.

## Non-Goals

- Reworking download managers (`ModelDownloadManager`, `Qwen3ModelDownloadManager`, `MLXTTSDownloadManager`) beyond integration touchpoints.
- Changing the Sortformer VAD runtime flow that was just added for Qwen3 streaming.
- Redesigning the Models page UX.

## Proposed Architecture

### 1. `ASRRuntimeStore`

Responsible only for ASR transcriber lifecycle:

- load / warm / reuse ASR transcribers
- deduplicate concurrent warmup/load requests
- expose readiness/loading state for ASR consumers
- support explicit preload and access-noting

Primary consumers:

- `VoiceTranscriber`
- `AICutView`
- `TranscriberWarmupCoordinator`

### 2. `AlignRuntimeStore`

Responsible only for Qwen3 aligner lifecycle:

- validate aligner model selection
- load / warm / reuse `Qwen3ASRTranscriber` aligner instances
- expose preload/readiness state for align models

Primary consumers:

- `AICutView`
- `ModelsView`

### 3. `TTSRuntimeStore`

Responsible only for TTS runtime lifecycle:

- Kokoro readiness/load
- MLX TTS model load/reuse
- preload and access tracking for TTS models

Primary consumers:

- `ModelsView`
- TTS-related views/services

### 4. `ModelLifecycleStore`

Responsible only for lifecycle/status aggregation:

- collect preload/loading/loaded/error state from the runtime stores
- collect memory estimates and last-access timestamps
- expose a unified snapshot for `AppConfiguration.refreshModelLifecycleState()`
- implement “clear idle cache but keep active model” behaviors used by `ModelsView`

This replaces the UI-facing part of `ModelCacheManager` without owning all runtime logic itself.

### 5. `ModelLanguageSupportService`

Responsible only for supported-language queries:

- ASR model language support
- aligner language support
- TTS language support
- cached filtered-language results

Primary consumer:

- `ModelAwareLanguageSelectionView`

## Data Flow

### Runtime loading

1. A view or service asks a specific runtime store for a model.
2. That store validates download/readiness using existing download managers.
3. The store loads or reuses the runtime.
4. The store publishes state updates to `ModelLifecycleStore`.

### Models page preload/status

1. `ModelsView` triggers preload through the specific runtime store.
2. The runtime store performs the load/warm operation.
3. `ModelLifecycleStore` aggregates status.
4. `AppConfiguration.refreshModelLifecycleState()` reads the lifecycle snapshot for UI.

### Language selection

1. `ModelAwareLanguageSelectionView` asks `ModelLanguageSupportService`.
2. The service queries the relevant runtime/download metadata path.
3. The service returns filtered supported languages without going through a monolithic cache manager.

## Migration Plan

1. Introduce new runtime stores and `ModelLifecycleStore` beside `ModelCacheManager`.
2. Move logic out incrementally:
   - ASR first
   - align second
   - TTS third
   - language support fourth
3. Switch consumers one group at a time.
4. Keep `ModelCacheManager` temporarily as a thin forwarding layer only if needed.
5. Remove `ModelCacheManager` once no callers remain.

## Error Handling

- Download-missing errors should remain explicit and user-facing.
- Runtime store boundaries should preserve typed errors where possible.
- Lifecycle aggregation should report errors without swallowing them.
- No silent fallback from one runtime family to another.

## Testing

- Unit tests for each runtime store:
  - warmup deduplication
  - readiness detection
  - preload success/failure
- Lifecycle store tests:
  - snapshot aggregation
  - clear-idle behavior
- Integration checks for:
  - `VoiceTranscriber`
  - `AICutView`
  - `ModelsView` preload/status flows
  - `ModelAwareLanguageSelectionView`

## Recommendation

Proceed with the split architecture above, but migrate incrementally rather than deleting `ModelCacheManager` in one patch. That keeps the preload/status UI intact while lowering risk for ASR, align, and TTS paths that currently share the same actor.
