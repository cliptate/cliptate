## 1. In-memory dictation capture

- [x] 1.1 Extend `StreamingAudioCaptureModule` to accumulate full-session normalized dictation samples and expose a finalized capture payload for stop-time finalization.
- [x] 1.2 Keep retained recording persistence optional and separable from capture reset so deferred file writing does not block final-text generation.

## 2. Samples-backed batch finalization

- [x] 2.1 Extend the dictation batch finalization path to accept in-memory samples and duration without requiring a source URL.
- [x] 2.2 Refactor speaker propagation / post-processing helpers so dictation finalization can preserve dictionary bias and speaker annotation from samples-backed input.

## 3. Voice transcriber integration

- [x] 3.1 Update `VoiceTranscriber.stop()` to finalize dictation from in-memory capture first and deliver final text before retained audio persistence completes.
- [x] 3.2 Persist retained dictation audio asynchronously after finalization and backfill `TranscriptSession` / history metadata when the recording becomes available.

## 4. Regression coverage

- [x] 4.1 Add focused tests for in-memory dictation finalization succeeding without a pre-existing recording file.
- [x] 4.2 Add focused tests for deferred recording persistence backfilling session metadata without regressing playback/retranscription availability.
