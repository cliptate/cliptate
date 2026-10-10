## Context

Currently, WhisperCutPro manages three types of models: ASR (Automatic Speech Recognition), align models, and TTS (Text-to-Speech) models. The existing implementation has several issues:

1. **Fragmented caching logic**: `TranscriberPool` manages ASR model instances but doesn't handle other model types
2. **Eager loading**: All models are loaded proactively, causing unnecessary memory overhead
3. **Duplicated UI**: Model selection appears in AI Cut and Voice To Text views, creating inconsistent UX
4. **Static language lists**: Language options don't adapt to the selected model's capabilities

The refactoring will centralize model management, implement lazy loading for non-essential models, and provide a unified model selection interface.

## Goals / Non-Goals

**Goals:**
- Create a unified `ModelCacheManager` actor to handle all model types (ASR, align, TTS)
- Implement lazy loading with automatic cleanup for align and TTS models
- Default to loading only ASR model on startup
- Centralize model selection UI in the Models page
- Make language selection dynamic based on selected model's supported languages
- Reduce memory footprint by releasing unused models

**Non-Goals:**
- Changing the underlying model inference engines (WhisperKit, FluidAudio)
- Modifying transcription quality or accuracy
- Changing the user workflow for transcription tasks
- Adding new model types beyond ASR, align, and TTS

## Decisions

### Decision 1: Unified Model Cache Manager as an Actor

**Choice**: Create a single `ModelCacheManager` actor to replace `TranscriberPool`

**Rationale**:
- Actors provide thread-safe access to mutable state without explicit locks
- Centralizes all model lifecycle management in one place
- Easier to implement consistent caching and cleanup policies
- Can track usage patterns across all model types

**Alternatives considered**:
- Separate cache managers for each model type: More flexible but duplicates logic and makes coordinated cleanup harder
- Extend existing `TranscriberPool`: Would require significant refactoring and naming becomes misleading

### Decision 2: Lazy Loading with Time-Based Cleanup

**Choice**: Load align and TTS models on-demand, automatically release after 10 minutes of inactivity

**Rationale**:
- Align and TTS are used less frequently than ASR
- 10-minute window balances memory savings with user experience (avoid reload delays)
- Consistent with existing `TranscriberPool` timeout approach
- Users can manually preload from Models page if needed

**Alternatives considered**:
- Immediate cleanup after use: Too aggressive, causes reload delays for repeated operations
- No cleanup: Defeats purpose of lazy loading, memory leak risk
- Manual cleanup only: Relies on users remembering, poor UX

### Decision 3: Configuration-Centric Model Selection

**Choice**: Store all model selections in `AppConfiguration`, remove from feature views

**Rationale**:
- Single source of truth for model state
- Consistent with existing pattern for other settings
- Models page already has infrastructure for selection
- Simplifies feature views by removing model management concerns

**Alternatives considered**:
- Keep model selection in feature views: Duplicates logic, inconsistent state management
- Separate model configuration object: Adds complexity without clear benefit

### Decision 4: Dynamic Language List from Model Metadata

**Choice**: Query the loaded model for supported languages and filter the language selection list

**Rationale**:
- Different models support different language sets
- Prevents user confusion from selecting unsupported languages
- Aligns with user's mental model: "choose model → see what it supports"
- No hardcoded language restrictions needed

**Alternatives considered**:
- Hardcoded language lists per model type: Doesn't account for model-specific capabilities
- Show all languages, validate on transcription: Poor UX, user discovers error late
- Separate language configuration per model: Overly complex, user might want same language across models

## Risks / Trade-offs

**Risk**: Models may take noticeable time to load on first use
- **Mitigation**: Show loading progress in UI; allow optional preloading from Models page

**Risk**: Aggressive cleanup might frustrate users switching between features frequently
- **Mitigation**: Configurable timeout in advanced settings; 10-minute default is generous

**Risk**: Breaking change removes model selection from familiar locations
- **Mitigation**: Clear UI indicators in Models page; migration guide in release notes

**Trade-off**: Increased complexity in `ModelCacheManager` vs. simpler but scattered model management
- **Acceptance**: Centralized complexity is easier to maintain than distributed complexity

**Trade-off**: Actor-based approach adds async/await requirements throughout codebase
- **Acceptance**: Already using async/await extensively; consistent with existing patterns

## Migration Plan

### Phase 1: Add ModelCacheManager (Non-Breaking)
1. Implement `ModelCacheManager` actor alongside existing `TranscriberPool`
2. Add new model selection properties to `AppConfiguration`
3. Update Models page to support all model types
4. Test extensively with new system

### Phase 2: Update Feature Views (Non-Breaking)
1. Modify AI Cut and Voice To Text to use `AppConfiguration` for model selection
2. Remove local model selection state from feature views
3. Maintain backward compatibility with existing configuration

### Phase 3: Deprecate TranscriberPool (Breaking)
1. Replace `TranscriberPool` references with `ModelCacheManager`
2. Remove model selection UI from feature views
3. Implement dynamic language filtering
4. Update tests and documentation

### Rollback Strategy
- Each phase is independently deployable
- Can revert to previous phase if issues arise
- Configuration changes are additive until Phase 3
- Keep `TranscriberPool` code until Phase 3 is stable

## Open Questions

1. **Should we allow users to configure the model cleanup timeout?**
   - Pro: Flexibility for different usage patterns
   - Con: Adds configuration complexity, most users won't change it
   - *Recommendation*: Add in advanced settings, default to 10 minutes

2. **How should we handle model loading failures during feature use?**
   - Need to design error recovery UX
   - Should we fall back to previously working model?
   - *Recommendation*: Show error with retry option; keep previous model if loaded

3. **Should language selection persist per model or globally?**
   - Currently global, but different models might be used for different languages
   - *Recommendation*: Keep global language selection for simplicity, but allow per-model override in advanced settings