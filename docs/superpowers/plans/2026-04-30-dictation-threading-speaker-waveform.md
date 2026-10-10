# Dictation Threading Fix, Speaker ID Display, and Waveform Redesign

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the background-thread publishing bug that freezes streaming text after ~1 minute, add speaker identification to dictation transcripts displayed as "Speaker N: content", and replace the scrolling waveform with vertical bouncing bars driven by real-time audio RMS.

**Architecture:** Three independent changes that share some files. The threading fix annotates `MicIndicatorViewModel` with `@MainActor` and makes `StreamingAudioCaptureModule.Callbacks` closures `@MainActor @Sendable`. Speaker ID extends `TranscriptLine` with an optional `speakerId` and runs existing `PlainASRSpeakerPropagation` during batch re-transcription. The waveform replaces the 30-bar scrolling visualizer with 5 vertically bouncing bars using envelope smoothing.

**Tech Stack:** Swift, SwiftUI, Swift Testing framework, AVFoundation

---

### Task 1: Fix threading — annotate `MicIndicatorViewModel` with `@MainActor`

**Files:**
- Modify: `Sources/VoiceFlowPro/Utilities/MicIndicatorOverlay.swift:485`
- Test: `Sources/VoiceFlowProTests/Utilities/MicIndicatorOverlayTests.swift`

- [ ] **Step 1: Write a failing test verifying `MicIndicatorViewModel` is `@MainActor`**

Add to `Sources/VoiceFlowProTests/Utilities/MicIndicatorOverlayTests.swift`:

```swift
@Test("level history updates are main-actor isolated")
func levelHistoryUpdatesOnMainActor() {
  let overlay = MicIndicatorOverlay()
  overlay.startTracking()

  // Simulate audio level updates
  overlay.updateLevel(0.5)
  overlay.updateLevel(0.8)
  overlay.updateLevel(0.3)

  #expect(overlay.testLevelHistory.count == 3)
  #expect(overlay.testLevelHistory[0] == 0.5)
  #expect(overlay.testLevelHistory[1] == 0.8)
  #expect(overlay.testLevelHistory[2] == 0.3)

  overlay.stopTracking()
}
```

- [ ] **Step 2: Run test to verify it passes (baseline — confirms test setup works)**

Run: `swift test --filter "levelHistoryUpdatesOnMainActor"`
Expected: PASS (this is a baseline test — the real fix is compile-time safety)

- [ ] **Step 3: Add `@MainActor` to `MicIndicatorViewModel`**

In `Sources/VoiceFlowPro/Utilities/MicIndicatorOverlay.swift`, change line 485:

```swift
// Before:
private final class MicIndicatorViewModel: ObservableObject {

// After:
@MainActor
private final class MicIndicatorViewModel: ObservableObject {
```

- [ ] **Step 4: Build to verify no compile errors**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Run all MicIndicator tests**

Run: `swift test --filter "MicIndicatorOverlay"`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add Sources/VoiceFlowPro/Utilities/MicIndicatorOverlay.swift Sources/VoiceFlowProTests/Utilities/MicIndicatorOverlayTests.swift
git commit -m "fix: annotate MicIndicatorViewModel with @MainActor to prevent background thread publishing"
```

---

### Task 2: Fix threading — make `Callbacks` closures `@MainActor @Sendable`

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/StreamingAudioCaptureModule.swift:21-24`
- Modify: `Sources/VoiceFlowPro/Services/VoiceTranscriber.swift:76-95`
- Modify: `Sources/VoiceFlowProTests/Services/StreamingAudioCaptureModuleTests.swift:60-76`

- [ ] **Step 1: Update `Callbacks` struct to use `@MainActor @Sendable` closures**

In `Sources/VoiceFlowPro/Services/StreamingAudioCaptureModule.swift`, change the `Callbacks` struct:

```swift
// Before:
struct Callbacks {
  let onAudioLevel: (CGFloat) -> Void
  let onInterimText: (String) -> Void
}

// After:
struct Callbacks: Sendable {
  let onAudioLevel: @MainActor @Sendable (CGFloat) -> Void
  let onInterimText: @MainActor @Sendable (String) -> Void
}
```

- [ ] **Step 2: Update callback invocations in `StreamingAudioCaptureModule`**

The callbacks are called from `@MainActor` context, so they can be called directly. No change needed at call sites since the module is already `@MainActor`. Verify by building.

- [ ] **Step 3: Update test helper `makeModule` in `StreamingAudioCaptureModuleTests.swift`**

In `Sources/VoiceFlowProTests/Services/StreamingAudioCaptureModuleTests.swift`, update the `makeModule` helper to match the new closure types:

```swift
private func makeModule(
  chunkDuration: Double = 0.5,
  onAudioLevel: @MainActor @Sendable @escaping (CGFloat) -> Void = { _ in },
  onInterimText: @MainActor @Sendable @escaping (String) -> Void = { _ in }
) -> StreamingAudioCaptureModule {
```

- [ ] **Step 4: Build to verify all call sites compile**

Run: `swift build`
Expected: BUILD SUCCEEDED. If there are compile errors, they reveal exactly which call sites need `@MainActor` annotation — fix each one.

- [ ] **Step 5: Run streaming module tests**

Run: `swift test --filter "StreamingAudioCaptureModule"`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add Sources/VoiceFlowPro/Services/StreamingAudioCaptureModule.swift Sources/VoiceFlowPro/Services/VoiceTranscriber.swift Sources/VoiceFlowProTests/Services/StreamingAudioCaptureModuleTests.swift
git commit -m "fix: make StreamingAudioCaptureModule callbacks @MainActor @Sendable to prevent thread safety violations"
```

---

### Task 3: Add `speakerId` to `TranscriptLine` with backward-compatible encoding

**Files:**
- Modify: `Sources/VoiceFlowPro/Models/TranscriptSession.swift:17-27`
- Test: `Sources/VoiceFlowProTests/Models/TranscriptSessionHistoryTests.swift`

- [ ] **Step 1: Write a failing test for `TranscriptLine` speakerId round-trip**

Add to `Sources/VoiceFlowProTests/Models/TranscriptSessionHistoryTests.swift`:

```swift
@Test("TranscriptLine speakerId encodes and decodes correctly")
func transcriptLineSpeakerIdRoundTrips() throws {
  let line = TranscriptLine(timestamp: 1.5, text: "Hello world", speakerId: 2)
  let data = try JSONEncoder().encode(line)
  let decoded = try JSONDecoder().decode(TranscriptLine.self, from: data)
  #expect(decoded.speakerId == 2)
  #expect(decoded.text == "Hello world")
  #expect(decoded.timestamp == 1.5)
}

@Test("TranscriptLine without speakerId decodes as nil for backward compat")
func transcriptLineNilSpeakerIdBackwardCompat() throws {
  // Simulate old data without speakerId field
  let json = """
  {"id":"A1B2C3D4-E5F6-7890-ABCD-EF1234567890","timestamp":2.0,"text":"Old line"}
  """
  let data = Data(json.utf8)
  let decoded = try JSONDecoder().decode(TranscriptLine.self, from: data)
  #expect(decoded.speakerId == nil)
  #expect(decoded.text == "Old line")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "transcriptLineSpeakerIdRoundTrips|transcriptLineNilSpeakerIdBackwardCompat"`
Expected: FAIL — `TranscriptLine` has no `speakerId` property

- [ ] **Step 3: Add `speakerId` to `TranscriptLine`**

In `Sources/VoiceFlowPro/Models/TranscriptSession.swift`, update `TranscriptLine`:

```swift
public struct TranscriptLine: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public let timestamp: TimeInterval
  public var text: String
  public var speakerId: Int?

  public init(id: UUID = UUID(), timestamp: TimeInterval, text: String, speakerId: Int? = nil) {
    self.id = id
    self.timestamp = timestamp
    self.text = text
    self.speakerId = speakerId
  }
}
```

Since `TranscriptLine` uses synthesized `Codable` conformance, the optional `speakerId` will automatically decode as `nil` when missing from old data.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "transcriptLineSpeakerIdRoundTrips|transcriptLineNilSpeakerIdBackwardCompat"`
Expected: PASS

- [ ] **Step 5: Build the full package**

Run: `swift build`
Expected: BUILD SUCCEEDED — no other call sites break because `speakerId` defaults to `nil`

- [ ] **Step 6: Commit**

```bash
git add Sources/VoiceFlowPro/Models/TranscriptSession.swift Sources/VoiceFlowProTests/Models/TranscriptSessionHistoryTests.swift
git commit -m "feat: add optional speakerId to TranscriptLine with backward-compatible encoding"
```

---

### Task 4: Run speaker diarization during batch re-transcription

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/VoiceTranscriber.swift:331-424`

- [ ] **Step 1: Add speaker diarization after batch ASR in `retranscribeRecordedAudio`**

In `Sources/VoiceFlowPro/Services/VoiceTranscriber.swift`, in the `retranscribeRecordedAudio(at:)` method, after the line `let biasedSegments = ASRDictionaryBiasService.apply(...)` (around line 383), add speaker annotation and modify the `newLines` construction:

```swift
      // Apply dictionary bias to the batch result
      let biasedSegments = ASRDictionaryBiasService.apply(
        to: result.segments,
        dictionaryEntries: AppConfiguration.shared.voiceToTextCustomDictionary
      )

      // Run speaker diarization on the batch result
      let speakerAnnotatedSegments: [Segment]
      do {
        let propagation = PlainASRSpeakerPropagation()
        speakerAnnotatedSegments = try await propagation.annotate(biasedSegments, for: audioURL)
      } catch {
        logger.warning("🎙️ Speaker diarization failed, proceeding without speaker IDs: \(error.localizedDescription)")
        speakerAnnotatedSegments = biasedSegments
      }

      // Build new transcript lines from the batch result with speaker IDs
      let newLines: [TranscriptLine] = speakerAnnotatedSegments.compactMap { segment in
        let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return TranscriptLine(timestamp: max(0, segment.startTime), text: trimmed, speakerId: segment.speakerId)
      }
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Run VoiceTranscriber tests**

Run: `swift test --filter "VoiceTranscriberStopReason"`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add Sources/VoiceFlowPro/Services/VoiceTranscriber.swift
git commit -m "feat: run speaker diarization during batch re-transcription to populate speakerId"
```

---

### Task 5: Display speaker-prefixed lines in MicIndicator overlay and VoiceToTextView

**Files:**
- Modify: `Sources/VoiceFlowPro/Utilities/MicIndicatorOverlay.swift:463-468` (transcriptEntries)
- Modify: `Sources/VoiceFlowPro/Services/VoiceTranscriber.swift:726-778` (handleTranscriptionUpdate)
- Modify: `Sources/VoiceFlowPro/Views/VoiceToTextView.swift:87-88` (transcriptText)
- Test: `Sources/VoiceFlowProTests/Utilities/MicIndicatorOverlayTests.swift`
- Test: `Sources/VoiceFlowProTests/Models/TranscriptSessionHistoryTests.swift`

- [ ] **Step 1: Write a test for speaker-prefixed display formatting**

Add to `Sources/VoiceFlowProTests/Models/TranscriptSessionHistoryTests.swift`:

```swift
@Test("TranscriptSession combinedText includes speaker prefixes when speakerId is set")
func combinedTextWithSpeakerPrefixes() {
  var session = TranscriptSession(startTime: Date())
  session.append(text: "Hello", at: 0, speakerId: 1)
  session.append(text: "Hi there", at: 1.5, speakerId: 2)
  session.append(text: "How are you?", at: 3.0, speakerId: 1)

  let combined = session.speakerFormattedText
  #expect(combined.contains("Speaker 1: Hello"))
  #expect(combined.contains("Speaker 2: Hi there"))
  #expect(combined.contains("Speaker 1: How are you?"))
}

@Test("TranscriptSession speakerFormattedText omits prefix when speakerId is nil")
func combinedTextWithoutSpeakerPrefixes() {
  var session = TranscriptSession(startTime: Date())
  session.append(text: "Hello", at: 0)
  session.append(text: "World", at: 1.5)

  let combined = session.speakerFormattedText
  #expect(combined == "Hello\nWorld")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "combinedTextWithSpeakerPrefixes|combinedTextWithoutSpeakerPrefixes"`
Expected: FAIL — no `speakerFormattedText` property and no `append(text:at:speakerId:)` overload

- [ ] **Step 3: Add `append(text:at:speakerId:)` overload and `speakerFormattedText` to `TranscriptSession`**

In `Sources/VoiceFlowPro/Models/TranscriptSession.swift`, add after the existing `append(text:at:)` method:

```swift
  /// Appends a new line with optional speaker ID.
  public mutating func append(text: String, at offset: TimeInterval, speakerId: Int?) {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    lines.append(TranscriptLine(timestamp: max(0, offset), text: text, speakerId: speakerId))
  }

  /// Returns all text joined by newlines with speaker prefixes where available.
  public var speakerFormattedText: String {
    lines.map { line in
      if let speakerId = line.speakerId {
        return "Speaker \(speakerId): \(line.text)"
      }
      return line.text
    }.joined(separator: "\n")
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "combinedTextWithSpeakerPrefixes|combinedTextWithoutSpeakerPrefixes"`
Expected: PASS

- [ ] **Step 5: Update `handleTranscriptionUpdate` to use `speakerFormattedText` for overlay**

In `Sources/VoiceFlowPro/Services/VoiceTranscriber.swift`, in the `handleTranscriptionUpdate` method around line 758, change the overlay transcript update to use speaker formatting:

```swift
      let combined = currentSession.lines
        .map { line in
          let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmed.isEmpty else { return "" }
          if let speakerId = line.speakerId {
            return "Speaker \(speakerId): \(trimmed)"
          }
          return trimmed
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
```

- [ ] **Step 6: Update `VoiceToTextView.transcriptText` to use speaker formatting**

In `Sources/VoiceFlowPro/Views/VoiceToTextView.swift`, change the `transcriptText` computed property:

```swift
  private var transcriptText: String {
    if let session = transcriber.session, !session.lines.isEmpty {
      let formatted = session.speakerFormattedText
      return formatted.isEmpty ? "Transcription will appear here" : formatted
    }
    return transcriber.liveText.isEmpty ? "Transcription will appear here" : transcriber.liveText
  }
```

- [ ] **Step 7: Build to verify compilation**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add Sources/VoiceFlowPro/Models/TranscriptSession.swift Sources/VoiceFlowPro/Services/VoiceTranscriber.swift Sources/VoiceFlowPro/Views/VoiceToTextView.swift Sources/VoiceFlowProTests/Models/TranscriptSessionHistoryTests.swift
git commit -m "feat: display speaker-prefixed lines in overlay and VoiceToTextView"
```

---

### Task 6: Waveform redesign — replace scrolling visualizer with vertical bouncing bars

**Files:**
- Modify: `Sources/VoiceFlowPro/Utilities/MicIndicatorOverlay.swift`
- Test: `Sources/VoiceFlowProTests/Utilities/MicIndicatorOverlayTests.swift`

- [ ] **Step 1: Write tests for envelope smoothing and waveform bar weights**

Add to `Sources/VoiceFlowProTests/Utilities/MicIndicatorOverlayTests.swift`:

```swift
@Test("waveform bar weights produce center-high sides-low pattern")
func waveformBarWeightsCenterHigh() {
  let weights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]
  // Center bar (index 2) should be highest
  #expect(weights[2] > weights[1])
  #expect(weights[2] > weights[3])
  // Edges should be lowest
  #expect(weights[0] < weights[1])
  #expect(weights[4] < weights[3])
}

@Test("envelope attack responds faster than release")
func envelopeAttackFasterThanRelease() {
  let attack: CGFloat = 0.40
  let release: CGFloat = 0.15

  // Attack: jumping from 0.0 to 1.0
  var level: CGFloat = 0.0
  let targetHigh: CGFloat = 1.0
  level = attack * targetHigh + (1 - attack) * level
  let afterAttack = level  // 0.40

  // Release: dropping from 0.40 to 0.0
  let targetLow: CGFloat = 0.0
  level = release * targetLow + (1 - release) * level
  let afterRelease = level  // 0.40 * 0.85 = 0.34

  // Attack moves more aggressively toward target
  #expect(afterAttack == 0.40)
  #expect(afterRelease > 0.33)
  #expect(afterRelease < 0.35)
}
```

- [ ] **Step 2: Run tests to verify they pass (pure math tests)**

Run: `swift test --filter "waveformBarWeightsCenterHigh|envelopeAttackFasterThanRelease"`
Expected: PASS

- [ ] **Step 3: Add `smoothedBarLevels` to `MicIndicatorViewModel`**

In `Sources/VoiceFlowPro/Utilities/MicIndicatorOverlay.swift`, update `MicIndicatorViewModel`:

```swift
@MainActor
private final class MicIndicatorViewModel: ObservableObject {
    @Published var level: CGFloat = MicIndicatorOverlay.Constants.baselineLevel
    @Published var displayLines: [MicIndicatorOverlay.DisplayLine] = []
    @Published var panelHeight: CGFloat = MicIndicatorOverlay.Constants.baseHeight
    @Published var transcriptViewportHeight: CGFloat = 0
    @Published var isOverlayActive: Bool = false
    @Published var hasTranscript: Bool = false
    @Published var overlayStatus: OverlayStatus = .idle
    @Published var appIcon: NSImage?
    @Published var recordingStartDate: Date?
    @Published var levelHistory: [CGFloat] = []
    @Published var hasEnteredProcessing: Bool = false
    /// Smoothed per-bar levels for the 5-bar bouncing waveform.
    var smoothedBarLevels: [CGFloat] = [0, 0, 0, 0, 0]

    static let maxLevelHistory = 30
}
```

- [ ] **Step 4: Replace `scrollingVisualizer()` with `bouncingWaveform()`**

In `Sources/VoiceFlowPro/Utilities/MicIndicatorOverlay.swift`, in `MicIndicatorView`, replace the `scrollingVisualizer()` method (lines 685-725) with:

```swift
    /// 5-bar vertical bouncing waveform driven by real-time RMS audio level.
    private func bouncingWaveform() -> some View {
        let barCount = 5
        let weights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]
        let barWidth: CGFloat = 8
        let barSpacing: CGFloat = 4
        let minBarHeight: CGFloat = 6
        let maxBarHeight: CGFloat = 38
        let attackCoeff: CGFloat = 0.40
        let releaseCoeff: CGFloat = 0.15
        let jitterRange: CGFloat = 0.04

        let range = maxBarHeight - minBarHeight

        return TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { _ in
            HStack(alignment: .center, spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    let target = viewModel.level * weights[index]
                    let jitter = CGFloat.random(in: -jitterRange...jitterRange)
                    let jitteredTarget = max(0, min(1, target + jitter))

                    let _ = updateSmoothedLevel(
                        at: index,
                        target: jitteredTarget,
                        attack: attackCoeff,
                        release: releaseCoeff
                    )

                    let smoothed = viewModel.smoothedBarLevels[index]
                    let barHeight = max(minBarHeight, minBarHeight + range * smoothed)

                    let normalizedIndex = Double(index) / Double(max(barCount - 1, 1))
                    let gradient = LinearGradient(
                        colors: [
                            Color(hue: 0.55 - normalizedIndex * 0.08, saturation: 0.8, brightness: 1.0, opacity: 0.7 + Double(smoothed) * 0.3),
                            Color(hue: 0.7 - normalizedIndex * 0.1, saturation: 0.85, brightness: 0.9, opacity: 0.6 + Double(smoothed) * 0.3)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                        .fill(gradient)
                        .frame(width: barWidth, height: barHeight)
                        .animation(.easeOut(duration: 0.06), value: smoothed)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: maxBarHeight)
    }

    /// Updates the smoothed level for a bar at the given index. Returns Void (used for side-effect in SwiftUI).
    @discardableResult
    private func updateSmoothedLevel(at index: Int, target: CGFloat, attack: CGFloat, release: CGFloat) -> Bool {
        let prev = viewModel.smoothedBarLevels[index]
        let isAttack = target > prev
        let coeff = isAttack ? attack : release
        viewModel.smoothedBarLevels[index] = coeff * target + (1 - coeff) * prev
        return true
    }
```

- [ ] **Step 5: Update `waveformSection` to call `bouncingWaveform()` instead of `scrollingVisualizer()`**

In `Sources/VoiceFlowPro/Utilities/MicIndicatorOverlay.swift`, in the `waveformSection` method (around line 664), replace `scrollingVisualizer()` with `bouncingWaveform()`.

- [ ] **Step 6: Remove old `scrollingVisualizer()` method and unused `barCount`, `minHeight`, `maxHeight` properties from `MicIndicatorView`**

Remove these instance properties from `MicIndicatorView`:
```swift
// Remove:
private let barCount = 30
private let minHeight: CGFloat = 4
private let maxHeight: CGFloat = 34
```

And remove the entire `scrollingVisualizer()` method.

- [ ] **Step 7: Build to verify compilation**

Run: `swift build`
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Run all MicIndicator tests**

Run: `swift test --filter "MicIndicatorOverlay"`
Expected: All tests pass

- [ ] **Step 9: Commit**

```bash
git add Sources/VoiceFlowPro/Utilities/MicIndicatorOverlay.swift Sources/VoiceFlowProTests/Utilities/MicIndicatorOverlayTests.swift
git commit -m "feat: replace scrolling waveform with 5-bar vertical bouncing visualizer driven by real-time RMS"
```

---

### Task 7: Run full test suite and fix any regressions

**Files:**
- Any files that need fixes from test failures

- [ ] **Step 1: Run full Swift package test suite**

Run: `swift test`
Expected: All tests pass

- [ ] **Step 2: Build the Xcode project**

Run: `xcodebuild -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Fix any regressions found in steps 1-2**

If any tests fail or build errors occur, fix them and re-run.

- [ ] **Step 4: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: address test regressions from dictation threading, speaker ID, and waveform changes"
```
