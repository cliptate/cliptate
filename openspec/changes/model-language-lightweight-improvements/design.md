## Context

VoiceFlowPro supports multiple ASR engines (Parakeet, Qwen3, FireRed) each with model variants that support different languages. The Whisper engine was deprecated and already redirects to Parakeet internally. Lightweight mode only hides the UI but leaves ~0.5–2 GB of ML model tensors in memory.

## Goals / Non-Goals

**Goals:**
- Remove Whisper from user-facing pickers while maintaining backward compat for persisted configs.
- Show only downloaded models in the menu bar ASR picker.
- Filter the dictation language picker by the active model's `supportedLanguages`.
- Evict all cached model runtimes on lightweight mode entry to reclaim memory.
- Re-warm the selected ASR model when exiting lightweight mode.

**Non-Goals:**
- Removing `TranscriberType.whisper` from the enum entirely (would break Codable decode of old snapshots).
- Changing the Models Library download UI (out of scope).
- Modifying language filtering in `ModelAwareLanguageSelectionView` (already correct).

## Decisions

### 1. Hide Whisper from pickers (not remove from enum)

Introduce a `var isSelectableByUser: Bool` on `TranscriberType`. Set it `false` for `.whisper`. Filter pickers by this property. This avoids Codable decode breakage for existing user snapshots.

**Alternative considered:** Remove case entirely → breaks persisted JSON, rejected.

### 2. Model-aware language filtering in LightweightMenuView

Replace `config.transcriberType.supportedLanguages` (deprecated, returns all) with `config.modelVariant.supportedLanguages`. This already works correctly—`ModelVariant` has per-model language lists.

### 3. Downloaded-only models in menu bar

Call `ModelDownloadManager.shared.hasLocalArtifacts(for:)` asynchronously on appear/notification and cache results in a `@State` dictionary. Filter the picker items by download status.

### 4. ModelCacheManager.evictAll() for lightweight mode

Add a public `evictAll()` method on `ModelCacheManager` that iterates all `entries`, calls `teardown(resource:)` on each, clears the dictionary, and calls `MLX.Memory.clearCache()`. `LightweightModeManager` calls this on entry.

On exit (`exitLightweightMode`), post a notification or call `TranscriberWarmupCoordinator` to re-warm the configured model.

### 5. TDD approach

Write failing tests first for:
- `TranscriberType.whisper.isSelectableByUser == false`
- `ModelVariant.supportedLanguages` filtering (already tested, verify)
- `ModelCacheManager.evictAll()` empties entries and calls teardown
- Language picker shows only model-supported languages

## Risks / Trade-offs

- [Lightweight → evict all] If the user rapidly toggles modes, they get repeated warm-ups. → Mitigation: debounce or skip warmup if re-entering lightweight within 2s.
- [Downloaded-only picker] On first launch before any download, the menu shows nothing. → Mitigation: show "No models downloaded" message with link to Models Library, consistent with `ModelSelectionView`.
- [Removing Whisper from picker] Users with saved `transcriberType: whisper` snapshots won't see their engine. → Mitigation: `applySnapshot` already maps whisper→parakeet via `supportedModels` fallback.
