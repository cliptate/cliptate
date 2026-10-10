# FireRed Engine and Sortformer Offline Removal Design

## Problem

The app currently exposes `Sortformer Offline` as a user-selectable model option even though it is not meant to remain part of the primary user workflow. At the same time, the project does not yet expose the upstream `FireRedASR2` model from `mlx-audio-swift` as a first-class ASR engine, even though the product now wants to support Chinese (Mandarin plus 20+ dialects and accents), English, mixed Chinese-English speech, and sung lyrics recognition.

The current architecture binds each ASR engine to its own model family:

- Parakeet engine -> Parakeet models
- Qwen3 engine -> Qwen3 ASR models

That means FireRed should be introduced as a distinct engine, not hidden under Qwen3 or Parakeet. The change also needs to be complete in one pass, including internationalization, configuration migration, and tests.

## Goals

- Add FireRed ASR 2 as a new first-class ASR engine alongside Parakeet and Qwen3.
- Expose FireRed in model download UI, engine/model selection UI, runtime loading, and transcription flow.
- Remove `Sortformer Offline` from user-visible selectable model options and migrate saved config away from it.
- Keep model downloads under the existing shared HuggingFace `mlx-audio` root.
- Internationalize all new or changed user-facing strings, not just English text.
- Deliver the change as one complete feature with TDD during implementation.

## Non-Goals

- Adding FireRed streaming transcription.
- Adding FireRed forced alignment or TTS support.
- Redesigning the entire ASR architecture.
- Moving model storage out of the existing `mlx-audio` root.
- Broad refactoring outside the model/engine surfaces directly touched by this feature.

## Design

### 1. Introduce FireRed as a new engine

FireRed will be introduced as a new `TranscriberType` rather than as an extra model under Qwen3.

This keeps the product model consistent with the current architecture, where engine choice and model family are tightly coupled. It also avoids polluting the Qwen3 or Parakeet runtime paths with special cases that do not belong there.

The resulting engine structure becomes:

- `parakeet` -> Parakeet models
- `qwen3` -> Qwen3 ASR models
- `fireRed` -> FireRed ASR 2 models

`TranscriberType.supportedModels`, engine descriptions, and engine-to-transcriber construction will all be updated to reflect this.

### 2. Add a FireRed model family

`ModelVariant` will gain a FireRed-specific ASR entry based on the upstream model currently exposed by `mlx-audio-swift`:

- `mlx-community/FireRedASR2-AED-mlx`

FireRed will be treated as its own ASR model family rather than being folded into the existing `isQwen3ASRModel` or `isParakeetModel` checks. New classification helpers will be added as needed so the code can distinguish:

- Parakeet ASR models
- Qwen3 ASR models
- FireRed ASR models
- aligner models
- VAD models
- TTS models

This keeps feature ownership clear and prevents future routing logic from depending on unrelated model-family checks.

### 3. Add a FireRed transcriber

A dedicated FireRed transcriber will be added for offline ASR. It will use:

- `FireRedASR2Model.fromPretrained(...)`
- FireRed’s `generate(audio:)` path

The transcriber should stay narrowly scoped to offline batch transcription for this feature. It should not inherit Qwen3-specific alignment behavior or Parakeet-specific VAD assumptions.

This transcriber becomes the implementation behind `TranscriberType.fireRed.createTranscriber(...)`.

### 4. FireRed download and load integration

FireRed downloads will continue to use the existing `ModelDownloadManager` and the same HuggingFace `mlx-audio` root directory as the rest of the MLX audio ecosystem.

The unified model download routing will be extended with a FireRed-specific branch so the manager can:

- detect FireRed as a supported downloadable model
- resolve its cache directory inside `mlx-audio/<repo-subdir>`
- load or download it through the correct upstream model API

This keeps FireRed aligned with the recent model-download unification work and avoids introducing a second storage or status-tracking system.

### 5. Remove Sortformer Offline from the user workflow

`Sortformer Offline` should not merely be hidden visually. The change needs to remove it from the actual user workflow:

- remove it from model library user-visible VAD options
- remove it from default selectable VAD sets
- ensure configuration defaults no longer point at it
- migrate saved configuration that still references it to a supported remaining VAD option

If any internal runtime path still depends on the offline variant today, implementation should either:

1. replace that dependency with a supported remaining internal/default option, or
2. retain the variant only as an internal implementation detail that is no longer user-selectable

The important product guarantee is that users should not see or be able to select `Sortformer Offline`, and existing saved settings should not become invalid.

### 6. Language and capability presentation

FireRed’s product-facing capability metadata should explicitly communicate support for:

- Chinese (Mandarin plus 20+ dialects and accents)
- English
- mixed Chinese-English speech
- sung lyrics recognition

This belongs in the model/engine metadata layer used by the UI:

- model summary
- language summary
- model highlights
- engine description
- any selection notices that explain language behavior

Implementation should avoid pretending FireRed has the exact same parameter model as Qwen3. If upstream usage is best with light or automatic language steering, the UI should prefer truthful capability messaging over fake precision in language-specific toggles.

### 7. Internationalization

All newly added or changed user-visible text must follow the project’s existing localization approach.

The requirement is not satisfied by adding only English strings. The FireRed feature and Sortformer Offline removal must cover all affected user-visible surfaces, including:

- engine names
- engine descriptions
- model names
- model summaries
- language notices
- highlights/capability bullets
- model library messaging
- download/error/help text affected by the new model family

Implementation should update the existing localization resources and usage sites consistently so the feature behaves correctly in localized builds.

## Data flow impact

### FireRed engine flow

1. User chooses the FireRed engine.
2. The model-selection UI restricts model choice to FireRed-supported models.
3. Model download/status logic recognizes FireRed and resolves its artifacts under the shared `mlx-audio` root.
4. `TranscriberType.fireRed.createTranscriber(...)` creates the dedicated FireRed transcriber.
5. Offline transcription uses the FireRed model API and returns normal app `TranscriptionResult` values.

### Sortformer Offline removal flow

1. User-visible model lists no longer offer `Sortformer Offline`.
2. Default VAD configuration uses only supported remaining choices.
3. Saved config pointing to `Sortformer Offline` is migrated to a supported replacement.
4. Runtime no longer depends on a user-visible removed option.

## Error handling

- FireRed should participate in the same explicit download/load failure reporting patterns as existing models.
- Unsupported or stale persisted `Sortformer Offline` selections should be migrated, not silently left invalid.
- Localization updates must avoid fallback-to-English-only regressions on surfaces touched by the feature.

## Testing strategy

Implementation will follow TDD.

Coverage should include:

### Model and engine metadata

- FireRed appears as a supported engine.
- FireRed maps only to FireRed model variants.
- Sortformer Offline is no longer present in user-visible VAD model lists.

### Download and routing

- FireRed routes through the shared `mlx-audio` download/storage system.
- FireRed resolves under the same root as the other MLX audio models.

### Configuration and migration

- persisted configs selecting `Sortformer Offline` migrate to a supported VAD variant
- FireRed can be selected and persisted as a distinct ASR engine/model pairing

### Runtime

- FireRed transcriber construction uses the FireRed model path, not Qwen3 or Parakeet code paths
- FireRed’s minimal transcription call chain works through test hooks or targeted unit seams

### UI/model selection

- FireRed appears in the expected engine/model selection surfaces
- Sortformer Offline no longer appears in user-visible VAD selection surfaces

### Internationalization

- newly introduced or changed localized keys are wired through the same surfaces that present FireRed and Sortformer changes

## Implementation notes

- Prefer additive FireRed-specific code over over-generalizing Parakeet or Qwen3 transcribers.
- Keep the product architecture easy to reason about: one engine, one model family, one transcriber path.
- If an existing file is already large, targeted extraction is acceptable only when it directly helps keep FireRed logic isolated and understandable.
- The feature is only complete when engine/model selection, downloads, runtime behavior, configuration migration, localization, and tests all land together.
