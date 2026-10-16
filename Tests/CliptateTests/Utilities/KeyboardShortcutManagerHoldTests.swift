import AppKit
import Foundation
import Testing

@testable import Cliptate

/// Tests for the Typeless-style shortcut flow:
///
/// - Hold modifier → auto-start recording after threshold
/// - Release modifier → end recording + end session (normal hold)
/// - Hold modifier + Space → enter hands-free mode (recording continues after release)
/// - Re-press modifier in hands-free → end session
/// - Esc → cancel session (escapePressed event, no output)
@Suite("KeyboardShortcutManager Typeless-style flow", .serialized)
@MainActor
struct KeyboardShortcutManagerHoldTests {

  @Test("tap activates and deactivates mode (no hold)")
  func tapToggle() async throws {
    let manager = KeyboardShortcutManager()
    var events: [KeyboardShortcutManager.ShortcutEvent] = []
    manager.bindShortcuts { events.append($0) }
    defer { manager.unbindShortcuts() }

    let dictKeyCode = manager.dictationPreset.keyInfo!.keyCode

    // Quick press (< hold threshold) → modeActivated
    manager.simulateModifierPress(keyCode: dictKeyCode, isDown: true)
    #expect(events.count == 1)
    #expect(events[0].phase == .modeActivated)
    #expect(events[0].mode == .dictation)

    // Quick release (before hold timer fires) → modeDeactivated
    manager.simulateModifierPress(keyCode: dictKeyCode, isDown: false)

    // Wait past hold threshold — no holdRecordingStarted should fire
    try await Task.sleep(for: .milliseconds(400))
    // Release before hold → immediate deactivation
    let deactivated = events.last { $0.phase == .modeDeactivated }
    #expect(deactivated != nil)
  }

  @Test("hold starts recording, release ends session")
  func holdAndRelease() async throws {
    let manager = KeyboardShortcutManager()
    var events: [KeyboardShortcutManager.ShortcutEvent] = []
    manager.bindShortcuts { events.append($0) }
    defer { manager.unbindShortcuts() }

    let dictKeyCode = manager.dictationPreset.keyInfo!.keyCode

    // Press and hold
    manager.simulateModifierPress(keyCode: dictKeyCode, isDown: true)
    #expect(events.count == 1)
    #expect(events[0].phase == .modeActivated)

    // Wait for hold threshold
    try await Task.sleep(for: .milliseconds(400))
    #expect(events.count == 2)
    #expect(events[1].phase == .holdRecordingStarted)
    #expect(events[1].mode == .dictation)

    // Release → holdRecordingEnded + modeDeactivated (session ends)
    manager.simulateModifierPress(keyCode: dictKeyCode, isDown: false)
    let holdEnded = events.contains { $0.phase == .holdRecordingEnded }
    let deactivated = events.contains { $0.phase == .modeDeactivated }
    #expect(holdEnded)
    #expect(deactivated)
    #expect(manager.activeMode == nil)
  }

  @Test("Space during hold enters hands-free, release keeps mode active")
  func spaceEntersHandsFree() async throws {
    let manager = KeyboardShortcutManager()
    var events: [KeyboardShortcutManager.ShortcutEvent] = []
    manager.bindShortcuts { events.append($0) }
    defer { manager.unbindShortcuts() }

    let dictKeyCode = manager.dictationPreset.keyInfo!.keyCode

    // Hold modifier → start recording
    manager.simulateModifierPress(keyCode: dictKeyCode, isDown: true)
    try await Task.sleep(for: .milliseconds(400))
    #expect(events.contains { $0.phase == .holdRecordingStarted })

    // Space → enters hands-free (spaceToggle emitted)
    manager.simulateSpacePress()
    #expect(events.contains { $0.phase == .spaceToggle })
    #expect(manager.isHandsFreeMode)

    // Release modifier → mode stays active (hands-free)
    manager.simulateModifierPress(keyCode: dictKeyCode, isDown: false)
    #expect(manager.activeMode == .dictation)

    // Re-press modifier → holdRecordingEnded + modeDeactivated (same as normal hold-release)
    events.removeAll()
    manager.simulateModifierPress(keyCode: dictKeyCode, isDown: true)
    #expect(events.count == 2)
    #expect(events[0].phase == .holdRecordingEnded)
    #expect(events[1].phase == .modeDeactivated)
    #expect(manager.activeMode == nil)
    #expect(!manager.isHandsFreeMode)
  }

  @Test("Escape cancels session during hold-recording")
  func escapeInHoldRecording() async throws {
    let manager = KeyboardShortcutManager()
    var events: [KeyboardShortcutManager.ShortcutEvent] = []
    manager.bindShortcuts { events.append($0) }
    defer { manager.unbindShortcuts() }

    let dictKeyCode = manager.dictationPreset.keyInfo!.keyCode

    manager.simulateModifierPress(keyCode: dictKeyCode, isDown: true)
    try await Task.sleep(for: .milliseconds(400))
    #expect(events.contains { $0.phase == .holdRecordingStarted })

    manager.simulateEscapePress()
    let escaped = events.last!
    #expect(escaped.phase == .escapePressed)
    #expect(escaped.mode == .dictation)
    #expect(manager.activeMode == nil)
  }

  @Test("Escape cancels session in hands-free mode")
  func escapeInHandsFree() async throws {
    let manager = KeyboardShortcutManager()
    var events: [KeyboardShortcutManager.ShortcutEvent] = []
    manager.bindShortcuts { events.append($0) }
    defer { manager.unbindShortcuts() }

    let dictKeyCode = manager.dictationPreset.keyInfo!.keyCode

    // Enter hands-free
    manager.simulateModifierPress(keyCode: dictKeyCode, isDown: true)
    try await Task.sleep(for: .milliseconds(400))
    manager.simulateSpacePress()
    #expect(manager.isHandsFreeMode)
    manager.simulateModifierPress(keyCode: dictKeyCode, isDown: false)
    #expect(manager.activeMode == .dictation)

    // Escape → cancel
    manager.simulateEscapePress()
    #expect(events.last!.phase == .escapePressed)
    #expect(manager.activeMode == nil)
    #expect(!manager.isHandsFreeMode)
  }

  @Test("Escape when no mode active does nothing")
  func escapeWithoutMode() async throws {
    let manager = KeyboardShortcutManager()
    var events: [KeyboardShortcutManager.ShortcutEvent] = []
    manager.bindShortcuts { events.append($0) }
    defer { manager.unbindShortcuts() }

    #expect(manager.activeMode == nil)
    manager.simulateEscapePress()
    #expect(events.isEmpty)
  }

  @Test("Fallback Escape cancels a modifier session and release does not deliver")
  func fallbackEscapeCancelsShortcut() throws {
    let manager = KeyboardShortcutManager()
    var events: [KeyboardShortcutManager.ShortcutEvent] = []
    manager.bindShortcuts { events.append($0) }
    defer { manager.unbindShortcuts() }
    let keyCode = manager.dictationPreset.keyInfo!.keyCode
    manager.simulateModifierPress(keyCode: keyCode, isDown: true)
    manager.simulateSpacePress()

    #expect(manager.processSpaceFallback(try keyEvent(keyCode: 53)))
    #expect(events.last?.phase == .escapePressed)
    #expect(manager.activeMode == nil)
    #expect(!manager.isHandsFreeMode)
    let countAfterCancel = events.count
    manager.simulateModifierPress(keyCode: keyCode, isDown: false)
    #expect(events.count == countAfterCancel)
  }

  @Test("Fallback Escape cancels UI dictation without an active shortcut mode")
  func fallbackEscapeCancelsUIDictation() throws {
    let manager = KeyboardShortcutManager()
    var events: [KeyboardShortcutManager.ShortcutEvent] = []
    manager.bindShortcuts { events.append($0) }
    defer { manager.unbindShortcuts() }
    manager.setDictationActive(true)

    #expect(manager.processSpaceFallback(try keyEvent(keyCode: 53)))
    #expect(events.count == 1)
    #expect(events.first?.phase == .escapePressed)
    #expect(events.first?.mode == .dictation)
    #expect(manager.processSpaceFallback(try keyEvent(keyCode: 53, isRepeat: true)))
    #expect(manager.processSpaceFallback(try keyEvent(keyCode: 53, type: .keyUp)))
    #expect(!manager.processSpaceFallback(try keyEvent(keyCode: 53)))
    #expect(events.count == 1)
  }

  @Test("Fallback leaves idle Escape, repeated Escape, and unrelated keys alone")
  func fallbackPassesUnrelatedEvents() throws {
    let manager = KeyboardShortcutManager()
    var events: [KeyboardShortcutManager.ShortcutEvent] = []
    manager.bindShortcuts { events.append($0) }
    defer { manager.unbindShortcuts() }
    #expect(!manager.processSpaceFallback(try keyEvent(keyCode: 53)))
    manager.setDictationActive(true)
    #expect(!manager.processSpaceFallback(try keyEvent(keyCode: 53, isRepeat: true)))
    #expect(!manager.processSpaceFallback(try keyEvent(keyCode: 49)))
    #expect(!manager.processSpaceFallback(try keyEvent(keyCode: 0)))
    #expect(events.isEmpty)
  }

  @Test("Event tap route consumes Escape for UI dictation from another app")
  func eventTapEscapeCancelsUIDictation() async throws {
    let manager = KeyboardShortcutManager()
    var events: [KeyboardShortcutManager.ShortcutEvent] = []
    manager.bindShortcuts { events.append($0) }
    defer { manager.unbindShortcuts() }
    #expect(!manager.processEscapeKey(isKeyDown: true, isRepeat: false))
    manager.setDictationActive(true)
    #expect(manager.processEscapeKey(isKeyDown: true, isRepeat: false))
    try await Task.sleep(for: .milliseconds(10))
    #expect(events.count == 1)
    #expect(events.first?.phase == .escapePressed)
    #expect(manager.processEscapeKey(isKeyDown: true, isRepeat: true))
    #expect(manager.processEscapeKey(isKeyDown: false, isRepeat: false))
    #expect(!manager.processEscapeKey(isKeyDown: true, isRepeat: false))
  }

  private func keyEvent(
    keyCode: UInt16, isRepeat: Bool = false, type: NSEvent.EventType = .keyDown
  ) throws -> NSEvent {
    try #require(NSEvent.keyEvent(
      with: type, location: .zero, modifierFlags: [], timestamp: 1,
      windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
      isARepeat: isRepeat, keyCode: keyCode
    ))
  }

  @Test("assistant mode via dictation key + Shift")
  func assistantMode() async throws {
    let manager = KeyboardShortcutManager()
    var events: [KeyboardShortcutManager.ShortcutEvent] = []
    manager.bindShortcuts { events.append($0) }
    defer { manager.unbindShortcuts() }

    let dictKeyCode = manager.dictationPreset.keyInfo!.keyCode

    manager.simulateModifierPress(keyCode: dictKeyCode, isDown: true)
    manager.simulateModifierPress(keyCode: 60, isDown: true)

    let lastActivated = events.last { $0.phase == .modeActivated }
    #expect(lastActivated?.mode == .assistant)

    // Wait for hold
    try await Task.sleep(for: .milliseconds(400))
    let holdEvent = events.last { $0.phase == .holdRecordingStarted }
    #expect(holdEvent?.mode == .assistant)
  }

  @Test("space monitor uses direct CGEventTap in regular dictation builds")
  func spaceMonitorUsesDirectEventTap() throws {
    let source = try keyboardShortcutManagerSource()

    #expect(source.contains("CGEvent.tapCreate("))
    #expect(source.contains("CFMachPortCreateRunLoopSource"))
    #expect(source.contains("eventTapRunLoopSource"))
    #expect(source.contains("AccessibilityGate.installKeyEventTap") == false)
  }

  private func keyboardShortcutManagerSource() throws -> String {
    let fileURL = URL(fileURLWithPath: #filePath)
    let projectRoot = fileURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    let sourceURL = projectRoot
      .appendingPathComponent("Sources/Cliptate/Utilities/KeyboardShortcutManager.swift")
    return try String(contentsOf: sourceURL, encoding: .utf8)
  }
}
