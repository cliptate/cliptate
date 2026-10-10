## 1. History Word Count Fix

- [x] 1.1 Replace whitespace-based word counting in HistoryView (both list badge and detail badge) with `voiceTextWordCount(in:)` linguistic tokenizer
- [x] 1.2 Add unit test verifying HistoryView word count matches VoiceToTextView for CJK and mixed text

## 2. Dictation Audio Playback in History

- [x] 2.1 Add audio playback bar (play/pause, progress slider, time display) to SessionDetailView for dictation sessions with retained recording files
- [x] 2.2 Implement seek functionality via slider drag and Timer-based progress updates
- [x] 2.3 Handle expired audio gracefully (hide playback when file no longer exists)

## 3. File Transcription Actions

- [x] 3.1 Add "Re-transcribe" button to file transcription session detail in HistoryView
- [x] 3.2 Implement re-transcription logic: resolve bookmark, run ASR with current settings, update session
- [x] 3.3 Add progress indicator during re-transcription
- [x] 3.4 Add "Reveal in Finder" button for file transcription sessions with bookmark validation

## 4. Lightweight Mode

- [x] 4.1 Add `launchInLightweightMode` property to AppConfiguration (persisted via snapshot)
- [x] 4.2 Modify VoiceFlowPro.swift app bootstrap to conditionally skip WindowGroup when lightweight mode enabled
- [x] 4.3 Set activation policy to `.accessory` in lightweight mode
- [x] 4.4 Create menu bar status item with controls: Start Dictation, Open Full App, Settings, Quit
- [x] 4.5 Ensure TranscriberWarmupCoordinator initializes in lightweight mode
- [x] 4.6 Implement "Open Full App" action to create main window and switch to `.regular` activation policy
- [x] 4.7 Add lightweight mode toggle to settings UI

## 5. Localization

- [x] 5.1 Add all new user-visible strings to Localizable.xcstrings with zh-Hans, ja, ko translations
