## ADDED Requirements

### Requirement: Centralized model selection in Models page
The system SHALL provide a unified interface for selecting and configuring all model types (ASR, align, TTS) in the Models page.

#### Scenario: Select ASR model from Models page
- **WHEN** a user navigates to the Models page
- **THEN** the system SHALL display the current ASR model selection
- **AND** provide options to change the ASR model
- **AND** show model details including size, language support, and status

#### Scenario: Select align model from Models page
- **WHEN** a user navigates to the Models page
- **THEN** the system SHALL display the current align model selection
- **AND** provide options to change the align model
- **AND** show whether the model is currently loaded

#### Scenario: Select TTS model from Models page
- **WHEN** a user navigates to the Models page
- **THEN** the system SHALL display the current TTS model selection
- **AND** provide options to change the TTS model
- **AND** show available voice options for the selected model

#### Scenario: Display model selection consistently
- **WHEN** the user views the Models page
- **THEN** all three model types SHALL use a consistent selection UI pattern
- **AND** each model type SHALL show relevant configuration options
- **AND** changes SHALL be immediately reflected in the UI

### Requirement: Configuration-driven model state
The system SHALL store all model selections in `AppConfiguration` and use it as the single source of truth.

#### Scenario: Persist model selection
- **WHEN** a user selects a model in the Models page
- **THEN** the system SHALL save the selection to `AppConfiguration`
- **AND** the selection SHALL persist across application restarts
- **AND** all components SHALL use the same model selection

#### Scenario: Load saved model on startup
- **WHEN** the application starts
- **THEN** the system SHALL read the model selections from `AppConfiguration`
- **AND** use these selections as the default models

#### Scenario: Notify components of model changes
- **WHEN** a model selection changes in `AppConfiguration`
- **THEN** the system SHALL publish the change to all observing components
- **AND** components SHALL update their behavior accordingly

## REMOVED Requirements

### Requirement: Model selection in AI Cut feature view
**Reason**: Model selection is now centralized in the Models page to avoid duplication and inconsistency

**Migration**: Users should select models from the Models page before using AI Cut functionality. The AI Cut view will use the currently configured model from `AppConfiguration`.

### Requirement: Model selection in Voice To Text feature view
**Reason**: Model selection is now centralized in the Models page to avoid duplication and inconsistency

**Migration**: Users should select models from the Models page before using Voice To Text functionality. The Voice To Text view will use the currently configured model from `AppConfiguration`.