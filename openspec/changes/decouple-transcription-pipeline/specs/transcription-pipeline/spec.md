## ADDED Requirements

### Requirement: Shared batch transcription stage ordering
The system SHALL execute batch transcription through a shared stage-based pipeline whose workflow-specific stage ordering is explicit: file transcription SHALL run `VAD -> ASR -> Align -> post-process`, while dictation retranscription/finalization SHALL run `VAD -> ASR -> post-process`.

#### Scenario: File transcription uses shared batch pipeline
- **WHEN** a user starts file transcription from the AI Cut workflow
- **THEN** the system runs speech detection before chunk transcription, runs alignment after chunk transcription, and applies post-processing to the combined batch result through a shared orchestration path

#### Scenario: Dictation finalization uses shared batch pipeline
- **WHEN** a dictation session stops normally and the system performs the accuracy pass on the recorded audio
- **THEN** the system routes that recorded audio through the same shared batch orchestration boundary used by file transcription
- **AND** the system skips Align before producing the final transcript

### Requirement: Stage implementations remain independently selectable
The system SHALL resolve VAD, ASR, and Align stages through stage-oriented contracts so that each stage can be selected independently from configuration and workflow policy without direct dependencies between concrete stage implementations.

#### Scenario: VAD implementation changes without ASR-specific branching in caller
- **WHEN** the active VAD model changes between Silero and Sortformer
- **THEN** the caller keeps invoking the same batch orchestration entry point and the system resolves the correct VAD stage implementation without introducing caller branches on concrete ASR or Align types

#### Scenario: ASR implementation changes without stage coupling
- **WHEN** the active ASR model changes between Qwen, Parakeet, and FireRed
- **THEN** the system resolves the appropriate ASR stage through a shared resolver and preserves the same orchestration boundary for downstream Align and post-processing stages

#### Scenario: Workflow disables align explicitly
- **WHEN** the dictation retranscription workflow requests batch transcription
- **THEN** the resolver returns a pipeline configuration that omits Align even if an aligner model is available

### Requirement: Streaming dictation and finalized dictation are separated by responsibility
The system SHALL keep live dictation capture on a streaming-focused path and SHALL use the shared batch pipeline only for finalized dictation outputs that require higher accuracy, without forcing those finalized dictation outputs through Align.

#### Scenario: Live dictation remains streaming-focused
- **WHEN** a user is actively speaking during a dictation session
- **THEN** the system produces interim text through the streaming capture path without invoking the shared batch finalization service for each live chunk

#### Scenario: History reprocessing reuses finalized dictation pipeline
- **WHEN** a user reprocesses a saved dictation session from history
- **THEN** the system uses the same shared batch transcription orchestration that is used for normal dictation finalization instead of maintaining a separate retranscription branch
- **AND** the system skips Align in that reprocessing workflow

### Requirement: Post-processing is shared after batch execution
The system SHALL apply shared batch post-processing after the batch runner completes so dictionary bias, speaker propagation, and transcript/session mapping behave consistently across file transcription and dictation finalization.

#### Scenario: Dictionary and speaker processing are applied consistently
- **WHEN** two workflows transcribe the same audio, one from file transcription and one from finalized dictation
- **THEN** both workflows apply dictionary bias and speaker propagation through the same post-processing layer before mapping the result into transcript/session output
