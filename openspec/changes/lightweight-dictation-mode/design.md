## Context

VoiceFlowPro is a macOS app with voice dictation, AI Cut video editing, and TTS. The app currently requires the full SwiftUI ContentView hierarchy to be rendered for hotkey-triggered dictation to work. The history page counts words using simple whitespace splitting (`components(separatedBy:).filter`)  while VoiceToTextView uses `voiceTextWordCount()` with `enumerateSubstrings(.byWords)` — a system linguistic tokenizer that correctly handles CJK word boundaries.

Dictation sessions retain audio files (M4A, 24h retention) but the HistoryView only exposes playback for TTS sessions. File transcription sessions have "Open in AI Cut" but lack re-transcribe and reveal-in-Finder actions.

## Goals / Non-Goals

**Goals:**
- Allow the app to operate without rendering the main window (lightweight/menu-bar mode)
- Ensure hotkey dictation works in lightweight mode
- Fix word counting in HistoryView to match VoiceToTextView's linguistic tokenizer
- Expose audio playback with seek for dictation sessions in history
- Add re-transcribe and reveal-in-Finder for file transcription sessions in history

**Non-Goals:**
- Replacing the app's existing full-UI mode
- Changing audio retention policy (stays at 24h for dictation)
- Adding new hotkey binding UI (existing KeyboardShortcutManager is sufficient)
- Real-time waveform visualization in history (simple progress bar is sufficient)

## Decisions

### 1. Lightweight mode via NSApp activation policy

**Decision**: Use `NSApp.setActivationPolicy(.accessory)` when lightweight mode is active, keeping the app as a menu-bar-only process. The main window is never created; only the existing `MicIndicatorOverlay` and status item are shown.

**Rationale**: This is the standard macOS pattern for menu-bar utilities. It avoids creating and hiding a window (which still consumes resources) and works seamlessly with the existing `KeyboardShortcutManager` which registers global hotkeys independent of any window.

**Alternative considered**: Creating the window but keeping it hidden — rejected because it still renders the full view hierarchy and wastes memory.

### 2. Lightweight mode preference in AppConfiguration

**Decision**: Add a `launchInLightweightMode: Bool` property to AppConfiguration (persisted via snapshot). When true, `VoiceFlowPro.swift` skips WindowGroup creation and only registers the status item + hotkey shortcuts.

**Rationale**: Fits the existing configuration architecture. Users can toggle from the menu bar status item or from the full app's settings.

### 3. Word count fix — use shared utility function

**Decision**: Call the existing `voiceTextWordCount(in:)` free function from HistoryView instead of the inline whitespace-split logic.

**Rationale**: Single source of truth. The linguistic tokenizer already handles CJK, mixed scripts, and punctuation correctly.

### 4. Dictation audio playback in history

**Decision**: Extend the existing `SessionDetailView` to show a playback bar (play/pause + scrubber) when `session.source == .voiceDictation && session.recordingURL != nil`. Reuse the same `AVAudioPlayer` pattern already used for TTS playback.

**Rationale**: Minimal new code; consistent with existing TTS playback pattern. The scrubber uses a `Slider` bound to `currentTime/duration` with a Timer-based update.

### 5. File transcription: re-transcribe and reveal

**Decision**: Add two buttons to the file transcription action row in `SessionDetailView`:
- "Re-transcribe": resolves the security-scoped bookmark, launches a new transcription with current model settings, replaces session content on completion.
- "Reveal in Finder": resolves bookmark and calls `NSWorkspace.shared.activateFileViewerSelecting([url])`.

**Rationale**: These are natural actions users expect. The bookmark and transcription infrastructure already exist.

## Risks / Trade-offs

- **[Risk] Lightweight mode may not prewarm ASR model** → Mitigation: `TranscriberWarmupCoordinator` already reacts to config changes; ensure it's initialized in lightweight mode too.
- **[Risk] Audio file missing after 24h retention** → Mitigation: Check file existence before showing play button; show "Audio expired" message if missing.
- **[Risk] Re-transcribe may take long for large files** → Mitigation: Show progress indicator; don't block UI.
- **[Risk] Security-scoped bookmark stale** → Mitigation: Already handled by existing `isStale` check pattern; show error alert on failure.
