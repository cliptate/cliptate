# Translation Display, Config Reactivity & UI Restructuring — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix translation display, make config changes real-time, move translation button to ControlPanelView with batch/single support.

**Architecture:** Include `translation` in `Segment.Equatable` so SwiftUI detects translation changes. Add translate callbacks to ControlPanelView. Remove translate button from SegmentsPanelView header.

**Tech Stack:** Swift, SwiftUI, Swift Testing

---

### Task 1: Fix Segment.Equatable to include translation

**Files:**
- Modify: `Sources/VoiceFlowPro/Models/DataTypes.swift:114-124`
- Modify: `Sources/VoiceFlowProTests/Models/SegmentTests.swift:117-123`

- [ ] **Step 1: Update existing test to expect translation-aware equality**

In `SegmentTests.swift`, change the test at line 117-123 from asserting equality-ignores-translation to asserting translation-affects-equality:

```swift
@Test("Equatable includes translation — different translations are not equal")
func equatableIncludesTranslation() {
  let a = Segment(startTime: 0, endTime: 1, text: "hello",
                  translation: SegmentTranslation(text: "你好", language: .chinese))
  let b = Segment(startTime: 0, endTime: 1, text: "hello")
  #expect(a != b, "Translation difference should affect equality")
}
```

- [ ] **Step 2: Add additional translation equality tests**

```swift
@Test("Equatable treats identical translations as equal")
func equatableSameTranslation() {
  let t = SegmentTranslation(text: "你好", language: .chinese)
  let a = Segment(startTime: 0, endTime: 1, text: "hello", translation: t)
  let b = Segment(startTime: 0, endTime: 1, text: "hello", translation: t)
  #expect(a == b)
}

@Test("Equatable treats both-nil translations as equal")
func equatableNilTranslations() {
  let a = Segment(startTime: 0, endTime: 1, text: "hello")
  let b = Segment(startTime: 0, endTime: 1, text: "hello")
  #expect(a == b)
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter SegmentTests 2>&1 | tail -20`
Expected: `equatableIncludesTranslation` FAILS

- [ ] **Step 4: Update Segment.Equatable to include translation**

In `DataTypes.swift:114-124`:
```swift
// MARK: - Equatable (content-based, excludes id)
extension Segment: Equatable {
  public static func == (lhs: Segment, rhs: Segment) -> Bool {
    lhs.startTime == rhs.startTime
      && lhs.endTime == rhs.endTime
      && lhs.text == rhs.text
      && lhs.words == rhs.words
      && lhs.confidence == rhs.confidence
      && lhs.speakerId == rhs.speakerId
      && lhs.translation == rhs.translation
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter SegmentTests 2>&1 | tail -20`
Expected: All PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/VoiceFlowPro/Models/DataTypes.swift Sources/VoiceFlowProTests/Models/SegmentTests.swift
git commit -m "fix: include translation in Segment.Equatable for SwiftUI reactivity"
```

---

### Task 2: Add translate callbacks to ControlPanelView

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/ControlPanelView.swift`

- [ ] **Step 1: Add new properties to ControlPanelView**

After existing `var onAIEnhance: () -> Void` (line 29), add:
```swift
var onTranslate: () -> Void
var isTranslating: Bool
```

Update `isOperationInFlight`:
```swift
private var isOperationInFlight: Bool {
  isTranscribing || isExporting || isAICorrecting || isAIEnhancing || isTranslating
}
```

- [ ] **Step 2: Add translate button to batch actions row**

In `batchActionsView` (after the AI Enhance button at ~line 345, before the Export Menu):
```swift
Button(action: onTranslate) {
  if isTranslating {
    ProgressView().controlSize(.mini)
  } else {
    Image(systemName: "globe")
      .font(.caption2)
  }
}
.buttonStyle(.bordered)
.controlSize(.mini)
.disabled(!hasAnyTranscribedVideo || isOperationInFlight)
.help(String(localized: "Translate all transcribed segments", comment: "Tooltip for batch translate button"))
```

- [ ] **Step 3: Add translate button to per-video row**

In `videoRow(for:)` HStack (after AI Enhance button, before Restore button):
```swift
Button(action: {
  activeVideoURL = url
  onTranslate()
}) {
  Image(systemName: "globe")
    .font(.caption2)
}
.buttonStyle(.bordered)
.controlSize(.mini)
.disabled(!hasTranscription || isOperationInFlight)
.help(String(localized: "Translate this video", comment: "Tooltip for per-video translate button"))
```

- [ ] **Step 4: Commit**

```bash
git add Sources/VoiceFlowPro/Views/ControlPanelView.swift
git commit -m "feat: add translate buttons to ControlPanelView batch and per-video rows"
```

---

### Task 3: Wire translate callbacks through AICutEditorView

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/AICutEditorView.swift`

- [ ] **Step 1: Add translate callback property**

After `let onAIEnhance: () -> Void` (line 69), add:
```swift
let onTranslate: () -> Void
let isTranslating: Bool
```

- [ ] **Step 2: Pass to ControlPanelView**

In the `ControlPanelView(...)` init call (~line 81-103), add after `onAIEnhance: onAIEnhance`:
```swift
onTranslate: onTranslate,
```

And add after `isAIEnhancing: isAIEnhancing`:
```swift
isTranslating: isTranslating,
```

- [ ] **Step 3: Commit**

```bash
git add Sources/VoiceFlowPro/Views/AICutEditorView.swift
git commit -m "feat: wire translate callback through AICutEditorView to ControlPanelView"
```

---

### Task 4: Pass translate handler from AICutView and remove from SegmentsPanelView

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/AICutView.swift`
- Modify: `Sources/VoiceFlowPro/Views/SegmentsPanelView.swift`

- [ ] **Step 1: Pass onTranslate in AICutView's editorWindowCoreContent**

In `editorWindowCoreContent` AICutEditorView init (~line 275-344), add after `onAIEnhance`:
```swift
onTranslate: translateActiveSegments,
isTranslating: isTranslating,
```

Remove the `onBatchTranslate` line (line 334):
```swift
// DELETE: onBatchTranslate: translateActiveSegments,
```

- [ ] **Step 2: Remove translate button from SegmentsPanelView**

Remove `onBatchTranslate` property and the translate button from the header.

In SegmentsPanelView, remove:
- Property `var onBatchTranslate: (() -> Void)? = nil` (line 16)
- The translate button block in headerView (lines 171-200)
- `isTranslating` property (line 15)
- `translationAvailable` from `headerControlState` (lines 26-32)

Simplify `SegmentsPanelHeaderControlState` to remove translate-related fields.

- [ ] **Step 3: Update SegmentsPanelView call site in AICutEditorView**

In AICutEditorView's SegmentsPanelView init (~line 180-191), remove:
```swift
// DELETE: isTranslating: isTranslating,
// DELETE: onBatchTranslate: onBatchTranslate,
```

- [ ] **Step 4: Build to verify compilation**

Run: `swift build 2>&1 | tail -20`
Expected: Build succeeds

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Views/AICutView.swift Sources/VoiceFlowPro/Views/AICutEditorView.swift Sources/VoiceFlowPro/Views/SegmentsPanelView.swift
git commit -m "refactor: move translate button from SegmentsPanelView to ControlPanelView"
```

---

### Task 5: Audit isTranslating state cleanup

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/AICutView.swift`

- [ ] **Step 1: Audit and fix isTranslating reset in translateActiveSegments**

Verify all exit paths in `translateActiveSegments()` and its callees reset `isTranslating = false`:
- `runDirectTranslation` has a `defer` block at line 3475-3480 that resets `isTranslating` ✅
- `runPendingTranslation` has a `defer` block at line 3519-3525 that resets `isTranslating` ✅
- Early returns in `translateActiveSegments()` (lines 3384-3413) happen BEFORE `isTranslating` is set ✅

Add a safety reset in the session-exit cleanup (around line 797):
```swift
// Already exists at line 797: isTranslating = false
```

This is already handled. No changes needed unless testing reveals otherwise.

- [ ] **Step 2: Run full test suite**

Run: `swift test 2>&1 | tail -30`
Expected: All tests pass

- [ ] **Step 3: Build with Xcode**

Run: `xcodebuild -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "fix: ensure isTranslating state is properly cleaned up in all exit paths"
```
