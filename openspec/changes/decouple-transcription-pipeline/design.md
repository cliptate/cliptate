## Context

The current transcription implementation mixes orchestration, model resolution, UI progress updates, and stage-specific behavior across multiple entry points. `AICutView` contains duplicated file/batch transcription branches, `VoiceTranscriber` performs its own dictation retranscription orchestration, and `VoiceToTextView` history reprocessing duplicates another batch transcription path. On top of that, some concrete modules still embed orchestration concerns, which makes it hard to reason about the intended stage order and to remove stale code safely.

The target workflow is:

```text
file batch source -> VAD -> ASR -> Align -> post-process -> session/result mapping
streaming dictation -> streaming VAD -> streaming ASR
dictation stop/history reprocess -> shared batch source -> VAD -> ASR -> post-process
```

The repository already has useful stage protocols (`VADProvider`, `ASRChunkProvider`, `AlignChunkProvider`, `StreamingVADProvider`) and a `BatchTranscriptionPipeline`, but the orchestration boundary is incomplete because callers still branch on concrete types and assemble the pipeline themselves.

## Goals / Non-Goals

**Goals:**
- Establish one shared batch transcription orchestration boundary for file transcription, dictation finalization, and history reprocessing, while allowing workflows to opt into or skip Align explicitly.
- Keep VAD, ASR, Align, and post-processing behind stage-oriented contracts so concrete implementations do not depend on one another directly.
- Move model-specific branching and stage selection out of views and into a dedicated resolver/service layer.
- Preserve current user-visible behavior: streaming dictation stays low latency, while finalized dictation results use the higher-accuracy batch path.
- Remove obsolete or redundant orchestration helpers once the shared path is in place.

**Non-Goals:**
- Changing transcription model outputs, prompt behavior, or adding new model families.
- Reworking unrelated export, translation, or dubbing flows.
- Replacing the existing cache/download systems (`ModelCacheManager`, `ModelDownloadManager`) beyond what is needed to support the new orchestration boundary.

## Decisions

### 1. Introduce a shared batch orchestration service

Create a dedicated service layer that accepts a source audio input, a transcription profile, and progress callbacks, then runs `VAD -> ASR -> [Align] -> post-process`. This service becomes the only path used by:
- AI Cut single-file transcription
- AI Cut imported batch transcription
- voice dictation stop-time retranscription
- voice dictation history reprocessing

**Why:** The duplicated branches in views and dictation code are the main source of coupling and drift.

**Alternatives considered:**
- Keep orchestration in views and extract only helper functions: rejected because the view layer would still own model-specific branching.
- Push orchestration into concrete transcriber types: rejected because it creates direct ASR/Align dependencies and prevents stage-level composition.

### 2. Split orchestration into resolver + runner responsibilities

Use a resolver to convert configuration into stage providers and a runner to execute the stages. The resolver owns model selection, compatibility checks, and cache access. The runner owns stage ordering, progress reporting, and source/result adaptation.

**Why:** This keeps configuration concerns separate from execution concerns and allows both file transcription and dictation finalization to reuse the same runner with different source adapters.

**Alternatives considered:**
- Keep a monolithic `TranscriptionPipelineFactory`: rejected because the current factory already leaks global configuration and concrete-type branching.

### 3. Treat Align as an optional first-class stage, not a Qwen-specific special case in callers

The batch pipeline will always reason in terms of an optional Align stage. File transcription and dictation finalization will not branch on `Qwen3ASRTranscriber` directly. Instead, the resolver determines whether Align is enabled for the current workflow and returns the appropriate stage set. File transcription enables Align when an aligner is available; dictation retranscription and history reprocessing explicitly disable Align even when an aligner is available.

**Why:** The desired architecture is stage-based, not model-based. Callers should not need to know whether Qwen/Parakeet/FireRed are active.

**Alternatives considered:**
- Keep explicit `if qwen3` branches in `AICutView` and dictation code: rejected because it preserves the highest-coupling paths we want to remove.

### 4. Keep streaming dictation separate, but route finalized accuracy passes through the batch service

Streaming dictation remains a dedicated low-latency path using `StreamingAudioCaptureModule`, `StreamingVADProvider`, and `StreamingASREngine`. When dictation stops normally, the recorded audio is handed to the shared batch orchestration service for final output and history persistence, but that finalized dictation path skips Align to avoid unnecessary extra processing.

**Why:** Streaming and batch have different latency/accuracy goals, but finalized dictation should still benefit from the same deterministic batch pipeline as file transcription.

**Alternatives considered:**
- Merge streaming and batch into one service: rejected because the lifecycle, threading, and latency requirements differ too much.

### 5. Centralize post-processing after batch transcription

Dictionary bias application, speaker propagation, and transcript/session mapping should happen after the shared batch runner returns a `TranscriptionResult`. This post-processing layer is shared across file transcription and dictation finalization.

**Why:** These concerns are currently duplicated or partially duplicated, especially around dictation retranscription and history reprocess flows.

**Alternatives considered:**
- Apply post-processing ad hoc in each caller: rejected because it recreates drift and complicates cleanup.

### 6. Remove legacy orchestration surfaces after migration

After the shared orchestration path is in place, redundant helpers such as `TranscriberPool` and any superseded "aligner that also transcribes" entry points should be retired or reduced to pure stage capabilities.

**Why:** Leaving old orchestration entry points in place would continue to invite accidental reuse and make future refactors harder.

## Risks / Trade-offs

- **[Risk] Migration touches multiple entry points at once** -> Mitigate by introducing the shared batch service first, then migrate callers one-by-one behind focused tests.
- **[Risk] Progress reporting regresses when moving orchestration out of views** -> Mitigate by keeping progress callback contracts stable and mapping service progress into existing UI state updates.
- **[Risk] Optional align behavior becomes ambiguous across workflows** -> Mitigate by making resolver output explicit about whether Align is enabled, unavailable, or intentionally disabled by the calling workflow.
- **[Risk] Cleanup removes code still needed by warmup or caching paths** -> Mitigate by migrating to the new orchestration boundary before deleting legacy helpers and by keeping cache access in the resolver layer.

## Migration Plan

1. Introduce the shared batch transcription resolver/service without changing user-facing behavior.
2. Migrate AI Cut file transcription and imported batch transcription to the shared batch service.
3. Migrate dictation stop-time retranscription and history reprocessing to the same batch service, with Align disabled for those workflows.
4. Remove duplicated model-specific branches and obsolete orchestration helpers.
5. Keep streaming dictation on its dedicated path, using only the shared finalization service for stop-time accuracy passes.

## Open Questions

- Should AI Cut require Align for all supported ASR models, or continue allowing a no-align fallback when no aligner is configured/downloaded?
- Should speaker propagation remain a post-processing concern only, or should the resolver expose speaker-capable VAD metadata to make downstream behavior more explicit?
