# Migration Guide: Model Lifecycle Refactor

## Summary

Model runtime management has moved from `TranscriberPool` to `ModelCacheManager`.

- ASR, align, and TTS model lifecycles are now unified
- Align and TTS runtimes are lazily loaded
- Idle non-ASR runtimes are automatically cleaned up (default: 10 minutes)
- Model selection UI is centralized in the Models page

## User-Facing Changes

- Voice To Text and AI Cut no longer expose model-selection controls directly
- Configure model selection from the Models page
- Language choices are now filtered by selected model capabilities
- Cache controls are available in Models (`Preload`, `Clear Cache`, status + retry)

## Technical Migration Notes

- New core actor: `ModelCacheManager`
- `TranscriberPool` is now deprecated and should not be used for new work
- `AppConfiguration` now persists `modelCleanupTimeoutSeconds`
- `AppConfiguration` publishes model lifecycle status for UI observation

## Developer Actions

1. Replace `TranscriberPool.shared.getTranscriber(...)` with `ModelCacheManager.shared.getASRTranscriber(...)`.
2. Use `getAlignTranscriber(...)` for forced aligner access.
3. Use `preloadTTSModel(...)` / `ensureTTSModel(...)` for TTS warm-up.
4. Read cache state via `ModelCacheManager.shared.snapshot()` or `AppConfiguration` published lifecycle fields.
