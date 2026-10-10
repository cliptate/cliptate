# Design: Dictation UI Polish — Icon, Waveform, Speaker Display

**Date:** 2026-04-30
**Status:** Draft

## Problem

Three UI issues after the initial dictation improvements:
1. Menubar app icon too small (24pt) — hard to see at a glance
2. Waveform feels static/sparse — needs more bars, snappier response, narrower footprint
3. Speaker ID prefixes appear during live streaming (where speaker data isn't available yet) — they should only appear in finished history records

## Changes

### 1. Menubar Icon Size
- Increase app icon from 24×24pt to 32×32pt
- Increase corner radius proportionally: 5pt → 7pt

### 2. Waveform Dynamics & Layout
- Increase bar count: 5 → 7 bars
- Update weights for 7 bars: `[0.35, 0.55, 0.75, 1.0, 0.80, 0.60, 0.40]`
- Reduce bar width: 8pt → 5pt
- Reduce bar spacing: 4pt → 3pt
- Increase attack coefficient: 0.40 → 0.55 (snappier rise)
- Increase jitter range: ±4% → ±6% (more organic movement)
- Reduce waveform section horizontal padding: 16pt → 12pt
- Reduce waveform section vertical padding: 12pt → 8pt
- Reduce HStack internal spacing: 12pt → 8pt

### 3. Speaker ID Display Scope
- **Live transcript (`VoiceToTextView.transcriptText`)**: Use `combinedText` while session is active (no speaker prefixes during streaming). Use `speakerFormattedText` only when session is finished.
- **Streaming overlay (`handleTranscriptionUpdate`)**: Remove speaker prefix logic — show raw text only.
- **History transcript preview (`HistorySessionRow.transcriptPreview`)**: Use `speakerFormattedText` instead of `combinedText` so finished sessions show speaker attribution.

## Testing
- Unit test: `smoothedBarLevels` array size matches new bar count (7)
- Unit test: `speakerFormattedText` used in history, `combinedText` used during live streaming
- Build verification for both Swift package and Xcode project
