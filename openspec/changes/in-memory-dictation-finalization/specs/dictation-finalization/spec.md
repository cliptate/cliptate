## ADDED Requirements

### Requirement: Dictation finalization SHALL use in-memory captured audio
The system SHALL finalize a stopped dictation session from the normalized in-memory audio captured during that session, without requiring a retained audio file to exist before batch retranscription begins.

#### Scenario: Normal stop finalizes from memory
- **WHEN** a user stops an active dictation session normally
- **THEN** the system starts batch dictation finalization from the captured in-memory audio samples
- **AND** the final transcript text does not depend on a retained recording file already existing on disk

#### Scenario: Final text survives retained-recording unavailability
- **WHEN** retained recording persistence is unavailable or delayed during dictation stop
- **THEN** the system still completes final dictation retranscription from in-memory audio
- **AND** the user still receives the final transcript text

### Requirement: Retained dictation audio persistence SHALL be deferred
The system SHALL persist the retained dictation recording outside the final-text critical path so that playback and manual retranscription artifacts are created after final transcript delivery.

#### Scenario: Final text is delivered before retained recording is ready
- **WHEN** a dictation session completes successfully
- **THEN** the system may deliver the final transcript before `recordingURL` is populated for that session
- **AND** retained audio persistence continues asynchronously

#### Scenario: Deferred persistence backfills session recording metadata
- **WHEN** deferred retained-audio persistence succeeds after final transcript delivery
- **THEN** the system updates the dictation session with a playable retained recording reference
- **AND** history playback and manual retranscription become available for that session

### Requirement: Dictation finalization SHALL preserve batch-processing accuracy behavior
The system SHALL apply the same dictation batch-processing behavior to in-memory finalization that it previously applied to file-backed finalization, including segmentation, dictionary bias, and speaker propagation when configured.

#### Scenario: In-memory finalization applies configured dictionary bias
- **WHEN** dictation finalization runs with custom dictionary entries configured
- **THEN** the final transcript reflects the same dictionary-bias behavior as the batch dictation pipeline

#### Scenario: In-memory finalization preserves speaker propagation support
- **WHEN** dictation finalization runs with a speaker-capable VAD configuration
- **THEN** the system applies speaker propagation using the captured dictation audio samples
- **AND** resulting transcript lines preserve speaker identifiers when the propagation step succeeds
