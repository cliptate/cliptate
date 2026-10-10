import Foundation
import Testing

@testable import Cliptate

@Suite("AICutSpeakerDiagnostics")
struct AICutSpeakerDiagnosticsTests {
  @Test("configured aligner + downloaded => speaker capable, nil message")
  func configuredAlignerDownloadedIsSpeakerCapable() {
    let result = AICutSpeakerDiagnostics.resolve(
      configuredAligner: .qwen3ForcedAligner,
      isAlignerDownloaded: true,
      autoDiscoveredAligner: nil
    )
    
    #expect(result.isSpeakerCapable == true)
    #expect(result.alignVariant == .qwen3ForcedAligner)
    #expect(result.missingRequirementMessage == nil)
  }
  
  @Test("no configured aligner, auto-discovered aligner present => speaker capable")
  func autoDiscoveredAlignerIsSpeakerCapable() {
    let result = AICutSpeakerDiagnostics.resolve(
      configuredAligner: nil,
      isAlignerDownloaded: false,
      autoDiscoveredAligner: .qwen3ForcedAligner06B5bit
    )
    
    #expect(result.isSpeakerCapable == true)
    #expect(result.alignVariant == .qwen3ForcedAligner06B5bit)
    #expect(result.missingRequirementMessage == nil)
  }
  
  @Test("configured aligner but not downloaded and no auto-discovered aligner => not speaker capable + exact missing message")
  func noDownloadedAlignerIsNotSpeakerCapable() {
    let result = AICutSpeakerDiagnostics.resolve(
      configuredAligner: .qwen3ForcedAligner,
      isAlignerDownloaded: false,
      autoDiscoveredAligner: nil
    )
    
    #expect(result.isSpeakerCapable == false)
    #expect(result.alignVariant == nil)
    #expect(result.missingRequirementMessage == AICutSpeakerDiagnostics.missingAlignModelMessage)
  }
  
  @Test("no configured aligner, no auto-discovered aligner => not speaker capable")
  func noAlignerAtAllIsNotSpeakerCapable() {
    let result = AICutSpeakerDiagnostics.resolve(
      configuredAligner: nil,
      isAlignerDownloaded: false,
      autoDiscoveredAligner: nil
    )
    
    #expect(result.isSpeakerCapable == false)
    #expect(result.alignVariant == nil)
    #expect(result.missingRequirementMessage == AICutSpeakerDiagnostics.missingAlignModelMessage)
  }
  
  @Test("configured aligner downloaded takes precedence over auto-discovered")
  func configuredAlignerTakesPrecedence() {
    let result = AICutSpeakerDiagnostics.resolve(
      configuredAligner: .qwen3ForcedAligner,
      isAlignerDownloaded: true,
      autoDiscoveredAligner: .qwen3ForcedAligner06B5bit
    )
    
    #expect(result.isSpeakerCapable == true)
    #expect(result.alignVariant == .qwen3ForcedAligner)
    #expect(result.missingRequirementMessage == nil)
  }

  @Test("configured aligner not downloaded does not fall back to auto-discovered aligner")
  func configuredAlignerMustBeDownloadedToEnableSpeakerPath() {
    let result = AICutSpeakerDiagnostics.resolve(
      configuredAligner: .qwen3ForcedAligner,
      isAlignerDownloaded: false,
      autoDiscoveredAligner: .qwen3ForcedAligner06B5bit
    )

    #expect(result.isSpeakerCapable == false)
    #expect(result.alignVariant == nil)
    #expect(result.missingRequirementMessage == AICutSpeakerDiagnostics.missingAlignModelMessage)
  }
}
