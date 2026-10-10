import AppKit

/// Configurable modifier-key presets for dictation and assistant shortcut modes.
public enum VoiceToggleShortcutPreset: String, CaseIterable, Identifiable, Sendable {
  case rightCommand
  case rightShift
  case function
  case rightOption
  case leftOption
  case rightControl
  case leftControl
  case custom

  public var id: String { rawValue }

  /// Default dictation preset — Right Cmd key (reliable, no system interception).
  static let defaultDictationPreset: VoiceToggleShortcutPreset = .rightCommand
  /// Default assistant preset — same key + Shift.
  static let defaultAssistantPreset: VoiceToggleShortcutPreset = .rightCommand

  var displayName: String {
    switch self {
    case .rightCommand: return "Right Cmd"
    case .rightShift: return "Right Shift"
    case .function: return "Fn"
    case .rightOption: return "Right Option"
    case .leftOption: return "Left Option"
    case .rightControl: return "Right Ctrl"
    case .leftControl: return "Left Ctrl"
    case .custom: return "Custom"
    }
  }

  var systemImageName: String {
    switch self {
    case .rightCommand: return "command"
    case .rightShift: return "shift"
    case .function: return "globe"
    case .rightOption, .leftOption: return "option"
    case .rightControl, .leftControl: return "control"
    case .custom: return "slider.horizontal.3"
    }
  }

  /// The physical key code and modifier flag for this preset, or `nil` for custom.
  var keyInfo: (keyCode: UInt16, flag: NSEvent.ModifierFlags)? {
    switch self {
    case .rightCommand: return (54, .command)
    case .rightShift: return (60, .shift)
    case .function: return (63, .function)
    case .rightOption: return (61, .option)
    case .leftOption: return (58, .option)
    case .rightControl: return (62, .control)
    case .leftControl: return (59, .control)
    case .custom: return nil
    }
  }
}
