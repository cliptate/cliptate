## Why

The model/language selection and lightweight mode have usability issues: (1) dictation language list shows all languages regardless of the selected model's actual support, (2) the Whisper engine still appears in the UI but just redirects to Parakeet—confusing users, (3) models that are not yet downloaded appear as selectable options in the menu bar, and (4) entering lightweight mode closes windows but does NOT evict cached ML models from memory, defeating the purpose of "saving memory."

## What Changes

- **Remove Whisper engine from TranscriberType selection**: The `whisper` case already redirects to Parakeet internally; remove it from `allCases`/UI pickers so users only see Parakeet, Qwen3, and FireRed.
- **Filter dictation language by selected model**: `LightweightMenuView` currently uses the deprecated `TranscriberType.supportedLanguages` which returns all languages. Switch to `ModelVariant.supportedLanguages` so the language picker reflects the actual model's capabilities.
- **Only show downloaded models in menu bar picker**: Filter the model list in `LightweightMenuView` to only display models whose artifacts are locally available (use `ModelDownloadManager.hasLocalArtifacts`).
- **Evict all cached models when entering lightweight mode**: When `LightweightModeManager.enterLightweightMode()` fires, call `ModelCacheManager` to unload all cached ASR/aligner/TTS models and flush GPU memory so the app genuinely reduces its memory footprint.

## Capabilities

### New Capabilities
- `lightweight-memory-eviction`: Evict all cached ML model runtimes from memory on lightweight mode entry, with re-warm on exit.

### Modified Capabilities
- (none — no existing openspec specs are affected at the requirement level)

## Impact

- **Files**: `DataTypes.swift` (TranscriberType), `LightweightMenuView.swift`, `LightweightModeManager.swift`, `ModelCacheManager.swift`, `VoiceFlowPro.swift` (warmup on exit).
- **Behavior**: Whisper engine disappears from all pickers. Language lists become model-aware everywhere. Menu bar only shows downloadable-and-downloaded models. Lightweight mode genuinely frees ~0.5–2 GB of RAM.
- **Migration**: Existing persisted `transcriberType == .whisper` snapshots already fall back to parakeet via `supportedModels`; no data migration needed.
