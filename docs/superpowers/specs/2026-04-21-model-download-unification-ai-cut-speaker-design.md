# Model Download Unification and Ai Cut Speaker Preservation Design

## Problem

The current model download flow still treats Parakeet as a separate path in `ModelDownloadManager`, even though Parakeet now belongs to the same MLXAudio model family as ASR, align, VAD, and TTS. This leaves duplicated download semantics (`downloadParakeetModel`, `isMLXAudioModel`) while the storage layout is already mostly converging on the same `mlx-audio` cache tree.

Separately, Ai Cut's segments panel is capable of rendering `speakerId`, but the value is lost before the view receives the processed segments. The loss happens in segment-processing steps that rebuild `Segment` values without preserving `speakerId`.

## Goals

- Use one root directory for Parakeet, ASR, VAD, align, and TTS downloads.
- Remove the dedicated Parakeet download path and route Parakeet through the same unified MLXAudio download flow.
- Remove `isMLXAudioModel` and rely on concrete model capabilities instead of a redundant aggregate flag.
- Preserve `speakerId` through Ai Cut's segment processing pipeline so it is visible whenever time display is enabled.
- Implement the change with TDD during the implementation phase.

## Non-Goals

- Moving models out of the HuggingFace hub cache into an app-private directory.
- Redesigning model selection UI or provider taxonomy.
- Changing speaker numbering, diarization behavior, or deriving new speaker identities.
- Adding new diarization or speaker-assignment algorithms.

## Design

### 1. Unified model root directory

All downloadable model types will continue to use the HuggingFace hub cache's `mlx-audio` subtree as the single root directory. The canonical directory resolution remains:

- root: `hubCacheRoot(...)/mlx-audio`
- model directory: `mlx-audio/<repo-id-with-slashes-replaced>`

`ModelDownloadManager` remains the single owner of this path resolution through:

- `mlxAudioBase()`
- `mlxAudioDirectory(forRepo:)`
- `getModelDirectory(_:)`
- `hasLocalArtifacts(for:)`
- `delete(model:)`

This keeps the on-disk layout stable while making the download semantics match the storage semantics.

### 2. Unified download entry for all MLXAudio-family models

`ModelDownloadManager.download(model:)` will stop branching into a separate `downloadParakeetModel` path. Instead:

- `downloadParakeetModel` will be removed
- `download(model:)` will always dispatch supported models to `downloadMLXAudioModel`
- `downloadMLXAudioModel` will branch internally by explicit model capability

The per-model behavior inside the unified function will be:

- Parakeet -> `ModelUtils.resolveOrDownloadModel(..., requiredExtension: "safetensors")`
- Qwen3 ASR -> `Qwen3ASRModel.fromPretrained(...)`
- Qwen3 align -> `Qwen3ForcedAlignerModel.fromPretrained(...)`
- Sortformer VAD -> `SortformerModel.fromPretrained(...)`
- TTS -> `ModelUtils.resolveOrDownloadModel(..., requiredExtension: "safetensors")`

This removes the false distinction that Parakeet is downloaded differently at the manager level. The implementation still chooses the correct library API for each model family, but it does so inside one download pathway with one progress/reporting structure.

### 3. Remove `isMLXAudioModel`

`isMLXAudioModel` will be removed from `ModelVariant`.

The download manager and any related logic that currently uses that aggregate flag will instead check concrete capabilities directly:

- `isParakeetModel`
- `isQwen3ASRModel`
- `isQwen3AlignerModel`
- `isSortformerVADModel`
- `isTTSModel`

This makes the code reflect the actual supported behaviors and avoids a second classification axis that no longer adds meaning.

### 4. Preserve `speakerId` through Ai Cut processing

Ai Cut currently obtains display data through `AICutView.paddedSegments(for:)`, which applies a chain of processing steps. Several of those steps reconstruct `Segment` values and currently omit `speakerId`, causing the value to become `nil` before the UI renders it.

The fix is to treat `speakerId` as part of the segment identity that must be preserved during transformations unless a step explicitly reassigns speakers. Since no step in this flow reassigns speakers, all reconstructed segments should carry forward the original speaker value.

The implementation will preserve `speakerId` in every relevant rebuild point, including:

- `SegmentProcess.PaddingImpl`
- `SegmentSplit`
- `SegmentSplitBySilence`
- `SegmentSplitBySentence`
- `SegmentSplitByNatural`
- `SegmentCompression`
- `FillerWordFilter`
- `ASRDictionaryBiasService`

Any additional Ai Cut-adjacent `Segment(...)` reconstruction points discovered during implementation will follow the same rule.

### 5. UI behavior

The product rule stays unchanged:

- the speaker badge is shown only when time display is enabled

No new UI rule is introduced here. The change is purely about data preservation so that the existing UI can display `speakerId` correctly when `showTimes == true`.

## Data flow impact

### Model downloads

1. UI requests `ModelDownloadManager.download(model:)`
2. Permission gating remains unchanged
3. Unified download function selects the correct concrete loader by model capability
4. Download artifacts land in the canonical `mlx-audio` directory
5. Status, size, open-folder, and delete operations continue to resolve against that same directory

### Ai Cut speaker propagation

1. Base segments enter `AICutView.paddedSegments(for:)`
2. Segment processing operations may split, pad, filter, or remap timing
3. Every reconstruction step copies forward `speakerId`
4. `processedSegments` retains the original speaker annotation
5. `SegmentsPanelView` renders the badge when `showTimes` is enabled

## Error handling

- Unsupported models will continue to surface explicit progress/error states rather than silently succeeding.
- The unified download path must preserve existing retry and cancellation behavior.
- Speaker propagation changes must be behavior-preserving for segments whose `speakerId` is already `nil`.

## Testing strategy

Implementation will follow TDD:

1. Write failing tests for the desired behavior.
2. Change implementation to make them pass.
3. Keep the scope constrained to download unification and speaker propagation.

The test coverage should include:

### Model download tests

- Parakeet uses the unified download path rather than a dedicated download method.
- `getModelDirectory`, `hasLocalArtifacts`, and `delete` resolve Parakeet, ASR, align, VAD, and TTS against the same `mlx-audio` directory layout.
- Removing `isMLXAudioModel` does not break status queries or artifact checks.

### Speaker propagation tests

- `speakerId` survives padding.
- `speakerId` survives silence-based splitting.
- `speakerId` survives sentence-based splitting.
- `speakerId` survives natural splitting.
- `speakerId` survives legacy split helpers where still reachable.
- `speakerId` survives filler-word filtering.
- `speakerId` survives dictionary bias application.
- `speakerId` survives compression/time remapping.

Heavy UI automation is not required for this change. The critical correctness point is that the processed `Segment` values still contain `speakerId` when passed to the panel.

## Implementation notes

- Keep repo IDs unchanged.
- Keep public callers of `ModelDownloadManager` unchanged where possible.
- Prefer surgical changes over broader provider/model taxonomy refactors.
- Preserve existing retry, cancellation, and notification behavior in `ModelDownloadManager`.
