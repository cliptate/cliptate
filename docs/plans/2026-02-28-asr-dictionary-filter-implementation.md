# ASR Dictionary Bias + Export Filter Punctuation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Apply Dictionary words to qwen3/whisper/parakeet transcription outputs (AICut + VoiceToText), move/rename punctuation export toggle to Enhance > Filter with default false, and fix Filler Word List multiline editing.

**Architecture:** Keep the existing transcriber protocol unchanged and add a shared dictionary post-processor service that rewrites transcript text with custom dictionary hints (budget-capped to 2000 chars) before persistence/delivery. Keep punctuation behavior export-only by reusing `ExportTextNormalizer` and refactoring only configuration defaults + UI location/label. Solve filler multiline UX by introducing a draft editor state in `ControlPanelConfigurationView` and committing parsed words on blur/module switch.

**Tech Stack:** Swift, SwiftUI, Apple Testing (`import Testing`), Xcodebuild (`VoicePinkPro` scheme).

---

### Task 1: Build dictionary bias service with tests

**Files:**
- Create: `Sources/VoiceFlowPro/Services/ASRDictionaryBiasService.swift`
- Create: `Sources/VoiceFlowProTests/Services/ASRDictionaryBiasServiceTests.swift`
- Modify: `Sources/VoiceFlowProTests/VoicePinkProTests.swift` (register focused regression case list if needed)

**Step 1: Write the failing test**

```swift
import Testing
@testable import VoiceFlowPro

struct ASRDictionaryBiasServiceTests {
  @Test
  func truncatesDictionaryContextTo2000Characters() {
    let entries = (0..<600).map { "term-\($0)" }
    let context = ASRDictionaryBiasService.dictionaryContext(from: entries, maxCharacters: 2000)
    #expect((context?.count ?? 0) <= 2000)
  }

  @Test
  func rewritesTranscriptUsingDictionaryEntriesCaseInsensitively() {
    let biased = ASRDictionaryBiasService.apply(
      to: "today we shipped whisper cut pro",
      dictionaryEntries: ["WhisperCutPro"]
    )
    #expect(biased.contains("WhisperCutPro"))
  }
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/ASRDictionaryBiasServiceTests | cat`
Expected: FAIL with missing `ASRDictionaryBiasService`.

**Step 3: Write minimal implementation**

```swift
enum ASRDictionaryBiasService {
  static func dictionaryContext(from entries: [String], maxCharacters: Int = 2000) -> String? {
    let normalized = AppConfiguration.normalizeDictionaryEntries(entries)
    guard !normalized.isEmpty else { return nil }
    var out = ""
    for entry in normalized {
      let candidate = out.isEmpty ? entry : "\(out)\n\(entry)"
      if candidate.count > maxCharacters { break }
      out = candidate
    }
    return out.isEmpty ? nil : out
  }

  static func apply(to text: String, dictionaryEntries: [String]) -> String {
    // deterministic minimal replacement logic using case-insensitive token matching
    text
  }
}
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/ASRDictionaryBiasServiceTests | cat`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Services/ASRDictionaryBiasService.swift Sources/VoiceFlowProTests/Services/ASRDictionaryBiasServiceTests.swift
git commit -m "feat: add ASR dictionary bias service and tests"
```

### Task 2: Apply dictionary bias in AICut transcription flow

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/AICutView.swift:641-676`
- Modify: `Sources/VoiceFlowPro/Views/AICutView.swift:815-892`
- Test: `Sources/VoiceFlowProTests/Services/ASRDictionaryBiasServiceTests.swift`

**Step 1: Write the failing test**

```swift
@Test
func appliesBiasToSegmentArrayBeforePersisting() {
  let segments = [Segment(startTime: 0, endTime: 1, text: "hello whisper cut pro")]
  let biased = ASRDictionaryBiasService.apply(to: segments, dictionaryEntries: ["WhisperCutPro"])
  #expect(biased.first?.text == "hello WhisperCutPro")
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/ASRDictionaryBiasServiceTests | cat`
Expected: FAIL because segment-array helper is missing.

**Step 3: Write minimal implementation**

```swift
extension ASRDictionaryBiasService {
  static func apply(to segments: [Segment], dictionaryEntries: [String]) -> [Segment] {
    segments.map { segment in
      Segment(
        startTime: segment.startTime,
        endTime: segment.endTime,
        text: apply(to: segment.text, dictionaryEntries: dictionaryEntries),
        words: segment.words,
        confidence: segment.confidence
      )
    }
  }
}
```

Then wire in `AICutView` after transcription result creation and before assigning `videoStates[url]?.segments`.

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/ASRDictionaryBiasServiceTests | cat`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Views/AICutView.swift Sources/VoiceFlowPro/Services/ASRDictionaryBiasService.swift Sources/VoiceFlowProTests/Services/ASRDictionaryBiasServiceTests.swift
git commit -m "feat: apply dictionary bias in AICut transcription results"
```

### Task 3: Apply dictionary bias in VoiceToText streaming + retranscribe

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/VoiceTranscriber.swift:569-612`
- Modify: `Sources/VoiceFlowPro/Services/VoiceTranscriber.swift:770-818`
- Modify: `Sources/VoiceFlowPro/Views/VoiceToTextView.swift:1545-1574`
- Test: `Sources/VoiceFlowProTests/Services/ASRDictionaryBiasServiceTests.swift`

**Step 1: Write the failing test**

```swift
@Test
func biasKeepsEmptyTextAsNoopAndPreservesWhitespaceRules() {
  #expect(ASRDictionaryBiasService.apply(to: "", dictionaryEntries: ["abc"]).isEmpty)
  #expect(
    ASRDictionaryBiasService.apply(to: "  hello world  ", dictionaryEntries: [])
      == "  hello world  "
  )
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/ASRDictionaryBiasServiceTests | cat`
Expected: FAIL (behavior contract not implemented yet).

**Step 3: Write minimal implementation**

Inject dictionary entries from `AppConfiguration.shared.voiceToTextCustomDictionary`:
- in `VoiceTranscriber.handleTranscriptionUpdate(...)` before `liveText`/session write
- in `VoiceToTextView.retranscribe(...)` before `buildTranscriptLines(from:)`

```swift
let biased = ASRDictionaryBiasService.apply(
  to: normalized,
  dictionaryEntries: AppConfiguration.shared.voiceToTextCustomDictionary
)
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/ASRDictionaryBiasServiceTests | cat`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Services/VoiceTranscriber.swift Sources/VoiceFlowPro/Views/VoiceToTextView.swift Sources/VoiceFlowPro/Services/ASRDictionaryBiasService.swift Sources/VoiceFlowProTests/Services/ASRDictionaryBiasServiceTests.swift
git commit -m "feat: apply dictionary bias in voice-to-text pipelines"
```

### Task 4: Rename/move punctuation toggle and force default false for all users

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/ControlPanelConfigurationView.swift:446-505`
- Modify: `Sources/VoiceFlowPro/Views/ControlPanelConfigurationView.swift:738-799`
- Modify: `Sources/VoiceFlowPro/Models/AppConfiguration.swift:535-607`
- Modify: `Sources/VoiceFlowPro/Models/AppConfiguration.swift:756-757`
- Modify: `Sources/VoiceFlowPro/Services/ConfigPresetStore.swift:233-235`
- Modify: `Sources/VoiceFlowPro/Tests/VoicePinkProTests.swift:165-245`

**Step 1: Write the failing test**

```swift
@Test
func keepPunctuationDefaultsToFalseWhenMissingInSnapshotAndPresetPayload() async throws {
  let json = #"{"transcriberType":"whisper","modelVariant":"tiny","language":"english","leftPadMs":100,"rightPadMs":100,"maxCharsPerSegment":50,"filterSilent":true,"fcpxmlProjectName":"Demo","fcpxmlFrameRate":25,"fcpxmlIncludeSubtitles":true,"fcpxmlIsResolveCompatible":false}"#
  let payload = try JSONDecoder().decode(ConfigPreset.Payload.self, from: Data(json.utf8))
  #expect(payload.keepPunctuationOnExport == false)
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/ConfigPresetPayloadEncodingTests | cat`
Expected: FAIL due current default `true`.

**Step 3: Write minimal implementation**

- Keep existing storage key for compatibility, but set default/fallback to `false`.
- Move toggle block from Output > Subtitle Files to Enhance > Filter.
- Rename visible label/help text to **Filter punctuation** and explicitly say “Only applied during export”.

```swift
Text("Filter punctuation")
Text("When enabled, punctuation is removed only during export.")
Toggle("", isOn: $config.keepPunctuationOnExport)
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/ConfigPresetPayloadEncodingTests -only-testing:VoiceFlowProTests/ExportTextNormalizerTests | cat`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Views/ControlPanelConfigurationView.swift Sources/VoiceFlowPro/Models/AppConfiguration.swift Sources/VoiceFlowPro/Services/ConfigPresetStore.swift Sources/VoiceFlowProTests/VoicePinkProTests.swift
git commit -m "feat: move export punctuation toggle to enhance filter and default false"
```

### Task 5: Fix Filler Word List multiline editing (commit on blur/module switch)

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/ControlPanelConfigurationView.swift:446-505`
- Test: `Sources/VoiceFlowProTests/VoicePinkProTests.swift` (regression for parse-on-commit flow helper if extracted)

**Step 1: Write the failing test**

If extracting a tiny helper:

```swift
@Test
func parseFillerWordsFromMultilineDraftOnCommit() {
  let parsed = SegmentEffectConfiguration.parseFillerWords(from: "uh\num\n嗯")
  #expect(parsed == ["uh", "um", "嗯"])
}
```

**Step 2: Run test to verify it fails**

Run: `xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/VoiceFlowProTests | cat`
Expected: FAIL if helper/commit path is not wired.

**Step 3: Write minimal implementation**

- Replace direct `TextEditor` binding with a draft `@State var fillerWordsDraft`.
- Initialize draft on appear / module open.
- Commit with `config.effectFillerWords = SegmentEffectConfiguration.parseFillerWords(from: fillerWordsDraft)` on:
  - editor blur (`@FocusState` change),
  - module switch away from `.filter`.

```swift
@State private var fillerWordsDraft = ""
@FocusState private var isFillerEditorFocused: Bool
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests/VoiceFlowProTests | cat`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Views/ControlPanelConfigurationView.swift Sources/VoiceFlowProTests/VoicePinkProTests.swift
git commit -m "fix: preserve multiline filler word editing until commit"
```

### Task 6: Full verification and documentation sync

**Files:**
- Modify: `docs/plans/2026-02-28-asr-dictionary-filter-design.md` (implementation notes section)
- Modify: `docs/plans/2026-02-28-asr-dictionary-filter-implementation.md` (mark done notes after execution)

**Step 1: Write the failing test**

No new code test; this task verifies integrated behavior.

**Step 2: Run test to verify baseline**

Run: `xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' | cat`
Expected: PASS (or only known unrelated failures).

**Step 3: Write minimal implementation**

Document final behavior deltas and migration behavior in docs.

```markdown
- Filter punctuation is export-only.
- Default false applies to existing users and new users.
- Dictionary bias is applied in AICut and VoiceToText.
```

**Step 4: Run test to verify it passes**

Run: `xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' | cat`
Expected: PASS.

**Step 5: Commit**

```bash
git add docs/plans/2026-02-28-asr-dictionary-filter-design.md docs/plans/2026-02-28-asr-dictionary-filter-implementation.md
git commit -m "docs: finalize dictionary bias and export punctuation behavior notes"
```

---

## Execution Notes

- Follow **@test-driven-development** discipline for each task (red → green → refactor).
- Run **@verification-before-completion** before announcing success.
- If implementing inside this session, use **@subagent-driven-development** for strict per-task isolation/review.
