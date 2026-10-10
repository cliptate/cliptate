## ADDED Requirements

### Requirement: Evict all cached models on lightweight mode entry
When the user enters lightweight mode, the system SHALL unload all cached ASR, aligner, and TTS model runtimes from memory and flush the GPU buffer pool, so that the application's memory footprint is genuinely reduced.

#### Scenario: Enter lightweight mode with warm ASR model
- **WHEN** an ASR model is loaded in ModelCacheManager and the user enters lightweight mode
- **THEN** the cached model is unloaded, entries dictionary is emptied, and MLX.Memory.clearCache() is called

#### Scenario: Enter lightweight mode with multiple cached models
- **WHEN** ASR, aligner, and TTS models are all cached and the user enters lightweight mode
- **THEN** all three are unloaded and GPU memory is freed

### Requirement: Re-warm ASR model on lightweight mode exit
When the user exits lightweight mode, the system SHALL trigger a warmup of the configured ASR model so transcription is ready without user-visible delay.

#### Scenario: Exit lightweight mode
- **WHEN** the user exits lightweight mode
- **THEN** TranscriberWarmupCoordinator re-warms the configured ASR model in the background

### Requirement: Remove Whisper engine from user-facing selection
The Whisper transcriber type SHALL NOT appear in any user-facing engine/model picker. The enum case is retained for backward compatibility with persisted snapshots.

#### Scenario: Engine picker does not show Whisper
- **WHEN** the user opens the engine picker in ModelSelectionView or LightweightMenuView
- **THEN** only Parakeet, Qwen3 ASR, and FireRed are listed

#### Scenario: Persisted whisper config loads gracefully
- **WHEN** a user has transcriberType "whisper" in a persisted snapshot
- **THEN** the system maps it to parakeet without error

### Requirement: Dictation language filtered by active model
The dictation language picker in LightweightMenuView SHALL display only the languages supported by the currently selected ModelVariant.

#### Scenario: Parakeet v2 selected — English only
- **WHEN** the active model is parakeetV2
- **THEN** the language picker shows only English

#### Scenario: Qwen3 ASR selected — multilingual
- **WHEN** the active model is a Qwen3 ASR variant
- **THEN** the language picker shows the 19 Qwen3-supported languages

### Requirement: Only downloaded models shown in menu bar picker
The ASR model submenu in LightweightMenuView SHALL only list models whose local artifacts are available (downloaded).

#### Scenario: Model not downloaded
- **WHEN** a model variant has no local artifacts
- **THEN** it does not appear in the menu bar model picker

#### Scenario: Model downloaded
- **WHEN** a model variant has local artifacts
- **THEN** it appears in the menu bar model picker and is selectable
