# AI Cut window separation design

## Summary

Refine the newly introduced AI Cut flow so transcription progress and clipping/editing happen in separate windows. The progress phase must open in its own dedicated window, then close before a new editor window opens and becomes the frontmost window. The editor window must no longer expose any file-import affordances and should operate only on the completed batch.

## Problem

The current AI Cut refactor established a landing page, import setup, progress state, and editor state, but the resulting UX still has three problems:

1. The progress experience is not yet treated as an independent window in the same way the user expects.
2. The clip editor still exposes import-oriented UI affordances inherited from the existing editor layout, including the drag-and-drop area and Add button.
3. Batch transcription progress is inconsistent because the UI still mixes multiple progress sources instead of treating the flow model batch state as the single source of truth.

The requested behavior is:

1. The progress view must open in a new window.
2. The clip editor must also open in a new window.
3. When transcription finishes, the progress window closes first, then the editor window opens and becomes frontmost.
4. The clip window must remove the drag-and-drop region and the Add button entirely.
5. The clip window edits only the current completed batch and does not support importing or appending files.
6. The transcription file progress display must be corrected.

## Goals

- Separate onboarding, progress tracking, and editing into distinct window responsibilities.
- Ensure the editor window is a pure editing workspace for the completed batch.
- Make `AICutFlowModel.currentBatch` the canonical source for batch progress in the progress window.
- Preserve the current editor capabilities once the batch reaches editing: file switching, preview, segments, presets, waveform, subtitles, correction, translation, and export.
- Keep the transition order explicit: close progress window, then open editor window, then bring it to front.

## Non-goals

- Reworking the transcript processing pipeline itself.
- Changing export behavior or segment processing algorithms.
- Reintroducing import affordances into the editor window.
- Supporting append/import actions from the editor window.
- Replacing the current editor internals beyond what is necessary to remove import entry points.

## User flow

### 1. Landing page

The AI Cut section in the main application remains the single import entry point. It shows only the enlarged drag-and-drop / click-to-browse surface.

### 2. Import setup

The import setup surface remains lightweight and configures one shared language for the batch.

### 3. Progress window

After the user starts transcription, the app opens a dedicated progress window. This window is not the editor and should not share the editor layout. It shows only:

- Batch headline and progress bar.
- Current file / current stage.
- Per-file status list from the flow model batch items.
- Model preparation progress when relevant.
- Cancel action.

### 4. Editor window

When all files in the batch reach terminal state:

1. The progress window closes.
2. A new clip editor window opens.
3. The editor window becomes frontmost.

The editor window is scoped to the successful files in the completed batch. It should not display:

- Drag-and-drop import regions.
- Add buttons.
- Any UI that implies importing or appending more files to this batch.

It should still display:

- File list for the current batch.
- Video preview.
- Segments list.
- Presets.
- Waveform.
- Subtitle and translation controls.
- Existing correction / enhancement / export tools.

## Proposed architecture

### Window coordinator

Introduce a focused window management layer, e.g. `AICutWindowCoordinator`, responsible for:

- Opening the progress window.
- Closing the progress window.
- Opening the editor window.
- Bringing the editor window to the front.
- Keeping the window transition order deterministic.

This coordinator owns window lifecycle only. It does not own transcription logic or batch state.

### Flow model responsibilities

`AICutFlowModel` remains the owner of the flow state machine and batch state:

- `landing`
- `importSetup`
- `transcribing`
- `editing`

It remains the canonical owner of batch item statuses and completion rules. It should not be bypassed by ad hoc progress calculations from separate local state.

### Editor mode separation

The editor layout should gain an explicit editing-only mode. The simplest acceptable version is a mode argument that removes source import affordances from the existing left-side panel. For example:

```swift
enum AICutEditorSourceMode {
  case importable
  case editingOnly
}
```

In `editingOnly` mode:

- No Add button.
- No drop/import area.
- No import language/setup affordances.
- File list stays available for navigating the current batch only.

### Progress presentation source of truth

The progress window should derive its visible progress from `AICutFlowModel.currentBatch`, not from a parallel mix of:

- `batchTranscriptionProgress`
- `statusText`
- local counters
- sheet/window-local progress bookkeeping

The model’s batch items should drive:

- Total progress fraction.
- Running file.
- Succeeded count.
- Failed count.
- Final completion.

`batchTranscriptionProgress` may remain for compatibility with older status surfaces, but it is no longer the primary source for the new progress window.

## Window behavior details

### Progress window lifecycle

- Opening import transcription starts the real batch task and opens the progress window.
- Closing/canceling the progress window cancels the live batch if it is still running.
- If the batch is canceled before editing is reached, the flow returns to landing.

### Editor window lifecycle

- The editor window is created only after the flow model reaches `.editing`.
- It is populated only with successful files, in original import order.
- It becomes key/frontmost after the progress window has been closed.
- If all files fail, the editor window is not opened.

### Transition ordering

This order is required and intentional:

1. Batch reaches terminal state.
2. Flow model determines whether editing is reachable.
3. If editing is reachable, close the progress window.
4. Build editor workspace state from successful batch files.
5. Open editor window.
6. Make editor window key/frontmost.

## Data flow

### Import start

- User confirms import setup.
- Flow model creates the batch and enters `.transcribing`.
- The progress window opens immediately.

### Batch execution

- Each file updates the flow model batch item state through `markFileRunning`, `markFileSucceeded`, and `markFileFailed`.
- The progress window reacts to `currentBatch`.

### Enter editing

- When all items are terminal, the flow model reaches `.editing` if at least one file succeeded.
- Successful files are used to build the editor workspace state.
- The editor window opens only after progress window teardown.

## Progress correctness rules

To fix the current progress issues, use these rules consistently:

1. `pending` means not started.
2. `running` means the active file.
3. `succeeded` and `failed` are the only terminal states.
4. Overall progress = terminal item count / total item count.
5. The active file label is the first `running` item if any.
6. If no item is running but the batch is still being prepared, show preparation copy rather than misleading file progress text.
7. The per-file list must reflect model batch item statuses directly rather than inferred strings from unrelated state.

## Error handling

### Partial success

- If one or more files succeed, the editor window opens with only successful files.
- Failed files remain visible only in the progress/result accounting layer, not as editable files in the editor window.

### Total failure

- If all files fail, close the progress window and return to landing.
- Do not open the editor window.
- Surface an actionable failure summary.

### Cancellation

- Cancel during progress closes the progress window and returns to landing if editing was not reached.
- If cancellation happens after the flow has already legitimately entered `.editing`, it must not tear down the editor workspace.

## Testing strategy

Follow TDD for each behavior change. Add focused tests before changing production code.

Key tests:

1. Opening transcription creates a progress-window state/event.
2. Progress state derives from flow model batch items rather than sidebar/local counters.
3. Partial success preserves import order among successful files when opening the editor window.
4. Total failure closes progress and returns to landing.
5. Cancellation from the progress window returns to landing unless editing is already active.
6. Editor window creation happens only after progress window closure.
7. Editor mode hides Add and drag-and-drop affordances completely.

## Implementation notes

- Prefer introducing a dedicated coordinator rather than burying window lifecycle logic in `AICutView`.
- Keep `AICutEditorView` reusable, but pass an explicit editing-only mode to remove import controls.
- Avoid mutating editor workspace state before the model has legitimately reached `.editing`.
- Preserve the existing editor interactions once editing starts.
