## ADDED Requirements

### Requirement: App launches in lightweight mode when preference enabled
The system SHALL support a "lightweight mode" where the app runs without rendering the main window or ContentView hierarchy. When `launchInLightweightMode` is true in AppConfiguration, the app SHALL use `.accessory` activation policy, show only a menu bar status item, and keep hotkey-triggered dictation fully functional.

#### Scenario: Launch in lightweight mode
- **WHEN** the user has enabled lightweight mode preference AND launches the app
- **THEN** the app SHALL NOT create or show the main application window
- **THEN** the app SHALL appear as a menu bar status item only
- **THEN** the app SHALL set activation policy to `.accessory`

#### Scenario: Hotkey dictation works in lightweight mode
- **WHEN** the app is running in lightweight mode AND the user presses the configured dictation hotkey
- **THEN** the voice dictation recording SHALL start normally
- **THEN** transcribed text SHALL be typed into the focused external application

#### Scenario: ASR model is prewarmed in lightweight mode
- **WHEN** the app launches in lightweight mode
- **THEN** the TranscriberWarmupCoordinator SHALL prewarm the selected ASR model
- **THEN** dictation response time SHALL be equivalent to full-UI mode

### Requirement: Menu bar status item provides essential controls
The system SHALL provide a menu bar status item in lightweight mode with controls to toggle dictation, open full UI, access settings, and quit.

#### Scenario: Status item menu actions
- **WHEN** the user clicks the menu bar status item in lightweight mode
- **THEN** a menu SHALL appear with options: "Start Dictation", "Open Full App", "Settings…", "Quit"

#### Scenario: Open full app from lightweight mode
- **WHEN** the user selects "Open Full App" from the status item menu
- **THEN** the main window SHALL be created and shown
- **THEN** the activation policy SHALL change to `.regular`

### Requirement: User can toggle lightweight mode from settings
The system SHALL allow users to enable/disable lightweight mode from the app's settings UI. The setting SHALL persist across launches.

#### Scenario: Enable lightweight mode from settings
- **WHEN** the user enables "Launch in Lightweight Mode" in settings
- **THEN** the preference SHALL be persisted in AppConfiguration
- **THEN** the next app launch SHALL start in lightweight mode
