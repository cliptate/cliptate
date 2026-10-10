# VAD+ASR → Per-segment Alignment Design

## Problem

The current `transcribeWithAlignment` method in `Qwen3ASRTranscriber` runs forced alignment on the **entire audio** with the **concatenated full text** from all ASR segments. This causes two issues:

1. Alignment quality degrades for longer audio since the aligner receives a large, undivided audio+text pair.
2. `rebuildAlignedSegments` uses a token-counting heuristic to re-map flat word-level alignment results back to ASR segment boundaries — a fragile operation prone to drift.

## Goal

Refactor `transcribeWithAlignment` so that forced alignment is always performed **per ASR segment**, on the exact audio slice corresponding to that segment. This guarantees:

- Each alignment call receives a short, focused audio+text pair.
- Segment boundaries come directly from the ASR output — no reconstruction heuristic needed.
- Precise, rebased word-level timestamps in the final output.

## Chosen Approach

Keep Phase 1 (ASR) unchanged. Refactor Phase 2 (Alignment) to operate per ASR segment.

## New Flow

```
transcribeWithAlignment(audioPath, language, asrTranscriber)
  │
  ├── Phase 1 (0–40%): ASR  [unchanged]
  │   Load audioSamples once (16kHz [Float])
  │   asrTranscriber.transcribeWithProgress(chunkDuration: 3.0)
  │   → asrResult: [Segment { startTime, endTime, text }]
  │
  └── Phase 2 (40–100%): Per-segment align  [refactored]
      For each asrSegment (i of n):
        samples_i = audioSamples[asrSegment.startTime .. asrSegment.endTime]
        wordTimings_i = alignerModel.generate(MLXArray(samples_i), text: asrSegment.text, language)
        rebase: word.startTime += asrSegment.startTime
                word.endTime   += asrSegment.startTime
        apply punctuation from asrSegment.text
        → emit Segment(startTime, endTime, text, words: rebased_words)
      → Return TranscriptionResult([Segment])
```

## Code Changes

### 1. `transcribeWithAlignment` (refactored Phase 2)

- Phase 1 returns `asrResult` and the already-loaded `audioSamples: [Float]` (avoids a second file load in Phase 2).
- Phase 2 replaces the single `alignWithText(fullAudio, fullText)` call with a per-segment loop:
  - Slice `audioSamples` by `[asrSegment.startTime, asrSegment.endTime]`.
  - Call private `alignSamples(_:text:language:)`.
  - Rebase all word timestamps by `asrSegment.startTime`.
  - Apply punctuation from `asrSegment.text` to rebased words.
  - Construct one output `Segment` per ASR segment.

### 2. New private method: `alignSamples`

```swift
private func alignSamples(
  _ samples: [Float],
  text: String,
  language: Language
) throws -> [WordTiming]
```

Wraps `alignerModel.generate(audio: MLXArray(samples), text: text, language:)` at the sample level. Throws on any failure (fail-fast behavior).

### 3. Delete `rebuildAlignedSegments`

The token-counting heuristic is no longer needed. Segment boundaries come directly from ASR output; alignment operates within each boundary.

### 4. Audio sample slicing helper (reuse existing)

Use the existing sample-slicing logic (as in `WhisperTranscriber.extractSamples`) extracted into or reused from `AudioProcessor`, or implemented inline as a private helper.

## Error Handling

Fail-fast: if `alignSamples` throws for any segment, `transcribeWithAlignment` rethrows immediately and the whole operation fails.

## Non-goals

- No changes to `transcribeWithProgress` (non-alignment path).
- No changes to the public `alignWithText` API.
- No new UI toggles or configuration knobs.
- No changes to `WhisperTranscriber` or `SegmentedAlignmentPipeline`.

## Testing Plan

1. **Per-segment coverage**: verify each ASR segment produces aligned words whose timestamps fall within `[asrSegment.startTime, asrSegment.endTime]` after rebasing.
2. **Timeline monotonicity**: merged word timings across all segments are sorted and non-overlapping.
3. **Fail-fast**: if any segment's alignment throws, the whole pipeline throws.
4. **Empty segment skipping**: ASR segments with empty text are skipped cleanly.
5. **Short audio regression**: single-segment audio produces the same output shape as before.
