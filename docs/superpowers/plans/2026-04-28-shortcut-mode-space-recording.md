# Shortcut Mode Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace long-press/short-press voice mode selection with explicit key combos (Right Cmd for dictation, Right Cmd + Right Shift for assistant) plus Space for recording control, and wire AI Enhance language output.

**Architecture:** The `KeyboardShortcutManager` becomes a state machine with CGEventTap for Space suppression and NSEvent monitors for modifier detection. `VoiceShortcutState` tracks session phase (idle/ready/recording) with segment accumulation. `AIPrompts` gains a `languageOutputRule(for:)` helper that formats the existing `%@` placeholder with language-specific instructions.

**Tech Stack:** Swift, SwiftUI, AppKit (NSEvent), CoreGraphics (CGEventTap), Swift Testing

---

### Task 1: VoiceShortcutState — New State Machine

**Files:**
- Modify: `Sources/VoiceFlowPro/Utilities/VoiceShortcutState.swift`
- Create: `Sources/VoiceFlowProTests/Utilities/VoiceShortcutStateTests.swift`
- Modify: `Package.swift` (add test file to sources list)

- [ ] **Step 1: Write failing tests for the new state machine**

```swift
// Sources/VoiceFlowProTests/Utilities/VoiceShortcutStateTests.swift
import Testing

@testable import VoiceFlowPro

@Suite("VoiceShortcutState")
@MainActor
struct VoiceShortcutStateTests {

  @Test("starts idle")
  func startsIdle() {
    let state = VoiceShortcutState()
    #expect(state.phase == .idle)
    #expect(state.activeMode == nil)
    #expect(state.accumulatedTranscript == "")
  }

  @Test("activateMode sets ready phase")
  func activateSetsReady() {
    let state = VoiceShortcutState()
    state.activateMode(.dictation)
    #expect(state.phase == .ready)
    #expect(state.activeMode == .dictation)
    #expect(state.accumulatedTranscript == "")
  }

  @Test("startRecording transitions from ready to recording")
  func startRecording() {
    let state = VoiceShortcutState()
    state.activateMode(.assistant)
    state.startRecording()
    #expect(state.phase == .recording)
    #expect(state.activeMode == .assistant)
  }

  @Test("stopRecording transitions from recording to ready")
  func stopRecording() {
    let state = VoiceShortcutState()
    state.activateMode(.dictation)
    state.startRecording()
    state.stopRecording()
    #expect(state.phase == .ready)
  }

  @Test("appendSegmentText accumulates text")
  func appendSegmentText() {
    let state = VoiceShortcutState()
    state.activateMode(.dictation)
    state.appendSegmentText("Hello ")
    state.appendSegmentText("World")
    #expect(state.accumulatedTranscript == "Hello World")
  }

  @Test("endSession returns mode and transcript, resets to idle")
  func endSession() {
    let state = VoiceShortcutState()
    state.activateMode(.assistant)
    state.startRecording()
    state.appendSegmentText("Test transcript")
    state.stopRecording()
    let result = state.endSession()
    #expect(result?.mode == .assistant)
    #expect(result?.transcript == "Test transcript")
    #expect(state.phase == .idle)
    #expect(state.activeMode == nil)
    #expect(state.accumulatedTranscript == "")
  }

  @Test("endSession returns nil when idle")
  func endSessionWhenIdle() {
    let state = VoiceShortcutState()
    #expect(state.endSession() == nil)
  }

  @Test("activateMode while in another mode cancels previous")
  func switchModeCancels() {
    let state = VoiceShortcutState()
    state.activateMode(.dictation)
    state.startRecording()
    state.appendSegmentText("partial")
    state.activateMode(.assistant)
    #expect(state.activeMode == .assistant)
    #expect(state.phase == .ready)
    #expect(state.accumulatedTranscript == "")
  }

  @Test("startRecording ignored when idle")
  func startRecordingWhenIdle() {
    let state = VoiceShortcutState()
    state.startRecording()
    #expect(state.phase == .idle)
  }

  @Test("stopRecording ignored when not recording")
  func stopRecordingWhenReady() {
    let state = VoiceShortcutState()
    state.activateMode(.dictation)
    state.stopRecording()
    #expect(state.phase == .ready)
  }
}
```

- [ ] **Step 2: Add test file to Package.swift sources list**

Add `"Utilities/VoiceShortcutStateTests.swift"` to the `sources:` array in the test target.

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter VoiceShortcutStateTests 2>&1 | tail -20`
Expected: Compilation errors because `VoiceShortcutState` still has old API

- [ ] **Step 4: Rewrite VoiceShortcutState**

```swift
// Sources/VoiceFlowPro/Utilities/VoiceShortcutState.swift
import Foundation

enum VoiceShortcutMode {
  case dictation
  case assistant
}

@MainActor
final class VoiceShortcutState: ObservableObject {
  static let shared = VoiceShortcutState()

  enum SessionPhase {
    case idle
    case ready
    case recording
  }

  @Published private(set) var activeMode: VoiceShortcutMode?
  @Published private(set) var phase: SessionPhase = .idle
  private(set) var accumulatedTranscript: String = ""

  init() {}

  func activateMode(_ mode: VoiceShortcutMode) {
    accumulatedTranscript = ""
    activeMode = mode
    phase = .ready
  }

  func startRecording() {
    guard phase == .ready else { return }
    phase = .recording
  }

  func stopRecording() {
    guard phase == .recording else { return }
    phase = .ready
  }

  func appendSegmentText(_ text: String) {
    accumulatedTranscript += text
  }

  func endSession() -> (mode: VoiceShortcutMode, transcript: String)? {
    guard let mode = activeMode else { return nil }
    let transcript = accumulatedTranscript
    activeMode = nil
    phase = .idle
    accumulatedTranscript = ""
    return (mode, transcript)
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter VoiceShortcutStateTests 2>&1 | tail -20`
Expected: All 9 tests PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/VoiceFlowPro/Utilities/VoiceShortcutState.swift \
       Sources/VoiceFlowProTests/Utilities/VoiceShortcutStateTests.swift \
       Package.swift
git commit -m "feat: rewrite VoiceShortcutState with idle/ready/recording state machine

Replace longPressThreshold-based mode detection with explicit phase tracking
and segment accumulation for the new shortcut mode design.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 2: AIPrompts — Language Output Rule

**Files:**
- Modify: `Sources/VoiceFlowPro/Models/AIPrompts.swift`
- Create: `Sources/VoiceFlowProTests/Models/AIPromptsLanguageRuleTests.swift`
- Modify: `Package.swift` (add test file to sources list)

- [ ] **Step 1: Write failing tests for languageOutputRule**

```swift
// Sources/VoiceFlowProTests/Models/AIPromptsLanguageRuleTests.swift
import Testing

@testable import VoiceFlowPro

@Suite("AIPrompts.languageOutputRule")
struct AIPromptsLanguageRuleTests {

  @Test("auto language returns English output rule")
  func autoLanguage() {
    let rule = AIPrompts.languageOutputRule(for: .auto)
    #expect(rule.contains("English"))
  }

  @Test("english returns English output rule")
  func englishLanguage() {
    let rule = AIPrompts.languageOutputRule(for: .english)
    #expect(rule.contains("English"))
  }

  @Test("chinese returns Chinese output rule with translation instruction")
  func chineseLanguage() {
    let rule = AIPrompts.languageOutputRule(for: .chinese)
    #expect(rule.contains("Chinese"))
    #expect(rule.contains("translate"))
  }

  @Test("japanese returns Japanese output rule")
  func japaneseLanguage() {
    let rule = AIPrompts.languageOutputRule(for: .japanese)
    #expect(rule.contains("Japanese"))
  }

  @Test("dictation system prompt contains %@ placeholder")
  func dictationPromptHasPlaceholder() {
    #expect(AIPrompts.dictationSystemPrompt.contains("%@"))
  }

  @Test("formatted dictation prompt replaces placeholder with language rule")
  func formattedDictationPrompt() {
    let rule = AIPrompts.languageOutputRule(for: .chinese)
    let formatted = String(format: AIPrompts.dictationSystemPrompt, rule)
    #expect(!formatted.contains("%@"))
    #expect(formatted.contains("Chinese"))
  }

  @Test("assistant prompt with language rule appended")
  func assistantPromptWithLanguage() {
    let rule = AIPrompts.languageOutputRule(for: .korean)
    let full = AIPrompts.assistantMode + "\n\n" + rule
    #expect(full.contains("Korean"))
    #expect(full.contains("AI assistant"))
  }
}
```

- [ ] **Step 2: Add test file to Package.swift sources list**

Add `"Models/AIPromptsLanguageRuleTests.swift"` to the `sources:` array in the test target.

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter AIPromptsLanguageRuleTests 2>&1 | tail -20`
Expected: Compilation error — `languageOutputRule` does not exist

- [ ] **Step 4: Implement languageOutputRule**

Add to `Sources/VoiceFlowPro/Models/AIPrompts.swift` after the existing functions:

```swift
static func languageOutputRule(for language: Language) -> String {
    switch language {
    case .auto, .english:
        return "Output your response in English."
    default:
        let name = language.displayName
        return "IMPORTANT: Your output MUST be entirely in \(name). If the transcript is in a different language, translate it to \(name). Do not mix languages."
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter AIPromptsLanguageRuleTests 2>&1 | tail -20`
Expected: All 7 tests PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/VoiceFlowPro/Models/AIPrompts.swift \
       Sources/VoiceFlowProTests/Models/AIPromptsLanguageRuleTests.swift \
       Package.swift
git commit -m "feat: add AIPrompts.languageOutputRule for language-aware AI output

Generates language-specific rules for dictation and assistant prompts.
Wires into the existing %@ placeholder in dictationSystemPrompt.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 3: KeyboardShortcutManager — Rewrite with CGEventTap + Modifier State Machine

**Files:**
- Modify: `Sources/VoiceFlowPro/Utilities/KeyboardShortcutManager.swift`

- [ ] **Step 1: Rewrite KeyboardShortcutManager**

Replace the entire file with the new implementation. Key changes:

1. Remove `VoiceToggleShortcutPreset`, `InteractionStyle`, all preset-related code, all `NSEvent` preset monitors
2. Keep the `KeyboardShortcuts.Name` extensions (for backward compat, even though unused — can remove later)
3. New event types:

```swift
public struct ShortcutEvent {
    public enum Phase {
        case modeActivated
        case modeDeactivated
        case spaceToggle
    }
    public let phase: Phase
    public let mode: VoiceShortcutMode
}
```

4. Track modifier state:

```swift
private var isRightCmdHeld = false
private var isRightShiftHeld = false
private var activeMode: VoiceShortcutMode?
```

5. Install `NSEvent` local+global monitors for `.flagsChanged` to track Right Cmd (keyCode 54) and Right Shift (keyCode 60) via `event.keyCode`.

6. Install a `CGEventTap` for `.keyDown` and `.keyUp` to intercept Space (keyCode 49) when `activeMode != nil`. The tap callback returns `nil` to suppress the event, or passes it through when no mode is active.

7. Mode activation logic in `flagsChanged` handler:
   - When Right Cmd pressed (`isRightCmdHeld` becomes true):
     - If Right Shift is also held → target mode is `.assistant`
     - Else → target mode is `.dictation`
     - If `activeMode == nil` → activate target mode
     - If `activeMode == target` → deactivate (end session)
     - If `activeMode != target` → switch modes (deactivate old, activate new)
   - When Right Shift pressed while Right Cmd is held:
     - If `activeMode == .dictation` → switch to `.assistant`
     - If `activeMode == nil` → activate `.assistant`
   - When Right Cmd released: no action (mode persists after release)
   - When Right Shift released: no action

8. Space handling in CGEventTap callback:
   - Only process when `activeMode != nil` and `isARepeat` is false (check CGEvent flag `kCGEventAutorepeat` via `event.getIntegerValueField(.keyboardEventAutorepeat) == 0`)
   - On keyDown: emit `.spaceToggle`
   - Suppress event by returning `nil`

9. Permissions: wrap CGEventTap creation in a check. If `CGEvent.tapCreate` returns `nil`, log a warning and fall back to NSEvent global monitor for keyDown (observation-only, Space will type into apps).

Full implementation:

```swift
import AppKit
import CoreGraphics
import Foundation
import KeyboardShortcuts
import os.log

extension KeyboardShortcuts.Name {
    public static let dictationVoiceTranscription = Self("dictationVoiceTranscription")
    public static let assistantVoiceTranscription = Self("assistantVoiceTranscription")
}

@MainActor
public final class KeyboardShortcutManager {
    public static let shared = KeyboardShortcutManager()

    public struct ShortcutEvent {
        public enum Phase {
            case modeActivated
            case modeDeactivated
            case spaceToggle
        }
        public let phase: Phase
        public let mode: VoiceShortcutMode
    }

    private let logger = Logger(subsystem: "com.VoiceFlowPro", category: "KeyboardShortcuts")
    private var shortcutHandler: ((ShortcutEvent) -> Void)?

    // Modifier tracking
    private var isRightCmdHeld = false
    private var isRightShiftHeld = false
    private(set) var activeMode: VoiceShortcutMode?

    // Event monitors
    private var flagsLocalMonitor: Any?
    private var flagsGlobalMonitor: Any?
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var spaceFallbackGlobalMonitor: Any?
    private var spaceFallbackLocalMonitor: Any?

    // Dedup
    private var lastFlagsEventTimestamp: TimeInterval = 0

    private init() {}

    public func registerDefaultShortcuts() {
        // No-op: presets removed. Kept for call-site compatibility.
    }

    @MainActor
    public func bindShortcuts(onEvent: @escaping (ShortcutEvent) -> Void) {
        shortcutHandler = onEvent
        installFlagsMonitors()
        installSpaceMonitor()
    }

    @MainActor
    public func unbindShortcuts() {
        removeFlagsMonitors()
        removeSpaceMonitor()
        shortcutHandler = nil
        isRightCmdHeld = false
        isRightShiftHeld = false
        activeMode = nil
    }

    // MARK: - Flags Monitors (Right Cmd / Right Shift)

    private func installFlagsMonitors() {
        removeFlagsMonitors()

        let handler: (NSEvent) -> NSEvent? = { [weak self] event in
            self?.processFlagsChanged(event)
            return event
        }

        flagsLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: handler)
        flagsGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.processFlagsChanged(event)
        }

        logger.notice("Installed flags monitors for Right Cmd / Right Shift mode detection")
    }

    private func removeFlagsMonitors() {
        if let m = flagsLocalMonitor { NSEvent.removeMonitor(m) }
        if let m = flagsGlobalMonitor { NSEvent.removeMonitor(m) }
        flagsLocalMonitor = nil
        flagsGlobalMonitor = nil
    }

    private func processFlagsChanged(_ event: NSEvent) {
        guard event.type == .flagsChanged else { return }
        guard event.timestamp != lastFlagsEventTimestamp else { return }
        lastFlagsEventTimestamp = event.timestamp

        let keyCode = event.keyCode

        // Track Right Cmd (keyCode 54)
        if keyCode == 54 {
            let nowHeld = event.modifierFlags.contains(.command)
            let wasHeld = isRightCmdHeld
            isRightCmdHeld = nowHeld

            if nowHeld && !wasHeld {
                // Right Cmd pressed
                handleModeKeyPressed()
            }
            // Release: no action — mode persists
            return
        }

        // Track Right Shift (keyCode 60)
        if keyCode == 60 {
            let nowHeld = event.modifierFlags.contains(.shift)
            let wasHeld = isRightShiftHeld
            isRightShiftHeld = nowHeld

            if nowHeld && !wasHeld && isRightCmdHeld {
                // Right Shift pressed while Right Cmd held — upgrade/switch to assistant
                handleModeKeyPressed()
            }
            // Release: no action
            return
        }
    }

    private func handleModeKeyPressed() {
        let targetMode: VoiceShortcutMode = (isRightCmdHeld && isRightShiftHeld) ? .assistant : .dictation

        if activeMode == nil {
            // No active mode → activate
            activeMode = targetMode
            emitEvent(ShortcutEvent(phase: .modeActivated, mode: targetMode))
        } else if activeMode == targetMode {
            // Same mode → deactivate (toggle off)
            let mode = activeMode!
            activeMode = nil
            emitEvent(ShortcutEvent(phase: .modeDeactivated, mode: mode))
        } else {
            // Different mode → switch: deactivate old, activate new
            let oldMode = activeMode!
            activeMode = nil
            emitEvent(ShortcutEvent(phase: .modeDeactivated, mode: oldMode))
            activeMode = targetMode
            emitEvent(ShortcutEvent(phase: .modeActivated, mode: targetMode))
        }
    }

    // MARK: - Space Monitor (CGEventTap)

    private func installSpaceMonitor() {
        removeSpaceMonitor()

        // Attempt CGEventTap for space suppression
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        let unmanagedSelf = Unmanaged.passUnretained(self)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<KeyboardShortcutManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleCGEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: unmanagedSelf.toOpaque()
        ) else {
            logger.warning("CGEventTap creation failed — falling back to NSEvent global monitor (Space will not be suppressed)")
            installSpaceFallbackMonitor()
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTapRunLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        logger.notice("Installed CGEventTap for Space key interception")
    }

    private nonisolated func handleCGEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // Re-enable if disabled by system
        if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
            if let tap = MainActor.assumeIsolated({ self.eventTap }) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == 49 else { // Space
            return Unmanaged.passUnretained(event)
        }

        // Check active mode on main actor
        let mode = MainActor.assumeIsolated { self.activeMode }
        guard let mode else {
            return Unmanaged.passUnretained(event) // Pass through
        }

        // Ignore auto-repeat
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat)
        if isRepeat != 0 {
            return nil // Suppress repeats too
        }

        if type == .keyDown {
            Task { @MainActor in
                self.emitEvent(ShortcutEvent(phase: .spaceToggle, mode: mode))
            }
        }

        return nil // Suppress space
    }

    private func installSpaceFallbackMonitor() {
        let handler: (NSEvent) -> NSEvent? = { [weak self] event in
            self?.processSpaceFallback(event)
            return event
        }

        spaceFallbackLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: handler)
        spaceFallbackGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.processSpaceFallback(event)
        }

        logger.notice("Installed NSEvent fallback monitors for Space (no suppression)")
    }

    private func processSpaceFallback(_ event: NSEvent) {
        guard event.keyCode == 49 else { return }
        guard !event.isARepeat else { return }
        guard let mode = activeMode else { return }
        emitEvent(ShortcutEvent(phase: .spaceToggle, mode: mode))
    }

    private func removeSpaceMonitor() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        eventTapRunLoopSource = nil

        if let m = spaceFallbackLocalMonitor { NSEvent.removeMonitor(m) }
        if let m = spaceFallbackGlobalMonitor { NSEvent.removeMonitor(m) }
        spaceFallbackLocalMonitor = nil
        spaceFallbackGlobalMonitor = nil
    }

    // MARK: - Event Emission

    private func emitEvent(_ event: ShortcutEvent) {
        shortcutHandler?(event)
    }
}
```

- [ ] **Step 2: Build to verify compilation**

Run: `swift build 2>&1 | tail -20`
Expected: Compilation errors in ContentView.swift and VoiceToTextView.swift (they reference old API). The KeyboardShortcutManager itself should compile.

- [ ] **Step 3: Commit the manager rewrite (allow build errors in dependents)**

```bash
git add Sources/VoiceFlowPro/Utilities/KeyboardShortcutManager.swift
git commit -m "feat: rewrite KeyboardShortcutManager with CGEventTap + modifier state machine

Replace preset-based monitor system with:
- flagsChanged monitors for Right Cmd (54) / Right Shift (60) tracking
- CGEventTap for Space suppression during active voice mode
- Toggle-based mode activation (tap to enter, tap again to exit)
- Fallback to NSEvent monitor if CGEventTap unavailable

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 4: ContentView — Update Shortcut Handler

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/ContentView.swift:181,286-336`

- [ ] **Step 1: Update ContentView to use new ShortcutEvent API**

Replace `isShortcutSessionActive` state and `handleGlobalVoiceShortcut` with:

```swift
// In ContentView struct, replace:
//   @State private var isShortcutSessionActive = false
// with nothing (remove it)

// Replace handleGlobalVoiceShortcut entirely:
private func handleGlobalVoiceShortcut(_ event: KeyboardShortcutManager.ShortcutEvent) {
    let shortcutState = VoiceShortcutState.shared
    switch event.phase {
    case .modeActivated:
        VoiceTranscriber.shared.captureExternalApp()
        currentSection = .voiceToText
        shortcutState.activateMode(event.mode)
        VoiceTranscriber.shared.deliverTranscriptsDirectly = true

    case .spaceToggle:
        switch shortcutState.phase {
        case .ready:
            shortcutState.startRecording()
            Task {
                await VoiceTranscriber.shared.start(
                    type: config.transcriberType,
                    model: config.modelVariant,
                    language: config.voiceToTextLanguage
                )
            }
        case .recording:
            shortcutState.stopRecording()
            Task {
                await VoiceTranscriber.shared.stop()
            }
        case .idle:
            break
        }

    case .modeDeactivated:
        if shortcutState.phase == .recording {
            shortcutState.stopRecording()
            Task {
                await VoiceTranscriber.shared.stop()
            }
        }
        // endSession triggers post-processing in VoiceToTextView
        // via handleTranscriberStateChange → processShortcutPostProcessingIfNeeded
        _ = shortcutState.endSession()
    }
}
```

- [ ] **Step 2: Build to check ContentView compiles**

Run: `swift build 2>&1 | grep -i "error" | head -20`
Expected: Errors only in VoiceToTextView.swift (not ContentView)

- [ ] **Step 3: Commit**

```bash
git add Sources/VoiceFlowPro/Views/ContentView.swift
git commit -m "feat: update ContentView shortcut handler for mode/space events

Handle modeActivated, spaceToggle, and modeDeactivated events from
the rewritten KeyboardShortcutManager. Remove isShortcutSessionActive
state in favor of VoiceShortcutState phase tracking.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 5: VoiceToTextView — Wire Post-Processing, Language, and UI

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/VoiceToTextView.swift`

This is the largest change. It touches:
1. Remove preset-related `@State` properties and UI
2. Update `processShortcutPostProcessingIfNeeded` to use new `VoiceShortcutState` API
3. Wire language into AI Enhance calls
4. Update `shortcutModesSection` UI

- [ ] **Step 1: Remove preset-related state and helper functions**

Remove from VoiceToTextView:
- `@State private var dictationShortcutPreset`
- `@State private var assistantShortcutPreset`
- `dictationShortcutBinding` computed property
- `assistantShortcutBinding` computed property
- `isUsingCustomDictationShortcut` computed property
- `isUsingCustomAssistantShortcut` computed property
- `refreshShortcutPresetSelection()` function
- `handleShortcutPresetChange(...)` function

Remove from `onAppear`:
- `refreshShortcutPresetSelection()` call (line 210)

- [ ] **Step 2: Update processShortcutPostProcessingIfNeeded**

Replace the function with:

```swift
private func processShortcutPostProcessingIfNeeded() {
    guard transcriber.state == .idle else { return }
    let shortcutState = VoiceShortcutState.shared

    // Append segment text when a recording segment stops
    if let rawText = transcriber.session?.combinedText {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            shortcutState.appendSegmentText(trimmed)
        }
    }

    // If still in a mode session (ready phase, waiting for more segments), don't process yet
    guard shortcutState.activeMode == nil else {
        return
    }

    // Session ended — consume accumulated transcript
    let accumulated = shortcutState.accumulatedTranscript
    guard !accumulated.isEmpty else {
        restoreTranscriptDeliveryIfNeeded()
        return
    }

    // Determine mode from the last completed session
    // The mode was already cleared by endSession(), so we check pendingPostProcessing
    // Actually, we need to capture the mode before endSession clears it.
    // This requires a different approach: store the pending result.
    // Let's add a pendingResult property to VoiceShortcutState.
    
    // For now, use a simpler approach: ContentView calls endSession() which
    // returns (mode, transcript). We store it in VoiceShortcutState as pending.
    guard let pending = shortcutState.consumePendingResult() else {
        restoreTranscriptDeliveryIfNeeded()
        return
    }

    switch pending.mode {
    case .dictation:
        startDictationAutofix(transcript: pending.transcript)
    case .assistant:
        startAssistantCommand(transcript: pending.transcript)
    }
}
```

Wait — this reveals we need a `pendingResult` in VoiceShortcutState. Let me revise: `endSession()` stores the result, and `consumePendingResult()` returns and clears it. This is needed because the transcriber stop is async and `processShortcutPostProcessingIfNeeded` fires when the transcriber transitions to idle.

- [ ] **Step 3: Add pendingResult to VoiceShortcutState**

Add to `VoiceShortcutState`:

```swift
struct SessionResult {
    let mode: VoiceShortcutMode
    let transcript: String
}

private(set) var pendingResult: SessionResult?

func endSession() -> SessionResult? {
    guard let mode = activeMode else { return nil }
    let transcript = accumulatedTranscript
    activeMode = nil
    phase = .idle
    accumulatedTranscript = ""
    let result = SessionResult(mode: mode, transcript: transcript)
    pendingResult = result
    return result
}

func consumePendingResult() -> SessionResult? {
    defer { pendingResult = nil }
    return pendingResult
}
```

Update the existing `endSession` tests to also verify `pendingResult` and add a test for `consumePendingResult`.

- [ ] **Step 4: Simplify processShortcutPostProcessingIfNeeded**

```swift
private func processShortcutPostProcessingIfNeeded() {
    guard transcriber.state == .idle else { return }
    let shortcutState = VoiceShortcutState.shared

    // Append segment text when a recording segment stops
    if let rawText = transcriber.session?.combinedText {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            shortcutState.appendSegmentText(trimmed)
        }
    }

    // If still in a mode session, don't post-process yet
    guard shortcutState.activeMode == nil else { return }

    // Session ended — consume pending result
    guard let pending = shortcutState.consumePendingResult() else {
        restoreTranscriptDeliveryIfNeeded()
        return
    }

    guard !pending.transcript.isEmpty else {
        restoreTranscriptDeliveryIfNeeded()
        return
    }

    switch pending.mode {
    case .dictation:
        startDictationAutofix(transcript: pending.transcript)
    case .assistant:
        startAssistantCommand(transcript: pending.transcript)
    }
}
```

- [ ] **Step 5: Wire language into startDictationAutofix**

In `startDictationAutofix`, change:
```swift
// Before (line ~1291):
systemPrompt: AIPrompts.dictationSystemPrompt,
// After:
systemPrompt: String(format: AIPrompts.dictationSystemPrompt, AIPrompts.languageOutputRule(for: config.voiceToTextLanguage)),
```

- [ ] **Step 6: Wire language into startAssistantCommand**

In `startAssistantCommand`, change:
```swift
// Before (line ~1364):
systemPrompt: AIPrompts.assistantMode,
// After:
systemPrompt: AIPrompts.assistantMode + "\n\n" + AIPrompts.languageOutputRule(for: config.voiceToTextLanguage),
```

- [ ] **Step 7: Replace shortcutModesSection UI**

Replace the entire `shortcutModesSection` computed property with:

```swift
private var shortcutModesSection: some View {
    VStack(alignment: .leading, spacing: 12) {
        Text("Shortcut Modes")
            .font(.headline)

        HStack(alignment: .top, spacing: 0) {
            // Dictation Mode
            VStack(alignment: .leading, spacing: 8) {
                Label("Dictation", systemImage: "bolt.horizontal.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)

                Text("Right ⌘")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)

                Text("Tap to enter, Space to record. AI Enhance uses context to improve accuracy.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    alignedToggle("AI Enhance", binding: $config.voiceToTextDictationAIEnhanceEnabled)
                    alignedToggle("Clipboard Context", binding: $config.aiIncludeClipboardContext)
                    alignedToggle("Window Context", binding: $config.aiIncludeWindowContext)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)

            Spacer().frame(width: 12)

            // Assistant Mode
            VStack(alignment: .leading, spacing: 8) {
                Label("Assistant", systemImage: "wand.and.stars")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.purple)

                Text("Right ⌘ + Right ⇧")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(4)

                Text("Tap to enter, Space to record. AI Enhance uses context to improve responses.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 6) {
                    alignedToggle("AI Enhance", binding: $config.voiceToTextAssistantAIEnhanceEnabled)
                    alignedToggle("Clipboard Context", binding: $config.voiceToTextAssistantIncludeClipboardContext)
                    alignedToggle("Window Context", binding: $config.voiceToTextAssistantIncludeWindowContext)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }

        // Phase indicator
        modePhaseIndicator

        // Status Area
        if isPostProcessing || postProcessingStatusMessage != nil || assistantSourceSummary != nil
            || postProcessingErrorMessage != nil
        {
            // (keep existing status area code unchanged)
        }
    }
    .padding(16)
    .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    .cornerRadius(12)
    .overlay(
        RoundedRectangle(cornerRadius: 12)
            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
    )
}

@ViewBuilder
private var modePhaseIndicator: some View {
    let shortcutState = VoiceShortcutState.shared
    if let mode = shortcutState.activeMode {
        HStack(spacing: 8) {
            switch shortcutState.phase {
            case .ready:
                Image(systemName: "circle")
                    .foregroundStyle(.green)
                Text("\(mode == .dictation ? "Dictation" : "Assistant") ready — press Space to record")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .recording:
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse)
                Text("Recording… press Space to stop")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .idle:
                EmptyView()
            }
            Spacer()
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}
```

- [ ] **Step 8: Remove dictationShortcutView, assistantShortcutView, preset picker rows**

Remove:
- `dictationShortcutView` computed property
- `assistantShortcutView` computed property
- `dictationShortcutPickerRow` computed property
- `assistantShortcutPickerRow` computed property

These are no longer used since preset selection is removed.

- [ ] **Step 9: Update restoreTranscriptDeliveryIfNeeded**

Change from checking `shortcutState.isSessionActive` to checking `shortcutState.activeMode`:

```swift
private func restoreTranscriptDeliveryIfNeeded() {
    if VoiceShortcutState.shared.activeMode == nil {
        transcriber.deliverTranscriptsDirectly = true
    }
}
```

- [ ] **Step 10: Build the full project**

Run: `swift build 2>&1 | tail -30`
Expected: Clean build with no errors

- [ ] **Step 11: Commit**

```bash
git add Sources/VoiceFlowPro/Views/VoiceToTextView.swift \
       Sources/VoiceFlowPro/Utilities/VoiceShortcutState.swift
git commit -m "feat: update VoiceToTextView for new shortcut mode UX

- Remove preset picker UI and related state
- Replace shortcutModesSection with fixed Right ⌘ / Right ⌘+⇧ labels
- Add mode phase indicator (ready/recording)
- Wire language output rules into dictation and assistant AI calls
- Update post-processing to use segment accumulation from VoiceShortcutState

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 6: Integration Build + Test Sweep

**Files:**
- All modified files

- [ ] **Step 1: Run full swift build**

Run: `swift build 2>&1 | tail -30`
Expected: Clean build

- [ ] **Step 2: Run all existing tests**

Run: `swift test 2>&1 | tail -40`
Expected: All tests pass (existing + new)

- [ ] **Step 3: Run new tests specifically**

Run: `swift test --filter VoiceShortcutStateTests 2>&1 | tail -20`
Run: `swift test --filter AIPromptsLanguageRuleTests 2>&1 | tail -20`
Expected: All pass

- [ ] **Step 4: Run xcodebuild to verify app target compiles**

Run: `xcodebuild -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro build 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Final commit if any fixups needed**

```bash
git add -A
git commit -m "fix: resolve any build/test issues from shortcut mode redesign

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
