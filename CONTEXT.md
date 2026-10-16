# Cliptate Context

Cliptate is a macOS transcription and editing app centered on AI Cut, Voice To Text, model management, and export workflows. This context records the project-specific terms that should stay stable as the architecture deepens.

[GLOSSARY.md](GLOSSARY.md) records the CLI request session and release-channel
vocabulary that complements the application terms below.

## Language

**AppConfiguration**:
The authoritative mutable application state object for model selection, language, export options, AI settings, and TTS settings.
_Avoid_: settings bag, snapshot

**ConfigurationRuntime**:
The module that owns configuration ordering: restore, preset selection, migration, persistence, and deferred warmup around `AppConfiguration`.
_Avoid_: bootstrap helper, persistence manager, startup coordinator

**AI Cut workspace**:
The module that owns one AI Cut editing session: per-video state, phase transitions, transcription, translation, and export requests for the active working set.
_Avoid_: giant view, editor controller

**Batch transcription runtime**:
The module that owns end-to-end transcription orchestration for a file or sample request: model acquire, pipeline selection, alignment, and post-processing.
_Avoid_: helper, pipeline wrapper

**Batch transcription session**:
The reusable opaque value that owns prepared batch-transcription resources for one ASR selection and context, so multiple files can reuse the same prepared plan through `ModelRuntime`.
_Avoid_: prepared batch blob, temporary resources, pipeline cache

**Live transcription session**:
The long-lived opaque value that owns one live dictation run through `ModelRuntime`, so recording, streaming transcription, and release stay behind an abstract interface instead of exposing concrete model implementations.
_Avoid_: active lease, streaming handle, voice helper

**VoiceCompletionRuntime**:
The module that owns Voice completion: final transcript accumulation, optional AI processing, cancellation, and delivery for a dictation or assistant session, independent of the visible page.
_Avoid_: page post-processing, shortcut finalization helper

**ModelRuntime**:
The module that owns acquire, preload, release, and status over model download, cache, and warmup adapters.
_Avoid_: cache manager cluster, model bootstrap

**TTS session**:
The module that owns one text-to-speech run: synthesis, preview-ready audio, and history persistence for generated speech.
_Avoid_: TTS helper, preview utility

**Dubbing runtime**:
The module that owns dubbed-audio generation: model resolution, preflight, synthesis, and export for translated segments.
_Avoid_: dubbing helper, resolver pair

**History runtime**:
The module that owns transcript-history queries and mutations over retained sessions.
_Avoid_: history store access, history helper

**ExportPlan**:
The module that turns one export request plus the current AI Cut workspace into explicit export phases and target URLs.
_Avoid_: export flags, ad-hoc export routing

**AccessibilityGate**:
The single seam that owns macOS Accessibility-backed focused-field text injection and trust checks. Callers use it to insert dictation into other apps or fall back to the clipboard when permission is unavailable.
_Avoid_: AX helper, permission manager, accessibility wrapper

**Direct distribution**:
The free Cliptate app distributed as a download. Debug and Release expose all models and features, Accessibility-backed dictation, and the embedded CLI. Development and production keep separate identities and data.
_Avoid_: store flavor, billing channel

## Example dialogue

Dev: "Should `ConfigurationRuntime` own the settings values?"

Domain expert: "No. `AppConfiguration` stays authoritative. `ConfigurationRuntime` owns the order around it: restore the current state, apply the selected preset when needed, persist changes, and start deferred warmup."

Dev: "Where should AI Cut and transcription start from?"

Domain expert: "The AI Cut workspace owns one editing session. When it needs transcription, it calls the Batch transcription runtime, which in turn goes through ModelRuntime instead of reaching into download, cache, and warmup modules directly."
