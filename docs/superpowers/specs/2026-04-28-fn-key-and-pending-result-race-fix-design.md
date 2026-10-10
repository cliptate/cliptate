# Fix: Fn Key Not Working & Hold-to-Record Pending Result Race

## Problem

Two bugs in the voice shortcut system:

1. **Fn key doesn't trigger dictation.** On modern macOS, the Fn/Globe key is intercepted by the system (Emoji picker, Input Source, Dictation) before NSEvent monitors see it. The default preset (Fn) doesn't work out of the box.

2. **Hold-to-record post-processing never runs.** `endSession()` is called before the transcriber delivers text, so `pendingResult` has an empty transcript. `processShortcutPostProcessingIfNeeded` consumes the empty result and skips post-processing (AI Enhance, assistant).

## Design

### Bug 1: Default Preset

Change default from `.function` to `.rightCommand` in `VoiceToggleShortcutPreset`. Keep Fn as an option. Use new UserDefaults keys (`V3`) to avoid stale values.

### Bug 2: Two-Phase Session End

Replace `endSession()` with a two-phase pattern:

**Phase 1 — `requestEndSession()`** (called from ContentView event handler):
- Stores `pendingEndMode = activeMode`
- Clears `activeMode` (so `processShortcutPostProcessingIfNeeded` won't return early)
- Sets `phase = .idle`
- Does NOT capture transcript, does NOT create `pendingResult`

**Phase 2 — `finalizeEndSession()`** (called in `processShortcutPostProcessingIfNeeded` after text is appended):
- Checks `pendingEndMode != nil`
- Creates `SessionResult` with current `accumulatedTranscript`
- Clears `accumulatedTranscript` and `pendingEndMode`
- Stores in `pendingResult`

**Flow for hold-to-record:**
1. User releases key → `requestEndSession()` → `pendingEndMode = .dictation`, `activeMode = nil`
2. Transcriber finishes → `processShortcutPostProcessingIfNeeded` → appends text → `finalizeEndSession()` creates result with text → post-processing runs

**Flow for space-toggle (deactivate after idle):**
1. Previous recordings already accumulated text
2. User releases mode key → `requestEndSession()` → `pendingEndMode = .dictation`
3. Transcriber is already idle — need explicit trigger
4. Solution: call `processShortcutPostProcessingIfNeeded()` from VoiceToTextView via `onChange(of: shortcutState.activeMode)` when it becomes nil

### ContentView Changes

Replace `_ = shortcutState.endSession()` with `shortcutState.requestEndSession()` in both `.modeDeactivated` and `.holdRecordingEnded` handlers.

### VoiceToTextView Changes

Add `onChange(of: shortcutState.activeMode)` to trigger `processShortcutPostProcessingIfNeeded()` when mode becomes nil and transcriber is already idle.

Update `processShortcutPostProcessingIfNeeded()`:
1. Append segment text
2. Call `shortcutState.finalizeEndSession()` if pending
3. Consume pending result
4. Route to dictation/assistant post-processing

## Files Changed

- `Sources/VoiceFlowPro/Utilities/VoiceShortcutState.swift` — two-phase session end
- `Sources/VoiceFlowPro/Models/VoiceToggleShortcutPreset.swift` — default to Right Cmd
- `Sources/VoiceFlowPro/Utilities/KeyboardShortcutManager.swift` — V3 keys
- `Sources/VoiceFlowPro/Views/ContentView.swift` — use requestEndSession()
- `Sources/VoiceFlowPro/Views/VoiceToTextView.swift` — finalizeEndSession + onChange trigger
- `Sources/VoiceFlowProTests/Utilities/VoiceShortcutStateTests.swift` — new tests
