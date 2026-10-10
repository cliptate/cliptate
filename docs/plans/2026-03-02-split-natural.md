# SplitNatural Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `SegmentSplitByNatural` — an NLTagger-based split that scores candidate break points by POS weight and proximity to the text midpoint, then maps the winning character index to the nearest word boundary.

**Architecture:** New `SegmentSplitByNatural.swift` service follows the same pattern as `SegmentSplitByCharCount.swift`. It is wired into `SegmentProcess.Operation`, `AppConfiguration`, the `ControlPanelConfigurationView` UI toggle, and the `AICutView` pipeline.

**Tech Stack:** Swift, NaturalLanguage framework (`NLTagger`), SwiftUI, existing `Segment`/`WordTiming` data types.

---

### Task 1: Create `SegmentSplitByNatural.swift`

**Files:**
- Create: `Sources/VoiceFlowPro/Services/SegmentSplitByNatural.swift`

**Step 1: Create the file with the full implementation**

```swift
import Foundation
import NaturalLanguage

/// Splits segments using Apple's NaturalLanguage framework.
///
/// Uses NLTagger to assign POS-based weights to candidate break points,
/// scoring each by `nextTokenWeight / (1 + distanceFromCenter × 0.5)`.
/// The winning break point is mapped to the nearest word-timing boundary
/// when `words` is present; otherwise timing is interpolated by char ratio.
enum SegmentSplitByNatural {

  struct Options: Sendable {
    /// Skip segments whose text is shorter than this many characters.
    var minLength: Int = 20

    init(minLength: Int = 20) {
      self.minLength = minLength
    }
  }

  // MARK: - Public API

  static func apply(segments: [Segment], options: Options) -> [Segment] {
    guard !segments.isEmpty else { return [] }
    var result: [Segment] = []
    result.reserveCapacity(segments.count)
    for segment in segments.sorted(by: { $0.startTime < $1.startTime }) {
      if segment.text.count > options.minLength {
        let split = splitSegment(segment)
        result.append(contentsOf: split)
      } else {
        result.append(segment)
      }
    }
    return result
  }

  // MARK: - Core Logic

  private static let tagWeights: [NLTag: Double] = [
    .punctuation: 10.0,
    .conjunction: 8.0,
    .preposition: 5.0,
    .verb: 3.0,
    .noun: 1.0,
  ]

  /// Returns 1 or 2 segments; returns the original segment unchanged if no
  /// suitable break point is found.
  private static func splitSegment(_ segment: Segment) -> [Segment] {
    let text = segment.text
    guard text.count >= 2 else { return [segment] }

    // 1. Find best split character index via NLTagger
    guard let splitIndex = bestSplitIndex(in: text) else { return [segment] }

    // 2. Split text strings
    let firstText = String(text[..<splitIndex]).trimmingCharacters(in: .whitespaces)
    let secondText = String(text[splitIndex...]).trimmingCharacters(in: .whitespaces)
    guard !firstText.isEmpty, !secondText.isEmpty else { return [segment] }

    // 3. Map to timing
    if let words = segment.words, words.count > 1 {
      return splitByWords(
        segment: segment, words: words,
        firstText: firstText, secondText: secondText)
    } else {
      return splitByCharRatio(
        segment: segment, firstText: firstText, secondText: secondText)
    }
  }

  // MARK: - NLTagger scoring

  private static func bestSplitIndex(in text: String) -> String.Index? {
    let tagger = NLTagger(schemes: [.lexicalClass])
    tagger.string = text

    struct Token {
      let upperBound: String.Index
      let weight: Double
    }
    var tokens: [Token] = []

    tagger.enumerateTags(
      in: text.startIndex..<text.endIndex,
      unit: .word,
      scheme: .lexicalClass,
      options: [.omitWhitespace, .omitPunctuation]
    ) { tag, range in
      let weight = tag.flatMap { tagWeights[$0] } ?? 1.0
      tokens.append(Token(upperBound: range.upperBound, weight: weight))
      return true
    }

    guard tokens.count > 1 else { return nil }

    let centerOffset = text.count / 2
    var bestIndex: String.Index = text.index(text.startIndex, offsetBy: centerOffset)
    var maxScore = -1.0

    for i in 0..<(tokens.count - 1) {
      let splitPos = tokens[i].upperBound
      let distance = abs(text.distance(from: text.startIndex, to: splitPos) - centerOffset)
      let score = tokens[i + 1].weight / (1.0 + Double(distance) * 0.5)
      if score > maxScore {
        maxScore = score
        bestIndex = splitPos
      }
    }
    return bestIndex
  }

  // MARK: - Timing helpers

  /// Split by mapping firstText / secondText char counts to the nearest word boundary.
  private static func splitByWords(
    segment: Segment,
    words: [WordTiming],
    firstText: String,
    secondText: String
  ) -> [Segment] {
    // Reconstruct cumulative character offsets per word end
    var cumulative = 0
    var wordEndOffsets: [Int] = []
    for w in words {
      let token = (w.word + w.punctuation).trimmingCharacters(in: .whitespaces)
      guard !token.isEmpty else {
        wordEndOffsets.append(cumulative)
        continue
      }
      cumulative += token.count
      wordEndOffsets.append(cumulative)
    }

    let target = firstText.count
    // Find word index whose end is closest to target
    var bestWordIdx = 0
    var bestDist = Int.max
    for (i, offset) in wordEndOffsets.enumerated() {
      let dist = abs(offset - target)
      if dist < bestDist {
        bestDist = dist
        bestWordIdx = i
      }
    }

    // Ensure we have at least one word in each half
    let splitWordIdx = max(0, min(bestWordIdx, words.count - 2))

    let firstWords = Array(words[0...splitWordIdx])
    let secondWords = Array(words[(splitWordIdx + 1)...])
    guard !firstWords.isEmpty, !secondWords.isEmpty else { return [segment] }

    let s1 = Segment(
      startTime: firstWords.first!.startTime,
      endTime: firstWords.last!.endTime,
      text: WordTimingTextComposer.composeText(from: firstWords),
      words: firstWords,
      confidence: segment.confidence
    )
    let s2 = Segment(
      startTime: secondWords.first!.startTime,
      endTime: secondWords.last!.endTime,
      text: WordTimingTextComposer.composeText(from: secondWords),
      words: secondWords,
      confidence: segment.confidence
    )
    return [s1, s2]
  }

  /// Fallback: interpolate timing by character ratio.
  private static func splitByCharRatio(
    segment: Segment,
    firstText: String,
    secondText: String
  ) -> [Segment] {
    let totalChars = firstText.count + secondText.count
    guard totalChars > 0 else { return [segment] }
    let ratio = Double(firstText.count) / Double(totalChars)
    let splitTime = segment.startTime + segment.duration * ratio
    let s1 = Segment(
      startTime: segment.startTime, endTime: splitTime,
      text: firstText, words: nil, confidence: segment.confidence)
    let s2 = Segment(
      startTime: splitTime, endTime: segment.endTime,
      text: secondText, words: nil, confidence: segment.confidence)
    return [s1, s2]
  }
}
```

**Step 2: Verify it compiles (no tests yet)**

```bash
cd /path/to/repo
xcodebuild build -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: `BUILD SUCCEEDED`

**Step 3: Commit**

```bash
git add Sources/VoiceFlowPro/Services/SegmentSplitByNatural.swift
git commit -m "feat: add SegmentSplitByNatural service"
```

---

### Task 2: Wire into `SegmentProcess`

**Files:**
- Modify: `Sources/VoiceFlowPro/Services/SegmentProcess.swift:8-13` (Operation enum) and `:23-38` (switch)

**Step 1: Add the new Operation case**

In `SegmentProcess.Operation` enum (after `case splitByCharCount`), add:

```swift
case splitByNatural(SegmentSplitByNatural.Options)
```

**Step 2: Add dispatch in the switch**

In the `switch op` block (after the `.splitByCharCount` case), add:

```swift
case .splitByNatural(let options):
  current = SegmentSplitByNatural.apply(segments: current, options: options)
```

**Step 3: Build**

```bash
xcodebuild build -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: `BUILD SUCCEEDED`

**Step 4: Commit**

```bash
git add Sources/VoiceFlowPro/Services/SegmentProcess.swift
git commit -m "feat: wire splitByNatural into SegmentProcess"
```

---

### Task 3: Add `splitByNatural` to `AppConfiguration`

**Files:**
- Modify: `Sources/VoiceFlowPro/Models/AppConfiguration.swift`

**Step 1: Add `@Published` property** (after line ~265 near `splitBySentence`)

```swift
// 按自然语言语义拆分（NLTagger）
@Published var splitByNatural: Bool
```

**Step 2: Add to `Snapshot` struct** (after `splitBySentence: Bool` line ~521)

```swift
var splitByNatural: Bool
```

**Step 3: Add default value** in `defaultSnapshot` (after `splitBySentence: true,`)

```swift
splitByNatural: false,
```

**Step 4: Add to `makeSnapshot()`** (after `splitBySentence: splitBySentence,`)

```swift
splitByNatural: splitByNatural,
```

**Step 5: Add to `applySnapshot(_:)`** (after `splitBySentence = snap.splitBySentence`)

```swift
splitByNatural = snap.splitByNatural
```

**Step 6: Add to `init()`** (after `splitBySentence = defaults.splitBySentence`)

```swift
splitByNatural = defaults.splitByNatural
```

**Step 7: Build**

```bash
xcodebuild build -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: `BUILD SUCCEEDED`

**Step 8: Commit**

```bash
git add Sources/VoiceFlowPro/Models/AppConfiguration.swift
git commit -m "feat: add splitByNatural to AppConfiguration"
```

---

### Task 4: Add UI toggle in `ControlPanelConfigurationView`

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/ControlPanelConfigurationView.swift` (~line 305)

**Step 1: Add the toggle** immediately after the `splitBySentence` Toggle's `.toggleStyle(.switch)` line (~line 305):

```swift
Toggle(isOn: $config.splitByNatural) {
  VStack(alignment: .leading, spacing: 2) {
    Text("Smart Split (NL)")
      .font(.caption)
    Text("Use Apple's NaturalLanguage framework to find semantically balanced break points.")
      .font(.caption2)
      .foregroundColor(.secondary)
  }
}
.toggleStyle(.switch)
```

**Step 2: Build**

```bash
xcodebuild build -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: `BUILD SUCCEEDED`

**Step 3: Commit**

```bash
git add Sources/VoiceFlowPro/Views/ControlPanelConfigurationView.swift
git commit -m "feat: add Smart Split (NL) toggle in ControlPanelConfigurationView"
```

---

### Task 5: Wire into `AICutView` pipeline

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/AICutView.swift` (~lines 66, 1940-1945)

**Step 1: Add to the hash function** (line ~66, after `hasher.combine(config.splitBySentence)`)

```swift
hasher.combine(config.splitByNatural)
```

**Step 2: Add to the operations pipeline** (after the `splitBySentence` block, ~line 1942)

```swift
if config.splitByNatural {
  ops.append(.splitByNatural(.init()))
}
```

**Step 3: Build**

```bash
xcodebuild build -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: `BUILD SUCCEEDED`

**Step 4: Commit**

```bash
git add Sources/VoiceFlowPro/Views/AICutView.swift
git commit -m "feat: wire splitByNatural into AICutView pipeline"
```

---

### Task 6: Final build verification

**Step 1: Full build**

```bash
xcodebuild build -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro -destination 'platform=macOS' 2>&1 | tail -30
```
Expected: `BUILD SUCCEEDED` with no warnings about the new code.
