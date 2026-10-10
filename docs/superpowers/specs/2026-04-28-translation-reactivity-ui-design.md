# Translation Display, Config Reactivity & UI Restructuring

**Date**: 2026-04-28
**Status**: Proposed

## Problem Statement

Four interrelated issues degrade the editing experience:

1. **Translations not visible in subtitle area** — FCPXML export contains translations, but neither the VideoPlayerView subtitle overlay nor the SegmentsPanelView shows them after translation completes.
2. **Config changes not real-time** — Modifying subtitle styles, translation placement, padding, filtering, and enhancement settings doesn't reliably update the preview.
3. **Translation button unresponsive on re-translate** — When translations already exist, clicking Translate again may have no visible effect.
4. **Translation button placement** — Currently buried in the SegmentsPanelView header; should be in the ControlPanelView alongside other batch/single operations.

## Root Cause Analysis

### RC1: `Segment.Equatable` excludes `translation`

```swift
// DataTypes.swift:114-124
extension Segment: Equatable {
  public static func == (lhs: Segment, rhs: Segment) -> Bool {
    lhs.startTime == rhs.startTime
      && lhs.endTime == rhs.endTime
      && lhs.text == rhs.text
      && lhs.words == rhs.words
      && lhs.confidence == rhs.confidence
      && lhs.speakerId == rhs.speakerId
    // ⚠️ translation NOT compared
  }
}
```

When `processedSegments = currentSegments` is set in `markTranslationsChanged()`, SwiftUI may treat the arrays as "equal" because translation differences are invisible to `==`. This breaks change propagation to child views.

### RC2: Fragile `translationsVersion` workaround

The current workaround (`translationsVersion` counter) requires every consuming view to explicitly watch it. Missing a single `.onChange(of: translationsVersion)` silently breaks translation display.

### RC3: Config signature incomplete

`segmentProcessingSignature` in AICutView drives the debounced reprocessing task. It includes segment processing fields (padding, splitting, filtering) but subtitle style, translation placement, and some enhancement configs are only passed as direct view parameters. If the parent body doesn't re-evaluate (e.g., due to SwiftUI optimizing away "equal" state changes), these parameters go stale.

### RC4: Translation button state

The `isTranslating` flag may not be cleared if the translation task is cancelled or fails under certain race conditions, permanently disabling the button.

## Design

### Change 1: Include `translation` in `Segment.Equatable`

Add `translation` to the `==` comparison:

```swift
extension Segment: Equatable {
  public static func == (lhs: Segment, rhs: Segment) -> Bool {
    lhs.startTime == rhs.startTime
      && lhs.endTime == rhs.endTime
      && lhs.text == rhs.text
      && lhs.words == rhs.words
      && lhs.confidence == rhs.confidence
      && lhs.speakerId == rhs.speakerId
      && lhs.translation == rhs.translation
  }
}
```

**Impact**: SwiftUI will now detect translation changes in segment arrays, triggering proper view updates. The separate `translationsVersion` mechanism becomes a redundant backup (can be kept for safety or removed in a follow-up).

**Risk**: Some places may rely on translation-excluded equality for deduplication or caching. We'll audit callers of `==` on `[Segment]` to ensure no unintended side effects.

### Change 2: Config reactivity audit

Ensure all config changes propagate to the preview:

- **Subtitle styles** (`config.subtitleStyles`): Already passed to VideoPlayerView as `styleConfiguration` with `.onChange(of: styleSignature)`. Verify the parent re-evaluates.
- **Translation placement** (`config.translationPlacement`): Passed directly. Verify `.onChange(of: translationPlacement)` fires.
- **Enhancement effects**: `effectsVersion` counter already exists. Verify `resolvedEffects(for:)` is re-evaluated.
- **Segment processing** (padding, splitting, filtering): Already in `segmentProcessingSignature`. Should work.

Key fix: Since `Segment.==` now includes `translation`, `processedSegments = currentSegments` will properly register as a change when translations differ, causing AICutView body to re-evaluate and pass fresh values to all child views.

### Change 3: Move translation to ControlPanelView

**Batch actions row**: Add a Translate button (globe icon) alongside existing batch actions (Transcribe All, AI Correct, AI Enhance, Export).

**Per-video buttons**: Add a Translate button per video row, alongside existing per-video actions.

New callbacks required in ControlPanelView:
- `onTranslate: () -> Void` — translate active video's segments
- `onTranslateAll: () -> Void` — translate all transcribed videos' segments

New state parameters:
- `isTranslating: Bool` — to show progress and disable button

Remove the translate button from SegmentsPanelView header.

### Change 4: Fix translation button responsiveness

1. Ensure `isTranslating = false` is always set in all exit paths (success, error, cancellation) — audit the `defer` blocks.
2. Allow re-translation when translations exist: no change needed (code already allows it).
3. Add a force-reset mechanism: if `isTranslating` is true but no active task exists, reset it.

## Files to Modify

| File | Change |
|------|--------|
| `Models/DataTypes.swift` | Add `translation` to `Segment.==` |
| `Views/ControlPanelView.swift` | Add translate buttons (batch + per-video), new callbacks |
| `Views/AICutEditorView.swift` | Wire new translate callbacks |
| `Views/AICutView.swift` | Pass translate handlers, add `translateAllVideos()`, audit `isTranslating` reset |
| `Views/SegmentsPanelView.swift` | Remove translate button from header |

## Testing Strategy

- **Unit test**: Verify `Segment.==` now detects translation differences
- **Unit test**: Verify `Segment.==` still correctly compares all other fields
- **Unit test**: Verify `translateAllVideos()` logic (if testable)
- **Manual test**: Translate → verify subtitle overlay updates immediately
- **Manual test**: Change config (style, placement, padding) → verify real-time update
- **Manual test**: Click Translate with existing translations → verify re-translation works
- **Manual test**: Verify batch + single translate buttons in ControlPanelView
