# i18n – Wrap All User-Visible Strings

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wrap every user-visible hardcoded English string in `String(localized:comment:)` or change return types to `LocalizedStringKey` so that all UI text participates in the localization pipeline.

**Architecture:** The existing `Localizable.xcstrings` (515 keys, zh-Hans/ja/ko) is the catalog. Strings in `Text("literal")` auto-localize via `LocalizedStringKey`. Strings passed as `String` variables to `Text(someVar)`, `Label(someVar, …)`, or set on `@State var statusText` do NOT auto-localize and must be wrapped. Model-layer `description`/`summary`/`displayName` computed properties that return raw string literals also need wrapping since their return values end up in `Text(model.displayName)` calls.

**Tech Stack:** Swift 5.9, SwiftUI, `String(localized:comment:)` (Swift 5.7+), `String.LocalizationValue` interpolation, `LocalizedStringKey`.

---

## Conventions used throughout

| Situation | Fix |
|---|---|
| `return "Foo"` in a computed `String` property surfaced to UI | `return String(localized: "Foo", comment: "…")` |
| `statusText = "Foo \(x)"` | `statusText = String(localized: "Foo \(x)", comment: "…")` |
| `var label: String { rawValue }` passed to `Text(section.label)` | Change to `var label: LocalizedStringKey { LocalizedStringKey(rawValue) }` |
| `Label(f.rawValue, systemImage: …)` | `Label(LocalizedStringKey(f.rawValue), systemImage: …)` |
| `("Today", sessions)` tuple in an array used as section header | `(String(localized: "Today", comment: "…"), sessions)` |

Interpolated `String(localized:)` calls use Swift 5.7 `String.LocalizationValue` interpolation; Xcode extracts the `%@`/`%lld` key automatically.

---

## Task 1: AICutProgressView – label(for:) function

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/AICutProgressView.swift:63-73`

- [ ] **Step 1: Wrap the four status label strings**

```swift
private func label(for status: AICutBatchItem.Status) -> String {
    switch status {
    case .pending:
        return String(localized: "Pending", comment: "Batch item status: not yet started")
    case .running:
        return String(localized: "Running", comment: "Batch item status: in progress")
    case .succeeded:
        return String(localized: "Done", comment: "Batch item status: completed successfully")
    case .failed:
        return String(localized: "Failed", comment: "Batch item status: completed with error")
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
swift build 2>&1 | grep -E "error:|warning:" | head -20
```

Expected: no new errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/VoiceFlowPro/Views/AICutProgressView.swift
git commit -m "i18n: localize AICutProgressView batch status labels

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 2: DetachedAICutSessionRootView – initial statusText

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/DetachedAICutSessionRootView.swift`

- [ ] **Step 1: Change initial value**

Locate:
```swift
@State private var statusText = "Preparing AI Cut session..."
```
Replace with:
```swift
@State private var statusText = String(localized: "Preparing AI Cut session...", comment: "Initial status when opening a detached AI Cut window")
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | grep "error:" | head -10
```

- [ ] **Step 3: Commit**

```bash
git add Sources/VoiceFlowPro/Views/DetachedAICutSessionRootView.swift
git commit -m "i18n: localize DetachedAICutSessionRootView initial status

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 3: ContentView – AppSection descriptions and label

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/ContentView.swift:85-124`

- [ ] **Step 1: Change label to return LocalizedStringKey**

Current:
```swift
var label: String { rawValue }
```
Replace with:
```swift
var label: LocalizedStringKey { LocalizedStringKey(rawValue) }
```

- [ ] **Step 2: Wrap description strings**

Replace the entire `var description: String` block:
```swift
var description: String {
    switch self {
    case .aiCut:       return String(localized: "Intelligent Video Editing",   comment: "AI Cut sidebar description")
    case .voiceToText: return String(localized: "Real-time dictation",         comment: "Voice To Text sidebar description")
    case .history:     return String(localized: "Transcript archives",         comment: "History sidebar description")
    case .ttsStudio:   return String(localized: "Generate narration clips",    comment: "TTS Studio sidebar description")
    case .models:      return String(localized: "Manage AI models",            comment: "Models sidebar description")
    case .setting:     return String(localized: "Providers, prompts, startup", comment: "Settings sidebar description")
    case .dictionary:  return String(localized: "Manage AI vocabulary",        comment: "Dictionary sidebar description")
    case .permissions: return String(localized: "System access guidance",      comment: "Permissions sidebar description")
    }
}
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | grep "error:" | head -10
```

- [ ] **Step 4: Commit**

```bash
git add Sources/VoiceFlowPro/Views/ContentView.swift
git commit -m "i18n: localize ContentView AppSection labels and descriptions

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 4: HistoryView – group headers and filter Picker

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/HistoryView.swift:74-80,196-199`

- [ ] **Step 1: Wrap group header labels**

Locate in `groupedSessions`:
```swift
return [
    ("Today", today),
    ("Yesterday", yesterday),
    ("This Week", thisWeek),
    ("Older", older),
].filter { !$0.sessions.isEmpty }
```
Replace with:
```swift
return [
    (String(localized: "Today",     comment: "History group: sessions from today"),     today),
    (String(localized: "Yesterday", comment: "History group: sessions from yesterday"), yesterday),
    (String(localized: "This Week", comment: "History group: sessions from this week"), thisWeek),
    (String(localized: "Older",     comment: "History group: older sessions"),          older),
].filter { !$0.sessions.isEmpty }
```

- [ ] **Step 2: Fix the filter Picker label**

Locate:
```swift
Label(f.rawValue, systemImage: f.systemImage).tag(f)
```
Replace with:
```swift
Label(LocalizedStringKey(f.rawValue), systemImage: f.systemImage).tag(f)
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | grep "error:" | head -10
```

- [ ] **Step 4: Commit**

```bash
git add Sources/VoiceFlowPro/Views/HistoryView.swift
git commit -m "i18n: localize HistoryView group headers and filter labels

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 5: ControlPanelView – ConfigTab and PresetEditorMode

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/ControlPanelView.swift`

- [ ] **Step 1: Change ConfigTab to use LocalizedStringKey for display**

`ConfigTab` raw values are used in `Picker` (check exactly how). Find every usage of `ConfigTab.rawValue` in the file and check if it flows into `Text(…)` as a String. The `var id: String { rawValue }` must remain String. The fix: add a `var label: LocalizedStringKey` property if the tab label is passed as a String variable to Text; if it's only used as `Text(rawValue)` directly from a `Picker` ForEach it may already be localizing. Search:

```bash
grep -n 'ConfigTab\|configTab' Sources/VoiceFlowPro/Views/ControlPanelView.swift | head -20
```

If used as `Text(tab.rawValue)` or `Label(tab.rawValue, …)`, wrap: `Text(LocalizedStringKey(tab.rawValue))`.

- [ ] **Step 2: Localize PresetEditorMode.title**

Locate:
```swift
var title: String { self == .create ? "New Preset" : "Rename Preset" }
```
Replace:
```swift
var title: String {
    self == .create
        ? String(localized: "New Preset",    comment: "Preset editor sheet title when creating")
        : String(localized: "Rename Preset", comment: "Preset editor sheet title when renaming")
}
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | grep "error:" | head -10
```

- [ ] **Step 4: Commit**

```bash
git add Sources/VoiceFlowPro/Views/ControlPanelView.swift
git commit -m "i18n: localize ControlPanelView ConfigTab and PresetEditorMode

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 6: ModelsView – ASRProvider, ModelCategory display names and empty state

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/ModelsView.swift`

- [ ] **Step 1: Wrap ASRProvider displayName values that aren't yet localized**

Locate `ASRProvider.displayName`:
```swift
case .all:      return "All"
case .parakeet: return "Parakeet"
case .qwen3:    return "Qwen3"
```
Replace:
```swift
case .all:      return String(localized: "All",      comment: "ASR provider filter: show all providers")
case .parakeet: return String(localized: "Parakeet", comment: "ASR provider name: Parakeet")
case .qwen3:    return String(localized: "Qwen3",    comment: "ASR provider name: Qwen3 ASR")
```

- [ ] **Step 2: Wrap ModelCategory displayName**

Locate `ModelCategory.displayName`:
```swift
case .asr:   return "ASR"
case .align: return "Align"
case .vad:   return "VAD"
case .tts:   return "TTS"
```
Replace:
```swift
case .asr:   return String(localized: "ASR",   comment: "Model category: Automatic Speech Recognition")
case .align: return String(localized: "Align", comment: "Model category: Forced alignment")
case .vad:   return String(localized: "VAD",   comment: "Model category: Voice Activity Detection")
case .tts:   return String(localized: "TTS",   comment: "Model category: Text To Speech")
```

- [ ] **Step 3: Wrap empty state strings (around line 793)**

Locate:
```swift
return "No models downloaded yet"
```
Replace:
```swift
return String(localized: "No models downloaded yet", comment: "Empty state when no models are installed")
```

Locate:
```swift
return "No models available"
```
Replace:
```swift
return String(localized: "No models available", comment: "Empty state when model list is empty")
```

- [ ] **Step 4: Build**

```bash
swift build 2>&1 | grep "error:" | head -10
```

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Views/ModelsView.swift
git commit -m "i18n: localize ModelsView provider filters, categories, empty state

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 7: AISettingsView – AI provider description strings

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/AISettingsView.swift` (around line 307)

- [ ] **Step 1: Find and wrap provider description computed property**

Search:
```bash
grep -n 'return "OpenAI\|return "Google\|return "DeepSeek\|return "Anthropic' Sources/VoiceFlowPro/Views/AISettingsView.swift
```

Wrap each:
```swift
return String(localized: "OpenAI GPT-4o models with balanced quality and latency.", comment: "OpenAI provider description")
return String(localized: "Google Gemini Flash for fast multimodal understanding.",   comment: "Gemini provider description")
return String(localized: "DeepSeek chat models tuned for cost-effective editing.",   comment: "DeepSeek provider description")
return String(localized: "Anthropic Claude for reliable enterprise responses.",       comment: "Anthropic provider description")
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | grep "error:" | head -10
```

- [ ] **Step 3: Commit**

```bash
git add Sources/VoiceFlowPro/Views/AISettingsView.swift
git commit -m "i18n: localize AISettingsView AI provider descriptions

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 8: PaywallView – subscription plan descriptions

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/PaywallView.swift` (around line 478)

- [ ] **Step 1: Wrap subscription plan description strings**

Search:
```bash
grep -n 'return "Flexible\|return "Annual\|return "One-time' Sources/VoiceFlowPro/Views/PaywallView.swift
```

Replace:
```swift
return String(localized: "Flexible monthly subscription, cancel anytime.",                 comment: "Monthly plan description in paywall")
return String(localized: "Annual plan saves 17%, perfect for long-term creators.",         comment: "Annual plan description in paywall")
return String(localized: "One-time payment for permanent Pro features unlock.",            comment: "Lifetime plan description in paywall")
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | grep "error:" | head -10
```

- [ ] **Step 3: Commit**

```bash
git add Sources/VoiceFlowPro/Views/PaywallView.swift
git commit -m "i18n: localize PaywallView subscription plan descriptions

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 9: SubscriptionStatusView and ModelSelectionView – misc strings

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/SubscriptionStatusView.swift:163`
- Modify: `Sources/VoiceFlowPro/Views/ModelSelectionView.swift`

- [ ] **Step 1: Wrap SubscriptionStatusView string**

Locate:
```swift
return "Lifetime access currently active"
```
Replace:
```swift
return String(localized: "Lifetime access currently active", comment: "Subscription status: lifetime purchase is active")
```

- [ ] **Step 2: Wrap ModelSelectionView string**

Locate:
```swift
return "Parakeet v2 is English-only."
```
Replace:
```swift
return String(localized: "Parakeet v2 is English-only.", comment: "Warning: Parakeet v2 model limitation")
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | grep "error:" | head -10
```

- [ ] **Step 4: Commit**

```bash
git add Sources/VoiceFlowPro/Views/SubscriptionStatusView.swift Sources/VoiceFlowPro/Views/ModelSelectionView.swift
git commit -m "i18n: localize misc view strings in SubscriptionStatusView and ModelSelectionView

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 10: AICutView – statusText assignments (part 1: simple strings without interpolation)

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/AICutView.swift`

There are 97 `statusText = "..."` assignments. This task covers the ones **without** string interpolation (easier; ~40 occurrences).

- [ ] **Step 1: Get list of all non-interpolated statusText assignments**

```bash
grep -n 'statusText = "' Sources/VoiceFlowPro/Views/AICutView.swift | grep -v '\\\(' | head -60
```

- [ ] **Step 2: Wrap each non-interpolated assignment**

For every line matching `statusText = "SomeLiteral"` (no `\(`), change to:
```swift
statusText = String(localized: "SomeLiteral", comment: "AI Cut status message")
```

Key strings to wrap (non-exhaustive, verify against grep output):
```swift
statusText = String(localized: "Cancelling transcription...",            comment: "Status: user requested cancel of transcription")
statusText = String(localized: "Model preparation cancelled",            comment: "Status: model warm-up was cancelled")
statusText = String(localized: "Preparing batch transcription...",       comment: "Status: about to start batch run")
statusText = String(localized: "AI Cut editor closed.",                  comment: "Status: editor window was dismissed")
statusText = String(localized: "Session restored from history.",         comment: "Status: loaded session from history store")
statusText = String(localized: "No videos selected to transcribe.",      comment: "Status: user tapped Transcribe with empty queue")
statusText = String(localized: "Model ready. Starting transcription...", comment: "Status: model loaded, transcription about to begin")
statusText = String(localized: "Preparing Qwen3-ASR model...",           comment: "Status: Qwen3 ASR model is loading")
statusText = String(localized: "Running VAD -> ASR -> ForcedAlign pipeline...", comment: "Status: full pipeline in progress")
statusText = String(localized: "Transcription cancelled.",               comment: "Status: transcription was cancelled successfully")
statusText = String(localized: "Model ready. Starting batch transcription...", comment: "Status: model ready for batch run")
statusText = String(localized: "Batch transcription cancelled.",         comment: "Status: batch run was cancelled")
statusText = String(localized: "No transcribed videos to export. Please transcribe some videos first.", comment: "Status: export attempted with no transcription")
statusText = String(localized: "Select at least one export option to continue.", comment: "Status: export attempted with nothing selected")
statusText = String(localized: "Enable audio export in Output settings before exporting audio files.", comment: "Status: audio export attempted with option disabled")
statusText = String(localized: "Export cancelled",                       comment: "Status: export was cancelled")
statusText = String(localized: "No transcription data available for export.", comment: "Status: export with no segments")
statusText = String(localized: "Exporting Final Cut projects...",        comment: "Status: FCPXML export in progress")
statusText = String(localized: "Exporting subtitle files...",            comment: "Status: subtitle file export in progress")
statusText = String(localized: "Exporting audio files...",              comment: "Status: audio file export in progress")
statusText = String(localized: "No export folder selected",             comment: "Status: export folder picker was cancelled")
statusText = String(localized: "Nothing to export for this video. Please transcribe it first.", comment: "Status: single-video export attempted before transcription")
statusText = String(localized: "Enable at least one export option in Output settings before exporting.", comment: "Status: export attempted with no options enabled")
statusText = String(localized: "Enable FCPXML export in Output settings to include Final Cut projects.", comment: "Status: FCPXML attempted with option disabled")
statusText = String(localized: "Enable audio export in Output settings before exporting audio files.", comment: "Status: audio attempted with option disabled")
statusText = String(localized: "Exporting Final Cut project...",         comment: "Status: single-video FCPXML export in progress")
statusText = String(localized: "Exporting subtitle files...",            comment: "Status: subtitle export in progress")
statusText = String(localized: "Exporting audio...",                    comment: "Status: audio export in progress")
statusText = String(localized: "Select a video before editing subtitles.", comment: "Status: subtitle edit attempted with no active video")
statusText = String(localized: "Select a video before editing translation.", comment: "Status: translation edit attempted with no active video")
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | grep "error:" | head -20
```

- [ ] **Step 4: Commit**

```bash
git add Sources/VoiceFlowPro/Views/AICutView.swift
git commit -m "i18n: localize AICutView statusText (non-interpolated)

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 11: AICutView – statusText assignments (part 2: interpolated strings)

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/AICutView.swift`

- [ ] **Step 1: Get list of interpolated statusText assignments**

```bash
grep -n 'statusText = "' Sources/VoiceFlowPro/Views/AICutView.swift | grep '\\\('
```

- [ ] **Step 2: Wrap each interpolated assignment using Swift 5.7 LocalizationValue interpolation**

```swift
// Line ~180
statusText = String(localized: "Translation target set to \(newLanguage.displayName). Run Translate to refresh subtitles.", comment: "Status: translation language changed; %@ is the new language name")

// Line ~546
statusText = String(localized: "Model preparation failed: \(error.localizedDescription)", comment: "Status: model warm-up failed; %@ is the error description")

// Line ~595
statusText = String(localized: "Loading \(resolvedAlignModel.displayName)...", comment: "Status: loading align model; %@ is the model name")

// Line ~615
statusText = String(localized: "Preparing \(model.displayName) in background...", comment: "Status: background model warm-up started; %@ is the model name")

// Line ~654
statusText = String(localized: "Already added: \(first.lastPathComponent)", comment: "Status: duplicate video dropped; %@ is the file name")

// Line ~837
statusText = String(localized: "Transcribing with \(config.transcriberType.displayName)...", comment: "Status: transcription running; %@ is the engine name")

// Line ~943
statusText = String(localized: "Preparing align model: \(progress.currentStep)", comment: "Status: aligner loading; %@ is current step description")

// Lines ~1058, ~1180
statusText = String(localized: "Transcribing \(index + 1)/\(totalVideos): \(url.lastPathComponent)...", comment: "Status: batch transcription progress; first %lld is current index, second %lld is total, %@ is file name")

// Lines ~1345
statusText = String(localized: "[\(index + 1)/\(totalVideos)] Preparing Qwen3-ASR model...", comment: "Status: Qwen3 model loading in batch; first %lld is index, second %lld is total")

// Lines ~1363, ~1406
statusText = String(localized: "[\(index + 1)/\(totalVideos)] Running VAD -> ASR -> ForcedAlign...", comment: "Status: pipeline in batch; %lld counters")

// Line ~1592 (verify exact text)
statusText = String(localized: "No transcribed videos to export. Please transcribe some videos first.", comment: "Status: export attempted with empty queue")

// Line ~1637
statusText = String(localized: "Export failed: \(error.localizedDescription)", comment: "Status: export failed; %@ is the error")

// Line ~1664
statusText = String(localized: "Exporting Final Cut projects...", comment: "Status: FCPXML batch export")

// Line ~1774
statusText = String(localized: "Export encountered issues: \(issues)", comment: "Status: export completed with warnings; %@ is issue list")

// Line ~2054
statusText = String(localized: "Exporting audio [\(index + 1)/\(urls.count)]: \(url.lastPathComponent)...", comment: "Status: audio export progress; %lld counters and %@ file name")

// Line ~2265
statusText = String(localized: "Export encountered issues: \(issues)", comment: "Status: single-video export had warnings; %@ is issue list")

// Line ~2268
statusText = String(localized: "Exported \(summary) with issues: \(issues). Files saved in selected folder.", comment: "Status: export done with warnings; first %@ is summary, second %@ is issues")

// Line ~2319
statusText = String(localized: "FCPXML export failed: \(error.localizedDescription)", comment: "Status: FCPXML export failed; %@ is the error")

// Line ~2327
statusText = String(localized: "Exporting FCPXML [\(index + 1)/\(urls.count)]: \(url.lastPathComponent)...", comment: "Status: FCPXML progress; %lld counters and %@ file name")

// Line ~2349
statusText = String(localized: "FCPXML files exported to \(directory.lastPathComponent).", comment: "Status: FCPXML batch done; %@ is folder name")

// Line ~2352
statusText = String(localized: "FCPXML export completed with issues: \(messages)", comment: "Status: FCPXML done with warnings; %@ is issue list")

// Line ~2654
statusText = String(localized: "Updated subtitle at \(formatTimecode(originalSegment.startTime)).", comment: "Status: subtitle text was edited; %@ is the timecode")
```

Also wrap the `return "..."` strings in helper functions (around line 3427–3468):
```swift
return String(localized: "Finish or cancel the current AI Cut import batch before starting another one.", comment: "Blocker message: batch already in progress")
return String(localized: "Close the current AI Cut editor before importing more videos.",               comment: "Blocker message: editor already open")
return String(localized: "Please wait for the current AI Cut transcription to finish cancelling before starting another import.", comment: "Blocker message: cancellation in progress")
return String(localized: "No transcription data available for export.",                               comment: "Export error: no segments to export")
```

For ETA strings (lines ~3466-3468) which combine `progress.currentStep` with a duration: use `String(localized:)` with interpolation for the ETA part:
```swift
return String(localized: "\(progress.currentStep) (ETA: \(minutes)m \(seconds)s)", comment: "Progress ETA with minutes and seconds; %@ is step name, %lld are time values")
return String(localized: "\(progress.currentStep) (ETA: \(seconds)s)",              comment: "Progress ETA with seconds only; %@ is step name, %lld is seconds")
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | grep "error:" | head -20
```

- [ ] **Step 4: Commit**

```bash
git add Sources/VoiceFlowPro/Views/AICutView.swift
git commit -m "i18n: localize AICutView statusText (interpolated)

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 12: Models – ExportOptions.swift descriptions

**Files:**
- Modify: `Sources/VoiceFlowPro/Models/ExportOptions.swift`

- [ ] **Step 1: Wrap ExportMode**

```swift
// ExportMode.displayName
case .merge:    return String(localized: "Merge",    comment: "Export mode: combine all videos")
case .separate: return String(localized: "Separate", comment: "Export mode: one folder per video")

// ExportMode.description
case .merge:
    return String(localized: "Combine all transcribed videos and assets into shared folders with a single timeline.", comment: "Merge export mode description")
case .separate:
    return String(localized: "Create per-video folders containing their own timeline, subtitles, and media exports.", comment: "Separate export mode description")
```

- [ ] **Step 2: Wrap VideoExportFormat.description**

```swift
case .mp4: return String(localized: "Balanced compatibility and size using H.264.",       comment: "MP4 export format description")
case .mov: return String(localized: "Apple QuickTime container in highest quality.",        comment: "MOV export format description")
case .m4v: return String(localized: "iTunes-friendly container similar to MP4.",           comment: "M4V export format description")
```

- [ ] **Step 3: Wrap VideoExportQuality.displayName and description**

```swift
// displayName
case .original: return String(localized: "Original",       comment: "Video quality: preserve source")
case .high:     return String(localized: "High (1080p)",   comment: "Video quality: 1080p")
case .medium:   return String(localized: "Medium (720p)",  comment: "Video quality: 720p")
case .low:      return String(localized: "Efficient (540p)", comment: "Video quality: 540p")

// description
case .original: return String(localized: "Preserve source quality. Uses passthrough when copying videos.", comment: "Original quality description")
case .high:     return String(localized: "Render at 1080p for crystal-clear playback.",                   comment: "High quality description")
case .medium:   return String(localized: "Balance quality and size by rendering at 720p.",                comment: "Medium quality description")
case .low:      return String(localized: "Smaller files optimized for reviews (540p).",                   comment: "Low quality description")
```

- [ ] **Step 4: Wrap AudioExportFormat displayName and description** (also in ExportOptions.swift)

```bash
grep -n 'AudioExportFormat\|m4a\|wav' Sources/VoiceFlowPro/Models/ExportOptions.swift | head -20
```

Wrap the display name and description strings found.

- [ ] **Step 5: Build**

```bash
swift build 2>&1 | grep "error:" | head -10
```

- [ ] **Step 6: Commit**

```bash
git add Sources/VoiceFlowPro/Models/ExportOptions.swift
git commit -m "i18n: localize ExportOptions displayNames and descriptions

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 13: Models – SubtitleStyle.swift

**Files:**
- Modify: `Sources/VoiceFlowPro/Models/SubtitleStyle.swift`

- [ ] **Step 1: Wrap SubtitleStyleKind displayName and description**

```swift
// displayName
case .primary:     return String(localized: "Primary Line",     comment: "Subtitle style kind: main transcription line")
case .translation: return String(localized: "Translation Line", comment: "Subtitle style kind: translation line")
case .highlight:   return String(localized: "Highlight",        comment: "Subtitle style kind: keyword highlight")

// description
case .primary:
    return String(localized: "Displayed for the main transcription line.", comment: "Primary subtitle style description")
case .translation:
    return String(localized: "Displayed for translated subtitles when a translation is available.", comment: "Translation subtitle style description")
case .highlight:
    return String(localized: "Applied to emphasized keywords extracted by AI Enhance.", comment: "Highlight subtitle style description")
```

- [ ] **Step 2: Wrap SubtitleStylePreset displayName and description**

```swift
// displayName
case .whiteOnBlackOutline:  return String(localized: "White • Black Outline",    comment: "Subtitle preset name")
case .orangeOnBlackOutline: return String(localized: "Orange • Black Outline",   comment: "Subtitle preset name")
case .yellowOnBlackOutline: return String(localized: "Yellow • Black Outline",   comment: "Subtitle preset name")
case .blueOnBlackOutline:   return String(localized: "Sky Blue • Black Outline", comment: "Subtitle preset name")

// description
case .whiteOnBlackOutline:
    return String(localized: "Classic white text with solid black stroke and soft shadow.", comment: "White preset description")
case .orangeOnBlackOutline:
    return String(localized: "Warm orange fill, bold black outline and subtle glow.",       comment: "Orange preset description")
case .yellowOnBlackOutline:
    return String(localized: "Bright yellow fill with strong contrast for emphasis.",       comment: "Yellow preset description")
case .blueOnBlackOutline:
    return String(localized: "Cool blue fill for secondary or translation lines.",          comment: "Blue preset description")
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | grep "error:" | head -10
```

- [ ] **Step 4: Commit**

```bash
git add Sources/VoiceFlowPro/Models/SubtitleStyle.swift
git commit -m "i18n: localize SubtitleStyle displayNames and descriptions

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 14: Models – SubtitleExportFormat, TranscriberType, DataTypes

**Files:**
- Modify: `Sources/VoiceFlowPro/Models/SubtitleExportFormat.swift`
- Modify: `Sources/VoiceFlowPro/Models/DataTypes.swift`

- [ ] **Step 1: Wrap SubtitleExportFormat.description**

```swift
case .srt: return String(localized: "Standard subtitle format compatible with most players.", comment: "SRT subtitle format description")
case .ass: return String(localized: "Advanced SubStation Alpha with styling support.",        comment: "ASS subtitle format description")
case .txt: return String(localized: "Plain text transcript with timestamps.",                 comment: "TXT subtitle format description")
```

- [ ] **Step 2: Wrap TranscriberType.displayName and description** (non-FireRed cases in DataTypes.swift around line 703)

```swift
// displayName
case .whisper:  return String(localized: "Whisper",    comment: "Transcription engine name: OpenAI Whisper")
case .parakeet: return String(localized: "Parakeet",   comment: "Transcription engine name: Parakeet")
case .qwen3:    return String(localized: "Qwen3 ASR",  comment: "Transcription engine name: Qwen3 ASR")

// description
case .whisper:  return String(localized: "OpenAI Whisper models with configurable local downloads",    comment: "Whisper engine description")
case .parakeet: return String(localized: "Parakeet engine with voice activity detection",             comment: "Parakeet engine description")
case .qwen3:    return String(localized: "Qwen3 ASR with MLX optimization for Apple Silicon",         comment: "Qwen3 ASR engine description")
```

- [ ] **Step 3: Wrap ModelVariant.summary strings (around lines 324-356)**

Each `return "…"` in `ModelVariant.summary` should be wrapped with `String(localized: "…", comment: "ModelVariant summary")`. There are ~12 strings. Wrap all non-`NSLocalizedString` ones.

```swift
case .parakeetV2:
    return String(localized: "English-only model optimized for voice activity detection.", comment: "Parakeet v2 model summary")
case .parakeetV3:
    return String(localized: "Parakeet model with multilingual support and VAD built-in.", comment: "Parakeet v3 model summary")
case .qwen3ASR, .qwen3ASR06B4bit, .qwen3ASR06B5bit, .qwen3ASR06B6bit, .qwen3ASR06Bbf16:
    return String(localized: "MLX-based ASR (0.6B) supporting 52 languages with high efficiency on Apple Silicon.", comment: "Qwen3 ASR 0.6B model summary")
case .qwen3ASR17B4bit, .qwen3ASR17B5bit, .qwen3ASR17B6bit, .qwen3ASR17B8bit, .qwen3ASR17Bbf16:
    return String(localized: "MLX-based ASR (1.7B) with higher accuracy, supporting 52 languages on Apple Silicon.", comment: "Qwen3 ASR 1.7B model summary")
case .qwen3ForcedAligner, .qwen3ForcedAligner06B5bit, .qwen3ForcedAligner06B6bit,
     .qwen3ForcedAligner06B8bit, .qwen3ForcedAligner06Bbf16:
    return String(localized: "Forced alignment model for precise word-level timestamp prediction.", comment: "Qwen3 ForcedAligner model summary")
case .sortformerOffline:
    return String(localized: "Offline diarization and speech activity detection for MLX audio processing.", comment: "Sortformer offline model summary")
case .qwen3TTS06B4bit, .qwen3TTS06B8bit, .qwen3TTS06Bbf16:
    return String(localized: "MLX-based TTS (0.6B) model for voice synthesis on Apple Silicon.", comment: "Qwen3 TTS 0.6B model summary")
case .qwen3TTS17B4bit, .qwen3TTS17B8bit, .qwen3TTS17Bbf16:
    return String(localized: "MLX-based TTS (1.7B) model with higher quality voice synthesis on Apple Silicon.", comment: "Qwen3 TTS 1.7B model summary")
case .qwen3TTS06BCustomVoice4bit, .qwen3TTS06BCustomVoice8bit, .qwen3TTS06BCustomVoiceBf16:
    return String(localized: "MLX-based TTS (0.6B) CustomVoice model with built-in preset speakers.", comment: "Qwen3 TTS 0.6B CustomVoice model summary")
case .qwen3TTS17BCustomVoice4bit, .qwen3TTS17BCustomVoice8bit, .qwen3TTS17BCustomVoiceBf16:
    return String(localized: "MLX-based TTS (1.7B) CustomVoice model with built-in preset speakers, higher quality.", comment: "Qwen3 TTS 1.7B CustomVoice model summary")
case .qwen3TTS06BVoiceDesign4bit, .qwen3TTS06BVoiceDesign8bit, .qwen3TTS06BVoiceDesignBf16:
    return String(localized: "MLX-based TTS (0.6B) VoiceDesign model — create voices from text descriptions.", comment: "Qwen3 TTS 0.6B VoiceDesign model summary")
case .qwen3TTS17BVoiceDesign4bit, .qwen3TTS17BVoiceDesign8bit, .qwen3TTS17BVoiceDesignBf16:
    return String(localized: "MLX-based TTS (1.7B) VoiceDesign model — create voices from text descriptions, higher quality.", comment: "Qwen3 TTS 1.7B VoiceDesign model summary")
```

- [ ] **Step 4: Also wrap `Language.displayName` entries** (non-native language names)

In `Sources/VoiceFlowPro/Models/Language.swift`, the `displayName` property returns English language names like `"English"`, `"Chinese"`, `"Japanese"`. These should be localized so Chinese users see "英语", "中文", "日语":

```swift
case .auto:       return String(localized: "Auto Detect", comment: "Language selection: auto-detect language from audio")
case .english:    return String(localized: "English",     comment: "Language name: English (localize to native name in each locale)")
case .chinese:    return String(localized: "Chinese",     comment: "Language name: Chinese")
case .german:     return String(localized: "German",      comment: "Language name: German")
// ... continue for all languages
```

> **Note:** There are 50+ language entries. Do a bulk find-replace: all `return "LanguageName"` lines in the `displayName` switch should become `return String(localized: "LanguageName", comment: "Language name")`.

- [ ] **Step 5: Build**

```bash
swift build 2>&1 | grep "error:" | head -20
```

- [ ] **Step 6: Commit**

```bash
git add Sources/VoiceFlowPro/Models/SubtitleExportFormat.swift Sources/VoiceFlowPro/Models/DataTypes.swift Sources/VoiceFlowPro/Models/Language.swift
git commit -m "i18n: localize model summaries, transcriber types, subtitle formats, language names

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 15: Remaining views – scan and fix stragglers

**Files:** All remaining view files.

- [ ] **Step 1: Find remaining unlocalised string returns in views**

```bash
grep -rn 'return "' Sources/VoiceFlowPro/Views/ --include="*.swift" \
  | grep -v '^\s*//' \
  | grep -v 'String(localized:\|NSLocalizedString\|systemImage\|rawValue\|fileExtension\|print\|log\|AVAsset\|url\|URL\|path\|scheme\|--:--\|0:00' \
  | grep -v '#Preview'
```

- [ ] **Step 2: Fix each remaining string**

For each hit, wrap with `String(localized: "…", comment: "…")`.

Common remaining hits include:
- `AICutView.swift` helper ETA functions around line 3466
- `VoiceToTextView.swift` if any
- `PermissionsView.swift` status strings (e.g., `"Granted"`, `"Denied"`, `"Pending"`, `"Open System Settings"`)

For `PermissionsView.swift`:
```swift
case .granted: return String(localized: "Granted", comment: "Permission status: access has been granted")
case .denied:  return String(localized: "Denied",  comment: "Permission status: access has been denied")
case .pending: return String(localized: "Pending", comment: "Permission status: not yet requested")
// ...
return String(localized: "Open System Settings", comment: "Button to open macOS System Settings for permissions")
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | grep "error:" | head -20
```

- [ ] **Step 4: Full Xcode build**

```bash
xcodebuild -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro build 2>&1 | grep -E "error:|Build succeeded|Build FAILED" | tail -5
```

- [ ] **Step 5: Commit**

```bash
git add Sources/VoiceFlowPro/Views/
git commit -m "i18n: localize remaining straggler strings in view layer

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Task 16: Update Localizable.xcstrings

After all code changes, Xcode automatically extracts new keys during the build. To add them to the catalog with proper metadata:

- [ ] **Step 1: Open Xcode and run "Product → Export Localizations…"** (or use `xcodebuild -exportLocalizations`)

This generates an `.xcloc` package containing all extracted strings including the new ones. Import it back if needed.

- [ ] **Step 2: Alternatively, run the Xcode build to trigger xcstrings auto-sync**

Xcode 15+ automatically syncs `Localizable.xcstrings` when `String(localized:comment:)` and `Text("literal")` are used. Build once in Xcode and save the file.

- [ ] **Step 3: Verify new keys appear in xcstrings**

```bash
python3 -c "
import json
d = json.load(open('Sources/VoiceFlowPro/Localizable.xcstrings'))
print('Total keys:', len(d['strings']))
"
```

Expected: count higher than 515 (previous baseline).

- [ ] **Step 4: Commit the updated xcstrings**

```bash
git add Sources/VoiceFlowPro/Localizable.xcstrings
git commit -m "i18n: update Localizable.xcstrings with new extracted string keys

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

## Self-Review

**Spec coverage checklist:**
- ✅ StatusText assignments in AICutView (97 occurrences) — Tasks 10 & 11
- ✅ Enum display labels (AppSection, ConfigTab, HistoryView.SourceFilter, ModelsView.ASRProvider, ModelsView.ModelCategory, AICutProgressView.status) — Tasks 1, 3, 4, 5, 6
- ✅ Model description/summary strings (DataTypes, ExportOptions, SubtitleStyle, SubtitleExportFormat) — Tasks 12, 13, 14
- ✅ Language.displayName — Task 14
- ✅ TranscriberType.displayName / description — Task 14
- ✅ View-level return strings (PaywallView, AISettingsView, SubscriptionStatusView, ModelSelectionView, PermissionsView) — Tasks 7, 8, 9, 15
- ✅ xcstrings catalog update — Task 16

**Not localized (intentional):**
- Technical model names in `ModelVariant.displayName` (e.g., "Qwen3 ASR 0.6B (4bit)") — these are product identifiers, not UI prose. They can be wrapped but translations would be identical.
- Brand names: "OpenAI", "Gemini", "DeepSeek", "Anthropic", "Groq" — proper nouns.
- System/format strings: `"--:--"`, `"0:00"`, `"0:00.000"` — technical display only.
- Log/debug strings inside `print(…)` calls.
