## ADDED Requirements

### Requirement: Dictation sessions display audio playback controls in history
The system SHALL show audio playback controls (play/pause button, progress scrubber, time display) for voice dictation sessions that have a retained recording file.

#### Scenario: Play dictation recording from history
- **WHEN** the user views a dictation session detail in HistoryView AND the recording file exists
- **THEN** a playback bar SHALL be visible with play/pause button, progress slider, and duration display
- **THEN** clicking play SHALL start audio playback from the beginning

#### Scenario: Seek within dictation recording
- **WHEN** the user drags the progress scrubber during playback
- **THEN** audio playback SHALL jump to the selected time position
- **THEN** the time display SHALL update to reflect the new position

#### Scenario: Audio file has expired
- **WHEN** the user views a dictation session detail AND the recording file no longer exists (expired past 24h retention)
- **THEN** the playback bar SHALL NOT be shown
- **THEN** an "Audio expired" indicator MAY be shown

### Requirement: Playback progress updates in real time
The system SHALL update the progress slider and time display continuously during audio playback.

#### Scenario: Progress updates during playback
- **WHEN** audio is playing
- **THEN** the progress slider position SHALL update at least every 100ms
- **THEN** the time label SHALL show current time / total duration in mm:ss format
