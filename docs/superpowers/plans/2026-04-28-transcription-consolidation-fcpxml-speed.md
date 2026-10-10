# Transcription Consolidation & FCPXML Speed Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate transcription post-processing into a single pipeline with graceful speaker annotation fallback, and add speed configuration to FCPXML export.

**Architecture:** Extract `TranscriptionPostProcessor` to unify dictionary bias + speaker annotation (with fallback) used by both single and batch transcription paths. Add `fcpxmlSpeed` property through the full AppConfiguration→Snapshot→ConfigPresetStore→FCPXMLExportSettings→FCPXMLExporter chain, implementing FCPXML `timeMap` elements for speed != 1.0.

**Tech Stack:** Swift, SwiftUI, Swift Testing, FCPXML 1.11/1.10

---

### Task 1: TranscriptionPostProcessor — Tests

**Files:**
- Create: `Sources/VoiceFlowProTests/Services/TranscriptionPostProcessorTests.swift`
- Modify: `Package.swift` (add to sources list)

- [ ] **Step 1: Create test file**

```swift
import Testing
@testable import VoiceFlowPro

@Suite("TranscriptionPostProcessor")
struct TranscriptionPostProcessorTests {

  /// Happy path: dictionary bias + speaker annotation both succeed.
  @Test func happyPath_appliesBiasAndSpeakers() async {
    let segments = [
      Segment(startTime: 0.0, endTime: 1.0, text: "hello world"),
      Segment(startTime: 1.0, endTime: 2.0, text: "foo bar"),
    ]
    let asrResult = TranscriptionResult(
      segments: segments,
      modelUsed: "test",
      processingTime: 1.0,
      totalDuration: 2.0
    )

    let speakerRanges: [AudioTimeRange] = [
      AudioTimeRange(startTime: 0.0, endTime: 1.5, speakerId: 0),
      AudioTimeRange(startTime: 1.5, endTime: 2.5, speakerId: 1),
    ]

    let propagation = PlainASRSpeakerPropagation(
      loadAudioSamples: { _ in [Float](repeating: 0, count: 16000) },
      detectSpeakerRanges: { _ in speakerRanges }
    )
    let processor = TranscriptionPostProcessor(speakerPropagation: propagation)

    let result = await processor.postProcess(
      asrResult: asrResult,
      sourceURL: URL(fileURLWithPath: "/tmp/test.wav"),
      dictionaryEntries: []
    )

    #expect(result.segments.count == 2)
    #expect(result.segments[0].speakerId == 0)
    #expect(result.segments[1].speakerId == 1)
    #expect(result.speakerAnnotationApplied == true)
    #expect(result.audioDuration == 2.0)
  }

  /// Speaker annotation throws → segments returned without speaker IDs.
  @Test func speakerAnnotationFails_gracefulFallback() async {
    let segments = [
      Segment(startTime: 0.0, endTime: 1.0, text: "hello"),
    ]
    let asrResult = TranscriptionResult(
      segments: segments,
      modelUsed: "test",
      processingTime: 0.5,
      totalDuration: 1.0
    )

    let propagation = PlainASRSpeakerPropagation(
      loadAudioSamples: { _ in throw NSError(domain: "test", code: 1) },
      detectSpeakerRanges: { _ in [] }
    )
    let processor = TranscriptionPostProcessor(speakerPropagation: propagation)

    let result = await processor.postProcess(
      asrResult: asrResult,
      sourceURL: URL(fileURLWithPath: "/tmp/test.wav"),
      dictionaryEntries: []
    )

    #expect(result.segments.count == 1)
    #expect(result.segments[0].speakerId == nil)
    #expect(result.speakerAnnotationApplied == false)
  }

  /// Empty ASR result → empty output, no crash.
  @Test func emptyASRResult_handlesGracefully() async {
    let asrResult = TranscriptionResult(
      segments: [],
      modelUsed: "test",
      processingTime: 0.0,
      totalDuration: 0.0
    )

    let propagation = PlainASRSpeakerPropagation(
      loadAudioSamples: { _ in [] },
      detectSpeakerRanges: { _ in [] }
    )
    let processor = TranscriptionPostProcessor(speakerPropagation: propagation)

    let result = await processor.postProcess(
      asrResult: asrResult,
      sourceURL: URL(fileURLWithPath: "/tmp/test.wav"),
      dictionaryEntries: []
    )

    #expect(result.segments.isEmpty)
    #expect(result.speakerAnnotationApplied == false)
  }
}
```

- [ ] **Step 2: Add test file to Package.swift sources list**

In `Package.swift`, add to the `sources:` array of the `VoiceFlowProTests` target:

```
"Services/TranscriptionPostProcessorTests.swift",
```

Add it after the existing `"Services/PlainASRSpeakerPropagationTests.swift",` line.

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter TranscriptionPostProcessorTests 2>&1 | tail -20`
Expected: Compilation error — `TranscriptionPostProcessor` not defined yet.

---

### Task 2: TranscriptionPostProcessor — Implementation

**Files:**
- Create: `Sources/VoiceFlowPro/Services/TranscriptionPostProcessor.swift`

- [ ] **Step 1: Create TranscriptionPostProcessor**

```swift
import Foundation

/// Unified post-ASR processing: dictionary bias → speaker annotation (graceful fallback).
struct TranscriptionPostProcessor {

  struct Result {
    let segments: [Segment]
    let audioDuration: TimeInterval
    let processingTime: TimeInterval
    let speakerAnnotationApplied: Bool
  }

  let speakerPropagation: PlainASRSpeakerPropagation

  /// Post-processes raw ASR output: applies dictionary bias, then speaker annotation.
  /// Speaker annotation failure is gracefully handled — returns unannotated segments.
  func postProcess(
    asrResult: TranscriptionResult,
    sourceURL: URL,
    dictionaryEntries: [String]
  ) async -> Result {
    let biasedSegments = ASRDictionaryBiasService.apply(
      to: asrResult.segments,
      dictionaryEntries: dictionaryEntries
    )

    var finalSegments = biasedSegments
    var speakerApplied = false

    do {
      finalSegments = try await speakerPropagation.annotate(biasedSegments, for: sourceURL)
      speakerApplied = finalSegments.contains(where: { $0.speakerId != nil })
    } catch {
      print("⚠️ Speaker annotation skipped: \(error.localizedDescription)")
    }

    return Result(
      segments: finalSegments,
      audioDuration: asrResult.totalDuration,
      processingTime: asrResult.processingTime,
      speakerAnnotationApplied: speakerApplied
    )
  }
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `swift test --filter TranscriptionPostProcessorTests 2>&1 | tail -20`
Expected: All 3 tests PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/VoiceFlowPro/Services/TranscriptionPostProcessor.swift \
  Sources/VoiceFlowProTests/Services/TranscriptionPostProcessorTests.swift \
  Package.swift
git commit -m "feat: add TranscriptionPostProcessor with graceful speaker fallback

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 3: Wire TranscriptionPostProcessor into AICutView

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/AICutView.swift`

- [ ] **Step 1: Add TranscriptionPostProcessor property to AICutView**

Near line 45, where `plainASRSpeakerPropagation` is declared, replace:

```swift
private let plainASRSpeakerPropagation = PlainASRSpeakerPropagation()
```

with:

```swift
private let transcriptionPostProcessor = TranscriptionPostProcessor(
  speakerPropagation: PlainASRSpeakerPropagation()
)
```

- [ ] **Step 2: Update performSingleTranscription to use TranscriptionPostProcessor**

In `performSingleTranscription`, replace the inline post-processing block (approximately lines 1067–1075):

```swift
      let biasedSegments = ASRDictionaryBiasService.apply(
        to: result.segments,
        dictionaryEntries: config.voiceToTextCustomDictionary
      )

      let speakerAnnotatedSegments = try await plainASRSpeakerPropagation.annotate(
        biasedSegments,
        for: url
      )
```

with:

```swift
      let postResult = await transcriptionPostProcessor.postProcess(
        asrResult: result,
        sourceURL: url,
        dictionaryEntries: config.voiceToTextCustomDictionary
      )
      let speakerAnnotatedSegments = postResult.segments
```

- [ ] **Step 3: Update transcribeBatchVideo to use TranscriptionPostProcessor**

In `transcribeBatchVideo`, replace the inline post-processing block (approximately lines 1412–1420):

```swift
    let biasedSegments = ASRDictionaryBiasService.apply(
      to: result.segments,
      dictionaryEntries: config.voiceToTextCustomDictionary
    )

    let speakerAnnotatedSegments = try await plainASRSpeakerPropagation.annotate(
      biasedSegments,
      for: url
    )
```

with:

```swift
    let postResult = await transcriptionPostProcessor.postProcess(
      asrResult: result,
      sourceURL: url,
      dictionaryEntries: config.voiceToTextCustomDictionary
    )
    let speakerAnnotatedSegments = postResult.segments
```

- [ ] **Step 4: Build to verify compilation**

Run: `swift build 2>&1 | tail -20`
Expected: Build succeeded.

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Views/AICutView.swift
git commit -m "refactor: wire TranscriptionPostProcessor into AICutView

Replaces duplicated dictionary bias + speaker annotation code in both
performSingleTranscription and transcribeBatchVideo with the unified
TranscriptionPostProcessor. Speaker annotation failure now gracefully
falls back to unannotated segments instead of killing the transcription.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 4: FCPXML Speed — Config Chain Tests

**Files:**
- Create: `Sources/VoiceFlowProTests/Services/FCPXMLSpeedConfigTests.swift`
- Modify: `Package.swift` (add to sources list)

- [ ] **Step 1: Create config round-trip test file**

```swift
import Testing
@testable import VoiceFlowPro

@Suite("FCPXML Speed Configuration")
struct FCPXMLSpeedConfigTests {

  @Test func snapshotRoundTrip_preservesSpeed() throws {
    var snapshot = AppConfiguration.Snapshot.defaultSnapshot
    snapshot.fcpxmlSpeed = 2.0

    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(AppConfiguration.Snapshot.self, from: data)

    #expect(decoded.fcpxmlSpeed == 2.0)
  }

  @Test func snapshotDefault_speedIsOne() {
    let snapshot = AppConfiguration.Snapshot.defaultSnapshot
    #expect(snapshot.fcpxmlSpeed == 1.0)
  }

  @Test func legacySnapshot_decodesSpeedAsDefault() throws {
    // Simulate a legacy snapshot JSON without fcpxmlSpeed
    var snapshot = AppConfiguration.Snapshot.defaultSnapshot
    let data = try JSONEncoder().encode(snapshot)
    var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    json.removeValue(forKey: "fcpxmlSpeed")
    let modifiedData = try JSONSerialization.data(withJSONObject: json)

    let decoded = try JSONDecoder().decode(AppConfiguration.Snapshot.self, from: modifiedData)
    #expect(decoded.fcpxmlSpeed == 1.0)
  }

  @Test func exportSettings_includesSpeed() {
    let settings = FCPXMLExportSettings(
      frameRate: 25.0,
      projectName: "Test",
      includeSubtitles: true,
      filterEmptySegments: true,
      isResolve: false,
      speed: 1.5
    )
    #expect(settings.speed == 1.5)
  }

  @Test func exportSettings_defaultSpeedIsOne() {
    let settings = FCPXMLExportSettings()
    #expect(settings.speed == 1.0)
  }
}
```

- [ ] **Step 2: Add test file to Package.swift sources list**

Add after the `"Services/TranscriptionPostProcessorTests.swift",` line:

```
"Services/FCPXMLSpeedConfigTests.swift",
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter FCPXMLSpeedConfigTests 2>&1 | tail -20`
Expected: Compilation error — `fcpxmlSpeed` not defined yet.

---

### Task 5: FCPXML Speed — Config Chain Implementation

**Files:**
- Modify: `Sources/VoiceFlowPro/Models/AppConfiguration.swift`
- Modify: `Sources/VoiceFlowPro/Services/ConfigPresetStore.swift`
- Modify: `Sources/VoiceFlowPro/Services/FCPXMLExporter.swift` (settings only)

- [ ] **Step 1: Add fcpxmlSpeed to AppConfiguration @Published properties**

After `@Published var fcpxmlIsResolveCompatible: Bool` (line 328), add:

```swift
  @Published var fcpxmlSpeed: Double {
    didSet {
      if fcpxmlSpeed < 0.1 { fcpxmlSpeed = 0.1 }
      if fcpxmlSpeed > 10.0 { fcpxmlSpeed = 10.0 }
    }
  }
```

- [ ] **Step 2: Add fcpxmlSpeed to Snapshot**

In the `Snapshot` struct, after `var fcpxmlIsResolveCompatible: Bool` (line 565), add:

```swift
    var fcpxmlSpeed: Double
```

- [ ] **Step 3: Add custom decoding for fcpxmlSpeed in Snapshot**

In the Snapshot `init(from decoder:)`, after line 647 (`fcpxmlIsResolveCompatible = try c.decode(...)`), add:

```swift
    fcpxmlSpeed = try c.decodeIfPresent(Double.self, forKey: .fcpxmlSpeed) ?? 1.0
```

Note: Snapshot uses auto-synthesized CodingKeys, so adding the property is sufficient for the key. The `decodeIfPresent` with fallback handles legacy snapshots.

- [ ] **Step 4: Add fcpxmlSpeed to defaultSnapshot**

In `defaultSnapshot` (around line 720-724), after `fcpxmlIsResolveCompatible: false,` add:

```swift
    fcpxmlSpeed: 1.0,
```

- [ ] **Step 5: Add fcpxmlSpeed to makeSnapshot()**

In `makeSnapshot()` (around line 800), after `fcpxmlIsResolveCompatible: fcpxmlIsResolveCompatible,` add:

```swift
      fcpxmlSpeed: fcpxmlSpeed,
```

- [ ] **Step 6: Add fcpxmlSpeed to applySnapshot(_:)**

In `applySnapshot(_:)` (around line 880), after `fcpxmlIsResolveCompatible = snap.fcpxmlIsResolveCompatible` add:

```swift
    fcpxmlSpeed = snap.fcpxmlSpeed
```

- [ ] **Step 7: Add fcpxmlSpeed to init (defaults)**

In the init that loads from defaults (around line 117), after `fcpxmlIsResolveCompatible = defaults.fcpxmlIsResolveCompatible` add:

```swift
    fcpxmlSpeed = defaults.fcpxmlSpeed
```

- [ ] **Step 8: Add fcpxmlSpeed to ConfigPresetStore.Payload**

In `ConfigPresetStore.Payload`:
1. Add CodingKey: `case fcpxmlSpeed` (after `case fcpxmlIsResolveCompatible`, line 20)
2. Add property: `var fcpxmlSpeed: Double` (after `var fcpxmlIsResolveCompatible: Bool`, line 69)
3. Add init parameter: `fcpxmlSpeed: Double = 1.0,` (after `fcpxmlIsResolveCompatible:`, line 114)
4. Add init body: `self.fcpxmlSpeed = fcpxmlSpeed` (after `self.fcpxmlIsResolveCompatible = ...`, line 158)
5. Add decode: `fcpxmlSpeed = try container.decodeIfPresent(Double.self, forKey: .fcpxmlSpeed) ?? 1.0` (after `fcpxmlIsResolveCompatible` decode, line 211)
6. Add encode: `try container.encode(fcpxmlSpeed, forKey: .fcpxmlSpeed)` (after `fcpxmlIsResolveCompatible` encode, line 303)

- [ ] **Step 9: Add speed to FCPXMLExportSettings**

In `FCPXMLExportSettings` (FCPXMLExporter.swift, line 81-101):

Add property after `isResolve`:
```swift
  public let speed: Double
```

Update init to include `speed` with default:
```swift
  public init(
    frameRate: Double = 25.0,
    projectName: String = "Cliptate Project",
    includeSubtitles: Bool = true,
    filterEmptySegments: Bool = true,
    isResolve: Bool = false,
    speed: Double = 1.0
  ) {
    self.frameRate = frameRate
    self.projectName = projectName
    self.includeSubtitles = includeSubtitles
    self.filterEmptySegments = filterEmptySegments
    self.isResolve = isResolve
    self.speed = max(0.1, min(speed, 10.0))
  }
```

- [ ] **Step 10: Wire speed in AICutView export call site**

In AICutView (around line 2431), update the `FCPXMLExportSettings` construction:

```swift
    let exportSettings = FCPXMLExportSettings(
      frameRate: config.fcpxmlFrameRate,
      projectName: projectName,
      includeSubtitles: config.fcpxmlIncludeSubtitles,
      filterEmptySegments: config.filterSilent,
      isResolve: config.fcpxmlIsResolveCompatible,
      speed: config.fcpxmlSpeed
    )
```

- [ ] **Step 11: Run config tests to verify they pass**

Run: `swift test --filter FCPXMLSpeedConfigTests 2>&1 | tail -20`
Expected: All 5 tests PASS.

- [ ] **Step 12: Commit**

```bash
git add Sources/VoiceFlowPro/Models/AppConfiguration.swift \
  Sources/VoiceFlowPro/Services/ConfigPresetStore.swift \
  Sources/VoiceFlowPro/Services/FCPXMLExporter.swift \
  Sources/VoiceFlowPro/Views/AICutView.swift \
  Sources/VoiceFlowProTests/Services/FCPXMLSpeedConfigTests.swift \
  Package.swift
git commit -m "feat: add fcpxmlSpeed to config chain and FCPXMLExportSettings

Adds speed property (0.1-10.0, default 1.0) through AppConfiguration,
Snapshot, ConfigPresetStore, and FCPXMLExportSettings. Legacy snapshots
decode with fallback to 1.0.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 6: FCPXML Speed — Exporter Tests

**Files:**
- Create: `Sources/VoiceFlowProTests/Services/FCPXMLSpeedExporterTests.swift`
- Modify: `Package.swift` (add to sources list)

- [ ] **Step 1: Create exporter speed tests**

```swift
import Testing
@testable import VoiceFlowPro
import CoreGraphics

@Suite("FCPXML Speed Export")
struct FCPXMLSpeedExporterTests {

  private func makeMediaFile(
    segments: [Segment],
    duration: TimeInterval
  ) -> MediaFile {
    MediaFile(
      url: URL(fileURLWithPath: "/tmp/test.mp4"),
      segments: segments,
      duration: duration,
      presentationSize: CGSize(width: 1920, height: 1080)
    )
  }

  @Test func speed1_noTimeMap() {
    let segments = [
      Segment(startTime: 0.0, endTime: 1.0, text: "hello"),
    ]
    let media = makeMediaFile(segments: segments, duration: 1.0)
    let settings = FCPXMLExportSettings(
      frameRate: 25.0, includeSubtitles: false, filterEmptySegments: true,
      isResolve: false, speed: 1.0
    )

    let xml = FCPXMLExporter.exportFCPXML(mediaFiles: [media], settings: settings)

    #expect(!xml.contains("timeMap"))
    #expect(xml.contains("duration=\"25/25s\""))
  }

  @Test func speed2_hasTimeMapAndHalvedDuration() {
    let segments = [
      Segment(startTime: 0.0, endTime: 2.0, text: "hello"),
    ]
    let media = makeMediaFile(segments: segments, duration: 2.0)
    let settings = FCPXMLExportSettings(
      frameRate: 25.0, includeSubtitles: false, filterEmptySegments: true,
      isResolve: false, speed: 2.0
    )

    let xml = FCPXMLExporter.exportFCPXML(mediaFiles: [media], settings: settings)

    #expect(xml.contains("timeMap"))
    // Source duration = 50 frames (2s * 25fps)
    // Timeline duration = ceil(50 / 2.0) = 25 frames
    #expect(xml.contains("duration=\"25/25s\""))
  }

  @Test func speed0_5_doublesTimelineDuration() {
    let segments = [
      Segment(startTime: 0.0, endTime: 1.0, text: "hello"),
    ]
    let media = makeMediaFile(segments: segments, duration: 1.0)
    let settings = FCPXMLExportSettings(
      frameRate: 25.0, includeSubtitles: false, filterEmptySegments: true,
      isResolve: false, speed: 0.5
    )

    let xml = FCPXMLExporter.exportFCPXML(mediaFiles: [media], settings: settings)

    #expect(xml.contains("timeMap"))
    // Source duration = 25 frames (1s * 25fps)
    // Timeline duration = ceil(25 / 0.5) = 50 frames
    #expect(xml.contains("duration=\"50/25s\""))
  }

  @Test func gapClipsAlsoGetTimeMap_whenSpeedNotOne() {
    let segments = [
      Segment(startTime: 0.0, endTime: 1.0, text: "hello"),
      Segment(startTime: 2.0, endTime: 3.0, text: "world"),
    ]
    let media = makeMediaFile(segments: segments, duration: 3.0)
    let settings = FCPXMLExportSettings(
      frameRate: 25.0, includeSubtitles: false, filterEmptySegments: false,
      isResolve: false, speed: 2.0
    )

    let xml = FCPXMLExporter.exportFCPXML(mediaFiles: [media], settings: settings)

    // With filterEmptySegments=false, gap clips are created
    // Both gap and content clips should have timeMap
    let timeMapCount = xml.components(separatedBy: "<timeMap>").count - 1
    #expect(timeMapCount >= 2) // at least 2 clips with timeMap (gap + segment or segment + segment)
  }
}
```

- [ ] **Step 2: Add test file to Package.swift sources list**

Add after `"Services/FCPXMLSpeedConfigTests.swift",`:

```
"Services/FCPXMLSpeedExporterTests.swift",
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter FCPXMLSpeedExporterTests 2>&1 | tail -20`
Expected: Tests fail — timeMap not implemented in exporter yet.

---

### Task 7: FCPXML Speed — Exporter Implementation

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/FCPXMLExporter.swift`

- [ ] **Step 1: Add speed-aware frame conversion helpers**

Inside `exportFCPXML`, after the existing `secondsToFrames` function (line 121-123), add:

```swift
    let timelineSpeed = settings.speed

    // Convert source frames to timeline frames, adjusted for speed
    func sourceToTimelineFrames(_ sourceFrames: Int) -> Int {
      if timelineSpeed == 1.0 { return sourceFrames }
      return max(1, Int(ceil(Double(sourceFrames) / timelineSpeed)))
    }

    // Build a FCPXML timeMap element for speed changes
    func buildTimeMap(sourceStart: Int, timelineDuration: Int, sourceDuration: Int) -> String {
      let fps = Int(settings.frameRate)
      var result = "              <timeMap>\n"
      result += "                <timept time=\"\(sourceStart)/\(fps)s\" value=\"\(sourceStart)/\(fps)s\" interp=\"smooth2\"/>\n"
      result += "                <timept time=\"\(sourceStart + timelineDuration)/\(fps)s\" value=\"\(sourceStart + sourceDuration)/\(fps)s\" interp=\"smooth2\"/>\n"
      result += "              </timeMap>\n"
      return result
    }
```

- [ ] **Step 2: Update Phase 1 — total timeline duration calculation**

In the first pass loop (lines 172–201), update to apply speed to frame durations.

Replace:
```swift
        if !settings.filterEmptySegments && startFrame > lastEndFrame {
          let gapFrames = startFrame - lastEndFrame
          fileFrames += gapFrames
        }

        fileFrames += max(segmentFrames, 0)
```

with:
```swift
        if !settings.filterEmptySegments && startFrame > lastEndFrame {
          let gapFrames = startFrame - lastEndFrame
          fileFrames += sourceToTimelineFrames(gapFrames)
        }

        fileFrames += sourceToTimelineFrames(max(segmentFrames, 0))
```

- [ ] **Step 3: Update Phase 2 — gap clips with speed**

In the second pass, update the gap clip generation (around lines 244–255).

Replace:
```swift
        if !settings.filterEmptySegments && startFrame > lastEndFrame {
          let gapFrames = startFrame - lastEndFrame

          buffer += "            <asset-clip ref=\"r\(currentAssetId)\""
          buffer += " offset=\"\(timelinePosition)/\(Int(settings.frameRate))s\""
          buffer += " duration=\"\(gapFrames)/\(Int(settings.frameRate))s\""
          buffer += " start=\"\(lastEndFrame)/\(Int(settings.frameRate))s\""
          buffer += " name=\"gap-\(currentAssetId)_\(index)\""
          buffer += " tcFormat=\"NDF\"/>\n"

          timelinePosition += gapFrames
        }
```

with:
```swift
        if !settings.filterEmptySegments && startFrame > lastEndFrame {
          let gapSourceFrames = startFrame - lastEndFrame
          let gapTimelineFrames = sourceToTimelineFrames(gapSourceFrames)

          if timelineSpeed != 1.0 {
            buffer += "            <asset-clip ref=\"r\(currentAssetId)\""
            buffer += " offset=\"\(timelinePosition)/\(Int(settings.frameRate))s\""
            buffer += " duration=\"\(gapTimelineFrames)/\(Int(settings.frameRate))s\""
            buffer += " start=\"\(lastEndFrame)/\(Int(settings.frameRate))s\""
            buffer += " name=\"gap-\(currentAssetId)_\(index)\""
            buffer += " tcFormat=\"NDF\">\n"
            buffer += buildTimeMap(
              sourceStart: lastEndFrame,
              timelineDuration: gapTimelineFrames,
              sourceDuration: gapSourceFrames
            )
            buffer += "            </asset-clip>\n"
          } else {
            buffer += "            <asset-clip ref=\"r\(currentAssetId)\""
            buffer += " offset=\"\(timelinePosition)/\(Int(settings.frameRate))s\""
            buffer += " duration=\"\(gapTimelineFrames)/\(Int(settings.frameRate))s\""
            buffer += " start=\"\(lastEndFrame)/\(Int(settings.frameRate))s\""
            buffer += " name=\"gap-\(currentAssetId)_\(index)\""
            buffer += " tcFormat=\"NDF\"/>\n"
          }

          timelinePosition += gapTimelineFrames
        }
```

- [ ] **Step 4: Update Phase 2 — segment clips with speed**

Update the segment asset-clip generation. Replace the segment duration and add timeMap.

Replace (around lines 260–265):
```swift
        buffer += "            <asset-clip ref=\"r\(currentAssetId)\""
        buffer += " offset=\"\(timelinePosition)/\(Int(settings.frameRate))s\""
        buffer += " duration=\"\(segmentFrames)/\(Int(settings.frameRate))s\""
        buffer += " start=\"\(startFrame)/\(Int(settings.frameRate))s\""
        buffer += " name=\"\(currentAssetId)_\(index)\""
        buffer += " tcFormat=\"NDF\">\n"
```

with:
```swift
        let segmentTimelineFrames = sourceToTimelineFrames(segmentFrames)

        buffer += "            <asset-clip ref=\"r\(currentAssetId)\""
        buffer += " offset=\"\(timelinePosition)/\(Int(settings.frameRate))s\""
        buffer += " duration=\"\(segmentTimelineFrames)/\(Int(settings.frameRate))s\""
        buffer += " start=\"\(startFrame)/\(Int(settings.frameRate))s\""
        buffer += " name=\"\(currentAssetId)_\(index)\""
        buffer += " tcFormat=\"NDF\">\n"

        if timelineSpeed != 1.0 {
          buffer += buildTimeMap(
            sourceStart: startFrame,
            timelineDuration: segmentTimelineFrames,
            sourceDuration: segmentFrames
          )
        }
```

Also update the timeline position advancement and title element duration. Replace:
```swift
        timelinePosition += segmentFrames
```

with:
```swift
        timelinePosition += segmentTimelineFrames
```

And update the `buildTitleElement` call's `durationFrames` parameter from `segmentFrames` to `segmentTimelineFrames`.

- [ ] **Step 5: Run exporter tests**

Run: `swift test --filter FCPXMLSpeedExporterTests 2>&1 | tail -20`
Expected: All 4 tests PASS.

- [ ] **Step 6: Run full test suite**

Run: `swift test 2>&1 | tail -30`
Expected: All tests PASS (including existing FCPXML-related tests if any).

- [ ] **Step 7: Commit**

```bash
git add Sources/VoiceFlowPro/Services/FCPXMLExporter.swift \
  Sources/VoiceFlowProTests/Services/FCPXMLSpeedExporterTests.swift \
  Package.swift
git commit -m "feat: implement FCPXML speed via timeMap elements

When speed != 1.0, emits timeMap elements in asset-clips to remap
timeline to source media timing. Timeline durations are divided by
the speed factor. Both segment clips and gap clips get timeMap.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 8: FCPXML Speed — UI Control

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/ControlPanelConfigurationView.swift`

- [ ] **Step 1: Add speed field to FCPXML configuration section**

In `ControlPanelConfigurationView`, inside the FCPXML settings VStack (after the Frame Rate HStack, around line 716), add:

```swift
        HStack {
          Text("Speed")
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          TextField(
            "",
            value: $config.fcpxmlSpeed,
            formatter: Self.decimalFormatter
          )
          .textFieldStyle(.roundedBorder)
          .frame(width: 70)
          .multilineTextAlignment(.trailing)
          Text("×")
            .font(.caption)
            .foregroundColor(.secondary)
        }
```

- [ ] **Step 2: Build to verify**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeded.

- [ ] **Step 3: Commit**

```bash
git add Sources/VoiceFlowPro/Views/ControlPanelConfigurationView.swift
git commit -m "feat: add FCPXML speed control to configuration UI

Adds a Speed field (with × suffix) in the FCPXML export settings,
next to Frame Rate. Uses the same decimal formatter pattern.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 9: Final Verification

- [ ] **Step 1: Run full test suite**

Run: `swift test 2>&1 | tail -40`
Expected: All tests PASS.

- [ ] **Step 2: Build Xcode project**

Run: `xcodebuild -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro build 2>&1 | tail -20`
Expected: Build succeeded.

- [ ] **Step 3: Final commit (if any fixups needed)**

Verify git status is clean or commit any remaining changes.
