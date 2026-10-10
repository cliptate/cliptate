# Shared ASR Cache Between AI Cut and Voice To Text

**Date:** 2026-04-21  
**Status:** Draft

---

## Problem Statement

AI Cut and Voice To Text both use ASR models, but the current ownership and configuration boundaries make reuse less reliable than it should be.

Today:

- both flows already load ASR models through `ModelCacheManager.shared`
- AI Cut still keeps a view-local `currentTranscriber` reference and signature cache
- Voice To Text uses a different ASR configuration source (`voiceToTextTranscriberType`, `voiceToTextModelVariant`)
- `ModelCacheManager` applies a generic cleanup timeout and ASR eviction policy that is not explicitly designed around shared reuse between these two product surfaces

The result is that AI Cut and Voice To Text can behave like separate consumers rather than two entry points to the same active ASR runtime, which risks unnecessary model reloads and wasted memory.

The desired behavior is:

1. AI Cut and Voice To Text use the same ASR model selection.
2. When either side has already loaded the current ASR model, the other side reuses that same loaded instance.
3. The shared ASR model is released only after an ASR-specific idle timeout expires.

---

## Goals

1. Make AI Cut and Voice To Text use one shared ASR configuration source.
2. Ensure both surfaces reuse the same in-memory ASR transcriber instance for the same `(type, model)` key.
3. Add a dedicated ASR idle-timeout setting instead of tying ASR lifetime to TTS or align cleanup behavior.
4. Preserve existing error behavior when a model is missing, loading, or unsupported.
5. Keep code changes focused on configuration, cache lifetime, and caller wiring.

---

## Non-Goals

1. Supporting different ASR models simultaneously in AI Cut and Voice To Text.
2. Redesigning TTS or align model lifecycle behavior.
3. Replacing `ModelCacheManager` with a new cache layer.
4. Broadly refactoring transcription UX unrelated to shared reuse.

---

## Recommended Approach

### 1. Unify ASR configuration

AI Cut and Voice To Text should read from the same ASR configuration fields in `AppConfiguration`.

Recommended end state:

- one shared `transcriberType`
- one shared `modelVariant`
- one shared `language` if the current product expectation is also unified
- one new shared `asrIdleTimeoutSeconds`

`voiceToTextTranscriberType` and `voiceToTextModelVariant` should stop acting as independent runtime selectors. If backward compatibility is needed for persisted settings, they should be migrated once into the shared fields rather than kept as parallel sources of truth.

This is the most important step, because reliable cache reuse depends on a stable shared key.

### 2. Keep `ModelCacheManager` as the single owner of ASR instances

Do not introduce another session or runtime manager for this feature.

`ModelCacheManager` should remain the only owner of loaded ASR transcribers:

- callers ask for a transcriber
- cache returns the existing loaded instance when the key matches
- cache decides when the model is released

`AICutView.currentTranscriber` can remain as a convenience reference, but it should be treated only as a short-lived UI handle to the cached object, not as a separate lifecycle owner.

### 3. Split ASR idle cleanup from generic model cleanup

Add a dedicated ASR idle-timeout setting in `ModelCacheManager`.

Recommended behavior:

- ASR models use `asrIdleTimeoutSeconds`
- TTS and align models continue using the existing cleanup timeout behavior
- every successful ASR cache hit, warm-up completion, or active use refreshes `lastAccess`
- the cleanup loop releases an ASR model only after it has been idle longer than the ASR-specific timeout

This keeps the change small because the app already has:

- cache entries with `lastAccess`
- cleanup loop infrastructure
- configuration-driven timeout updates

### 4. Preserve same-key reuse and make lifetime rules explicit

When AI Cut and Voice To Text request the same `(type, model)`:

- `ModelCacheManager.shared.getASRTranscriber(...)` should return the same cached transcriber instance
- no second warm-up should occur
- no extra per-surface model residency should be created

Because the product currently does not support different ASR choices between the two surfaces, this design does not need to solve concurrent multi-ASR residency.

---

## Alternatives Considered

### Option A - Unified config + shared cache + dedicated ASR timeout (**recommended**)

Use one ASR configuration source, reuse the same cached transcriber instance, and add a dedicated ASR idle timeout.

**Pros**

- directly matches the desired product behavior
- small-to-medium code change
- builds on the existing `ModelCacheManager`
- avoids permanently pinning memory
- keeps TTS and align lifecycle isolated

**Cons**

- requires settings migration and caller rewiring

### Option B - Permanent ASR residency until model switch or app exit

Load the ASR model once and never release it unless the user changes the model or quits.

**Pros**

- simplest mental model
- minimizes reloads

**Cons**

- keeps memory occupied longer than necessary
- adds more special-case lifecycle rules
- user explicitly preferred timeout-based expiry instead

### Option C - Cache-only adjustment without unifying config

Only tweak `ModelCacheManager` cleanup logic and leave AI Cut / Voice To Text with separate ASR configuration sources.

**Pros**

- smallest surface-level change

**Cons**

- does not guarantee stable reuse if the two config sources drift
- leaves a confusing product model: separate selectors, shared runtime

---

## Impacted Components

- `Sources/VoiceFlowPro/Models/AppConfiguration.swift`
- `Sources/VoiceFlowPro/Views/AICutView.swift`
- `Sources/VoiceFlowPro/Views/VoiceToTextView.swift`
- `Sources/VoiceFlowPro/Services/VoiceTranscriber.swift`
- `Sources/VoiceFlowPro/Services/ModelCacheManager.swift`
- tests covering configuration persistence and cache lifecycle

Potentially:

- `Sources/VoiceFlowPro/Services/TranscriberWarmupCoordinator.swift`
- any UI that currently edits Voice To Text-specific ASR fields

---

## Detailed Design

### Configuration model

Add:

```swift
@Published var asrIdleTimeoutSeconds: TimeInterval
```

Recommended default:

- `600` seconds to match the current cleanup default unless product wants a different default later

Configuration responsibilities:

- shared ASR selection lives in one place
- ASR timeout lives in one place
- persistence snapshot includes the new timeout
- old Voice To Text-specific ASR settings are migrated or aliased so the app ends with a single authoritative ASR selection

### Cache lifecycle

`ModelCacheManager` should maintain separate timeout behavior:

- `asrIdleTimeout`
- existing timeout for non-ASR resources

Expected internal behavior:

1. `getASRTranscriber(...)` reuses the loaded entry if the key matches.
2. On reuse or successful load, update `lastAccess`.
3. Cleanup loop checks ASR entries against `asrIdleTimeout`.
4. Cleanup loop checks align/TTS entries against the existing timeout.
5. Changing the ASR timeout at runtime updates future cleanup decisions without forcing immediate teardown.

### Caller behavior

#### AI Cut

AI Cut should:

- continue requesting transcribers through `ModelCacheManager.shared`
- stop being treated as an independent owner of ASR lifetime
- update only its local reference cache for convenience and signature comparison

#### Voice To Text

Voice To Text and `VoiceTranscriber` should:

- use the shared ASR configuration source
- request the same cache key as AI Cut
- naturally hit the same loaded transcriber instance when the shared ASR model is already warm

### Switching models

When the user changes the shared ASR model:

- subsequent requests use the new cache key
- old ASR entry becomes idle and is released after the ASR timeout
- no silent immediate teardown is required unless existing app behavior already explicitly clears cache on model switch

This avoids abrupt churn while still freeing memory eventually.

---

## Error Handling

- Missing download: preserve current model-not-downloaded errors.
- Unsupported selection: preserve current validation behavior.
- Invalid timeout values: clamp to a safe minimum and optionally preserve the current lower bound style already used by the cache.
- Cache miss after timeout expiry: caller reloads through the existing warm-up path.

No new broad catch blocks or silent fallback behavior should be introduced.

---

## Testing Strategy (TDD)

### Configuration tests

1. shared ASR settings are the only runtime source for AI Cut and Voice To Text
2. persisted settings restore `asrIdleTimeoutSeconds`
3. legacy Voice To Text-specific ASR settings migrate into the shared ASR fields if migration is needed

### Cache lifecycle tests

4. repeated `getASRTranscriber(...)` for the same key returns the same cached instance
5. AI Cut path and Voice To Text path requesting the same key reuse the same instance
6. ASR entry is retained before `asrIdleTimeoutSeconds` expires
7. ASR entry is released after `asrIdleTimeoutSeconds` expires
8. TTS and align cleanup behavior is unchanged by the new ASR timeout

### Flow tests

9. changing the shared ASR selection causes future requests to use a new key
10. previous ASR entry is not forcibly removed immediately unless existing behavior explicitly requests cache clearing

---

## Rollout Notes

This feature should be implemented as a behavior-preserving infrastructure change:

- same missing-model errors
- same warm-up path
- same page-level transcription behavior
- improved reuse and reduced redundant memory residency

The most likely regression risk is configuration divergence during migration, so that area should be tested first.

---

## Final Recommendation

Implement shared ASR reuse by:

1. unifying AI Cut and Voice To Text onto one ASR configuration source
2. keeping `ModelCacheManager` as the single owner of ASR instances
3. adding a dedicated `asrIdleTimeoutSeconds` setting and matching ASR cleanup path

This is the smallest design that reliably delivers cross-surface model reuse without turning ASR residency into a permanent special case.
