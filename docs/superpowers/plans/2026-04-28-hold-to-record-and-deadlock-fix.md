# Hold-to-Record & CGEventTap Deadlock Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the `DispatchQueue.main.sync` deadlock in CGEventTap and add hold-to-record so long-pressing Right ⌘ or Right ⌘+Right ⇧ immediately starts recording.

**Architecture:** Replace GCD sync with `os_unfair_lock`-protected snapshot for thread-safe mode reads. Add hold timer (0.3s) to discriminate tap vs hold on modifier keys. Emit new `holdRecordingStarted`/`holdRecordingEnded` events.

**Tech Stack:** Swift, CoreGraphics CGEventTap, os_unfair_lock, Swift Testing

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `Sources/VoiceFlowPro/Utilities/KeyboardShortcutManager.swift` | Modify | Fix deadlock, add hold timer, emit hold events |
| `Sources/VoiceFlowPro/Views/ContentView.swift` | Modify | Handle `holdRecordingStarted`/`holdRecordingEnded` events |
| `Sources/VoiceFlowProTests/Utilities/KeyboardShortcutManagerHoldTests.swift` | Create | Tests for hold timer logic |
| `Package.swift` | Modify | Add new test file to explicit sources list |

---

### Task 1: Fix CGEventTap Deadlock (Thread-Safe Snapshot)

**Files:**
- Modify: `Sources/VoiceFlowPro/Utilities/KeyboardShortcutManager.swift`

- [ ] **Step 1: Add lock-protected snapshot properties**

Add these properties to `KeyboardShortcutManager` (after existing properties, around line 43):

```swift
// Thread-safe snapshot for CGEventTap callback
private let _snapshotLock = OSAllocatedUnfairLock(initialState: VoiceShortcutMode?.none)
```

- [ ] **Step 2: Create helper to update snapshot**

Add a private method that updates both `activeMode` and the snapshot:

```swift
private func setActiveMode(_ mode: VoiceShortcutMode?) {
  activeMode = mode
  _snapshotLock.withLock { $0 = mode }
}
```

- [ ] **Step 3: Replace all `activeMode =` assignments with `setActiveMode()`**

In `unbindShortcuts()`, change `activeMode = nil` to `setActiveMode(nil)`.
In `handleModeKeyPressed()`, change all `activeMode = ...` / `activeMode = nil` to `setActiveMode(...)` / `setActiveMode(nil)`.

- [ ] **Step 4: Replace `DispatchQueue.main.sync` in `handleCGEvent` with lock read**

Replace lines 207-211:

```swift
// OLD (deadlocks on main thread):
// var mode: VoiceShortcutMode?
// DispatchQueue.main.sync { [weak self] in
//   mode = self?.activeMode
// }

// NEW (lock-based, safe from any thread):
let mode = _snapshotLock.withLock { $0 }
```

- [ ] **Step 5: Build and verify fix**

Run: `swift build 2>&1 | grep "error:"`
Expected: No errors. The deadlock is eliminated.

- [ ] **Step 6: Commit**

```bash
git add Sources/VoiceFlowPro/Utilities/KeyboardShortcutManager.swift
git commit -m "fix: replace DispatchQueue.main.sync with lock in CGEventTap callback

The CGEventTap callback can run on the main thread when the run loop
source is on the main run loop. DispatchQueue.main.sync from the main
thread deadlocks (EXC_BREAKPOINT). Use OSAllocatedUnfairLock instead.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 2: Write Failing Tests for Hold Timer Logic

**Files:**
- Create: `Sources/VoiceFlowProTests/Utilities/KeyboardShortcutManagerHoldTests.swift`
- Modify: `Package.swift` (add to sources list)

- [ ] **Step 1: Write the test file**

```swift
import Testing

@testable import VoiceFlowPro

@Suite("KeyboardShortcutManager hold detection")
@MainActor
struct KeyboardShortcutManagerHoldTests {
  // We test via ShortcutEvent emissions. The manager exposes
  // `activeMode` and accepts `bindShortcuts(onEvent:)`.
  // We simulate modifier changes via the internal method we'll expose for testing.

  @Test("tap emits modeActivated only, no holdRecordingStarted")
  func tapEmitsModeActivatedOnly() async throws {
    let manager = KeyboardShortcutManager.shared
    var events: [KeyboardShortcutManager.ShortcutEvent] = []
    manager.bindShortcuts { events.append($0) }
    defer { manager.unbindShortcuts() }

    // Simulate: press Right Cmd
    manager.simulateModifierPress(keyCode: 54, isDown: true)
    // Should immediately get modeActivated
    #expect(events.count == 1)
    #expect(events[0].phase == .modeActivated)
    #expect(events[0].mode == .dictation)

    // Simulate: release Right Cmd quickly (before hold threshold)
    manager.simulateModifierPress(keyCode: 54, isDown: false)

    // Wait a bit to ensure no holdRecordingStarted fires
    try await Task.sleep(for: .milliseconds(400))
    // Should still be just 1 event (modeActivated) — no hold events
    #expect(events.count == 1)
  }

  @Test("hold emits modeActivated then holdRecordingStarted")
  func holdEmitsHoldRecordingStarted() async throws {
    let manager = KeyboardShortcutManager.shared
    var events: [KeyboardShortcutManager.ShortcutEvent] = []
    manager.bindShortcuts { events.append($0) }
    defer { manager.unbindShortcuts() }

    // Simulate: press Right Cmd
    manager.simulateModifierPress(keyCode: 54, isDown: true)
    #expect(events.count == 1)
    #expect(events[0].phase == .modeActivated)

    // Wait for hold threshold to fire
    try await Task.sleep(for: .milliseconds(400))
    #expect(events.count == 2)
    #expect(events[1].phase == .holdRecordingStarted)
    #expect(events[1].mode == .dictation)
  }

  @Test("release after hold emits holdRecordingEnded")
  func releaseAfterHoldEmitsEnded() async throws {
    let manager = KeyboardShortcutManager.shared
    var events: [KeyboardShortcutManager.ShortcutEvent] = []
    manager.bindShortcuts { events.append($0) }
    defer { manager.unbindShortcuts() }

    manager.simulateModifierPress(keyCode: 54, isDown: true)
    try await Task.sleep(for: .milliseconds(400))
    #expect(events.count == 2) // modeActivated + holdRecordingStarted

    // Release
    manager.simulateModifierPress(keyCode: 54, isDown: false)
    #expect(events.count == 3)
    #expect(events[2].phase == .holdRecordingEnded)
    #expect(events[2].mode == .dictation)
    #expect(manager.activeMode == nil)
  }

  @Test("hold Right Cmd + Right Shift triggers assistant mode")
  func holdAssistantMode() async throws {
    let manager = KeyboardShortcutManager.shared
    var events: [KeyboardShortcutManager.ShortcutEvent] = []
    manager.bindShortcuts { events.append($0) }
    defer { manager.unbindShortcuts() }

    // Press Right Cmd first
    manager.simulateModifierPress(keyCode: 54, isDown: true)
    // Then press Right Shift while Cmd held — this cancels dictation and activates assistant
    manager.simulateModifierPress(keyCode: 60, isDown: true)

    // Find the last modeActivated event
    let lastActivated = events.last { $0.phase == .modeActivated }
    #expect(lastActivated?.mode == .assistant)

    // Wait for hold threshold
    try await Task.sleep(for: .milliseconds(400))
    let holdEvent = events.last { $0.phase == .holdRecordingStarted }
    #expect(holdEvent?.mode == .assistant)
  }
}
```

- [ ] **Step 2: Add test file to Package.swift**

Add `"Utilities/KeyboardShortcutManagerHoldTests.swift"` to the test sources list after line 96 (after `VoiceShortcutStateTests.swift`).

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter KeyboardShortcutManagerHoldTests 2>&1 | tail -20`
Expected: Compilation errors — `simulateModifierPress` doesn't exist, `holdRecordingStarted`/`holdRecordingEnded` phases don't exist.

- [ ] **Step 4: Commit failing tests**

```bash
git add Sources/VoiceFlowProTests/Utilities/KeyboardShortcutManagerHoldTests.swift Package.swift
git commit -m "test(red): add hold detection tests for KeyboardShortcutManager

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 3: Implement Hold Timer Logic (GREEN)

**Files:**
- Modify: `Sources/VoiceFlowPro/Utilities/KeyboardShortcutManager.swift`

- [ ] **Step 1: Add new event phases**

In `ShortcutEvent.Phase`, add:

```swift
case holdRecordingStarted
case holdRecordingEnded
```

- [ ] **Step 2: Add hold-tracking properties**

```swift
private var holdTimer: DispatchSourceTimer?
private var isHoldRecording = false
private static let holdThreshold: TimeInterval = 0.3
```

- [ ] **Step 3: Add `simulateModifierPress` for testability**

```swift
/// Test-only entry point to simulate modifier key presses.
func simulateModifierPress(keyCode: UInt16, isDown: Bool) {
  if keyCode == 54 {
    isRightCmdHeld = isDown
  } else if keyCode == 60 {
    isRightShiftHeld = isDown
  }

  if isDown {
    handleModeKeyPressed()
  } else {
    handleModeKeyReleased()
  }
}
```

- [ ] **Step 4: Refactor `processFlagsChanged` to call `handleModeKeyReleased` on key-up**

Update `processFlagsChanged` so that when a modifier key is released, it calls `handleModeKeyReleased()`:

```swift
private func processFlagsChanged(_ event: NSEvent) {
  guard event.type == .flagsChanged else { return }
  guard event.timestamp != lastFlagsEventTimestamp else { return }
  lastFlagsEventTimestamp = event.timestamp

  let keyCode = event.keyCode

  if keyCode == 54 {
    let nowHeld = event.modifierFlags.contains(.command)
    let wasHeld = isRightCmdHeld
    isRightCmdHeld = nowHeld

    if nowHeld && !wasHeld {
      handleModeKeyPressed()
    } else if !nowHeld && wasHeld {
      handleModeKeyReleased()
    }
    return
  }

  if keyCode == 60 {
    let nowHeld = event.modifierFlags.contains(.shift)
    let wasHeld = isRightShiftHeld
    isRightShiftHeld = nowHeld

    if nowHeld && !wasHeld && isRightCmdHeld {
      handleModeKeyPressed()
    } else if !nowHeld && wasHeld {
      handleModeKeyReleased()
    }
    return
  }
}
```

- [ ] **Step 5: Rewrite `handleModeKeyPressed` with hold timer**

```swift
private func handleModeKeyPressed() {
  let targetMode: VoiceShortcutMode =
    (isRightCmdHeld && isRightShiftHeld) ? .assistant : .dictation

  if activeMode == nil {
    // Fresh activation
    setActiveMode(targetMode)
    emitEvent(ShortcutEvent(phase: .modeActivated, mode: targetMode))
    startHoldTimer(for: targetMode)
  } else if activeMode == targetMode {
    // Toggle off (only if not hold-recording — tap in ready state)
    if !isHoldRecording {
      cancelHoldTimer()
      let mode = activeMode!
      setActiveMode(nil)
      emitEvent(ShortcutEvent(phase: .modeDeactivated, mode: mode))
    }
  } else {
    // Switch mode
    cancelHoldTimer()
    let oldMode = activeMode!
    setActiveMode(nil)
    isHoldRecording = false
    emitEvent(ShortcutEvent(phase: .modeDeactivated, mode: oldMode))
    setActiveMode(targetMode)
    emitEvent(ShortcutEvent(phase: .modeActivated, mode: targetMode))
    startHoldTimer(for: targetMode)
  }
}
```

- [ ] **Step 6: Implement `handleModeKeyReleased`**

```swift
private func handleModeKeyReleased() {
  cancelHoldTimer()

  guard isHoldRecording, let mode = activeMode else { return }

  // End hold-recording session
  isHoldRecording = false
  setActiveMode(nil)
  emitEvent(ShortcutEvent(phase: .holdRecordingEnded, mode: mode))
}
```

- [ ] **Step 7: Implement hold timer helpers**

```swift
private func startHoldTimer(for mode: VoiceShortcutMode) {
  cancelHoldTimer()
  let timer = DispatchSource.makeTimerSource(queue: .main)
  timer.schedule(deadline: .now() + Self.holdThreshold)
  timer.setEventHandler { [weak self] in
    guard let self else { return }
    self.isHoldRecording = true
    self.emitEvent(ShortcutEvent(phase: .holdRecordingStarted, mode: mode))
  }
  holdTimer = timer
  timer.resume()
}

private func cancelHoldTimer() {
  holdTimer?.cancel()
  holdTimer = nil
}
```

- [ ] **Step 8: Update `unbindShortcuts` to cancel hold timer**

Add `cancelHoldTimer()` and `isHoldRecording = false` to `unbindShortcuts()`.

- [ ] **Step 9: Run tests**

Run: `swift test --filter KeyboardShortcutManagerHoldTests 2>&1 | tail -20`
Expected: All 4 tests pass.

- [ ] **Step 10: Run full test suite**

Run: `swift test 2>&1 | tail -5`
Expected: All tests pass, exit code 0.

- [ ] **Step 11: Commit**

```bash
git add Sources/VoiceFlowPro/Utilities/KeyboardShortcutManager.swift
git commit -m "feat: add hold-to-record with tap/hold discrimination

Hold Right ⌘ (0.3s+) starts dictation recording immediately.
Hold Right ⌘ + Right ⇧ starts assistant recording immediately.
Quick tap still toggles mode for Space-based recording.

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

---

### Task 4: Wire Hold Events in ContentView

**Files:**
- Modify: `Sources/VoiceFlowPro/Views/ContentView.swift`

- [ ] **Step 1: Add `holdRecordingStarted` handler**

In `handleGlobalVoiceShortcut`, add a new case:

```swift
case .holdRecordingStarted:
  shortcutState.startRecording()
  Task {
    await VoiceTranscriber.shared.start(
      type: config.transcriberType,
      model: config.modelVariant,
      language: config.voiceToTextLanguage
    )
  }
```

- [ ] **Step 2: Add `holdRecordingEnded` handler**

```swift
case .holdRecordingEnded:
  if shortcutState.phase == .recording {
    shortcutState.stopRecording()
    Task {
      await VoiceTranscriber.shared.stop()
    }
  }
  _ = shortcutState.endSession()
```

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | grep "error:"`
Expected: No errors.

- [ ] **Step 4: Run full tests**

Run: `swift test 2>&1 | tail -5`
Expected: All tests pass.

- [ ] **Step 5: Verify Xcode build**

Run: `xcodebuild -project Sources/VoiceFlowPro.xcodeproj -scheme VoicePinkPro build 2>&1 | tail -3`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Sources/VoiceFlowPro/Views/ContentView.swift
git commit -m "feat: wire holdRecordingStarted/holdRecordingEnded in ContentView

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```
