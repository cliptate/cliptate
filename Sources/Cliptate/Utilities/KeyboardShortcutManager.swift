import AppKit
import Foundation
import KeyboardShortcuts
import os.log

import CoreGraphics

extension KeyboardShortcuts.Name {
  public static let dictationVoiceTranscription = Self("dictationVoiceTranscription")
  public static let assistantVoiceTranscription = Self("assistantVoiceTranscription")
}

@MainActor
public final class KeyboardShortcutManager: ObservableObject {
  public static let shared = KeyboardShortcutManager()

  public struct ShortcutEvent {
    public enum Phase {
      case modeActivated
      case modeDeactivated
      case spaceToggle
      case holdRecordingStarted
      case holdRecordingEnded
      case escapePressed
    }
    public let phase: Phase
    public let mode: VoiceShortcutMode
  }

  private let logger = Logger(subsystem: "com.Cliptate", category: "KeyboardShortcuts")
  private var shortcutHandler: ((ShortcutEvent) -> Void)?

  // Configurable presets (V3 keys to pick up new Right Cmd default)
  private let dictationPresetDefaultsKey = "VoiceToTextDictationPresetV3"
  private let assistantPresetDefaultsKey = "VoiceToTextAssistantPresetV3"
  @Published private(set) var dictationPreset: VoiceToggleShortcutPreset
  @Published private(set) var assistantPreset: VoiceToggleShortcutPreset

  // Modifier tracking
  private var isDictationKeyHeld = false
  private var isShiftHeld = false
  private(set) var activeMode: VoiceShortcutMode?

  // Thread-safe snapshot for CGEventTap callback (runs on arbitrary thread)
  private struct EventSnapshot {
    var mode: VoiceShortcutMode?
    var isDictationActive = false
    var isEscapeHeld = false
  }
  private let _snapshotLock = OSAllocatedUnfairLock(initialState: EventSnapshot())

  // Event monitors
  private var flagsLocalMonitor: Any?
  private var flagsGlobalMonitor: Any?
  private var eventTap: CFMachPort?
  private var eventTapRunLoopSource: CFRunLoopSource?
  private var spaceFallbackGlobalMonitor: Any?
  private var spaceFallbackLocalMonitor: Any?

  // Dedup
  private var lastFlagsEventTimestamp: TimeInterval = 0

  // Hold-to-record
  private var holdTimer: DispatchSourceTimer?
  private var isHoldRecording = false
  private(set) var isHandsFreeMode = false
  static let holdThreshold: TimeInterval = 0.3

  init() {
    // Migrate from V2 keys: preserve non-Fn custom values, replace Fn with new default
    let oldDictationKey = "VoiceToTextDictationPresetV2"
    let oldAssistantKey = "VoiceToTextAssistantPresetV2"

    if let raw = UserDefaults.standard.string(forKey: dictationPresetDefaultsKey),
       let preset = VoiceToggleShortcutPreset(rawValue: raw) {
      dictationPreset = preset
    } else if let oldRaw = UserDefaults.standard.string(forKey: oldDictationKey),
              let oldPreset = VoiceToggleShortcutPreset(rawValue: oldRaw),
              oldPreset != .function {
      // Preserve non-Fn custom value from V2
      dictationPreset = oldPreset
      UserDefaults.standard.set(oldPreset.rawValue, forKey: dictationPresetDefaultsKey)
    } else {
      dictationPreset = .defaultDictationPreset
    }

    if let raw = UserDefaults.standard.string(forKey: assistantPresetDefaultsKey),
       let preset = VoiceToggleShortcutPreset(rawValue: raw) {
      assistantPreset = preset
    } else if let oldRaw = UserDefaults.standard.string(forKey: oldAssistantKey),
              let oldPreset = VoiceToggleShortcutPreset(rawValue: oldRaw),
              oldPreset != .function {
      assistantPreset = oldPreset
      UserDefaults.standard.set(oldPreset.rawValue, forKey: assistantPresetDefaultsKey)
    } else {
      assistantPreset = .defaultAssistantPreset
    }
  }

  private func setActiveMode(_ mode: VoiceShortcutMode?) {
    activeMode = mode
    _snapshotLock.withLock { $0.mode = mode }
  }

  /// Includes recordings started from the UI, which have no modifier-key session.
  func setDictationActive(_ isActive: Bool) {
    _snapshotLock.withLock { $0.isDictationActive = isActive }
  }

  // MARK: - Preset Management

  /// Update the preset for a given mode and persist to UserDefaults.
  public func updatePreset(_ preset: VoiceToggleShortcutPreset, for mode: VoiceShortcutMode) {
    logger.notice("Updating preset for \(String(describing: mode)): \(preset.displayName) (keyCode: \(String(describing: preset.keyInfo?.keyCode)))")
    switch mode {
    case .dictation:
      dictationPreset = preset
      UserDefaults.standard.set(preset.rawValue, forKey: dictationPresetDefaultsKey)
    case .assistant:
      assistantPreset = preset
      UserDefaults.standard.set(preset.rawValue, forKey: assistantPresetDefaultsKey)
    }
    // Reset state to avoid stale modifier tracking
    isDictationKeyHeld = false
    isShiftHeld = false
    // Re-install monitors with new key bindings
    if shortcutHandler != nil {
      installFlagsMonitors()
    }
  }

  /// The current preset for a given mode.
  public func currentPreset(for mode: VoiceShortcutMode) -> VoiceToggleShortcutPreset {
    switch mode {
    case .dictation: return dictationPreset
    case .assistant: return assistantPreset
    }
  }

  /// Display label for the current shortcut (e.g., "Fn" or "Fn + Shift").
  public func shortcutLabel(for mode: VoiceShortcutMode) -> String {
    let preset = currentPreset(for: mode)
    switch mode {
    case .dictation:
      return preset.displayName
    case .assistant:
      return "\(preset.displayName) + Shift"
    }
  }

  public func registerDefaultShortcuts() {
    // No-op: presets are loaded from UserDefaults in init.
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
    cancelHoldTimer()
    shortcutHandler = nil
    isDictationKeyHeld = false
    isShiftHeld = false
    isHoldRecording = false
    isHandsFreeMode = false
    setActiveMode(nil)
    _snapshotLock.withLock { $0.isEscapeHeld = false }
  }

  /// Test-only entry point to simulate modifier key presses.
  func simulateModifierPress(keyCode: UInt16, isDown: Bool) {
    let dictKeyCode = dictationPreset.keyInfo?.keyCode

    if keyCode == dictKeyCode {
      isDictationKeyHeld = isDown
    } else if keyCode == 60 || keyCode == 56 {
      isShiftHeld = isDown
    }

    if isDown {
      handleModeKeyPressed()
    } else {
      handleModeKeyReleased()
    }
  }

  /// Test-only entry point to simulate Escape key press.
  func simulateEscapePress() {
    handleEscapePressed()
  }

  /// Test-only entry point to simulate Space key press (enters hands-free mode).
  func simulateSpacePress() {
    guard let mode = activeMode else { return }
    isHandsFreeMode = true
    emitEvent(ShortcutEvent(phase: .spaceToggle, mode: mode))
  }

  // MARK: - Flags Monitors

  private func installFlagsMonitors() {
    removeFlagsMonitors()

    let handler: (NSEvent) -> NSEvent? = { [weak self] event in
      self?.processFlagsChanged(event)
      return event
    }

    flagsLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: handler)

    flagsGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) {
      [weak self] event in
      self?.processFlagsChanged(event)
    }
    logger.notice("Installed local/global flags monitors for \(self.dictationPreset.displayName) / \(self.assistantPreset.displayName) + Shift")
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
    logger.debug("flagsChanged: keyCode=\(keyCode), modifiers=\(event.modifierFlags.rawValue), dictPreset=\(self.dictationPreset.displayName)(keyCode:\(String(describing: self.dictationPreset.keyInfo?.keyCode)))")

    // Check dictation key
    if let dictInfo = dictationPreset.keyInfo, keyCode == dictInfo.keyCode {
      let nowHeld = event.modifierFlags.contains(dictInfo.flag)
      let wasHeld = isDictationKeyHeld
      isDictationKeyHeld = nowHeld

      if nowHeld && !wasHeld {
        handleModeKeyPressed()
      } else if !nowHeld && wasHeld {
        handleModeKeyReleased()
      }
      return
    }

    // Check shift key (for assistant combo) — Right Shift (60) or Left Shift (56)
    if keyCode == 60 || keyCode == 56 {
      let nowHeld = event.modifierFlags.contains(.shift)
      let wasHeld = isShiftHeld
      isShiftHeld = nowHeld

      if nowHeld && !wasHeld && isDictationKeyHeld {
        handleModeKeyPressed()
      } else if !nowHeld && wasHeld {
        handleModeKeyReleased()
      }
      return
    }
  }

  private func handleModeKeyPressed() {
    let targetMode: VoiceShortcutMode =
      (isDictationKeyHeld && isShiftHeld) ? .assistant : .dictation

    if activeMode == nil {
      // Fresh activation
      setActiveMode(targetMode)
      emitEvent(ShortcutEvent(phase: .modeActivated, mode: targetMode))
      startHoldTimer(for: targetMode)
    } else if activeMode == targetMode {
      if isHandsFreeMode {
        // Re-press modifier in hands-free → same flow as normal hold-release:
        // emit holdRecordingEnded first (stops recording), then modeDeactivated (ends session)
        cancelHoldTimer()
        let mode = activeMode!
        isHoldRecording = false
        isHandsFreeMode = false
        emitEvent(ShortcutEvent(phase: .holdRecordingEnded, mode: mode))
        setActiveMode(nil)
        emitEvent(ShortcutEvent(phase: .modeDeactivated, mode: mode))
      } else if !isHoldRecording {
        // Toggle off (quick double-tap before hold fires)
        cancelHoldTimer()
        let mode = activeMode!
        setActiveMode(nil)
        emitEvent(ShortcutEvent(phase: .modeDeactivated, mode: mode))
      }
      // If hold-recording is active, ignore re-press of same key
    } else {
      // Switch mode
      cancelHoldTimer()
      let oldMode = activeMode!
      setActiveMode(nil)
      isHoldRecording = false
      isHandsFreeMode = false
      emitEvent(ShortcutEvent(phase: .modeDeactivated, mode: oldMode))
      setActiveMode(targetMode)
      emitEvent(ShortcutEvent(phase: .modeActivated, mode: targetMode))
      startHoldTimer(for: targetMode)
    }
  }

  private func handleModeKeyReleased() {
    cancelHoldTimer()

    guard let mode = activeMode else { return }

    if isHandsFreeMode {
      // Hands-free mode: modifier release is a no-op — session continues
      return
    }

    guard isHoldRecording else {
      // Quick tap release (no hold) → deactivate mode
      setActiveMode(nil)
      isHandsFreeMode = false
      emitEvent(ShortcutEvent(phase: .modeDeactivated, mode: mode))
      return
    }

    // Normal hold-release: end recording + end session
    isHoldRecording = false
    emitEvent(ShortcutEvent(phase: .holdRecordingEnded, mode: mode))
    setActiveMode(nil)
    emitEvent(ShortcutEvent(phase: .modeDeactivated, mode: mode))
  }

  /// Handles Escape key: cancels the entire mode session.
  private func handleEscapePressed() {
    let snapshot = _snapshotLock.withLock { $0 }
    guard snapshot.mode != nil || snapshot.isDictationActive else { return }
    cancelHoldTimer()
    let mode = snapshot.mode ?? .dictation
    isHoldRecording = false
    isHandsFreeMode = false
    setActiveMode(nil)
    setDictationActive(false)
    emitEvent(ShortcutEvent(phase: .escapePressed, mode: mode))
  }

  // MARK: - Hold Timer

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

  // MARK: - Space and Escape Monitor (CGEventTap with fallback)

  private enum EscapeAction {
    case passThrough
    case consume
    case cancel
  }

  /// Consume the entire cancelling keystroke, even after the session becomes idle.
  private nonisolated func escapeAction(isKeyDown: Bool, isRepeat: Bool) -> EscapeAction {
    _snapshotLock.withLock { snapshot in
      if snapshot.isEscapeHeld {
        if !isKeyDown { snapshot.isEscapeHeld = false }
        return .consume
      }
      guard isKeyDown, !isRepeat,
            snapshot.mode != nil || snapshot.isDictationActive else { return .passThrough }
      snapshot.isEscapeHeld = true
      return .cancel
    }
  }

  /// Route Escape from an event-tap callback without touching main-actor state synchronously.
  nonisolated func processEscapeKey(isKeyDown: Bool, isRepeat: Bool) -> Bool {
    switch escapeAction(isKeyDown: isKeyDown, isRepeat: isRepeat) {
    case .passThrough:
      return false
    case .consume:
      return true
    case .cancel:
      DispatchQueue.main.async { [weak self] in
        self?.handleEscapePressed()
      }
      return true
    }
  }

  private func installSpaceMonitor() {
    removeSpaceMonitor()

    let mask: CGEventMask =
      (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

    let unmanagedSelf = Unmanaged.passUnretained(self)

    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: mask,
        callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
          guard let refcon else { return Unmanaged.passUnretained(event) }
          let manager = Unmanaged<KeyboardShortcutManager>.fromOpaque(refcon)
            .takeUnretainedValue()
          return manager.handleCGEvent(type: type, event: event)
        },
        userInfo: unmanagedSelf.toOpaque()
      )
    else {
      logger.warning(
        "CGEventTap creation failed — falling back to NSEvent monitor (global keys will not be suppressed)"
      )
      installSpaceFallbackMonitor(includeGlobalMonitor: true)
      return
    }

    eventTap = tap
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    eventTapRunLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)

    logger.notice("Installed CGEventTap for Space and Escape key interception")
  }

  private nonisolated func handleCGEvent(
    type: CGEventType,
    event: CGEvent
  ) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
      DispatchQueue.main.async { [weak self] in
        guard let self, let tap = self.eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
      }
      return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown || type == .keyUp else {
      return Unmanaged.passUnretained(event)
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

    // Thread-safe read via lock (no GCD sync to avoid main-thread deadlock)
    let snapshot = _snapshotLock.withLock { $0 }
    let mode = snapshot.mode

    // Escape also cancels recordings started from the UI.
    if keyCode == 53 {
      let shouldConsume = processEscapeKey(
        isKeyDown: type == .keyDown,
        isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
      )
      return shouldConsume ? nil : Unmanaged.passUnretained(event)
    }

    guard keyCode == 49 else {
      return Unmanaged.passUnretained(event)
    }

    guard let mode else {
      return Unmanaged.passUnretained(event)
    }

    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat)
    if isRepeat != 0 {
      return nil
    }

    if type == .keyDown {
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.isHandsFreeMode = true
        self.emitEvent(ShortcutEvent(phase: .spaceToggle, mode: mode))
      }
    }

    return nil
  }

  private func installSpaceFallbackMonitor(includeGlobalMonitor: Bool) {
    let handler: (NSEvent) -> NSEvent? = { [weak self] event in
      self?.processSpaceFallback(event) == true ? nil : event
    }

    spaceFallbackLocalMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.keyDown, .keyUp], handler: handler)

    if includeGlobalMonitor {
      spaceFallbackGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) {
        [weak self] event in
        self?.processSpaceFallback(event)
      }
    }

    logger.notice("Installed NSEvent fallback monitors for Space and Escape (global events cannot be suppressed)")
  }

  /// Returns whether the local monitor should consume the event.
  @discardableResult
  func processSpaceFallback(_ event: NSEvent) -> Bool {
    guard event.type == .keyDown || event.type == .keyUp else { return false }
    if event.keyCode == 53 {
      switch escapeAction(isKeyDown: event.type == .keyDown, isRepeat: event.isARepeat) {
      case .passThrough: return false
      case .consume: return true
      case .cancel:
        handleEscapePressed()
        return true
      }
    }
    guard event.type == .keyDown, !event.isARepeat,
          event.keyCode == 49, let mode = activeMode else { return false }
    isHandsFreeMode = true
    emitEvent(ShortcutEvent(phase: .spaceToggle, mode: mode))
    return false
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
