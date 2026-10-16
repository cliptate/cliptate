# Copilot instructions for Cliptate

## Build and test commands

Use the Swift package for fast feedback, and build the app bundle when a change depends on app lifecycle or UI behavior.

```bash
swift build
swift test
swift test --filter SegmentTests
swift test --filter speakerIdRoundTrips
```

```bash
./scripts/build-and-run.sh build
./scripts/build-and-run.sh --verify
```

The SwiftPM app product is `Cliptate`; the bundler produces `Cliptate Dev.app` in Debug.

## High-level architecture

- `Sources/Cliptate/Cliptate.swift` is the real bootstrap path. It creates the shared `AppConfiguration`, `ConfigPresetStore`, and `ModelDownloadStateStore`, loads either the persisted snapshot or the default preset before the first scene appears, binds debounced persistence, and prewarms the selected ASR model.
- `Sources/Cliptate/Views/ContentView.swift` is mainly a section router. The actual editing workflow lives in `AICutView`, which owns the multi-video working set (`selectedVideoURLs`, `activeVideoURL`, `videoStates`) and keeps one `VideoState` per file so switching videos preserves playback state, raw segments, processed deletions, translations, and effect state.
- `AppConfiguration` is the source of truth for model selection, language, export options, AI provider settings, voice-to-text settings, and TTS settings. `AppConfigurationPersistence` stores the live snapshot in Application Support, while `ConfigPresetStore` separately manages named user presets.
- Model management is intentionally split:
  - `ModelDownloadManager` handles on-disk model artifacts and download progress.
  - `ModelCacheManager` owns in-memory ASR / align / TTS runtime caching, deduplicated loads, ASR leases, and idle eviction.
  - `TranscriberWarmupCoordinator` reacts to configuration changes and keeps the selected model warm.
  - `TranscriberPool` is legacy and explicitly deprecated; new workflows should not depend on it.
- Segment editing and export are timing-aware pipelines. `AICutView` derives `processedSegments` from the current `VideoState` through `SegmentProcess`, and export services (`VideoExporter`, `VideoCompositionBuilder`, subtitle exporters, `FCPXMLExporter`) consume those timing decisions. When silent filtering is enabled, the composition timeline is rebuilt instead of just hiding subtitle rows.

## Key conventions

- Do **not** use the `using-git-worktrees` skill in this repository. Work directly in the current workspace unless the user explicitly asks for a worktree-based workflow.
- Use **test-driven-development (TDD)** for implementation work in this repository: add or update a focused failing test first when practical, make the minimal code change to pass it, then refactor safely.
- Treat `AppConfiguration` as the authoritative state object. If you add a new persisted setting, it usually needs to be wired through `defaultSnapshot`, `Snapshot`, `makeSnapshot()`, `applySnapshot(_:)`, and the preset payload in `ConfigPresetStore`.
- Keep model/transcriber/language combinations normalized through `AppConfiguration` helpers rather than setting fields independently. `applySnapshot(_:)` intentionally makes voice-to-text follow the active AI Cut ASR selection.
- Use `ModelCacheManager.shared` for active model runtime access. Migration tests assert that active transcription flows no longer reference `TranscriberPool.shared`.
- Preserve per-video state in `VideoState` when changing the AI Cut workflow. `segments`, `originalSegments`, `segmentEffects`, `segmentTranslations`, `translationSignature`, `removedProcessedSegmentIDs`, and `playback` are designed to survive video switching.
- Use `SegmentIdentifier` for selection/deletion state that must survive padding, splitting, and other segment reshaping. Do not rely on array indices or `Segment.id` for cross-view coordination.
- Normalize custom dictionary entries with `AppConfiguration.normalizeDictionaryEntries(...)` or `replaceDictionaryEntries(with:)`. The app treats dictionary terms case-insensitively and diacritic-insensitively.
- SwiftPM automatically discovers tests under `Tests/CliptateTests`.
- **Internationalization (i18n)**: Every user-visible string must support localization. The app ships `Localizable.xcstrings` with translations for **zh-Hans, ja, ko** (Simplified Chinese, Japanese, Korean). Target 100% effective coverage; intentionally-untranslated entries are limited to pure format specifiers (`%@ / %@`), separator symbols (`·`, `→`), and language names shown in their own script (`中文`, `日本語`, `한국어`).
  - In SwiftUI `Text` views, **string literals** are automatically looked up in the strings catalog: `Text("Hello")` ✓. **String interpolation** (`Text("Active: \(name)")`) also creates a `LocalizedStringKey`; add the format key (e.g. `"Active: %@"`) to `Localizable.xcstrings` with zh-Hans / ja / ko translations.
  - For strings passed to parameters that accept `String` (not `LocalizedStringKey`), such as `.help("…")`, `.accessibilityLabel("…")`, `message:`, `prompt:`, always use `String(localized: "Key", comment: "Context")` (Swift 5.7+). Never pass a plain string literal or concatenated/interpolated `String` to these parameters.
  - For strings in model/service layers (business logic, log messages excluded), use `String(localized:)` or `NSLocalizedString`.
  - When adding a new user-visible string: (a) write it with the appropriate API in Swift, (b) add the key to `Localizable.xcstrings` with `"state": "translated"` entries for zh-Hans, ja, and ko. Use a Python helper script or direct JSON editing—do not leave any new key without all three translations.
  - Language names shown natively in their own script (`中文`, `日本語`, `한국어`) are acceptable as-is without further localization.
  - The app UI language can be overridden by the user from the Settings → Display Language picker, which writes `["<code>"]` to `UserDefaults` key `"AppleLanguages"`. A restart is required for the change to take effect.

## Agent skills

### Issue tracker

Issues are tracked in this repo's GitHub Issues (`cliptate/cliptate`) via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The triage workflow uses the canonical labels `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

This repo uses a single-context layout with a root `CONTEXT.md` and optional root `docs/adr/`. See `docs/agents/domain.md`.

## Requirement tracking

- When the user makes a clear product or UX change request, append a concise note to this file so later sessions can recover the recent intent and context without relying only on chat history.

## Recent tracked requirements

- 2026-10-16: keep only free direct distribution in Debug and Release; remove RevenueCat, subscription UI and access restrictions, and App Store build configuration. Preserve existing data migration, Accessibility-backed dictation, CLI, and automatic updates.

- Support URL must point to a functional support webpage instead of Telegram, and the Getting Started "Manage in Voice To Text" keyboard shortcut button must navigate reliably even while required permissions are still missing.
- Microphone/screen-recording permission prompt buttons should use neutral wording such as "Continue" instead of "Request permission."
- MicOverlay should lean further into a sci-fi / HUD look, offer multiple visual directions for comparison, and keep the right-side elapsed-time area frameless.
- During AI Enhance, MicOverlay must stay visible until enhancement actually finishes and should show the localized "Thinking..." status while enhancement is running.
- MicOverlay should use a deeper near-black "space black" surface so accent colors read as emitted light rather than tinted background chrome.
- If dictation starts while the selected ASR model is still warming, the shortcut flow should remain in startup/preparing state and continue automatically once the model is ready instead of flashing MicOverlay and aborting.
- Shortcut-triggered AI post-processing should restore MicOverlay into the AI Enhance / "Thinking..." state after retranscription completes so the enhancement phase is visible again.
- Qwen3 TTS voice cloning should end less abruptly by stabilizing clone decoding and giving sentence endings a slightly fuller release.
- TTS synthesis should support cancellation, use multilingual duration estimates that account for CJK/kana scripts, and let voice-clone reference audio be selected by drag and drop as well as Finder.
- While TTS synthesis is running, keep the generate button visible and add a neighboring cancel button; canceling should preserve any previously generated playable preview, and Finder audio drops must attach successfully.
- TTS preview generation should avoid end-of-run UI/CPU hitching by removing redundant tail-stage audio file work from the main interaction path.
- Qwen3 TTS automatic variant selection must not cap long scripts with the short/default token budget; long scripts should use the extended generation budget while explicit Short mode remains low-latency.
- Dictation should only copy transcript text to the clipboard when Accessibility permission is unavailable; with Accessibility granted, it should type directly without replacing the clipboard.
- Accessibility permission guidance should use localized hands-free text insertion copy, never auto-trigger the macOS Accessibility prompt, and send users to System Settings for manual enablement.
- The permissions section should be presented as a localized "Getting Started" guide, auto-open only when the app is freshly opened and required permissions are missing, refresh permission state when the app becomes active without forcing a section switch, and disappear from navigation once all required permissions are granted.
- The Models page should switch to a default dense row list that shows more models at once, keep only name/status/size/language summary/primary action always visible, compress the header into a compact toolbar with Refresh visible and other actions collapsed, and demote Cache Memory below Downloaded and Disk Usage.
- The Models page should use one shared visual system across ASR / Align / VAD / TTS, keep category identity to a single accent per category, avoid per-section color drift, and use semantic status colors consistently for shared states like Active / Downloaded.
- The latest Models page styling pass should override the earlier per-category-accent direction: Cache Memory should use the same primary badge treatment as Disk Usage, and ASR / Align / VAD / TTS should share the same ASR-style accent so the page reads as one cohesive library surface.
- The Models page TTS catalog should support the same downloaded-only and search-based browsing flow as other model categories so users can inspect only installed TTS models.
