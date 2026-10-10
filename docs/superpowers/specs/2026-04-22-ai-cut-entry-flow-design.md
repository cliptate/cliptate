# AI Cut entry flow refactor design

## Summary

Refactor the AI Cut experience so the initial page is a simplified landing surface with an oversized drag-and-drop target, while preserving the existing full editing workspace after transcription completes. The new flow separates the AI Cut experience into four phases: landing, import setup, transcription progress, and editing.

## Problem

The current AI Cut page mixes onboarding, file import, transcription progress, and full editing in the same workspace. This makes the entry experience visually heavy and exposes advanced editing controls before the user has completed the basic import and transcription steps.

The requested behavior is:

1. The initial AI Cut page should only show an enlarged drag-and-drop region.
2. Dragging files or clicking to add files should open a lightweight setup window for file confirmation and transcription language selection.
3. Starting transcription should open a dedicated progress window with batch progress feedback similar to the provided screenshot.
4. The full AI Cut editor should appear only after all files in the batch finish transcription.
5. Existing editor capabilities must remain available after the transition: file list, video preview thumbnails, segments list, presets, waveform, subtitles, and related editing/export features.

## Goals

- Simplify the first impression of AI Cut.
- Make the import and transcription flow feel guided and focused.
- Preserve the existing editing workspace and current AI Cut capabilities.
- Reuse existing data/state structures where possible, especially `selectedVideoURLs`, `activeVideoURL`, `videoStates`, `VideoState`, and the current segment/export pipelines.
- Keep one shared transcription language for all files imported in a batch.

## Non-goals

- Rebuilding the existing AI Cut editor from scratch.
- Changing the segment-processing pipeline, export pipeline, or subtitle editing features.
- Introducing per-file transcription language overrides within one batch.
- Entering the full editor while batch transcription is still running.

## User flow

### 1. Landing

When the user enters AI Cut, the detail area shows only a large drop target and a light “click to add videos” affordance. No presets panel, waveform, segments list, or editing controls are shown in this state.

### 2. Import setup window

When the user drags files onto the landing area or clicks to choose files, the app opens a lightweight setup window. This window contains:

- The selected file list, with invalid or duplicate files removed before display.
- A shared transcription language picker for the whole batch.
- A primary action to start transcription.
- A cancel action that returns the user to the landing page without entering the editor.

The language selector should continue using model-aware language filtering so the selected ASR configuration remains the source of truth for supported languages.

### 3. Transcription progress window

After the user starts transcription, the setup window closes and a dedicated progress window opens. This window is focused on batch progress rather than editing. It shows:

- Overall batch progress.
- Current file name.
- Current processing stage text.
- Completed / failed file states.
- Model preparation progress when applicable.
- A cancel action.

The progress window remains visible until the batch finishes or the user cancels.

### 4. Editing workspace

The full AI Cut editor opens only after all files in the batch finish transcription. At that moment:

- `selectedVideoURLs` contains the imported batch.
- `videoStates` contains any successfully prepared `VideoState` entries.
- `activeVideoURL` is set to the first successfully transcribed file.
- The user sees the existing editing workspace with file switching, video preview, segments, presets, waveform, subtitles, corrections, translation, and export functionality intact.

If at least one file succeeds, the editor opens with the successful files available. Failed files remain represented in the batch state and can be surfaced in the file list as failed/retryable entries.

## Proposed architecture

### Flow state

Introduce a lightweight phase model to sit above the existing editor:

```swift
enum AICutFlowPhase {
  case landing
  case importSetup(pendingURLs: [URL])
  case transcribing(batch: AICutBatchContext)
  case editing
}
```

`AICutBatchContext` should capture transient batch-level workflow information such as:

- Imported URLs for the current batch.
- Shared transcription language.
- Per-file progress / status.
- Current file index.
- Any batch-level error summaries needed by the progress window.

This phase model should be owned by the AI Cut shell layer, not by the editor internals.

### View boundaries

Split responsibilities into a shell + editor structure:

- `AICutFlowView` or an equivalent shell owns the current phase and routes between landing, setup, progress, and editing.
- `AICutLandingView` renders the simplified initial state and handles drag/drop or click-to-import entry.
- `AICutImportSetupView` renders the batch confirmation and shared language selection UI.
- `AICutProgressView` renders the dedicated transcription progress window content.
- `AICutEditorView` becomes the existing full editor workspace extracted from today’s `AICutView`.

The current `AICutView` can either be renamed to `AICutEditorView` or reduced so it only owns editor behavior. The important design constraint is that the oversized landing state no longer lives inside the full editing workspace.

### Reuse boundaries

The following logic should remain part of the editor path with minimal behavior changes:

- `VideoState`
- `processedSegments` derivation
- `ControlPanelView`
- `VideoPlayerView`
- `SegmentsPanelView`
- existing AI correction, translation, waveform, subtitle, and export actions

The following concerns should move out of the editor:

- Initial empty-state onboarding UI
- Import setup UI
- The dedicated batch progress presentation

## Data flow

### Import

1. User imports files from drag/drop or file picker.
2. The shell filters to supported local video URLs and removes duplicates.
3. The shell transitions to `importSetup`.
4. The user confirms the shared transcription language.

### Start transcription

1. The shell commits the batch context.
2. The shell transitions to `transcribing`.
3. Existing transcription routines process the batch and populate `videoStates[url]`.
4. Existing `statusText`, `isTranscribing`, `batchTranscriptionProgress`, and `modelDownloadProgress` continue to be driven from the transcription pipeline, but the progress window becomes the primary presentation surface for them.

### Enter editing

1. When the batch completes, the shell checks how many files succeeded.
2. If none succeeded, the flow returns to landing with an explicit error summary.
3. If at least one succeeded, `selectedVideoURLs` is updated to the successful batch ordering, `activeVideoURL` is set, and the shell transitions to `editing`.
4. The editor then behaves like the current AI Cut workspace.

## Error handling

### Import-time errors

- Unsupported files are filtered out before the setup window is shown.
- If no valid files remain, the app stays in landing and shows a clear error message.
- Security-scope failures are surfaced explicitly rather than silently ignored.

### Batch transcription errors

- A single file failure does not abort the whole batch by default.
- Failed files are recorded in batch status so the progress window can show them.
- If at least one file succeeds, the editor still opens after the batch completes.
- If every file fails, the editor does not open; the user returns to landing with an actionable summary.

### Cancellation

- Canceling during import setup returns to landing with no editor transition.
- Canceling during transcription stops the active task, closes the progress window, and returns to landing unless there is already a completed batch ready for editing.

## Testing strategy

The implementation should follow TDD and cover the shell workflow separately from the editor internals.

Key tests:

1. Landing state renders without editor controls when no batch is active.
2. Importing valid files transitions to setup with duplicate and invalid items removed.
3. Starting transcription stores one shared language for the entire batch.
4. The flow stays in progress until every file reaches a terminal state.
5. The editor opens only after batch completion.
6. Partial success opens the editor with successful files preserved.
7. Total failure returns to landing and does not open the editor.
8. Existing editor state behavior remains intact once the flow enters editing.

## Implementation notes

- Treat `AppConfiguration` as the authoritative source for the active ASR/language/model relationship.
- Keep the full editor state in `selectedVideoURLs`, `activeVideoURL`, and `videoStates` so the rest of AI Cut behavior continues to work with minimal changes.
- Prefer reusing `ModelAwareLanguageSelectionView` inside the setup window instead of creating a new language-selection path.
- Upgrade the current status/progress presentation into a dedicated progress window rather than embedding it in the editor sidebar.
- Ensure the first editor presentation has a fully populated file list so the user lands in a complete workspace instead of a partially initialized one.
