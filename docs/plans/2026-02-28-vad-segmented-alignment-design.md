# VAD Segmented Alignment Design

## Problem

Current forced alignment quality drops sharply when a single `alignWithText` request contains very long audio (notably beyond ~5 minutes).  
The root issue is that the aligner receives overly long context in one pass, causing unstable token-to-time mapping.

## Goal

Introduce a unified pipeline that guarantees alignment is always performed on short speech chunks, while preserving the final output contract (`single Segment + full words`) for downstream compatibility.

## Final Approach

Use **one mandatory flow for all engines**:

1. Run independent **VAD segmentation** on full audio.
2. For each VAD speech segment:
   - Extract segment audio.
   - Run ASR on this segment to get text.
   - Run forced alignment on the same segment audio + segment text.
3. Rebase aligned timestamps by global segment offset.
4. Merge all aligned words in timeline order.
5. Return one final `Segment` containing merged `words`.

This guarantees no alignment call sees a long (>300s) input and removes the previous long-audio failure mode.

## Architecture Changes

### 1) Shared speech segmentation utility

- Add a reusable `SpeechSegmenter` service to encapsulate:
  - VAD model setup
  - segmentation config
  - clamping to media duration
  - output normalization to `VadSegment`

### 2) Unified segmented alignment orchestration

- Add a single orchestration path in AI Cut flow (`runSegmentedAlignmentPipeline`), used by all engines when forced alignment is enabled.
- This path owns:
  - VAD segmentation
  - per-segment ASR
  - per-segment alignment
  - timestamp offset merge
  - progress reporting

### 3) Audio segment extraction helpers

- Extend `AudioProcessor` with helpers for:
  - sample slicing by `[startTime, endTime]`
  - temporary segment WAV export
  - cleanup of temporary artifacts

### 4) Qwen3 two-phase path alignment

- Refactor `Qwen3ASRTranscriber.transcribeWithAlignment` to align with the same segmented orchestration semantics (VAD -> ASR -> align), eliminating whole-audio align calls.

## Data Flow

1. Load source audio and duration.
2. `SpeechSegmenter.segment(audio)` -> `[VadSegment]`.
3. For each `VadSegment` in order:
   - Build temporary chunk audio file.
   - ASR transcribe chunk.
   - Align chunk text on chunk audio.
   - Offset chunk word timings by `segment.startTime`.
4. Append into global `allWordTimings`.
5. Build final merged text with `WordTimingTextComposer`.
6. Return one merged segment.

## Error Handling

Adopt **fail-fast** behavior:

- If any chunk fails in VAD/ASR/align, abort entire pipeline immediately.
- Surface explicit error context (chunk index + stage) in thrown error.
- If no valid speech segments, return empty alignment result with clear status.

## Progress Reporting

- Progress is chunk-based and stage-aware:
  - `VAD` initialization/detection
  - `ASR i/n`
  - `Align i/n`
- Keep UI status messages deterministic and user-readable.

## Testing Plan

Add/extend tests covering:

1. **Long audio safety**: >5 minute audio always executes chunked alignment, and each align request stays below 300s.
2. **Timeline integrity**: merged word timings are monotonic and correctly offset to global timeline.
3. **Fail-fast correctness**: any single-chunk ASR/align failure aborts whole process.
4. **Short audio parity**: <=5 minute audio through the new pipeline remains equivalent in output shape/timing characteristics.

## Non-Goals

- No new UI toggles or user-facing configuration for chunk thresholds in this change.
- No fallback path that performs whole-audio `alignWithText` for long inputs.
