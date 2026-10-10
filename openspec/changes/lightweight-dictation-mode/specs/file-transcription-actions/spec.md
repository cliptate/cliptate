## ADDED Requirements

### Requirement: File transcription sessions support re-transcription
The system SHALL allow users to re-transcribe a file transcription session using the current ASR model and language settings.

#### Scenario: Re-transcribe with current model
- **WHEN** the user clicks "Re-transcribe" on a file transcription session in HistoryView
- **THEN** the system SHALL resolve the security-scoped bookmark to the source file
- **THEN** the system SHALL start a new transcription with the currently configured ASR model and language
- **THEN** a progress indicator SHALL be shown during transcription
- **THEN** on completion, the session content SHALL be updated with the new transcription result

#### Scenario: Re-transcribe with stale bookmark
- **WHEN** the user clicks "Re-transcribe" AND the security-scoped bookmark is stale or invalid
- **THEN** the system SHALL show an error message indicating the source file cannot be accessed
- **THEN** the original session content SHALL remain unchanged

### Requirement: File transcription sessions support reveal in Finder
The system SHALL allow users to reveal the source file in Finder for file transcription sessions.

#### Scenario: Reveal source file in Finder
- **WHEN** the user clicks "Reveal in Finder" on a file transcription session
- **THEN** the system SHALL resolve the security-scoped bookmark
- **THEN** Finder SHALL open with the source file selected

#### Scenario: Reveal with missing file
- **WHEN** the user clicks "Reveal in Finder" AND the source file no longer exists
- **THEN** the system SHALL show an error message indicating the file was not found
