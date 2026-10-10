## ADDED Requirements

### Requirement: Unified model cache management
The system SHALL provide a centralized `ModelCacheManager` actor that manages the lifecycle of all model types (ASR, align, TTS) with thread-safe access and automatic cleanup.

#### Scenario: Load ASR model on startup
- **WHEN** the application starts
- **THEN** the system SHALL automatically load the configured ASR model
- **AND** the ASR model SHALL be immediately available for transcription

#### Scenario: Lazy load align model on demand
- **WHEN** a user requests alignment functionality
- **AND** the align model is not currently loaded
- **THEN** the system SHALL load the configured align model
- **AND** make it available for use

#### Scenario: Lazy load TTS model on demand
- **WHEN** a user requests TTS functionality
- **AND** the TTS model is not currently loaded
- **THEN** the system SHALL load the configured TTS model
- **AND** make it available for use

#### Scenario: Automatic model cleanup after inactivity
- **WHEN** an align or TTS model has been idle for 10 minutes
- **THEN** the system SHALL automatically release the model from memory
- **AND** free associated resources

#### Scenario: Access cached model instance
- **WHEN** a model is requested that is already loaded in the cache
- **THEN** the system SHALL return the existing instance without reloading
- **AND** reset the inactivity timer for that model

#### Scenario: Handle concurrent model requests safely
- **WHEN** multiple components request the same model simultaneously
- **THEN** the system SHALL ensure only one model instance is created
- **AND** all requests SHALL receive the same model instance

### Requirement: Model cache configuration
The system SHALL allow configuration of model caching behavior including timeout duration and preload options.

#### Scenario: Configure cleanup timeout
- **WHEN** a user sets a custom cleanup timeout in advanced settings
- **THEN** the system SHALL use the specified timeout duration for model cleanup
- **AND** apply this timeout to both align and TTS models

#### Scenario: Preload models from Models page
- **WHEN** a user clicks a "Preload" button for a model in the Models page
- **THEN** the system SHALL load that model into the cache immediately
- **AND** display loading progress during the operation

#### Scenario: Clear model cache manually
- **WHEN** a user clicks "Clear Cache" in the Models page
- **THEN** the system SHALL release all cached models except the currently active ASR model
- **AND** update the UI to reflect the cleared state

### Requirement: Model lifecycle state tracking
The system SHALL track and expose the current state of each model type including loading status, loaded state, and cache statistics.

#### Scenario: Query model loading status
- **WHEN** the UI requests the current status of a model
- **THEN** the system SHALL return whether the model is: not loaded, loading, loaded, or error
- **AND** include the time since last access for loaded models

#### Scenario: Display cache memory usage
- **WHEN** the user views the Models page
- **THEN** the system SHALL display the memory usage of each cached model
- **AND** show total cache memory consumption

#### Scenario: Handle model loading errors gracefully
- **WHEN** a model fails to load
- **THEN** the system SHALL record the error with details
- **AND** notify the user with an option to retry
- **AND** maintain any previously loaded model if available