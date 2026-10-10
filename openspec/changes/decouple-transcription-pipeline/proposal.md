## Why

The current transcription flow is split across `AICutView`, `VoiceTranscriber`, `VoiceToTextView`, and several model-specific services, so file transcription and dictation finalization assemble the pipeline differently and duplicate orchestration logic. This makes the VAD -> ASR -> Align sequence hard to reason about, increases concrete-module coupling, and leaves dead or overlapping code paths in place.

## What Changes

- Introduce a unified transcription orchestration layer that resolves and runs the `VAD -> ASR -> Align` pipeline for file transcription, while allowing dictation finalization to reuse the same batch orchestration boundary with Align explicitly skipped.
- Separate stage contracts from concrete implementations so VAD, ASR, and Align modules can be selected independently without direct cross-module knowledge.
- Refactor file transcription and voice dictation finalization to reuse shared batch transcription and post-processing services instead of duplicating model-selection and alignment branches in views.
- Keep streaming dictation focused on low-latency capture and streaming ASR, while routing stop-time accuracy passes through the shared batch pipeline.
- Remove or retire redundant orchestration paths and obsolete helpers that are superseded by the shared pipeline services.

## Capabilities

### New Capabilities
- `transcription-pipeline`: Defines a shared, stage-based transcription orchestration model that applies `VAD -> ASR -> Align` to file transcription and `VAD -> ASR` to dictation retranscription/finalization, while keeping stage implementations loosely coupled.

### Modified Capabilities
- None.

## Impact

- Affected code: `AICutView`, `VoiceTranscriber`, `VoiceToTextView`, `TranscriptionPipelineFactory`, batch/streaming transcription services, speaker post-processing, and related model resolution code.
- Affected systems: file transcription, microphone dictation, dictation retranscription/history reprocessing, model cache access, and transcription post-processing.
- Expected cleanup: duplicate Qwen-specific orchestration branches, legacy transcriber pooling, and cross-stage implementation dependencies.
