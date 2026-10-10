import Foundation
import Testing

@testable import Cliptate

@Suite("VoiceToggleShortcutPreset")
struct VoiceToggleShortcutPresetTests {

  @Test("Preset enum has all expected cases")
  func allCases() {
    let all = VoiceToggleShortcutPreset.allCases
    #expect(all.count == 8)
    #expect(all.contains(.function))
    #expect(all.contains(.rightCommand))
    #expect(all.contains(.rightShift))
    #expect(all.contains(.rightOption))
    #expect(all.contains(.leftOption))
    #expect(all.contains(.rightControl))
    #expect(all.contains(.leftControl))
    #expect(all.contains(.custom))
  }

  @Test("Fn preset has correct keyCode and flag")
  func fnKeyInfo() {
    let info = VoiceToggleShortcutPreset.function.keyInfo
    #expect(info != nil)
    #expect(info?.keyCode == 63)
    #expect(info?.flag == .function)
  }

  @Test("Right Cmd preset has correct keyCode")
  func rightCmdKeyInfo() {
    let info = VoiceToggleShortcutPreset.rightCommand.keyInfo
    #expect(info != nil)
    #expect(info?.keyCode == 54)
  }

  @Test("Custom preset has nil keyInfo")
  func customHasNilKeyInfo() {
    #expect(VoiceToggleShortcutPreset.custom.keyInfo == nil)
  }

  @Test("Default dictation preset is rightCommand")
  func defaultDictation() {
    #expect(VoiceToggleShortcutPreset.defaultDictationPreset == .rightCommand)
  }

  @Test("Default assistant preset is rightCommand (with shift)")
  func defaultAssistant() {
    #expect(VoiceToggleShortcutPreset.defaultAssistantPreset == .rightCommand)
  }

  @Test("Display names are non-empty")
  func displayNames() {
    for preset in VoiceToggleShortcutPreset.allCases {
      #expect(!preset.displayName.isEmpty)
    }
  }

  @Test("RawValue round-trips correctly")
  func rawValueRoundTrip() {
    for preset in VoiceToggleShortcutPreset.allCases {
      let recovered = VoiceToggleShortcutPreset(rawValue: preset.rawValue)
      #expect(recovered == preset)
    }
  }
}
