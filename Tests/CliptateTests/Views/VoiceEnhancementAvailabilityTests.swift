import Testing

@testable import Cliptate

@Suite("Voice enhancement availability")
struct VoiceEnhancementAvailabilityTests {
  @Test("global disable takes precedence over a saved provider key")
  func globalDisable() {
    #expect(VoiceEnhancementAvailability(aiEnabled: false, apiKey: "configured") == .disabled)
  }

  @Test("enabled AI needs a provider key")
  func missingKey() {
    #expect(VoiceEnhancementAvailability(aiEnabled: true, apiKey: nil) == .missingKey)
    #expect(VoiceEnhancementAvailability(aiEnabled: true, apiKey: "") == .missingKey)
  }

  @Test("a configured provider makes enhancement available")
  func available() {
    #expect(VoiceEnhancementAvailability(aiEnabled: true, apiKey: "configured") == .available)
  }
}
