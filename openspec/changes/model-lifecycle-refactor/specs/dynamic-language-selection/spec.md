## ADDED Requirements

### Requirement: Dynamic language list based on model capabilities
The system SHALL filter the available language selection list based on the currently selected model's supported languages.

#### Scenario: Display supported languages for ASR model
- **WHEN** a user selects an ASR model
- **THEN** the system SHALL query the model's supported languages
- **AND** display only those languages in the language selection UI
- **AND** preserve the user's language selection if it remains supported

#### Scenario: Display supported languages for align model
- **WHEN** a user selects an align model
- **THEN** the system SHALL query the model's supported languages
- **AND** display only those languages in the alignment language selection UI

#### Scenario: Display supported languages for TTS model
- **WHEN** a user selects a TTS model
- **THEN** the system SHALL query the model's supported languages
- **AND** display only those languages in the TTS voice language selection UI

#### Scenario: Handle language selection change due to model switch
- **WHEN** a user switches to a model that doesn't support the currently selected language
- **THEN** the system SHALL automatically select the model's default language
- **AND** notify the user of the automatic change

#### Scenario: Preserve language selection across compatible models
- **WHEN** a user switches between models that both support the currently selected language
- **THEN** the system SHALL preserve the user's language selection
- **AND** continue using the same language without interruption

### Requirement: Language support metadata query
The system SHALL provide a mechanism to query each model's supported languages without fully loading the model.

#### Scenario: Query supported languages quickly
- **WHEN** the UI needs to display the language list for a model configuration
- **THEN** the system SHALL return the supported languages without loading the full model
- **AND** complete the query within 100 milliseconds

#### Scenario: Handle models with unknown language support
- **WHEN** a model's language support metadata is unavailable
- **THEN** the system SHALL fall back to displaying all supported languages
- **AND** log a warning about the missing metadata

#### Scenario: Cache language support metadata
- **WHEN** language support metadata is queried for a model
- **THEN** the system SHALL cache the result for subsequent queries
- **AND** invalidate the cache when the model configuration changes