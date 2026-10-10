## 1. Core Infrastructure - ModelCacheManager

- [x] 1.1 Create `ModelCacheManager.swift` with actor-based implementation
- [x] 1.2 Define model state enum (notLoaded, loading, loaded, error)
- [x] 1.3 Implement model cache entry structure with timestamp tracking
- [x] 1.4 Add model loading methods for ASR, align, and TTS models
- [x] 1.5 Implement lazy loading logic with concurrency handling
- [x] 1.6 Add automatic cleanup timer for idle models (default 10 minutes)
- [x] 1.7 Implement thread-safe model retrieval with cache checking
- [x] 1.8 Add error handling and state tracking for failed loads
- [x] 1.9 Create model cache statistics tracking (memory usage, last access time)

## 2. Configuration Updates

- [x] 2.1 Add align model selection properties to `AppConfiguration`
- [x] 2.2 Add TTS model selection properties to `AppConfiguration`
- [x] 2.3 Add model cleanup timeout configuration property
- [x] 2.4 Implement configuration persistence for new model properties
- [x] 2.5 Add published properties for model state observation

## 3. Language Support Infrastructure

- [x] 3.1 Create protocol for querying model supported languages
- [x] 3.2 Implement language support query for ASR models
- [x] 3.3 Implement language support query for align models
- [x] 3.4 Implement language support query for TTS models
- [x] 3.5 Add language support metadata caching
- [x] 3.6 Implement language list filtering based on model capabilities

## 4. Models Page UI Enhancement

- [x] 4.1 Update Models page to display ASR model section with selection UI
- [x] 4.2 Add align model selection section with lazy load indicator
- [x] 4.3 Add TTS model selection section with voice options
- [x] 4.4 Implement model status display (not loaded, loading, loaded, error)
- [x] 4.5 Add "Preload" button for align and TTS models
- [x] 4.6 Add "Clear Cache" button with confirmation
- [x] 4.7 Display memory usage per model and total cache size
- [x] 4.8 Add loading progress indicators during model operations
- [x] 4.9 Implement error display with retry option

## 5. Dynamic Language Selection UI

- [x] 5.1 Create language selection component that observes model selection
- [x] 5.2 Implement language list filtering based on selected ASR model
- [x] 5.3 Implement language list filtering for align model context
- [x] 5.4 Implement language list filtering for TTS model context
- [x] 5.5 Add automatic language selection fallback when switching models
- [x] 5.6 Add user notification for automatic language changes

## 6. Feature View Updates - AI Cut

- [x] 6.1 Remove model selection UI from AI Cut view
- [x] 6.2 Update AI Cut to use `AppConfiguration` for model selection
- [x] 6.3 Integrate with `ModelCacheManager` for lazy model loading
- [x] 6.4 Add loading state handling for align model
- [x] 6.5 Update error handling to use new model lifecycle system

## 7. Feature View Updates - Voice To Text

- [x] 7.1 Remove model selection UI from Voice To Text view
- [x] 7.2 Update Voice To Text to use `AppConfiguration` for model selection
- [x] 7.3 Integrate with `ModelCacheManager` for ASR model access
- [x] 7.4 Update error handling to use new model lifecycle system

## 8. TranscriberPool Migration

- [x] 8.1 Identify all `TranscriberPool` usage in codebase
- [x] 8.2 Replace `TranscriberPool` references with `ModelCacheManager` for ASR models
- [x] 8.3 Update transcription logic to use new model retrieval methods
- [x] 8.4 Verify all transcription workflows work with new system
- [x] 8.5 Deprecate or remove `TranscriberPool.swift` (after verification)

## 9. Testing and Validation

- [x] 9.1 Write unit tests for `ModelCacheManager` lazy loading logic
- [x] 9.2 Write unit tests for automatic cleanup timer
- [x] 9.3 Write unit tests for language filtering based on model
- [x] 9.4 Write integration tests for model selection UI flow
- [x] 9.5 Test model loading error scenarios and recovery
- [x] 9.6 Test concurrent model request handling
- [x] 9.7 Test memory cleanup effectiveness
- [x] 9.8 Verify configuration persistence across app restarts
- [x] 9.9 Test migration from existing `TranscriberPool` usage

## 10. Documentation and Polish

- [x] 10.1 Update CLAUDE.md with new model management architecture
- [x] 10.2 Add inline documentation to `ModelCacheManager` public interface
- [x] 10.3 Create user-facing documentation for Models page
- [x] 10.4 Add migration guide for release notes
- [x] 10.5 Performance profiling and optimization
- [x] 10.6 Final UI polish and accessibility review
