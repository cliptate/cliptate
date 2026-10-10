## Why

Users want to use voice dictation as a system-wide utility without loading the full VoiceFlowPro UI. Currently the hotkey system works but requires the complete app window to be visible. Additionally, the history page has inconsistent word counting (uses whitespace splitting instead of the linguistic tokenizer used in VoiceToTextView), dictation sessions don't expose their recorded audio for playback/seeking in history, and file transcription sessions lack re-transcription and file reveal actions.

## What Changes

- **Lightweight mode**: Allow the app to run in a minimal state (menu bar only / no main window) so hotkey-triggered dictation works without rendering the full ContentView. Add a preference to launch in lightweight mode.
- **History word count fix**: Replace `components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count` in HistoryView with the same `voiceTextWordCount()` linguistic tokenizer used in VoiceToTextView, ensuring CJK text is counted correctly.
- **Dictation audio playback in history**: Show audio playback controls (play/pause, progress bar, seek) for dictation sessions that have a retained recording file, consistent with TTS playback in history.
- **File transcription actions**: Add "Re-transcribe" (re-run ASR with current model settings) and "Reveal in Finder" buttons to file transcription session detail in HistoryView.

## Capabilities

### New Capabilities
- `lightweight-mode`: System-wide dictation without rendering the main app UI; menu bar presence with hotkey activation; preference to launch in lightweight mode.
- `dictation-audio-playback`: Audio playback controls (play/pause, seek, progress) for voice dictation sessions in HistoryView, reusing the retained recording file.
- `file-transcription-actions`: Re-transcribe and Reveal-in-Finder actions for file transcription sessions in HistoryView.

### Modified Capabilities
- `history-word-count`: Fix word counting in HistoryView to use `voiceTextWordCount()` (linguistic tokenizer) instead of whitespace splitting, matching VoiceToTextView behavior.

## Impact

- **Views**: HistoryView.swift (word count fix, dictation playback, file transcription actions), ContentView.swift (lightweight mode routing), VoiceFlowPro.swift (app lifecycle for lightweight launch)
- **Models**: AppConfiguration (lightweight mode preference)
- **Services**: KeyboardShortcutManager (ensure works without active main window)
- **No breaking changes**: All existing functionality preserved; lightweight mode is opt-in
