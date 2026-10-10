# Ai Cut Speaker Visibility and Translation Availability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Ai Cut reliably show `S1` / `S2` speaker badges when diarization data exists and make batch translation behave correctly on supported macOS versions with explicit feedback when it cannot run.

**Architecture:** Keep the existing `Segment.speakerId -> SegmentsPanelView` rendering path and fix the actual branch-selection / availability logic around it. Extract two small, testable helpers: one for Apple Translation runtime availability and one for Ai Cut speaker-capable transcription diagnostics, then wire both back into `AICutView` and `SegmentsPanelView` with localized status text.

**Tech Stack:** Swift 6.2, SwiftUI, Swift Testing (`import Testing`), Swift Package Manager, Apple Translation framework, existing Ai Cut transcription pipeline

---

## File map

### Existing files to modify

- `Package.swift` — register any new test files in the explicit `VoiceFlowProTests` source list.
- `Sources/VoiceFlowPro/Services/AppleTranslator.swift` — replace the incorrect runtime gate and reuse the shared translation-availability helper.
- `Sources/VoiceFlowPro/Views/SegmentsPanelView.swift` — use the centralized translation-availability decision for header state and help text.
- `Sources/VoiceFlowPro/Views/AICutView.swift` — use the centralized translation gate, emit clearer translation status, and surface speaker-capability diagnostics when Ai Cut falls back away from the diarization-capable path.
- `Sources/VoiceFlowPro/Localizable.xcstrings` — add localized status/help strings introduced by the new diagnostics.
- `Sources/VoiceFlowProTests/Views/SegmentsPanelInteractionTests.swift` — update expectations around translation button availability.

### New files to create

- `Sources/VoiceFlowPro/Services/AppleTranslationAvailability.swift` — small helper that answers whether Apple Translation is supported at runtime and what requirement text to show.
- `Sources/VoiceFlowPro/Services/AICutSpeakerDiagnostics.swift` — pure logic for deciding whether the active Ai Cut transcription branch can produce speaker labels and what missing-prerequisite reason should be reported.
- `Sources/VoiceFlowProTests/Services/AppleTranslationAvailabilityTests.swift` — focused tests for runtime support decisions.
- `Sources/VoiceFlowProTests/Services/AICutSpeakerDiagnosticsTests.swift` — focused tests for diarization-capable branch diagnostics.

### Existing files to read during implementation

- `docs/superpowers/specs/2026-04-27-ai-cut-speaker-translation-design.md`
- `Sources/VoiceFlowPro/Views/AICutView.swift`
- `Sources/VoiceFlowPro/Views/SegmentsPanelView.swift`
- `Sources/VoiceFlowProTests/Services/SegmentedAlignmentPipelineTests.swift`
- `Sources/VoiceFlowProTests/Services/SegmentSpeakerPropagationPipelineTests.swift`

---

### Task 1: Centralize Apple Translation runtime availability with TDD

**Files:**
- Create: `Sources/VoiceFlowPro/Services/AppleTranslationAvailability.swift`
- Create: `Sources/VoiceFlowProTests/Services/AppleTranslationAvailabilityTests.swift`
- Modify: `Package.swift`
- Test: `Sources/VoiceFlowProTests/Services/AppleTranslationAvailabilityTests.swift`

- [ ] **Step 1: Write the failing availability tests**

```swift
import Testing

@testable import VoiceFlowPro

@Suite("AppleTranslationAvailability")
struct AppleTranslationAvailabilityTests {
  @Test("macOS 15 and later are supported")
  func supportsMacOS15AndLater() {
    #expect(AppleTranslationAvailability.isSupported(majorVersion: 15))
    #expect(AppleTranslationAvailability.isSupported(majorVersion: 16))
  }

  @Test("macOS 14 and earlier are unsupported")
  func rejectsMacOS14AndEarlier() {
    #expect(AppleTranslationAvailability.isSupported(majorVersion: 14) == false)
    #expect(AppleTranslationAvailability.isSupported(majorVersion: 13) == false)
  }

  @Test("unsupported message names the correct floor")
  func unsupportedMessageUsesCorrectFloor() {
    #expect(
      AppleTranslationAvailability.minimumRequirementMessage
        == "Apple Translation requires macOS 15 or later"
    )
  }
}
```

- [ ] **Step 2: Register the new test file in `Package.swift`**

```swift
sources: [
    "Services/ModelDownloadStateStoreTests.swift",
    "Services/ModelCacheManagerLanguageTests.swift",
    "Services/ModelCacheManagerLifecycleTests.swift",
    "Services/ModelDownloadManagerTests.swift",
    "Services/SortformerVADSegmenterTests.swift",
    "Services/SegmentedAlignmentPipelineTests.swift",
    "Services/SegmentSpeakerPropagationPipelineTests.swift",
    "Services/SpeechSegmenterTests.swift",
    "Services/MLXParakeetTranscriberTests.swift",
    "Services/FireRedASRTranscriberTests.swift",
    "Services/Qwen3ASRTranscriberContextTests.swift",
    "Services/AudioProcessorChunkTests.swift",
    "Services/AppleTranslationAvailabilityTests.swift",
    "Services/AICutSpeakerDiagnosticsTests.swift",
    "Integration/ModelSelectionUIFlowTests.swift",
    "Integration/TranscriberPoolMigrationTests.swift",
    "Integration/AICutFlowModelTests.swift",
    "Integration/AICutWindowFlowTests.swift",
    "Models/AppConfigurationModelLifecyclePersistenceTests.swift",
    "Models/DataTypesTests.swift",
    "Models/SegmentTests.swift",
    "Models/ModelVariantTTSTests.swift",
    "Models/TTSModelDefinitionCapabilityTests.swift",
    "Models/AppConfigurationTTSTests.swift",
    "Models/FireRedEngineMetadataTests.swift",
    "Models/TranscriptSessionHistoryTests.swift",
    "Services/TTSAudioBookmarkTests.swift",
    "Models/TTSPresetSpeakerLocalizationTests.swift",
    "Models/TTSPresetSpeakerConfigTests.swift",
    "Views/VoiceUsageStatsTests.swift",
    "Views/SegmentsPanelInteractionTests.swift",
    "Services/VADProviderTests.swift",
    "Services/BatchTranscriptionPipelineTests.swift",
    "Services/TranscriptionPipelineFactoryTests.swift",
    "TestBundleAccessor.swift"
]
```

- [ ] **Step 3: Run the focused test and verify it fails**

Run:

```bash
swift test --filter AppleTranslationAvailabilityTests
```

Expected: FAIL with unresolved symbol errors because `AppleTranslationAvailability` does not exist yet.

- [ ] **Step 4: Add the minimal availability helper**

```swift
import Foundation

enum AppleTranslationAvailability {
  static let minimumSupportedMajorVersion = 15

  static func isSupported(majorVersion: Int) -> Bool {
    majorVersion >= minimumSupportedMajorVersion
  }

  static var isRuntimeSupported: Bool {
    isSupported(majorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
  }

  static var minimumRequirementMessage: String {
    "Apple Translation requires macOS 15 or later"
  }
}
```

- [ ] **Step 5: Run the focused test again and verify it passes**

Run:

```bash
swift test --filter AppleTranslationAvailabilityTests
```

Expected: PASS for all three availability assertions.

- [ ] **Step 6: Commit the helper and tests**

```bash
git add Package.swift \
  Sources/VoiceFlowPro/Services/AppleTranslationAvailability.swift \
  Sources/VoiceFlowProTests/Services/AppleTranslationAvailabilityTests.swift
git commit -m $'test: add apple translation availability helper\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```

---

### Task 2: Wire translation availability into the UI and execution path

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/AppleTranslator.swift`
- Modify: `Sources/VoiceFlowPro/Views/SegmentsPanelView.swift`
- Modify: `Sources/VoiceFlowPro/Views/AICutView.swift`
- Modify: `Sources/VoiceFlowPro/Localizable.xcstrings`
- Modify: `Sources/VoiceFlowProTests/Views/SegmentsPanelInteractionTests.swift`
- Test: `Sources/VoiceFlowProTests/Views/SegmentsPanelInteractionTests.swift`

- [ ] **Step 1: Rewrite the header-control test to match the intended button behavior**

```swift
@Test("translate disables when runtime support is unavailable")
func translateDisablesWhenUnsupported() {
  let state = SegmentsPanelHeaderControlState(
    translationAvailable: false,
    isTranslating: false,
    hasSegments: true,
    showTimes: true
  )

  #expect(state.isTranslateDisabled)
  #expect(state.translateSymbolName == "globe")
}

@Test("translate disables only for unsupported, busy, or empty states")
func translateDisablesForExplicitUnavailableStates() {
  let busy = SegmentsPanelHeaderControlState(
    translationAvailable: true,
    isTranslating: true,
    hasSegments: true,
    showTimes: true
  )
  #expect(busy.isTranslateDisabled)

  let empty = SegmentsPanelHeaderControlState(
    translationAvailable: true,
    isTranslating: false,
    hasSegments: false,
    showTimes: true
  )
  #expect(empty.isTranslateDisabled)
}
```

- [ ] **Step 2: Run the segments-panel test and verify it fails**

Run:

```bash
swift test --filter SegmentsPanelInteractionTests
```

Expected: FAIL because `SegmentsPanelHeaderControlState.isTranslateDisabled` currently ignores `translationAvailable`.

- [ ] **Step 3: Make the minimal production change for shared availability**

```swift
// Sources/VoiceFlowPro/Services/AppleTranslator.swift
guard AppleTranslationAvailability.isRuntimeSupported else {
  throw AppleTranslationError.platformUnavailable
}

// Sources/VoiceFlowPro/Views/SegmentsPanelView.swift
private var headerControlState: SegmentsPanelHeaderControlState {
  SegmentsPanelHeaderControlState(
    translationAvailable: AppleTranslationAvailability.isRuntimeSupported,
    isTranslating: isTranslating,
    hasSegments: !segments.isEmpty,
    showTimes: showTimes
  )
}

var isTranslateDisabled: Bool {
  !translationAvailable || isTranslating || !hasSegments
}

// Sources/VoiceFlowPro/Views/AICutView.swift
guard AppleTranslationAvailability.isRuntimeSupported else {
  revealStatusPanel()
  statusText = String(
    localized: "Apple Translation requires macOS 15 or later.",
    comment: "AI Cut status message"
  )
  return
}
```

- [ ] **Step 4: Localize the new translation requirement strings**

```json
"Apple Translation requires macOS 15 or later.": {
  "localizations": {
    "zh-Hans": { "stringUnit": { "state": "translated", "value": "Apple 翻译需要 macOS 15 或更高版本。" } },
    "ja": { "stringUnit": { "state": "translated", "value": "Apple翻訳を使うには macOS 15 以降が必要です。" } },
    "ko": { "stringUnit": { "state": "translated", "value": "Apple 번역을 사용하려면 macOS 15 이상이 필요합니다." } }
  }
}
```

- [ ] **Step 5: Run the focused segments-panel test again and verify it passes**

Run:

```bash
swift test --filter SegmentsPanelInteractionTests
```

Expected: PASS with the unsupported-runtime case now disabling the control and the existing time-toggle tests still passing.

- [ ] **Step 6: Run the focused availability test again to guard the integration**

Run:

```bash
swift test --filter AppleTranslationAvailabilityTests
```

Expected: PASS, confirming that the UI and service layer still agree on the same availability rule.

- [ ] **Step 7: Commit the translation wiring**

```bash
git add Sources/VoiceFlowPro/Services/AppleTranslator.swift \
  Sources/VoiceFlowPro/Views/SegmentsPanelView.swift \
  Sources/VoiceFlowPro/Views/AICutView.swift \
  Sources/VoiceFlowPro/Localizable.xcstrings \
  Sources/VoiceFlowProTests/Views/SegmentsPanelInteractionTests.swift
git commit -m $'fix: align ai cut translation availability with runtime support\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```

---

### Task 3: Add a pure diagnostic helper for speaker-capable Ai Cut paths

**Files:**
- Create: `Sources/VoiceFlowPro/Services/AICutSpeakerDiagnostics.swift`
- Create: `Sources/VoiceFlowProTests/Services/AICutSpeakerDiagnosticsTests.swift`
- Modify: `Package.swift`
- Test: `Sources/VoiceFlowProTests/Services/AICutSpeakerDiagnosticsTests.swift`

- [ ] **Step 1: Write the failing speaker-diagnostic tests**

```swift
import Testing

@testable import VoiceFlowPro

@Suite("AICutSpeakerDiagnostics")
struct AICutSpeakerDiagnosticsTests {
  @Test("aligner-ready path reports speaker support")
  func alignerReadyReportsSpeakerSupport() {
    let result = AICutSpeakerDiagnostics.resolve(
      configuredAligner: .qwen3ForcedAligner,
      isAlignerDownloaded: true,
      autoDiscoveredAligner: nil
    )

    #expect(result.isSpeakerCapable)
    #expect(result.missingRequirementMessage == nil)
  }

  @Test("auto-discovered downloaded aligner reports speaker support")
  func autoDiscoveredAlignerReportsSpeakerSupport() {
    let result = AICutSpeakerDiagnostics.resolve(
      configuredAligner: nil,
      isAlignerDownloaded: false,
      autoDiscoveredAligner: .qwen3ForcedAligner
    )

    #expect(result.isSpeakerCapable)
  }

  @Test("missing aligner reports diagnostic message")
  func missingAlignerReportsMessage() {
    let result = AICutSpeakerDiagnostics.resolve(
      configuredAligner: .qwen3ForcedAligner,
      isAlignerDownloaded: false,
      autoDiscoveredAligner: nil
    )

    #expect(result.isSpeakerCapable == false)
    #expect(result.missingRequirementMessage == "Speaker labels are unavailable because no downloaded align model is ready.")
  }
}
```

- [ ] **Step 2: Register the new test file in `Package.swift`**

```swift
sources: [
    "Services/ModelDownloadStateStoreTests.swift",
    "Services/ModelCacheManagerLanguageTests.swift",
    "Services/ModelCacheManagerLifecycleTests.swift",
    "Services/ModelDownloadManagerTests.swift",
    "Services/SortformerVADSegmenterTests.swift",
    "Services/SegmentedAlignmentPipelineTests.swift",
    "Services/SegmentSpeakerPropagationPipelineTests.swift",
    "Services/SpeechSegmenterTests.swift",
    "Services/MLXParakeetTranscriberTests.swift",
    "Services/FireRedASRTranscriberTests.swift",
    "Services/Qwen3ASRTranscriberContextTests.swift",
    "Services/AudioProcessorChunkTests.swift",
    "Services/AppleTranslationAvailabilityTests.swift",
    "Services/AICutSpeakerDiagnosticsTests.swift",
    "Integration/ModelSelectionUIFlowTests.swift",
    "Integration/TranscriberPoolMigrationTests.swift",
    "Integration/AICutFlowModelTests.swift",
    "Integration/AICutWindowFlowTests.swift",
    "Models/AppConfigurationModelLifecyclePersistenceTests.swift",
    "Models/DataTypesTests.swift",
    "Models/SegmentTests.swift",
    "Models/ModelVariantTTSTests.swift",
    "Models/TTSModelDefinitionCapabilityTests.swift",
    "Models/AppConfigurationTTSTests.swift",
    "Models/FireRedEngineMetadataTests.swift",
    "Models/TranscriptSessionHistoryTests.swift",
    "Services/TTSAudioBookmarkTests.swift",
    "Models/TTSPresetSpeakerLocalizationTests.swift",
    "Models/TTSPresetSpeakerConfigTests.swift",
    "Views/VoiceUsageStatsTests.swift",
    "Views/SegmentsPanelInteractionTests.swift",
    "Services/VADProviderTests.swift",
    "Services/BatchTranscriptionPipelineTests.swift",
    "Services/TranscriptionPipelineFactoryTests.swift",
    "TestBundleAccessor.swift"
]
```

- [ ] **Step 3: Run the focused test and verify it fails**

Run:

```bash
swift test --filter AICutSpeakerDiagnosticsTests
```

Expected: FAIL with unresolved symbol errors because `AICutSpeakerDiagnostics` does not exist yet.

- [ ] **Step 4: Add the minimal speaker-diagnostic helper**

```swift
import Foundation

struct AICutSpeakerDiagnosticResult: Equatable {
  let isSpeakerCapable: Bool
  let alignVariant: ModelVariant?
  let missingRequirementMessage: String?
}

enum AICutSpeakerDiagnostics {
  static func resolve(
    configuredAligner: ModelVariant?,
    isAlignerDownloaded: Bool,
    autoDiscoveredAligner: ModelVariant?
  ) -> AICutSpeakerDiagnosticResult {
    if let configuredAligner, isAlignerDownloaded {
      return .init(isSpeakerCapable: true, alignVariant: configuredAligner, missingRequirementMessage: nil)
    }
    if let autoDiscoveredAligner {
      return .init(isSpeakerCapable: true, alignVariant: autoDiscoveredAligner, missingRequirementMessage: nil)
    }
    return .init(
      isSpeakerCapable: false,
      alignVariant: nil,
      missingRequirementMessage: "Speaker labels are unavailable because no downloaded align model is ready."
    )
  }
}
```

- [ ] **Step 5: Run the focused test again and verify it passes**

Run:

```bash
swift test --filter AICutSpeakerDiagnosticsTests
```

Expected: PASS for the configured-aligner, auto-discovered-aligner, and missing-aligner cases.

- [ ] **Step 6: Commit the helper and tests**

```bash
git add Package.swift \
  Sources/VoiceFlowPro/Services/AICutSpeakerDiagnostics.swift \
  Sources/VoiceFlowProTests/Services/AICutSpeakerDiagnosticsTests.swift
git commit -m $'test: add ai cut speaker diagnostics helper\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```

---

### Task 4: Wire speaker diagnostics into Ai Cut and verify the full regression slice

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/AICutView.swift`
- Modify: `Sources/VoiceFlowPro/Localizable.xcstrings`
- Test: `Sources/VoiceFlowProTests/Services/AICutSpeakerDiagnosticsTests.swift`
- Test: `Sources/VoiceFlowProTests/Services/SegmentedAlignmentPipelineTests.swift`
- Test: `Sources/VoiceFlowProTests/Services/SegmentSpeakerPropagationPipelineTests.swift`

- [ ] **Step 1: Run the speaker-focused suites to capture the pre-integration baseline**

```bash
swift test --filter AICutSpeakerDiagnosticsTests && \
swift test --filter SegmentedAlignmentPipelineTests && \
swift test --filter SegmentSpeakerPropagationPipelineTests
```

- Expected: PASS. This is the regression baseline before wiring the tested helper into `AICutView`.

- [ ] **Step 2: Make the minimal Ai Cut integration change**

```swift
// Sources/VoiceFlowPro/Views/AICutView.swift
let diagnostic = AICutSpeakerDiagnostics.resolve(
  configuredAligner: config.alignModelVariant,
  isAlignerDownloaded: alignDownloaded,
  autoDiscoveredAligner: alignVariant
)

if let alignVariant = diagnostic.alignVariant {
  result = try await runSegmentedAlignmentPipeline(
    sourceURL: url,
    language: config.language,
    asrTranscriber: activeASRTranscriber,
    aligner: try await ModelCacheManager.shared.getAlignTranscriber(model: alignVariant) { _ in },
    modelUsed: "\(config.modelVariant.rawValue) + \(alignVariant.rawValue)",
    dictionaryContext: dictionaryContext,
    progressHandler: progressHandler
  )
} else {
  if let message = diagnostic.missingRequirementMessage {
    applyIfCurrentAICutSession(sessionGeneration) {
      statusText = String(localized: message, comment: "AI Cut status message")
    }
  }
  if let qwen3Transcriber = activeASRTranscriber as? Qwen3ASRTranscriber {
    result = try await qwen3Transcriber.transcribeWithProgress(
      audioPath: url.path,
      language: config.language,
      dictionaryContext: dictionaryContext,
      progressHandler: progressHandler
    )
  } else {
    result = try await activeASRTranscriber.transcribeWithProgress(
      audioPath: url.path,
      language: config.language,
      progressHandler: progressHandler
    )
  }
}
```

- [ ] **Step 3: Localize the new speaker-diagnostic string**

```json
"Speaker labels are unavailable because no downloaded align model is ready.": {
  "localizations": {
    "zh-Hans": { "stringUnit": { "state": "translated", "value": "当前没有可用的已下载对齐模型，因此无法提供说话人标签。" } },
    "ja": { "stringUnit": { "state": "translated", "value": "ダウンロード済みのアラインモデルが利用できないため、話者ラベルは表示できません。" } },
    "ko": { "stringUnit": { "state": "translated", "value": "다운로드된 정렬 모델이 준비되지 않아 화자 라벨을 표시할 수 없습니다." } }
  }
}
```

- [ ] **Step 4: Run the focused suites again and verify they still pass after integration**

Run:

```bash
swift test --filter AICutSpeakerDiagnosticsTests && \
swift test --filter SegmentedAlignmentPipelineTests && \
swift test --filter SegmentSpeakerPropagationPipelineTests
```

Expected: PASS for the new diagnostics suite and the existing speaker-propagation regressions.

- [ ] **Step 5: Run the broader package build slice**

Run:

```bash
swift build && swift test --filter SegmentsPanelInteractionTests
```

Expected: `swift build` succeeds and the focused panel-interaction suite remains green with the new translation gating.

- [ ] **Step 6: Commit the final Ai Cut wiring**

```bash
git add Sources/VoiceFlowPro/Views/AICutView.swift \
  Sources/VoiceFlowPro/Localizable.xcstrings \
git commit -m $'fix: clarify ai cut speaker and translation readiness\n\nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'
```
