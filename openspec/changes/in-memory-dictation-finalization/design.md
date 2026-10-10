## Context

Voice dictation currently uses a two-step accuracy path: streaming ASR for live feedback, then batch retranscription after stop for the final result. The recent recording-sink regression exposed that the finalization path is tightly coupled to persisted audio files: dictation cannot complete its accuracy pass unless the retained recording exists on disk and can be loaded back through the batch service.

The current flow also places file I/O directly on the stop-recording critical path. `StreamingAudioCaptureModule` captures microphone PCM, resamples/chunks it for streaming ASR, and now also writes the same capture stream to a retained WAV file. `VoiceTranscriber.stop()` waits for that retained recording to finalize before starting `BatchTranscriptionService.transcribe(...)`, which then reloads the file back into memory. This creates avoidable latency and keeps the user waiting for work that is not required to compute the final transcript text.

## Goals / Non-Goals

**Goals:**
- Finalize stopped dictation sessions from in-memory normalized audio samples without requiring a retained file to exist first.
- Keep dictation finalization accuracy equivalent to the current batch path, including VAD-driven segmentation, dictionary bias, and speaker propagation where available.
- Move retained recording persistence off the user-facing critical path while preserving history playback and manual re-transcription behavior once persistence completes.
- Keep failure handling robust: if deferred persistence fails, final text still succeeds.

**Non-Goals:**
- Changing the existing 24-hour dictation audio retention behavior.
- Removing retained dictation recordings from history.
- Reworking file-transcription or AI Cut batch transcription flows.
- Changing the live streaming ASR experience or endpointing configuration.

## Decisions

### 1. Add an in-memory dictation capture artifact at 16 kHz mono

**Decision:** `StreamingAudioCaptureModule` will accumulate a full-session normalized audio buffer using the same 16 kHz mono samples already produced for streaming chunk processing.

**Rationale:** The batch retranscription pipeline ultimately consumes normalized sample arrays, not raw mic buffers. Reusing the post-resample working format avoids a second conversion pass and lets dictation finalization skip the “write file -> read file back into samples” round trip.

**Alternative considered:** Buffer original `AVAudioPCMBuffer` instances and convert them later. Rejected because it keeps more format variability in memory and preserves more data than the batch path actually needs.

### 2. Split dictation finalization from retained recording persistence

**Decision:** `VoiceTranscriber.stop()` will first request a finalized in-memory capture payload and immediately run batch dictation finalization from samples. Persisting the retained WAV file becomes a background follow-up step that updates the session/history once complete.

**Rationale:** This removes file persistence from the critical path the user feels when releasing the shortcut or pressing stop. It also reduces coupling between “produce final text” and “retain playback artifact”.

**Alternative considered:** Keep the current file-backed pipeline and merely write asynchronously earlier. Rejected because the finalization path would still be fundamentally dependent on file availability, which keeps the same fragility class.

### 3. Extend batch dictation finalization to support samples-first input

**Decision:** `BatchTranscriptionService` and post-processing helpers will support a samples-backed dictation input path in addition to the existing URL-backed path.

**Rationale:** Batch ASR already runs on `[Float]` samples. The remaining URL dependency exists mostly at the service boundary and in speaker propagation helpers. Making those layers accept in-memory samples keeps the batch logic unified while removing the dictation-specific file requirement.

**Alternative considered:** Create a dictation-only batch pipeline separate from `BatchTranscriptionService`. Rejected because it would duplicate segmentation, progress, and post-processing logic that already exists.

### 4. History metadata may be updated after final text delivery

**Decision:** Dictation sessions may initially complete with transcript text but without `recordingURL`, then receive a follow-up history/session update once deferred persistence succeeds.

**Rationale:** This matches the desired UX priority: final text first, playback artifact second. The session model and history store already support updates, so this can be represented as a lifecycle change rather than a separate entity.

**Alternative considered:** Delay history insertion until the recording file is available. Rejected because it would defer visibility of completed dictation sessions and keep the UX penalty.

## Risks / Trade-offs

- **[Risk] Increased memory usage for long dictation sessions** → Mitigation: store normalized mono samples only, consider compact storage (e.g. Int16) if profiling shows pressure, and reset capture state immediately after finalization handoff.
- **[Risk] Samples-backed speaker propagation diverges from file-backed behavior** → Mitigation: refactor propagation helpers to share the same segmentation code and add regression tests that compare expected speaker annotation behavior.
- **[Risk] Deferred persistence races with history UI state** → Mitigation: update the current session and history store atomically when the retained recording becomes available, and keep playback/retranscribe buttons disabled until `recordingURL` exists.
- **[Risk] Background persistence failure leaves no playback artifact** → Mitigation: treat persistence as best-effort, surface logs/status for diagnostics, and never block final transcript delivery on retention failures.

## Migration Plan

1. Introduce a samples-backed dictation finalization path alongside the existing file-backed service path.
2. Switch `VoiceTranscriber` to prefer the in-memory path for stopped dictation sessions.
3. Defer retained WAV persistence to a post-finalization background task that updates the session/history on success.
4. Keep file-backed history retranscription unchanged so archived sessions remain compatible.

## Open Questions

- Whether normalized dictation capture should be stored as `Float` for implementation simplicity or `Int16` to reduce peak memory.
- Whether history should surface an explicit “Preparing audio…” state for very recent dictation sessions before deferred persistence completes.
