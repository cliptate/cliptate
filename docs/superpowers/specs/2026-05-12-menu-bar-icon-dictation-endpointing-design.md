# Design: Menu Bar Icon Sizing and Accuracy-First Dictation Endpointing

**Date:** 2026-05-12
**Status:** Draft

## Problem

Two small but user-visible issues in the lightweight dictation flow should be improved together:

1. **Menu bar icon feels undersized.** The current `MenuBarExtra` label rasterizes the app icon at 18pt, which makes it read slightly too small in the macOS menu bar.
2. **Streaming dictation ends segments too aggressively.** The current streaming VAD flow flushes buffered speech as soon as a chunk has no detected speech. In practice, short pauses, breaths, and tail decay are treated as end-of-utterance boundaries too early, which can fragment context and make interim text less stable.

The goal is to make the menu bar entry easier to spot and make live dictation text more accurate and less jittery, without redesigning the dictation UI or changing the final batch re-transcription flow.

## Chosen Direction

Use a narrow, behavior-safe update:

1. Increase the menu bar icon target size from **18pt to 22pt**.
2. Change streaming dictation from **single-silence flush** to **accuracy-first endpointing**:
   - keep the existing 0.5s chunk size
   - require **3 consecutive silent chunks** before flushing the current speech window
   - keep the maximum speech window cap so long utterances still produce interim results
   - always flush trailing speech when the user stops recording

This keeps the architecture intact while making the endpointing logic less trigger-happy.

## Alternatives Considered

### 1. Icon-only tweak

Increase the menu bar icon size and leave VAD behavior unchanged.

**Pros**
- Smallest possible change
- Near-zero behavioral risk

**Cons**
- Does not address the dictation accuracy complaint
- Leaves the main UX problem in place

### 2. Accuracy-first endpointing (**chosen**)

Keep the current streaming pipeline, but delay flush until silence is stable.

**Pros**
- Improves sentence continuity and ASR context
- Keeps current UI and service boundaries
- Small enough to verify with focused tests

**Cons**
- Interim text appears slightly later than today
- Needs accumulator behavior changes and regression coverage

### 3. Two-layer live text model

Introduce separate “unstable” and “stable” streaming text states, or a richer endpointing state machine.

**Pros**
- Best long-term UX potential
- More explicit model for live transcription confidence

**Cons**
- Larger UI and state-management change
- Unnecessary scope for the current request

## Design Details

## 1. Menu Bar Icon

The `MenuBarExtra` label in `Sources/Cliptate/Cliptate.swift` currently loads `AppIcon` and draws it into an 18×18 `NSImage`.

The design change is intentionally minimal:

- keep using the app icon rather than switching to a template symbol
- keep the current fallback to `mic.fill`
- change only the target raster size from **18pt** to **22pt**

No icon asset changes are needed. This is a presentation-only tweak in the menu bar entry.

## 2. Dictation Endpointing Behavior

### Current behavior

`StreamingSpeechAccumulator` currently behaves like this:

- append speech sample ranges from each chunk into `pendingSpeech`
- if the next chunk contains no speech, flush immediately
- if `pendingSpeech` reaches the configured maximum, flush immediately

This makes endpointing extremely sensitive to momentary silence.

### New behavior

The accumulator should become silence-aware:

- track the count of **consecutive silent chunks** seen while `pendingSpeech` is non-empty
- do **not** flush on the first silent chunk
- do **not** flush on the second silent chunk
- flush only when the silent chunk count reaches **3**
- if speech resumes before reaching the threshold, reset the silent chunk count to zero and continue accumulating into the same speech window

This changes endpointing from “first silent chunk ends the utterance” to “stable silence ends the utterance.”

### Why this improves accuracy

The main issue is not necessarily poor VAD classification; it is premature segmentation.

When a short pause fragments a sentence into multiple micro-windows:

- the ASR engine sees less linguistic context
- trailing words are more likely to be clipped or misread
- interim text changes more often and feels less stable

Requiring stable silence before flush preserves more natural sentence structure and gives the streaming ASR stage better context.

## 3. Interim Text Timing

Interim text should remain **segment-based**, not chunk-based.

That means:

- UI text updates only after a speech window is actually submitted to ASR and returns text
- short pauses no longer trigger immediate interim refreshes
- interim text becomes slower but more stable

This is the intended trade-off for the selected **accuracy-first** direction.

## 4. Forced Flush Rules

The endpointing threshold must not block output forever.

The design keeps two forced flush paths:

1. **Max speech window cap**  
   If buffered speech reaches the configured `maxSpeechWindowDuration`, emit it even if stable silence has not yet arrived.

2. **Stop / finalization flush**  
   When the user stops dictation, all remaining buffered speech must be flushed even if the silence threshold was not met.

These rules preserve responsiveness on long utterances and correctness on stop.

## 5. Implementation Boundaries

The change should stay within the existing streaming stack:

- `Sources/Cliptate/Cliptate.swift`
  - increase menu bar icon raster size to 22pt
- `Sources/Cliptate/Services/StreamingSpeechAccumulator.swift`
  - add consecutive-silence tracking and threshold-based flush
- `Sources/Cliptate/Services/StreamingAudioCaptureModule.swift`
  - configure the accumulator with accuracy-first endpointing parameters
- `Sources/Cliptate/Services/VoiceTranscriber.swift`
  - keep dictation chunk/window configuration explicit and align tests with the chosen endpointing policy

The following are intentionally out of scope:

- new UI settings for endpointing sensitivity
- changes to the final batch re-transcription workflow
- separate unstable/stable transcript presentation layers
- a full endpointing state machine rewrite

## Testing Strategy

Implementation should follow TDD with focused regression coverage first.

### Unit tests

Add or update tests for `StreamingSpeechAccumulator` to cover:

1. one silent chunk does not flush buffered speech
2. two consecutive silent chunks still do not flush
3. the third consecutive silent chunk flushes the buffered speech
4. speech resuming before the threshold resets the silent count
5. max buffered speech still forces an emission
6. `flush()` still returns trailing buffered speech on stop

### Integration and configuration tests

Keep or update tests that assert dictation streaming configuration so the selected values remain intentional:

- streaming chunk duration stays at 0.5s
- live dictation keeps a bounded speech window
- the new endpointing threshold is wired into the streaming stack

## Success Criteria

The change is successful if:

1. the menu bar icon is visibly easier to spot than the current 18pt version
2. short pauses during live dictation no longer split speech into overly small interim segments
3. interim text appears slightly later but changes less often and reads more coherently
4. long utterances still produce interim updates because the max speech window cap remains active
5. stopping dictation still returns the final trailing text reliably
