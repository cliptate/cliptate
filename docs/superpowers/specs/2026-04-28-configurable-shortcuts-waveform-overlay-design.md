# Configurable Shortcuts, Waveform Polish, and Overlay Lifecycle

**Date:** 2026-04-28
**Status:** Draft

## Problem

Three related improvements to the voice-to-text shortcut system:

1. The shortcut key redesign (commit d7f4572) removed the configurable preset system. Users can no longer choose which keys trigger dictation/assistant modes. Default should change from Right ⌘ to **Fn** (dictation) and **Fn+Shift** (assistant).

2. The waveform visualizer uses uniform random multipliers. The user wants a natural center-high/sides-low shape with weights `[0.5, 0.8, 1.0, 0.75, 0.55]` and ±4% random jitter for organic feel.

3. The floating overlay (`MicIndicatorOverlay`) closes as soon as transcription stops. It should remain visible during post-processing (Transcribe → AI Enhance), showing a status indicator and spinner.

---

## Subsystem A: Restore Configurable Shortcut Keys

### Design

Restore `VoiceToggleShortcutPreset` with the original modifier key options from commit c5775ad, but adapted to the new toggle+hold interaction model:

**Presets (same as old system):**
- `.function` (Fn, keyCode 63) — **new default for dictation**
- `.rightCommand` (Right ⌘, keyCode 54)
- `.rightShift` (Right ⇧, keyCode 60)
- `.rightOption` (Right ⌥, keyCode 61)
- `.leftOption` (Left ⌥, keyCode 58)
- `.rightControl` (Right ⌃, keyCode 62)
- `.leftControl` (Left ⌃, keyCode 59)
- `.custom` (via KeyboardShortcuts library)

**Default configuration:**
- Dictation: `.function` (Fn)
- Assistant: `.function` + Shift (Fn+Shift combo)

**Interaction model (unchanged from current):**
- **Tap** the dictation key → toggle dictation mode, use Space to record
- **Hold** the dictation key (≥0.3s) → immediate recording, release to stop
- **Tap/hold** the assistant combo → same pattern for assistant mode
- Space suppression via CGEventTap remains active during any mode

**Storage:** UserDefaults keys `"VoiceToTextDictationPreset"` and `"VoiceToTextAssistantPreset"` (same as old system).

**KeyboardShortcutManager changes:**
- Restore `VoiceToggleShortcutPreset` enum
- `processFlagsChanged` reads the configured preset keyCodes instead of hardcoded 54/60
- Keep the hold timer, CGEventTap, and `OSAllocatedUnfairLock` snapshot from recent work
- Restore `applyPreset(_:for:)`, `currentPreset(for:)`, `updateShortcut(_:for:)` methods

**VoiceToTextView changes:**
- Restore dictation/assistant shortcut picker rows in the UI
- Show current preset name in the shortcut modes section (instead of hardcoded "Right ⌘" / "Right ⌘ + Right ⇧")

### Edge Cases

- Fn key on some external keyboards may not send `.function` modifier flag. Fall back to rightCommand if Fn detection fails on first use.
- If both dictation and assistant are set to the same key, assistant combo requires that key + Shift (like current Fn+Shift model).

---

## Subsystem B: Waveform Shape and Jitter

### Design

The current visualizer uses 24 bars with random multipliers (`CGFloat.random(in: 0.5...1.5)`). Replace with a 5-element weight pattern `[0.5, 0.8, 1.0, 0.75, 0.55]` that tiles across bars, forming a natural center-high/sides-low envelope, plus ±4% random jitter per frame.

**Weight assignment:**
- Define `static let barWeights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]`
- For each bar `i`, base weight = `barWeights[i % barWeights.count]`
- Mirror from center: compute distance from center, blend weight with center emphasis
- Per-frame jitter: multiply by `CGFloat.random(in: 0.96...1.04)` in `updateTargets(for:)`

**Changes in `MicIndicatorView`:**
- Replace `self.multipliers = (0..<24).map { _ in CGFloat.random(in: 0.5...1.5) }` with the weighted pattern
- In `updateTargets(for:)`, apply ±4% jitter to each bar's target height per update cycle

---

## Subsystem C: Overlay Lifecycle and Status Display

### Design

Currently, `MicIndicatorOverlay.stopTracking()` is called in `updateMicIndicator(for:)` when `VoiceTranscriber.state != .running`. The overlay closes immediately when transcription stops, before AI post-processing.

**New lifecycle:**
1. `startTracking()` — called when recording starts (unchanged)
2. When recording stops → overlay stays open, shows "Transcribing..." status
3. When post-processing begins → shows "AI Enhance..." status with spinner
4. When post-processing completes (or fails) → overlay closes after brief delay (0.5s)

**Implementation:**

Add a `status` property to `MicIndicatorViewModel`:

```swift
enum OverlayStatus {
  case idle
  case listening
  case transcribing
  case aiEnhance
}
```

**MicIndicatorOverlay API additions:**
- `updateStatus(_ status: OverlayStatus)` — updates the displayed status label and spinner
- `finishAndDismiss()` — shows completion briefly, then calls `stopTracking()` after 0.5s delay

**Callers:**
- `VoiceTranscriber.updateMicIndicator(for:)` — stop calling `stopTracking()` directly when state leaves `.running`. Instead, update status to `.transcribing`.
- `VoiceToTextView.processShortcutPostProcessingIfNeeded()` — update overlay status to `.aiEnhance` when starting AI post-processing, call `finishAndDismiss()` when done.
- `ContentView.handleGlobalVoiceShortcut(.modeDeactivated/.holdRecordingEnded)` — if no post-processing needed, call `finishAndDismiss()` directly.

**Visual changes to `MicIndicatorView.waveformSection`:**
- The existing `VisualizerState.label` maps to "Idle"/"Ready"/"Listening". Add "Transcribing"/"AI Enhance" labels.
- Show `ProgressView()` spinner for `.transcribing` and `.aiEnhance` states (similar to existing `ProgressAnimation` for `.listening`).

---

## Testing Strategy

- **Subsystem A**: Unit test preset storage/retrieval round-trip, keyCode mapping
- **Subsystem B**: Unit test weight pattern generation (verify center-high/sides-low shape, jitter bounds)
- **Subsystem C**: Unit test overlay status transitions, finishAndDismiss timing
- Existing hold-detection tests and VoiceShortcutState tests remain valid
