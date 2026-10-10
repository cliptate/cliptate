# Design: Download Progress Fix & Speaker Display in Segments

**Date**: 2026-04-21  
**Status**: Approved

---

## Problem 1: Download Progress Jumps to 100% Prematurely

### Root Cause

`ModelDownloadManager.hasLocalModel()` only checks that files **exist**, not that they are **complete**. If a prior download was interrupted, partial files remain on disk:
- directory exists ✓
- `config.json` exists ✓
- `.safetensors` file exists (0 bytes or partial) ✓

This causes the early-exit guard at the top of `downloadMLXAudioModel` / `downloadParakeetModel` to fire immediately, reporting `progress: 1.0` even though the model is broken.

Additionally, the simulated progress (timer-based, +0.15 or +0.18 per 2s) reaches 0.95 in ~12 seconds then stalls — misleading for large models (400–2000 MB).

### Solution

**1. Fix `hasLocalModel()` to match the library's own validation**

The underlying `ModelUtils.resolveOrDownloadModel` already checks `fileSize > 0` for safetensors files and validates `config.json` is parseable JSON. `hasLocalModel()` must enforce the same rules:

- `config.json` exists AND parses as valid JSON
- At least one `.safetensors` file exists AND has `fileSize > 0`

**2. Replace time-based simulated progress with file-size polling**

Since `ModelVariant.fileSize` gives approximate expected sizes (in MB), we can poll the actual download directory size every 0.5s and derive a real-ish progress:

```
progress = min(actualDirectorySizeMB / expectedSizeMB, 0.95)
```

This reflects actual bytes written to disk, not wall-clock time.

### Architecture

- `hasLocalModel(for:)` — tighten validation (check `fileSize > 0`, validate JSON)
- `downloadMLXAudioModel(_:progressHandler:)` — replace `progressTask` with `fileSizeProgressTask`
- `downloadParakeetModel(_:progressHandler:)` — same
- New helper `pollFileSizeProgress(at:expectedMB:)` — returns async stream/task that polls and reports bytes

### Behaviors to Test

1. `hasLocalModel` returns `false` when safetensors file has zero bytes
2. `hasLocalModel` returns `false` when config.json is invalid/missing JSON content
3. `hasLocalModel` returns `true` when safetensors > 0 bytes AND config.json is valid JSON
4. File-size progress polling: `computeProgress(actualMB:expectedMB:)` correctly clamps to [0, 0.95]

---

## Problem 2: Speaker Identity Not Shown in Segments List

### Current State

`Segment.speakerId: Int?` exists and is populated by the diarization pipeline (Sortformer), but `SegmentRowView` does not render it.

### Solution

Add a compact speaker badge `S1`, `S2`, etc. in the time-display row (alongside `→` time arrow). Badge is:
- Only shown when `speakerId != nil`
- Color-coded using a fixed palette of 8 colors (cycles for speaker index ≥ 8)
- Rendered as a capsule-shaped label to match the app's existing badge style

### Architecture

- `SegmentRowView` — add speaker badge to the times `HStack`
- New pure function `speakerColor(id: Int) -> Color` — deterministic, testable
- New `speakerBadgeText(id: Int) -> String` — returns "S1", "S2", etc.

### Behaviors to Test

1. `speakerColor(id: 0)` returns first palette color
2. `speakerColor(id: 8)` wraps around (same color as id 0)
3. `speakerBadgeText(id: 0)` returns `"S1"` (1-indexed for user display)
4. `speakerBadgeText(id: 7)` returns `"S8"`

---

## TDD Plan

### Red-Green Cycles (vertical slices)

**Cycle 1** *(tracer bullet)*: `hasLocalModel` rejects zero-byte safetensors  
**Cycle 2**: `hasLocalModel` rejects invalid/empty config.json  
**Cycle 3**: `hasLocalModel` accepts valid files (regression guard)  
**Cycle 4**: `computeProgress(actualMB:expectedMB:)` clamps to [0, 0.95]  
**Cycle 5**: `speakerBadgeText` returns 1-indexed label  
**Cycle 6**: `speakerColor` wraps correctly at palette boundary  

---

## Files Changed

| File | Change |
|------|--------|
| `Services/ModelDownloadManager.swift` | Fix `hasLocalModel()`, replace simulated progress with file-size polling |
| `Views/SegmentsPanelView.swift` | Add speaker badge to `SegmentRowView` |
| `Tests/Services/ModelDownloadManagerTests.swift` | New tests for file-size validation |
| `Tests/Models/SegmentTests.swift` | New tests for speaker badge helpers |
