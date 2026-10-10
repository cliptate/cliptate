import AppKit
import Foundation
import KeyboardShortcuts
import os.log

#if !APP_STORE
  import CoreGraphics
#endif

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
  private let _snapshotLock = OSAllocatedUnfairLock(initialState: VoiceShortcutMode?.none)

  // Event monitors
  private var flagsLocalMonitor: Any?
  private var flagsGlobalMonitor: Any?
  #if !APP_STORE
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
  #endif
  private var spaceFallbackGlobalMonitor: Any?
  private var spaceFallbackLocalMonitor: Any?

  // Dedup
  private var lastFlagsEventTimestamp: TimeInterval = 0

  // Hold-to-record
  private var holdTimer: DispatchSourceTimer?
  private var isHoldRecording = false
  private(set) var isHandsFreeMode = false
  static let holdThreshold: TimeInterval = 0.3

  private init() {
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
    _snapshotLock.withLock { $0 = mode }
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

    #if !APP_STORE
      flagsGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) {
        [weak self] event in
        self?.processFlagsChanged(event)
      }
      logger.notice("Installed local/global flags monitors for \(self.dictationPreset.displayName) / \(self.assistantPreset.displayName) + Shift")
    #else
      logger.notice("Installed local flags monitor for App Store build")
    #endif
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
    cancelHoldTimer()
    guard let mode = activeMode else { return }
    isHoldRecording = false
    isHandsFreeMode = false
    setActiveMode(nil)
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

  // MARK: - Space Monitor (CGEventTap with fallback)

  private func installSpaceMonitor() {
    removeSpaceMonitor()

    #if APP_STORE
      installSpaceFallbackMonitor(includeGlobalMonitor: false)
    #else
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
            return manager.handleCGEvent(proxy: proxy, type: type, event: event)
          },
          userInfo: unmanagedSelf.toOpaque()
        )
      else {
        logger.warning(
          "CGEventTap creation failed — falling back to NSEvent monitor (Space will not be suppressed)"
        )
        installSpaceFallbackMonitor(includeGlobalMonitor: true)
        return
      }

      eventTap = tap
      let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
      eventTapRunLoopSource = source
      CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
      CGEvent.tapEnable(tap: tap, enable: true)

      logger.notice("Installed CGEventTap for Space key interception")
    #endif
  }

  #if !APP_STORE
  private nonisolated func handleCGEvent(
    proxy: CGEventTapProxy,
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
    let mode = _snapshotLock.withLock { $0 }

    // Escape key (keyCode 53) — end session when mode is active
    if keyCode == 53, let _ = mode {
      if type == .keyDown {
        DispatchQueue.main.async { [weak self] in
          self?.handleEscapePressed()
        }
      }
      return nil  // Suppress Escape while mode is active
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
  #endif

  private func installSpaceFallbackMonitor(includeGlobalMonitor: Bool) {
    let handler: (NSEvent) -> NSEvent? = { [weak self] event in
      self?.processSpaceFallback(event)
      return event
    }

    spaceFallbackLocalMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.keyDown], handler: handler)

    #if !APP_STORE
      if includeGlobalMonitor {
        spaceFallbackGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) {
          [weak self] event in
          self?.processSpaceFallback(event)
        }
      }
    #endif

    logger.notice("Installed NSEvent fallback monitors for Space (no suppression)")
  }

  private func processSpaceFallback(_ event: NSEvent) {
    guard event.keyCode == 49 else { return }
    guard !event.isARepeat else { return }
    guard let mode = activeMode else { return }
    isHandsFreeMode = true
    emitEvent(ShortcutEvent(phase: .spaceToggle, mode: mode))
  }

  private func removeSpaceMonitor() {
    #if !APP_STORE
      if let tap = eventTap {
        CGEvent.tapEnable(tap: tap, enable: false)
      }
      if let source = eventTapRunLoopSource {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
      }
      eventTap = nil
      eventTapRunLoopSource = nil
    #endif

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
