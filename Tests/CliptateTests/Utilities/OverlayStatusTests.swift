import Foundation
import Testing

@testable import Cliptate

@Suite("Overlay status transitions")
struct OverlayStatusTests {

  @Test("OverlayStatus has all expected cases")
  func allCases() {
    let cases: [OverlayStatus] = [.idle, .listening, .transcribing, .aiEnhance, .copiedToClipboard]
    #expect(cases.count == 5)
  }

  @Test("OverlayStatus labels are correct")
  func labels() {
    #expect(OverlayStatus.idle.label == "Idle")
    #expect(OverlayStatus.listening.label == "Listening")
    #expect(OverlayStatus.transcribing.label == "Transcribing")
    #expect(OverlayStatus.aiEnhance.label == "AI Enhance")
    #expect(OverlayStatus.copiedToClipboard.label == "Copied")
  }

  @Test("OverlayStatus showsSpinner is true for processing states")
  func spinnerStates() {
    #expect(!OverlayStatus.idle.showsSpinner)
    #expect(!OverlayStatus.listening.showsSpinner)
    #expect(OverlayStatus.transcribing.showsSpinner)
    #expect(OverlayStatus.aiEnhance.showsSpinner)
    #expect(!OverlayStatus.copiedToClipboard.showsSpinner)
  }

  @Test("OverlayStatus processing copy matches dictation phases")
  func processingCopy() {
    #expect(OverlayStatus.listening.processingLabel == nil)
    #expect(OverlayStatus.transcribing.processingLabel == "Transcribing")
    #expect(OverlayStatus.aiEnhance.processingLabel == "Thinking")
    #expect(OverlayStatus.copiedToClipboard.processingLabel == "Copied · ⌘V")
  }
}
