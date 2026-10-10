## 1. Shared batch orchestration

- [x] 1.1 Introduce a shared batch transcription resolver/service that resolves VAD, ASR, Align, and post-processing stages without caller branching on concrete model types
- [x] 1.2 Refactor `TranscriptionPipelineFactory` and related stage adapters so resolver inputs come from explicit configuration/profile data instead of view-owned branching or global configuration lookups
- [x] 1.3 Add or update focused tests for shared batch stage ordering, stage selection, and shared post-processing behavior

## 2. Migrate file and dictation workflows

- [x] 2.1 Migrate AI Cut single-file transcription and imported batch transcription to the shared batch orchestration service
- [x] 2.2 Migrate `VoiceTranscriber` stop-time retranscription to the shared batch orchestration service while preserving the streaming live path and explicitly skipping Align
- [x] 2.3 Migrate `VoiceToTextView` history reprocessing to the same finalized dictation batch service used by normal dictation finalization, also skipping Align

## 3. Cleanup and verification

- [x] 3.1 Remove duplicated model-specific orchestration branches and retire obsolete helpers superseded by the shared pipeline boundary
- [x] 3.2 Reduce concrete modules such as aligner-specific helpers to pure stage capabilities instead of alternate orchestration entry points
- [x] 3.3 Run and update focused tests for AI Cut, dictation finalization, and shared transcription pipeline regressions
