## Why

The current model management is fragmented across multiple components, leading to inefficient resource usage and duplicated UI logic. Models are loaded eagerly without a centralized caching strategy, causing unnecessary memory overhead. The user experience is inconsistent, with model selection scattered across AI Cut and Voice To Text views instead of being centralized in one location.

## What Changes

- **BREAKING**: Consolidate model caching logic into a unified `ModelCacheManager` actor
- Remove eager loading for align and TTS models; implement lazy loading with automatic cleanup
- Default to loading ASR model only; align and TTS models load on-demand and release after use
- Remove model selection UI from AI Cut and Voice To Text feature views
- Centralize all model selection in the Models page (similar to current align model workflow)
- Make language selection dynamic based on the currently selected model's supported languages
- Refactor model lifecycle management to follow a consistent pattern across all model types

## Capabilities

### New Capabilities

- `model-lifecycle-management`: Unified model loading, caching, and lifecycle management with lazy loading support
- `dynamic-language-selection`: Language list adapts to selected model's supported languages

### Modified Capabilities

- `model-selection-ui`: Consolidate model selection into Models page, remove duplicate selection logic from feature views

## Impact

**Affected Code**:
- `TranscriberPool.swift`: Will be replaced or significantly refactored by `ModelCacheManager`
- `AppConfiguration.swift`: Model selection and language configuration logic
- `ContentView.swift`: Remove model selection UI components
- AI Cut and Voice To Text feature views: Remove model selection modules
- Models page view: Enhance to support all model types

**Dependencies**:
- WhisperKit: Model loading and management
- FluidAudio: Alternative transcription engine

**Systems**:
- Model loading and caching system
- UI state management
- Configuration persistence