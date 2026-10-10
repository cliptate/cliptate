# Shortcut Mode Redesign: Distinct Keys + Space Recording

## Problem

The current voice-to-text shortcut system conflates mode selection with recording control. Right Cmd is a toggle for dictation, Right Shift is hold-to-talk for assistant, and the long-press threshold (`VoiceShortcutState.longPressThreshold`) adds unnecessary complexity. The user wants a clearer separation:

- **Right Cmd** = dictation mode
- **Right Cmd + Right Shift** = assistant mode
- **Space** = start/stop recording within either mode
- AI Enhance must output in the selected `voiceToTextLanguage` for both modes

## Design

### Interaction Model

**Toggle-Mode + Space Recording:**

The mode key is a **toggle**: tapping it enters the mode, tapping it again exits. The mode **persists after the modifier key is released** — releasing Right Cmd does NOT end the session. Only a second deliberate tap of the same mode key ends it.

1. **Enter mode**: Tap Right Cmd (press + release with no other modifier held) → dictation session begins (UI indicator). Hold Right Cmd, then tap Right Shift (press + release of Right Shift while Right Cmd is still held, in either order) → assistant session begins.
2. **Record**: Press Space (keyDown, `isARepeat == false`) to start recording. Press Space again to stop recording. Press Space again to start a new recording segment. Multiple start/stop cycles allowed for long sessions. Each segment is captured independently and merged before post-processing.
3. **End session**: Tap the same mode key combo again → session ends, all recording segments are merged, post-processing triggers with the accumulated transcript.
4. **Cancel/Switch**: If the user activates the *other* mode while a session is active, the current session is discarded (no post-processing, partial audio discarded), and a new session begins in the new mode.

**Combo detection (Right Cmd + Right Shift for assistant):**
- Accepted sequences: Either Right Cmd then Right Shift, or Right Shift then Right Cmd — order does not matter.
- The combo is recognized when both keyCode 54 (Right Cmd) and keyCode 60 (Right Shift) are simultaneously held. This is detected by tracking individual key states via `flagsChanged` events using `event.keyCode`, NOT via `.command`/`.shift` modifier flags (which are side-agnostic).
- When both are held, the mode is assistant. When Right Shift is released (while Right Cmd is still held), the state does NOT downgrade — the mode was already selected.

State machine:

```
Idle ──[RCmd tap]──► Dictation:Ready ──[Space]──► Dictation:Recording
                                       ◄──[Space]──┘ (stop segment, stays Ready)
                     ──[RCmd tap]──► Idle (end session, merge segments, process)

Idle ──[RCmd+RShift]──► Assistant:Ready ──[Space]──► Assistant:Recording
                                          ◄──[Space]──┘ (stop segment, stays Ready)
                        ──[RCmd+RShift]──► Idle (end session, merge segments, process)
```

### Recording Segments (no pause/resume needed)

The current `VoiceTranscriber` exposes `start()` and `stop()` but no `pause()`/`resume()`. Rather than adding pause/resume semantics, Space performs **start/stop of recording segments**:

- Each Space press calls `VoiceTranscriber.start()` or `.stop()` alternately.
- `stop()` produces a `TranscriptionResult` for that segment.
- All segment results are accumulated in `VoiceShortcutState.accumulatedTranscript`.
- When the session ends (mode key tapped again), the accumulated transcript is sent to post-processing.
- This avoids changes to the transcriber layer entirely.

### KeyboardShortcutManager Changes

**Remove:**
- `VoiceToggleShortcutPreset` enum and all preset-related logic
- `longPressThreshold` from `VoiceShortcutState`
- Hold vs toggle `InteractionStyle` distinction
- All preset monitors, preset persistence, preset selection UI

**Add:**
- `CGEventTap`-based key monitoring (replaces NSEvent global monitors for key events) to enable **suppression** of Space when a mode is active. This prevents Space from typing into the frontmost app during recording.
- `flagsChanged` monitoring continues to use NSEvent monitors (observation-only is fine for modifier keys — they don't type characters).
- Internal state: `isRightCmdHeld: Bool`, `isRightShiftHeld: Bool`, `activeMode: VoiceShortcutMode?`

**Event flow:**

1. **flagsChanged (NSEvent monitors)**: Track `isRightCmdHeld` and `isRightShiftHeld` via `event.keyCode` (54 and 60 respectively). On state change:
   - If both held → emit `.modeActivated(.assistant)` (if not already in assistant)
   - If only Right Cmd was tapped (pressed and released without Right Shift) → toggle dictation mode
   - Mode activation/deactivation is toggled: first tap enters, second tap exits
2. **CGEventTap (for keyDown/keyUp)**: When `activeMode != nil` and keyCode is 49 (Space) and `isARepeat == false`:
   - Suppress the event (return `nil` from the tap callback to prevent it from reaching the frontmost app)
   - Emit `.spaceToggle` to the shortcut handler
3. When `activeMode == nil`, the CGEventTap passes Space through unmodified.

**Permissions**: CGEventTap requires **Input Monitoring** (macOS 10.15+) or **Accessibility** permission. The app already requests Accessibility for its existing global event monitors. If the tap cannot be created (permission denied), fall back to NSEvent global monitor (Space will type into apps but recording still works) and show a permission prompt.

### VoiceShortcutState Changes

Replace current properties with:

```swift
enum SessionPhase {
    case idle           // no active mode
    case ready          // mode selected, not recording
    case recording      // actively recording a segment
}

@Published var activeMode: VoiceShortcutMode?  // nil when idle
@Published var phase: SessionPhase = .idle
var accumulatedTranscript: String = ""  // merged text from all segments
```

Remove: `longPressThreshold`, `pendingMode`, `isSessionActive`, `consumePendingMode()`

Add:
- `activateMode(_:)` — set mode, phase = .ready, clear accumulated transcript
- `startRecording()` / `stopRecording()` — phase transitions, called by Space toggle
- `appendSegmentText(_:)` — append completed segment text to accumulatedTranscript
- `endSession() -> (mode: VoiceShortcutMode, transcript: String)?` — return mode + accumulated transcript for post-processing, reset to idle

### ContentView.handleGlobalVoiceShortcut Changes

Replace the current began/ended handler with mode-aware logic:
- On `.modeActivated(mode)`: capture frontmost app, switch to Voice-to-Text tab, call `VoiceShortcutState.shared.activateMode(mode)`
- On `.spaceToggle`: if phase is `.ready`, call `VoiceTranscriber.shared.start(...)` and `shortcutState.startRecording()`. If phase is `.recording`, call `VoiceTranscriber.shared.stop()` and `shortcutState.stopRecording()`, then append the segment's combinedText.
- On `.modeDeactivated(mode)`: stop transcriber if recording, call `shortcutState.endSession()`, trigger post-processing with the returned transcript and mode.

### AI Enhance Language Output

**Problem:** `AIPrompts.dictationSystemPrompt` has a `%@` placeholder for "Important Rules" that is never formatted. Neither dictation nor assistant prompts tell the AI what language to output in.

**Solution:** Add language-specific rules to both prompts when AI Enhance is active:

1. Add `AIPrompts.languageOutputRule(for: Language) -> String` that returns:
   - For `.auto` or `.english`: `"Output your response in English."`
   - For other languages: `"IMPORTANT: Your output MUST be entirely in {language.displayName}. If the transcript is in a different language, translate it to {language.displayName}. Do not mix languages."`

2. Wire this into `startDictationAutofix`:
   - Format the `%@` in `dictationSystemPrompt` with the language rule: `String(format: AIPrompts.dictationSystemPrompt, languageRule)`
   - Pass `config.voiceToTextLanguage` to construct the rule

3. Wire into `startAssistantCommand`:
   - Append language rule to the `assistantMode` system prompt: `AIPrompts.assistantMode + "\n\n" + languageRule`

### UI Changes (VoiceToTextView)

**Shortcut Modes Section:** Replace the current "Short press" / "Long press ≥ 0.7s" cards with:
- **Dictation card**: "Right ⌘ · Tap to enter, Space to record"
- **Assistant card**: "Right ⌘ + Right ⇧ · Tap to enter, Space to record"
- Remove the shortcut preset picker UI (no more customizable presets)

**Recording indicator:** When a mode is active but not recording, show "Ready — press Space to record". When recording, show the existing waveform/timer. When stopped between segments, show "Segment saved — press Space to record more, or tap mode key to finish".

### Files to Modify

1. `Sources/VoiceFlowPro/Utilities/KeyboardShortcutManager.swift` — Major rewrite: CGEventTap for Space, flagsChanged for modifiers, state machine
2. `Sources/VoiceFlowPro/Utilities/VoiceShortcutState.swift` — New state machine with segment accumulation
3. `Sources/VoiceFlowPro/Views/ContentView.swift` — Updated shortcut handler with mode/space/deactivation events
4. `Sources/VoiceFlowPro/Views/VoiceToTextView.swift` — UI updates for mode indicators, remove preset picker, language-aware AI calls
5. `Sources/VoiceFlowPro/Models/AIPrompts.swift` — `languageOutputRule(for:)` function
6. Tests for: VoiceShortcutState state machine, AIPrompts language rules

### Edge Cases

- **Space suppression**: CGEventTap returns `nil` for Space keyDown/keyUp when `activeMode != nil`, preventing it from reaching the frontmost app. When `activeMode == nil`, Space passes through unmodified.
- **Space key repeat**: Only respond to `isARepeat == false` to prevent rapid toggles from held Space.
- **Focus lost during session**: Session remains active (CGEventTap and global flagsChanged monitors work regardless of app focus).
- **Rapid mode switching**: If dictation is active and user activates assistant combo, dictation session is discarded (accumulated transcript lost, no post-processing), assistant session starts fresh.
- **Permissions**: CGEventTap requires Input Monitoring permission. On failure, fall back to observation-only NSEvent monitor (Space types into apps but recording still works). Show permission prompt in VoiceToTextView.
- **Assistant combo ordering**: Either Right Cmd then Right Shift, or Right Shift then Right Cmd — both recognized. Simultaneous press treated as combo.
