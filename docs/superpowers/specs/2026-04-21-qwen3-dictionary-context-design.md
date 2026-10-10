# Qwen3 ASR Dictionary Context Integration

**Date:** 2026-04-21  
**Status:** Approved

---

## Problem Statement

The app already stores a custom ASR dictionary in `AppConfiguration.voiceToTextCustomDictionary`, but Qwen3 ASR currently only uses it as a **post-processing correction pass** via `ASRDictionaryBiasService.apply(...)`. That improves some outputs, but it does **not** influence the model's decoding decisions.

After updating `mlx-audio-swift` to the latest `main`, Qwen3 ASR's native API now exposes a real `context: String` parameter on:

- `Qwen3ASRModel.generate(...)`
- `Qwen3ASRModel.generateStream(...)`

This change should be used so dictionary entries are passed into the model as transcription context, while retaining the current bias pass as a fallback correction layer.

---

## Goals

1. Pass Dictionary entries into Qwen3 ASR as native model context.
2. Cover **all Qwen3 ASR paths that can accept context**:
   - file transcription
   - segmented chunk transcription
   - realtime / streaming transcription
   - history reprocessing
3. Preserve current behavior for non-Qwen3 transcribers.
4. Keep existing dictionary post-processing as a second-pass fallback.
5. Avoid changing unrelated transcription UX or non-Qwen3 model flows.

---

## Recommended Approach

### 1. Build a single canonical dictionary context string

Reuse:

- `ASRDictionaryBiasService.dictionaryContext(from:maxCharacters:)`

This remains the canonical conversion layer from raw dictionary entries to a compact context string. It already normalizes entries and applies a size cap, so there is no need to invent a second formatter.

### 2. Thread `dictionaryContext` through Qwen3-specific call paths

Add Qwen3-specific overloads / optional parameters in `Qwen3ASRTranscriber` for:

- `transcribeWithProgress(...)`
- `transcribeChunk(...)`
- `transcribeStreamingChunk(...)`

The parameter should be optional:

```swift
dictionaryContext: String? = nil
```

Inside Qwen3 calls:

- convert `nil` to `""`
- pass the resulting string into the native model call:
  - `generate(..., context: ...)`
  - `generateStream(..., context: ...)`

This keeps the public interface stable for existing callers while allowing Qwen3 paths to opt in.

### 3. Update all Qwen3 call sites

#### A. AICut / file transcription

For direct Qwen3 file transcription in `AICutView`:

- derive `dictionaryContext` from `config.voiceToTextCustomDictionary`
- pass it into `Qwen3ASRTranscriber.transcribeWithProgress(...)`

#### B. SegmentedAlignmentPipeline chunk transcription

For Qwen3 chunk-level transcription inside `runSegmentedAlignmentPipeline(...)`:

- build one `dictionaryContext` string once per transcription job
- pass it through the chunk transcription closure
- each Qwen3 chunk call uses the same context

#### C. Realtime streaming transcription

For `Qwen3StreamingModule`:

- accept dictionary entries or prebuilt context during setup/start
- pass it into `transcribeStreamingChunk(...)`

#### D. VoiceToText history reprocessing

For the re-run path in `VoiceToTextView`:

- build dictionary context from current config
- pass it into the Qwen3 transcriber when reprocessing prior sessions

### 4. Keep post-processing fallback

Do **not** remove:

- `ASRDictionaryBiasService.apply(to:text/segments, ...)`

Instead, use both layers:

1. model-level context injection
2. result-level dictionary correction fallback

This gives the best near-term accuracy without depending entirely on model prompt adherence.

---

## Alternatives Considered

### Option A — Native context + fallback bias (**recommended**)

Use Qwen3's real `context` parameter and keep the existing post-processing correction.

**Pros**

- aligns with the user's requested behavior
- improves model decoding directly
- keeps current correction safety net
- easy to extend if more Qwen3 paths are added

**Cons**

- requires touching several Qwen3 entry points

### Option B — Native context only

Pass dictionary context into the model and remove post-processing bias.

**Pros**

- cleaner pipeline

**Cons**

- loses current correction safety net
- weaker resilience when model output only partially follows the context

### Option C — Post-processing only

Keep current system and just apply it in more places.

**Pros**

- smallest code change

**Cons**

- does not satisfy the requirement to pass dictionary content into recognition itself

---

## Impacted Components

- `Sources/VoiceFlowPro/Services/Qwen3ASRTranscriber.swift`
- `Sources/VoiceFlowPro/Views/AICutView.swift`
- `Sources/VoiceFlowPro/Services/SegmentedAlignmentPipeline.swift` or the closure path feeding it
- `Sources/VoiceFlowPro/Services/Qwen3StreamingModule.swift`
- `Sources/VoiceFlowPro/Views/VoiceToTextView.swift`
- `Sources/VoiceFlowPro/Services/ASRDictionaryBiasService.swift`

Potentially:

- protocol surfaces in `DataTypes.swift` if a reusable context-aware interface is needed

---

## Interface Strategy

Prefer **Qwen3-specific optional parameters** over broad protocol churn.

Reason:

- only Qwen3 currently supports native context
- widening the base `Transcriber` protocol would force unrelated implementations to absorb a parameter they cannot use
- a targeted overload keeps the feature localized and easier to test

If needed, callers can downcast to `Qwen3ASRTranscriber` at Qwen3-specific branches that already exist in the codebase.

---

## Error Handling

- Empty dictionary -> `dictionaryContext == nil` -> pass empty string to model
- Oversized dictionary -> trimmed by `ASRDictionaryBiasService.dictionaryContext(...)`
- Non-Qwen3 transcriber paths -> unchanged
- Missing context support at a specific call site -> no silent fallback there; wire the path explicitly or leave it unchanged until implemented

No new broad catch blocks should be introduced.

---

## Testing Strategy (TDD)

### Qwen3ASRTranscriber tests

1. **file transcription passes dictionary context into Qwen3 generate**
2. **streaming chunk transcription passes dictionary context into Qwen3 generate path**
3. **empty dictionary context falls back to empty string**

### Integration / flow tests

4. **AICut Qwen3 path builds context from AppConfiguration dictionary**
5. **SegmentedAlignmentPipeline Qwen3 chunk path reuses one dictionary context across chunks**
6. **VoiceToText reprocessing path passes dictionary context**

### Bias fallback tests

7. **dictionary post-processing still runs after Qwen3 transcription**

Tests should focus on observable behavior:

- the correct context string is threaded into the Qwen3 path
- outputs still receive fallback biasing
- non-Qwen3 paths remain unchanged

---

## Out of Scope

- changing dictionary UI/UX
- redesigning the dictionary data model
- adding context support to non-Qwen3 engines
- modifying upstream `mlx-audio-swift`

---

## Implementation Notes

- The upstream Qwen3 wrapper in `mlx-audio-swift` currently hardcodes `context: ""` inside its `STTGenerationModel` convenience layer, but the concrete Qwen3 model API already supports `context`. The app should call the native Qwen3 methods directly from `Qwen3ASRTranscriber` rather than waiting for upstream wrapper changes.
- The context string should be built once per job where possible, not once per chunk, to avoid repeated normalization work.
