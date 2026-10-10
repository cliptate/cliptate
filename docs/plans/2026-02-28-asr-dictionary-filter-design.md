# ASR Dictionary Bias + Export Punctuation Filter Design

Date: 2026-02-28
Status: Approved

## Problem

Current behavior has three gaps:

1. Dictionary words are not used in ASR-stage recognition paths for qwen3 / whisper / parakeet flows, so recognition quality for custom terms is weaker.
2. `Keep Punctuation` is located in Output > Subtitle Files and naming does not match desired behavior.
3. `Filler Word List` parses on each keystroke, causing newline input to collapse and making multi-line editing difficult.

## Confirmed Scope

- Dictionary words should be applied for both **AICut** and **Voice To Text** paths.
- Punctuation switch should be renamed to **`Filter punctuation`**, moved to **Enhance > Filter**, and be **export-only** behavior.
- Default should be **false for all users** (including existing users).
- Filler word editing should allow free newline editing, and parse/save on **blur or module switch**.
- Dictionary context budget: truncate to **2000 characters**.

## Chosen Approach (Option 1)

Use a minimal, non-invasive path:

- Do **not** change `Transcriber` protocol signatures.
- Add a shared dictionary text-bias post-processor for transcript text normalization/correction.
- Apply this post-processor in both AICut and Voice To Text pipelines where transcript text is finalized/updated.
- Keep ASR engines untouched to minimize risk and surface area.

## Architecture & Components

1. **ASRDictionaryBiasService** (new service/helper)
   - Input: transcript text + dictionary entries.
   - Output: corrected text.
   - Rules:
     - Build dictionary context from `voiceToTextCustomDictionary`.
     - Enforce 2000-char budget.
     - Perform deterministic normalization/correction (case-insensitive matching behavior aligned with existing dictionary normalization).

2. **AICut integration**
   - After transcription result generation and before state persistence, apply dictionary bias to segment text.
   - Keep existing timing/segment structures unchanged.

3. **VoiceToText integration**
   - Apply dictionary bias before live/final text is written to session output paths.
   - Preserve existing session lifecycle and delivery mechanics.

4. **Export punctuation switch refactor**
   - Rename config semantics from `keepPunctuationOnExport` to `filterPunctuationOnExport` (or equivalent migration-safe mapping).
   - Move toggle UI from Output > Subtitle Files to Enhance > Filter.
   - Behavior remains export-only through export normalization path.
   - Default false is enforced globally (new and existing users).

5. **Filler Word List editing model**
   - Replace direct parse-on-type binding with draft text state.
   - Commit parse to `effectFillerWords` only on blur/module switch.
   - Preserve existing parse rules and normalization.

## Data Flow

1. User edits Dictionary entries.
2. Dictionary entries normalize and cap into bias context budget.
3. Transcription text is produced (AICut or VoiceToText).
4. Dictionary bias post-processor transforms text.
5. Transformed text flows into existing segment/session persistence.

For punctuation:

1. User toggles `Filter punctuation` in Enhance > Filter.
2. During export only, text normalization strips punctuation when enabled.
3. No effect on live transcript, timeline, AI Enhance keyword extraction, or editor display text.

## Error Handling

- Empty dictionary => no-op.
- Bias processing failures should not block transcription pipeline; fallback to original text output.
- Keep existing export error behavior unchanged; punctuation filtering remains within current export normalization layer.

## Testing Plan

1. Config/UI tests:
   - Toggle renamed and relocated.
   - Default false for all users.
   - Export-only behavior validation.

2. Filler editor tests:
   - Multi-line input is preserved while editing.
   - Parse/save occurs on blur or module switch.

3. Dictionary bias tests:
   - AICut path applies bias before final state write.
   - VoiceToText path applies bias before session/live output.
   - 2000-char truncation behavior is deterministic.

## Non-Goals

- No changes to ASR SDK internals or transcriber protocol interface.
- No changes to alignment strategy or subtitle timing logic.
