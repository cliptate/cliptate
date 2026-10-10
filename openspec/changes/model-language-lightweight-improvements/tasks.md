## 1. Remove Whisper from UI pickers (TDD)

- [x] 1.1 Add `isSelectableByUser` property to `TranscriberType` — write test asserting `.whisper.isSelectableByUser == false` and other cases `== true`; implement property.
- [x] 1.2 Filter `ModelSelectionView` engine picker to only show `TranscriberType.allCases.filter { $0.isSelectableByUser }`.
- [x] 1.3 Filter `LightweightMenuView` ASR model submenu to only iterate selectable engines.

## 2. Language filtering by model in LightweightMenuView (TDD)

- [x] 2.1 Write test that `ModelVariant.parakeetV2.supportedLanguages` returns only `.english` (verify existing behavior).
- [x] 2.2 Replace `config.transcriberType.supportedLanguages` in `LightweightMenuView` with `config.modelVariant.supportedLanguages`.

## 3. Downloaded-only models in menu bar picker

- [x] 3.1 Add `@State` dictionary to `LightweightMenuView` to track per-model download status.
- [x] 3.2 Load download statuses on appear and on `.modelArtifactsDidChange` notification.
- [x] 3.3 Filter model list to show only downloaded models; show "No models" fallback if empty.

## 4. Lightweight mode memory eviction (TDD)

- [x] 4.1 Add `evictAll()` method to `ModelCacheManager` — write test asserting entries are emptied and teardown is called.
- [x] 4.2 Call `ModelCacheManager.shared.evictAll()` from `LightweightModeManager.enterLightweightMode()`.
- [x] 4.3 On `exitLightweightMode()`, trigger `TranscriberWarmupCoordinator` to re-warm the configured ASR model.
- [x] 4.4 Verify memory savings by checking that no model entries remain after `evictAll()`.

## 5. Integration & validation

- [x] 5.1 Run `swift test` to verify all new and existing tests pass.
- [x] 5.2 Run `swift build` to ensure no compilation errors.
