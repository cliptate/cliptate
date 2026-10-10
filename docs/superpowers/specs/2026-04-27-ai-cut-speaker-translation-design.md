# Ai Cut Speaker Visibility and Translation Availability Design

**Date:** 2026-04-27  
**Status:** Approved

---

## Problem

Two user-facing issues are currently converging in Ai Cut:

1. **Sortformer-backed speaker data is not visible in the editor** even though the segments panel already knows how to render per-segment speaker badges from `Segment.speakerId`.
2. **Batch translation appears unresponsive** on systems that should support Apple Translation, making it unclear whether the problem is platform support, a missing model, an unsupported language pair, or a silent UI failure.

The investigation shows that the UI layer already contains the intended speaker badge presentation, while translation availability is gated by inconsistent platform checks. The remaining work is to make the active data path and status reporting match the intended product behavior.

---

## Goals

- Show `S1`, `S2`, ... speaker badges before each Ai Cut segment whenever `speakerId` is present.
- Preserve or recover speaker annotation through the actual Ai Cut transcription path instead of adding a UI-only workaround.
- Make the translation button and execution path use one consistent availability rule.
- Surface translation failures and missing diarization prerequisites explicitly in the status area.
- Keep the implementation aligned with TDD during the implementation phase.

## Non-Goals

- Redesigning the segments panel layout beyond the existing per-row badge.
- Introducing a new speaker clustering or diarization algorithm.
- Adding a separate downloadable translation model managed by `ModelDownloadManager`.
- Changing export formats or subtitle placement behavior.

---

## Design

### 1. Speaker presentation remains a thin view over `Segment.speakerId`

`SegmentsPanelView` already contains the correct product behavior for speaker display:

- show a speaker badge only when a segment has `speakerId`
- render the badge inline before the editable transcript text
- use the existing `speakerBadgeText` / `speakerBadgeColor` helpers

No new view model or alternate speaker presentation layer is needed. The fix should preserve the current UI contract and focus on the upstream data path that populates `processedSegments`.

### 2. Ai Cut must prefer the diarization-capable transcription path when prerequisites exist

The intended speaker-preserving batch path is:

1. Sortformer VAD produces `AudioTimeRange` values with `speakerId`
2. `BatchTranscriptionPipeline` passes those ranges into `SegmentedAlignmentPipeline`
3. `SegmentedAlignmentPipeline` emits final `Segment` values with `speakerId: chunk.speakerId`
4. `AICutView.paddedSegments(for:)` and downstream segment processing preserve `speakerId`
5. `SegmentsPanelView` renders the badge

This path already supports diarization. The risk is that Ai Cut sometimes falls back to a direct ASR path, especially when the aligner is unavailable, and the fallback branch does not guarantee speaker propagation. The implementation should therefore:

- keep using the VAD -> ASR -> ForcedAlign branch whenever the aligner prerequisite is satisfied
- avoid silently pretending diarization is available when Ai Cut has fallen back to a branch that does not emit `speakerId`
- surface a clear status message when the active branch cannot provide speaker labels because its prerequisites are missing

The implementation may either restore speaker propagation in the fallback branch or keep the fallback behavior unchanged and explicitly report that speaker labels are unavailable without the diarization-capable path. The recommended behavior is to preserve speaker output whenever technically available and otherwise explain why it is missing.

### 3. Translation availability must be centralized and use the real platform requirement

`AppleTranslator` is declared with `@available(macOS 15.0, *)`, but the current UI and execution path use `#available(macOS 26.0, *)`, which incorrectly disables or blocks translation on supported systems.

The implementation should introduce one shared availability decision for batch translation and use it in all of these places:

- segments panel header button enabled/disabled state
- translation button tooltip/help text
- `AICutView.translateActiveSegments()`
- any translation-specific status messaging

The shared decision should answer:

- whether the current OS can use Apple Translation at all
- whether translation should be shown as available in the current UI

This removes the current split-brain behavior where the service, button state, and click handler disagree.

### 4. Translation errors should explain the failure mode instead of looking idle

Apple Translation in this feature does **not** depend on repository-managed ASR, align, VAD, or TTS artifacts. A missing local model download is therefore not the primary diagnosis for the current translation issue.

The execution flow should make these cases visible:

- **platform unsupported** -> tell the user the OS version requirement
- **unsupported language pair** -> report the source and target language mismatch
- **empty or unavailable segments** -> report that there is nothing to translate
- **runtime translation failure** -> surface the underlying error

The status panel should transition immediately into an in-progress message when translation starts so the user gets confirmation that the button press was handled.

### 5. Missing speaker labels should produce explicit status feedback when caused by prerequisites

If Ai Cut completes transcription without any `speakerId`, and the active branch is known to have skipped the diarization-capable path because an aligner or related prerequisite was unavailable, the user should see an explicit explanation in the status text.

The message should distinguish between:

- transcription succeeded but the active path does not produce speaker labels
- speaker-capable processing is unavailable because a required model is not ready

This is intentionally diagnostic, not a silent fallback. The user should be able to tell whether the absence of badges reflects missing diarization data rather than a rendering bug.

---

## Data Flow Impact

### Speaker flow

1. Ai Cut chooses a transcription branch
2. If the diarization-capable branch is available, Sortformer VAD emits speaker-tagged ranges
3. Aligned segments inherit `speakerId`
4. Segment processing preserves `speakerId`
5. The editor renders `S1`, `S2`, ... before each segment row

### Translation flow

1. The segments panel evaluates a shared translation-availability rule
2. If available, the user can trigger batch translation
3. Ai Cut immediately shows translation progress in the status panel
4. `AppleTranslator` returns per-segment translations or an explicit error
5. The editor updates translations or shows a precise failure message

---

## Error Handling

- Do not silently treat unsupported translation as a no-op.
- Do not imply that Apple Translation depends on `ModelDownloadManager`.
- Preserve existing explicit error propagation from `AppleTranslator`.
- Keep speaker rendering behavior unchanged for segments whose `speakerId` is genuinely `nil`.
- When Ai Cut falls back away from a speaker-capable branch, report that condition instead of masking it.

---

## Testing Strategy

Implementation should follow TDD:

1. Write failing focused tests for availability and speaker-path behavior.
2. Make the minimal code changes required to satisfy them.
3. Refactor only after behavior is covered.

The implementation coverage should include:

### Translation tests

- translation availability reflects the real supported macOS version
- the segments header control state uses the centralized availability decision
- unsupported systems return the expected explicit error instead of appearing idle

### Ai Cut speaker / status tests

- when the diarization-capable path is used, resulting segments retain `speakerId`
- when Ai Cut cannot use the speaker-capable path, status text explains why speaker badges are absent
- segment processing after transcription does not strip `speakerId` from already-annotated segments

Heavy UI automation is unnecessary. The critical correctness points are:

- the chosen transcription path produces or clearly explains speaker output
- the translation action becomes obviously available or unavailable for the right reason

---

## Implementation Notes

- Prefer surgical changes in Ai Cut branch selection and translation availability checks over broad architecture refactors.
- Reuse the existing speaker badge UI instead of introducing another presentation layer.
- Keep user-visible status messages localized.
- Preserve the current translation storage model in `VideoState.segmentTranslations`.
