# Menu Bar Icon and Dictation Endpointing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Increase the menu bar icon to 22pt and make streaming dictation wait for stable silence before flushing speech so interim text is more accurate and less jittery.

**Architecture:** Keep the existing `MenuBarExtra` and streaming dictation pipeline intact. Extract a tiny menu bar icon renderer so the icon sizing change is testable, then evolve `StreamingSpeechAccumulator` from immediate-on-silence flush to a configurable consecutive-silence endpointing model that is wired through `StreamingAudioCaptureModule` and selected by `VoiceTranscriber`.

**Tech Stack:** Swift 6.2, SwiftUI/AppKit, Swift Testing, existing streaming VAD/ASR pipeline, `./scripts/swift-safe.sh test`

---

## File map

### Existing files to modify

- `Package.swift` — register the new menu bar renderer test file in the explicit `CliptateTests` source list.
- `Sources/Cliptate/Cliptate.swift` — swap the inline 18pt menu bar image drawing for the shared 22pt renderer.
- `Sources/Cliptate/Services/StreamingSpeechAccumulator.swift` — add consecutive-silence tracking and threshold-based flush behavior.
- `Sources/Cliptate/Services/StreamingAudioCaptureModule.swift` — carry the endpointing threshold in configuration, initialize the accumulator with it, and expose a debug accessor for tests.
- `Sources/Cliptate/Services/VoiceTranscriber.swift` — choose the accuracy-first threshold for live dictation and expose a debug accessor for tests.
- `Sources/CliptateTests/Services/Qwen3StreamingSpeechAccumulatorTests.swift` — add accumulator regressions for delayed flush and silence reset.
- `Sources/CliptateTests/Services/StreamingAudioCaptureModuleTests.swift` — assert the configured endpointing threshold is wired into the module.
- `Sources/CliptateTests/Services/VoiceTranscriberStopReasonTests.swift` — assert live dictation uses the accuracy-first silent-chunk threshold.

### New files to create

- `Sources/Cliptate/Utilities/MenuBarIconRenderer.swift` — focused helper that renders a 22pt non-template menu bar icon from the app icon asset.
- `Sources/CliptateTests/Utilities/MenuBarIconRendererTests.swift` — focused regression tests for renderer output size and template behavior.

### Existing files to read during implementation

- `Sources/Cliptate/Cliptate.swift`
- `Sources/Cliptate/Services/StreamingSpeechAccumulator.swift`
- `Sources/Cliptate/Services/StreamingAudioCaptureModule.swift`
- `Sources/Cliptate/Services/VoiceTranscriber.swift`
- `Sources/CliptateTests/Services/Qwen3StreamingSpeechAccumulatorTests.swift`
- `Sources/CliptateTests/Services/StreamingAudioCaptureModuleTests.swift`
- `Sources/CliptateTests/Services/VoiceTranscriberStopReasonTests.swift`

---

### Task 1: Extract a testable 22pt menu bar icon renderer

**Files:**
- Create: `Sources/Cliptate/Utilities/MenuBarIconRenderer.swift`
- Create: `Sources/CliptateTests/Utilities/MenuBarIconRendererTests.swift`
- Modify: `Package.swift`
- Modify: `Sources/Cliptate/Cliptate.swift`
- Test: `Sources/CliptateTests/Utilities/MenuBarIconRendererTests.swift`

- [ ] **Step 1: Write the failing menu bar icon renderer test**

```swift
import AppKit
import Testing

@testable import Cliptate

@Suite("MenuBarIconRenderer")
struct MenuBarIconRendererTests {
  @Test("renders a 22pt non-template menu bar icon")
  func renders22PointMenuBarIcon() {
    let source = NSImage(size: NSSize(width: 128, height: 128))

    let rendered = MenuBarIconRenderer.makeImage(from: source)

    #expect(rendered.size == NSSize(width: 22, height: 22))
    #expect(rendered.isTemplate == false)
  }
}
```

- [ ] **Step 2: Register the new test file in `Package.swift`**

```swift
"Utilities/MenuBarIconRendererTests.swift",
```

- [ ] **Step 3: Run the focused test to verify RED**

Run:

```bash
./scripts/swift-safe.sh test --filter MenuBarIconRendererTests
```

Expected: FAIL with unresolved symbol errors because `MenuBarIconRenderer` does not exist yet.

- [ ] **Step 4: Add the minimal renderer helper**

```swift
import AppKit

enum MenuBarIconRenderer {
  static let targetSize = NSSize(width: 22, height: 22)

  static func makeImage(from appIcon: NSImage) -> NSImage {
    let image = NSImage(size: targetSize)
    image.lockFocus()
    appIcon.draw(in: NSRect(origin: .zero, size: targetSize))
    image.unlockFocus()
    image.isTemplate = false
    return image
  }
}
```

- [ ] **Step 5: Use the shared renderer in `Cliptate.swift`**

```swift
if let appIcon = NSImage(named: "AppIcon") {
  Image(nsImage: MenuBarIconRenderer.makeImage(from: appIcon))
} else {
  Image(systemName: "mic.fill")
}
```

- [ ] **Step 6: Re-run the focused test to verify GREEN**

Run:

```bash
./scripts/swift-safe.sh test --filter MenuBarIconRendererTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Package.swift \
  Sources/Cliptate/Cliptate.swift \
  Sources/Cliptate/Utilities/MenuBarIconRenderer.swift \
  Sources/CliptateTests/Utilities/MenuBarIconRendererTests.swift
git commit -m "feat: enlarge menu bar icon" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 2: Add TDD coverage for delayed endpointing in `StreamingSpeechAccumulator`

**Files:**
- Modify: `Sources/Cliptate/Services/StreamingSpeechAccumulator.swift`
- Modify: `Sources/CliptateTests/Services/Qwen3StreamingSpeechAccumulatorTests.swift`
- Test: `Sources/CliptateTests/Services/Qwen3StreamingSpeechAccumulatorTests.swift`

- [ ] **Step 1: Extend the accumulator tests with the new accuracy-first endpointing expectations**

```swift
@Test("requires three silent chunks before flushing buffered speech")
func requiresThreeSilentChunksBeforeFlush() {
  var accumulator = StreamingSpeechAccumulator(
    maxBufferedSamples: 12,
    requiredConsecutiveSilentChunks: 3
  )

  _ = accumulator.ingest(
    chunk: [0, 1, 2, 3],
    speechSampleRanges: [0..<4]
  )

  #expect(accumulator.ingest(chunk: [4, 5], speechSampleRanges: []) == nil)
  #expect(accumulator.ingest(chunk: [6, 7], speechSampleRanges: []) == nil)
  #expect(accumulator.ingest(chunk: [8, 9], speechSampleRanges: []) == [0, 1, 2, 3])
}

@Test("speech after a short pause resets the silent chunk counter")
func speechAfterShortPauseResetsSilentCounter() {
  var accumulator = StreamingSpeechAccumulator(
    maxBufferedSamples: 20,
    requiredConsecutiveSilentChunks: 3
  )

  _ = accumulator.ingest(chunk: [0, 1], speechSampleRanges: [0..<2])
  #expect(accumulator.ingest(chunk: [2, 3], speechSampleRanges: []) == nil)

  _ = accumulator.ingest(chunk: [4, 5], speechSampleRanges: [0..<2])
  #expect(accumulator.ingest(chunk: [6, 7], speechSampleRanges: []) == nil)
  #expect(accumulator.ingest(chunk: [8, 9], speechSampleRanges: []) == nil)
  #expect(accumulator.ingest(chunk: [10, 11], speechSampleRanges: []) == [0, 1, 4, 5])
}
```

- [ ] **Step 2: Run the focused accumulator tests to verify RED**

Run:

```bash
./scripts/swift-safe.sh test --filter Qwen3StreamingSpeechAccumulatorTests
```

Expected: FAIL because `StreamingSpeechAccumulator` does not yet accept `requiredConsecutiveSilentChunks`, and silent chunks still flush immediately.

- [ ] **Step 3: Implement the minimal silence-aware accumulator**

```swift
struct StreamingSpeechAccumulator: Sendable {
  private(set) var pendingSpeech: [Float] = []
  private let maxBufferedSamples: Int
  private let requiredConsecutiveSilentChunks: Int
  private var consecutiveSilentChunks: Int = 0

  init(maxBufferedSamples: Int, requiredConsecutiveSilentChunks: Int = 1) {
    self.maxBufferedSamples = max(1, maxBufferedSamples)
    self.requiredConsecutiveSilentChunks = max(1, requiredConsecutiveSilentChunks)
  }

  mutating func ingest(
    chunk: [Float],
    speechSampleRanges: [Range<Int>]
  ) -> [Float]? {
    guard !chunk.isEmpty else { return nil }

    if speechSampleRanges.isEmpty {
      guard !pendingSpeech.isEmpty else { return nil }
      consecutiveSilentChunks += 1
      guard consecutiveSilentChunks >= requiredConsecutiveSilentChunks else { return nil }
      return flush()
    }

    consecutiveSilentChunks = 0

    for range in speechSampleRanges {
      guard !range.isEmpty else { continue }
      let lowerBound = max(0, min(range.lowerBound, chunk.count))
      let upperBound = max(lowerBound, min(range.upperBound, chunk.count))
      guard lowerBound < upperBound else { continue }
      pendingSpeech.append(contentsOf: chunk[lowerBound..<upperBound])
    }

    guard pendingSpeech.count >= maxBufferedSamples else { return nil }
    let emission = Array(pendingSpeech.prefix(maxBufferedSamples))
    pendingSpeech.removeAll(keepingCapacity: true)
    consecutiveSilentChunks = 0
    return emission
  }

  mutating func flush() -> [Float]? {
    guard !pendingSpeech.isEmpty else { return nil }
    let emission = pendingSpeech
    pendingSpeech.removeAll(keepingCapacity: true)
    consecutiveSilentChunks = 0
    return emission
  }
}
```

- [ ] **Step 4: Re-run the focused accumulator tests to verify GREEN**

Run:

```bash
./scripts/swift-safe.sh test --filter Qwen3StreamingSpeechAccumulatorTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add \
  Sources/Cliptate/Services/StreamingSpeechAccumulator.swift \
  Sources/CliptateTests/Services/Qwen3StreamingSpeechAccumulatorTests.swift
git commit -m "feat: delay dictation flush until stable silence" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 3: Wire the accuracy-first threshold through the streaming stack

**Files:**
- Modify: `Sources/Cliptate/Services/StreamingAudioCaptureModule.swift`
- Modify: `Sources/Cliptate/Services/VoiceTranscriber.swift`
- Modify: `Sources/CliptateTests/Services/StreamingAudioCaptureModuleTests.swift`
- Modify: `Sources/CliptateTests/Services/VoiceTranscriberStopReasonTests.swift`
- Test: `Sources/CliptateTests/Services/StreamingAudioCaptureModuleTests.swift`
- Test: `Sources/CliptateTests/Services/VoiceTranscriberStopReasonTests.swift`

- [ ] **Step 1: Add failing configuration assertions for the module and transcriber**

```swift
@Test("Configured silent chunk threshold is exposed for streaming endpointing")
func configuredSilentChunkThresholdIsExposed() {
  let module = makeModule(requiredConsecutiveSilentChunks: 3)

  #expect(module.testRequiredConsecutiveSilentChunks == 3)
}
```

```swift
@Test("VoiceTranscriber uses accuracy-first endpointing for live dictation")
func voiceTranscriberUsesAccuracyFirstEndpointing() {
  let transcriber = VoiceTranscriber.shared

  #expect(transcriber.testStreamingChunkDuration == 0.5)
  #expect(transcriber.testStreamingSpeechWindowDuration > 0)
  #expect(transcriber.testStreamingRequiredSilentChunks == 3)
}
```

- [ ] **Step 2: Run the focused configuration tests to verify RED**

Run:

```bash
./scripts/swift-safe.sh test --filter StreamingAudioCaptureModuleAsyncTests
./scripts/swift-safe.sh test --filter VoiceTranscriberStopReasonTests
```

Expected: FAIL because `requiredConsecutiveSilentChunks` and the related debug accessors do not exist yet.

- [ ] **Step 3: Add the minimal streaming configuration support**

```swift
struct Configuration {
  let chunkDuration: Double
  let maxSpeechWindowDuration: Double
  let requiredConsecutiveSilentChunks: Int
  let levelCalculator: ([Float]) -> CGFloat

  init(
    chunkDuration: Double,
    maxSpeechWindowDuration: Double = 2.0,
    requiredConsecutiveSilentChunks: Int = 1,
    levelCalculator: @escaping ([Float]) -> CGFloat
  ) {
    self.chunkDuration = chunkDuration
    self.maxSpeechWindowDuration = maxSpeechWindowDuration
    self.requiredConsecutiveSilentChunks = max(1, requiredConsecutiveSilentChunks)
    self.levelCalculator = levelCalculator
  }
}
```

```swift
self.speechAccumulator = StreamingSpeechAccumulator(
  maxBufferedSamples: Self.maxSpeechWindowSamples(for: configuration),
  requiredConsecutiveSilentChunks: configuration.requiredConsecutiveSilentChunks
)
```

```swift
var testRequiredConsecutiveSilentChunks: Int {
  configuration.requiredConsecutiveSilentChunks
}
```

- [ ] **Step 4: Select the accuracy-first threshold in `VoiceTranscriber`**

```swift
let configuration = StreamingAudioCaptureModule.Configuration(
  chunkDuration: 0.5,
  maxSpeechWindowDuration: 2.5,
  requiredConsecutiveSilentChunks: 3,
  levelCalculator: micRMSLevel
)
```

```swift
var testStreamingRequiredSilentChunks: Int {
  streamingModule.testRequiredConsecutiveSilentChunks
}
```

- [ ] **Step 5: Re-run the focused configuration tests to verify GREEN**

Run:

```bash
./scripts/swift-safe.sh test --filter StreamingAudioCaptureModuleAsyncTests
./scripts/swift-safe.sh test --filter VoiceTranscriberStopReasonTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add \
  Sources/Cliptate/Services/StreamingAudioCaptureModule.swift \
  Sources/Cliptate/Services/VoiceTranscriber.swift \
  Sources/CliptateTests/Services/StreamingAudioCaptureModuleTests.swift \
  Sources/CliptateTests/Services/VoiceTranscriberStopReasonTests.swift
git commit -m "feat: wire accuracy-first dictation endpointing" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 4: Run end-to-end regression coverage for the narrow change set

**Files:**
- Modify: none
- Test: `Sources/CliptateTests/Utilities/MenuBarIconRendererTests.swift`
- Test: `Sources/CliptateTests/Services/Qwen3StreamingSpeechAccumulatorTests.swift`
- Test: `Sources/CliptateTests/Services/StreamingAudioCaptureModuleTests.swift`
- Test: `Sources/CliptateTests/Services/VoiceTranscriberStopReasonTests.swift`

- [ ] **Step 1: Run the focused menu bar regression**

Run:

```bash
./scripts/swift-safe.sh test --filter MenuBarIconRendererTests
```

Expected: PASS.

- [ ] **Step 2: Run the focused endpointing regressions**

Run:

```bash
./scripts/swift-safe.sh test --filter Qwen3StreamingSpeechAccumulatorTests
./scripts/swift-safe.sh test --filter StreamingAudioCaptureModuleAsyncTests
./scripts/swift-safe.sh test --filter VoiceTranscriberStopReasonTests
```

Expected: PASS.

- [ ] **Step 3: Run the full package test suite**

Run:

```bash
./scripts/swift-safe.sh test
```

Expected: PASS.

- [ ] **Step 4: Commit the green validation checkpoint if any follow-up edits were needed**

```bash
git status --short
```

Expected: no unexpected modified files remain. If a follow-up fix was required during validation, commit it with:

```bash
git add -A
git commit -m "test: lock down menu bar icon and dictation endpointing regressions" \
  -m "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
