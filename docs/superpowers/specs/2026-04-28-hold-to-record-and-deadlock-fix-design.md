# Hold-to-Record + CGEventTap Deadlock Fix

**Date:** 2026-04-28
**Status:** Draft

## Problem

Two issues with the current keyboard shortcut system:

1. **Crash**: `DispatchQueue.main.sync` in the CGEventTap callback deadlocks when the callback executes on the main thread (which happens when the event tap run loop source is on the main run loop). Result: `EXC_BREAKPOINT` on Right ⌘ + Space.

2. **Missing hold-to-record**: Long-pressing Right ⌘ or Right ⌘ + Right ⇧ should start recording directly (hold = record, release = stop & process). Currently, a modifier press only toggles mode; recording requires a separate Space press.

## Design

### Bug Fix: CGEventTap Thread Safety

**Root cause:** `DispatchQueue.main.sync` called from a CGEventTap callback that may already be on the main thread.

**Fix:** Replace `DispatchQueue.main.sync` with a lock-protected `nonisolated` snapshot of `activeMode`. Use `os_unfair_lock` (lowest overhead, no priority inversion) to protect a `activeModeSnapshot: VoiceShortcutMode?` that mirrors `activeMode`. The main-thread setter updates both `activeMode` and the snapshot under the lock. The CGEventTap callback reads only the snapshot under the lock—no GCD needed.

```
Main thread:                  CGEventTap callback (any thread):
  lock.lock()                   lock.lock()
  _snapshot = activeMode        let mode = _snapshot
  lock.unlock()                 lock.unlock()
```

### Feature: Hold-to-Record

**Interaction model — Approach B (immediate mode + auto-escalation):**

When a mode key combo is pressed:
1. Immediately activate the mode (enter `ready` phase) — no delay.
2. Start a hold timer (0.3s threshold).
3. If the key is **released before** the timer fires → it was a **tap** → stay in `ready` phase (user can use Space to record).
4. If the timer fires while the key is still held → it was a **hold** → auto-start recording.
5. On key **release after hold** → stop recording → end session → process result.

This means:
- **Tap** Right ⌘ → enter dictation mode → Space to record/stop → tap Right ⌘ again to exit
- **Hold** Right ⌘ → dictation records while held → release stops & processes
- Same pattern for Right ⌘ + Right ⇧ (assistant mode)

**New event phases in `ShortcutEvent`:**
- `holdRecordingStarted` — timer fired, recording should begin
- `holdRecordingEnded` — modifier released after hold

The existing `modeActivated`, `modeDeactivated`, and `spaceToggle` remain unchanged.

### Changes by File

**KeyboardShortcutManager.swift:**
- Add `os_unfair_lock` + `activeModeSnapshot` for thread-safe CGEventTap access
- Add `holdTimer: DispatchSourceTimer?` started on mode key press
- Track `isHoldRecording: Bool` to know if we're in hold-to-record flow
- On modifier release: if `isHoldRecording`, emit `holdRecordingEnded`; else if mode was just activated by tap, it stays in ready
- On modifier release: if in tap-toggled mode (not hold), just track modifier state (mode persists)
- Add `holdRecordingStarted` and `holdRecordingEnded` to `ShortcutEvent.Phase`

**ContentView.swift:**
- Handle `holdRecordingStarted`: call `shortcutState.startRecording()` + start transcriber
- Handle `holdRecordingEnded`: call `shortcutState.stopRecording()` + stop transcriber + `endSession()`

**VoiceShortcutState.swift:**
- No changes needed — existing `activateMode`/`startRecording`/`stopRecording`/`endSession` flow covers both tap+Space and hold patterns

### Edge Cases

1. **Hold Right ⌘, then press Right ⇧ mid-hold**: Ignore the shift press — mode is already locked to dictation for this session.
2. **Tap Right ⌘ (mode active), then hold Right ⌘ (same mode)**: Second press deactivates mode (existing toggle behavior). Hold detection only applies to the initial activation press.
3. **Hold threshold**: 0.3s. Short enough to feel responsive, long enough to avoid false holds.
4. **Hold while Space-recording in progress**: If user tapped to enter mode, started Space recording, then presses the mode key again — that's a mode deactivation (existing behavior). Hold detection only fires on mode activation.
5. **CGEventTap runs on main thread**: Fixed by lock-based snapshot. No `DispatchQueue.main.sync`.

### Testing Strategy

- Unit tests for hold timer logic (tap vs hold discrimination)
- Unit tests for thread-safe snapshot reads
- Existing VoiceShortcutState tests remain valid (no state machine changes)
