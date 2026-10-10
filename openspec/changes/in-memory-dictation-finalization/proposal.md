## Why

Voice dictation currently depends on a retained recording file before the higher-accuracy batch finalization path can run. That adds file I/O to the stop-recording critical path, which makes final dictation results feel slower than necessary and recently made the retranscription path fragile when recording persistence regressed.

## What Changes

- Finalize stopped dictation sessions from in-memory normalized audio samples instead of requiring a persisted recording file before batch retranscription can begin.
- Move dictation audio file persistence off the critical path so final text can be produced before retained playback/retranscription artifacts are written.
- Preserve existing history behavior by asynchronously backfilling the retained dictation recording after final text delivery, including playback and manual retranscription support once persistence completes.
- Add regression coverage for the new in-memory finalization path and the deferred recording persistence behavior.

## Capabilities

### New Capabilities
- `dictation-finalization`: Fast, accuracy-first dictation finalization from in-memory captured audio with deferred retained-recording persistence.

### Modified Capabilities

## Impact

- **Services**: `StreamingAudioCaptureModule`, `VoiceTranscriber`, `BatchTranscriptionService`, and post-processing helpers that currently assume a source URL-backed dictation finalization flow.
- **Models / History**: `TranscriptSession` lifecycle and history update timing for dictation recordings that may become available after text finalization.
- **Tests**: Streaming capture, voice transcriber finalization, and history-facing regression coverage for deferred recording persistence.
