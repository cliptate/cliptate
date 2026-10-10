# Segmentation + Export Punctuation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add comma-aware sentence splitting, align Whisper/Parakeet offline chunk segmentation with Qwen3 punctuation-driven behavior, and add an export toggle to remove punctuation from SRT/FCPXML/burned-in subtitles (including translations).

**Architecture:** Introduce a shared punctuation-boundary helper used by sentence splitting and offline transcriber chunk flush logic, so all engines follow the same split rule surface. Add a dedicated export text normalizer and wire it only into export-time media construction to keep editing/runtime transcript text unchanged. Persist a new `keepPunctuationOnExport` flag in configuration + preset payload and expose it in Export settings UI with default `true` for backward compatibility.

**Tech Stack:** Swift, SwiftUI, Foundation, AVFoundation, Swift Testing (`Testing`), xcodebuild.

---

### Task 1: Add failing tests for comma split + export punctuation toggle

**Files:**
- Modify: `Sources/VoiceFlowProTests/VoicePinkProTests.swift`

**Step 1: Write the failing tests**

```swift
struct SegmentSplitBySentenceCommaTests {
  @Test
  func splitsOnCommaPunctuation() async throws {
    let words = [
      WordTiming(word: "你好", startTime: 0.0, endTime: 0.3, punctuation: "，"),
      WordTiming(word: "世界", startTime: 0.31, endTime: 0.7, punctuation: "。")
    ]
    let segment = Segment(startTime: 0, endTime: 0.7, text: "你好，世界。", words: words)
    let output = SegmentSplitBySentence.apply(segments: [segment])
    #expect(output.count == 2)
    #expect(output[0].text == "你好，")
    #expect(output[1].text == "世界。")
  }
}

struct ExportPunctuationToggleTests {
  @Test
  func stripsPunctuationFromOriginalAndTranslationWhenDisabled() async throws {
    let media = /* build media with punctuation in segment + translation */
    let normalized = ExportTextNormalizer.normalize(media: media, keepPunctuation: false)
    #expect(!normalized.segments[0].text.contains("，"))
    #expect(!(normalized.translation(for: normalized.segments[0])?.text.contains("，") ?? true))
  }
}
```

**Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoiceFlowPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests
```

Expected: FAIL with missing `ExportTextNormalizer` and comma split assertion failure.

**Step 3: Commit test-only red state**

```bash
git add Sources/VoiceFlowProTests/VoicePinkProTests.swift
git commit -m "test: add red tests for comma split and export punctuation toggle"
```

---

### Task 2: Implement shared punctuation boundary rules + sentence splitting

**Files:**
- Create: `Sources/VoiceFlowPro/Services/SegmentationRules.swift`
- Modify: `Sources/VoiceFlowPro/Services/SegmentSplitBySentence.swift`
- Modify: `Sources/VoiceFlowPro/Services/WordTimingTextComposer.swift`

**Step 1: Write minimal shared rule implementation**

```swift
enum SegmentationRules {
  static let sentenceEnders: CharacterSet = /* existing enders */
  static let commaEnders: CharacterSet = CharacterSet(charactersIn: ",，、")

  static func shouldSplitAfter(word: WordTiming) -> Bool {
    let punctuation = word.punctuation.unicodeScalars
    if punctuation.contains(where: { sentenceEnders.contains($0) || commaEnders.contains($0) }) {
      return true
    }
    return false
  }
}
```

**Step 2: Integrate with sentence splitting**

```swift
if SegmentationRules.shouldSplitAfter(word: w) {
  emitSegment(...)
}
```

**Step 3: Keep `WordTimingTextComposer` in sync**

```swift
static func endsWithSentencePunctuation(_ word: WordTiming) -> Bool {
  SegmentationRules.shouldSplitAfter(word: word)
}
```

**Step 4: Run tests**

Run:
```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoiceFlowPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests
```

Expected: comma split tests PASS; export toggle tests still FAIL.

**Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Services/SegmentationRules.swift Sources/VoiceFlowPro/Services/SegmentSplitBySentence.swift Sources/VoiceFlowPro/Services/WordTimingTextComposer.swift
git commit -m "feat: support comma boundaries in shared sentence split rules"
```

---

### Task 3: Refactor Whisper + Parakeet offline chunk flush logic to shared rules

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/WhisperTranscriber.swift`
- Modify: `Sources/VoiceFlowPro/Services/FluidAudioTranscriptionModule.swift`
- Modify: `Sources/VoiceFlowProTests/VoicePinkProTests.swift`

**Step 1: Add/extend failing tests for shared-rule chunk boundaries**

```swift
@Test
func parakeetChunkBuilderFlushesOnCommaLikeQwen3() async throws {
  // token stream containing comma punctuation should flush into a segment boundary
}

@Test
func whisperPostChunkSegmentsRespectSharedPunctuationRules() async throws {
  // verify post-processing split behavior matches shared rule set
}
```

**Step 2: Replace hard-coded punctuation checks in Parakeet builder**

```swift
// before: local set [".", "?", "!", "。", "？", "！"]
// after:
if SegmentationRules.shouldSplitAfterToken(tokens[i].token) { flush() }
```

**Step 3: Apply same rule surface in Whisper offline segmentation post-process**

```swift
let splitSegments = SegmentationRules.splitSegmentTextByPunctuation(...)
```

**Step 4: Run tests**

Run:
```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoiceFlowPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests
```

Expected: new Whisper/Parakeet rule-consistency tests PASS.

**Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Services/WhisperTranscriber.swift Sources/VoiceFlowPro/Services/FluidAudioTranscriptionModule.swift Sources/VoiceFlowProTests/VoicePinkProTests.swift
git commit -m "refactor: align whisper and parakeet offline chunk splitting with shared punctuation rules"
```

---

### Task 4: Add `keepPunctuationOnExport` config + preset persistence

**Files:**
- Modify: `Sources/VoiceFlowPro/Models/AppConfiguration.swift`
- Modify: `Sources/VoiceFlowPro/Services/ConfigPresetStore.swift`
- Modify: `Sources/VoiceFlowProTests/VoicePinkProTests.swift`

**Step 1: Add failing persistence tests**

```swift
@Test
func keepPunctuationOnExportRoundTripsInPresetPayload() async throws {
  let payload = ConfigPreset.Payload(..., keepPunctuationOnExport: false, ...)
  let decoded = try JSONDecoder().decode(ConfigPreset.Payload.self, from: JSONEncoder().encode(payload))
  #expect(decoded.keepPunctuationOnExport == false)
}
```

**Step 2: Add new config field with default true**

```swift
@Published var keepPunctuationOnExport: Bool
```

Wire it through:
- defaults load/save
- snapshot init/apply
- `defaultExportRequest()` if needed for export-time access

**Step 3: Add preset payload field**

```swift
case keepPunctuationOnExport
var keepPunctuationOnExport: Bool
```

Update initializer, decode fallback default (`true`), encode, payload mapping from/to `AppConfiguration`.

**Step 4: Run tests**

Run:
```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoiceFlowPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests
```

Expected: persistence tests PASS.

**Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Models/AppConfiguration.swift Sources/VoiceFlowPro/Services/ConfigPresetStore.swift Sources/VoiceFlowProTests/VoicePinkProTests.swift
git commit -m "feat: add export keep-punctuation configuration with preset persistence"
```

---

### Task 5: Implement export-time punctuation normalizer and wire to all export paths

**Files:**
- Create: `Sources/VoiceFlowPro/Services/ExportTextNormalizer.swift`
- Modify: `Sources/VoiceFlowPro/Views/AICutView.swift`
- (Optional minimal touch) Modify: `Sources/VoiceFlowPro/Services/SubtitleFileExporter.swift` (only if required for clean API)
- (Optional minimal touch) Modify: `Sources/VoiceFlowPro/Services/FCPXMLExporter.swift` (only if required for clean API)
- Modify: `Sources/VoiceFlowProTests/VoicePinkProTests.swift`

**Step 1: Implement normalizer**

```swift
enum ExportTextNormalizer {
  static func normalize(text: String, keepPunctuation: Bool) -> String { ... }
  static func normalize(media: MediaFile, keepPunctuation: Bool) -> MediaFile { ... }
}
```

Rules:
- `keepPunctuation == true` => return unchanged.
- `false` => strip punctuation but preserve readable spacing (collapse repeated spaces).
- apply to both segment primary text and translation text.

**Step 2: Wire export data flow in AICutView**

At export-preparation boundary (`buildMediaFiles` and any direct burn-in path), apply:

```swift
let normalized = ExportTextNormalizer.normalize(
  media: mediaFile,
  keepPunctuation: config.keepPunctuationOnExport
)
```

Ensure SRT/FCPXML/ASS/video burn-in all consume normalized media.

**Step 3: Add/extend export output tests**

```swift
@Test
func srtFcpxmlAssDropPunctuationWhenToggleOff() async throws {
  // export sample media via SubtitleFileExporter + FCPXMLExporter + ASSGenerator
  // assert punctuation removed in original and translation lines
}
```

**Step 4: Run tests**

Run:
```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoiceFlowPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests
```

Expected: all punctuation-toggle export tests PASS.

**Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Services/ExportTextNormalizer.swift Sources/VoiceFlowPro/Views/AICutView.swift Sources/VoiceFlowProTests/VoicePinkProTests.swift
git commit -m "feat: add export-time punctuation stripping across srt fcpxml and burn-in video"
```

---

### Task 6: Add export UI toggle + final verification

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/ControlPanelConfigurationView.swift`
- Modify: `Sources/VoiceFlowProTests/VoicePinkProTests.swift` (if UI-related config assertions are needed)

**Step 1: Add UI control in Export section**

```swift
Toggle(isOn: $config.keepPunctuationOnExport) {
  Text("Keep Punctuation In Export")
}
```

Copy text:
- On: keep punctuation in exported subtitle/video text
- Off: remove punctuation in exported text

**Step 2: Verify final regression**

Run:
```bash
xcodebuild test -project Sources/VoiceFlowPro.xcodeproj -scheme VoiceFlowPro -destination 'platform=macOS' -only-testing:VoiceFlowProTests
```

Expected: PASS for the full test target.

Then run a focused build:
```bash
xcodebuild -project Sources/VoiceFlowPro.xcodeproj -scheme VoiceFlowPro -destination 'platform=macOS' build
```

Expected: **BUILD SUCCEEDED**.

**Step 3: Final commit**

```bash
git add Sources/VoiceFlowPro/Views/ControlPanelConfigurationView.swift
git commit -m "feat: expose export punctuation toggle in output settings"
```

