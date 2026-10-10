import AppKit
import CoreGraphics
import Testing

@testable import Cliptate

@Suite("MicIndicatorOverlay transcript freeze behavior")
@MainActor
struct MicIndicatorOverlayTests {


  @Test("Failed dictation keeps a readable warning without appearing to still record")
  func failedDictationShowsFinishedWarning() {
    let overlay = MicIndicatorOverlay()
    overlay.startTracking()
    overlay.updateStatus(.transcribing)
    overlay.showInputWarning("No microphone input")
    #expect(overlay.testIsActive)
    #expect(overlay.testInputWarning == "No microphone input")
    #expect(overlay.testOverlayStatus == .idle)
    #expect(overlay.testRecordingStartDate == nil)
    overlay.startTracking()
    #expect(overlay.testInputWarning == nil)
    overlay.stopTracking()
  }

  @Test("updateTranscript is ignored after status leaves listening when transcript was never shown")
  func transcriptFrozenAfterDictationEndsWithoutTranscript() {
    let overlay = MicIndicatorOverlay()
    overlay.startTracking()

    // Status transitions to transcribing before any transcript was shown
    overlay.updateStatus(.transcribing)

    // Now try to update transcript — should be ignored
    overlay.updateTranscript("Late transcript text")

    // hasTranscript should remain false
    #expect(overlay.testHasTranscript == false)

    overlay.stopTracking()
  }

  @Test("updateTranscript still works if transcript was already shown before status change")
  func transcriptNotFrozenIfAlreadyShown() {
    let overlay = MicIndicatorOverlay()
    overlay.startTracking()

    // Show transcript during listening
    overlay.updateTranscript("First transcript")
    #expect(overlay.testHasTranscript == true)

    // Status transitions to transcribing
    overlay.updateStatus(.transcribing)

    // Update transcript — should still work since transcript was already visible
    overlay.updateTranscript("Updated transcript")
    #expect(overlay.testHasTranscript == true)

    overlay.stopTracking()
  }

  @Test("transcript freeze resets on new startTracking session")
  func transcriptFreezeResetsOnNewSession() {
    let overlay = MicIndicatorOverlay()

    // First session: freeze because no transcript shown
    overlay.startTracking()
    overlay.updateStatus(.transcribing)
    overlay.updateTranscript("Ignored text")
    #expect(overlay.testHasTranscript == false)
    overlay.stopTracking()

    // Second session: should work again
    overlay.startTracking()
    overlay.updateTranscript("New session transcript")
    #expect(overlay.testHasTranscript == true)
    overlay.stopTracking()
  }

  @Test("finishAndDismiss is a no-op while processing is active")
  func finishAndDismissBlockedDuringProcessing() {
    let overlay = MicIndicatorOverlay()
    overlay.startTracking()

    // Enter processing state
    overlay.updateStatus(.transcribing)

    // Attempt to dismiss — should be blocked
    overlay.finishAndDismiss()

    // Overlay should still be active (not torn down)
    #expect(overlay.testIsActive == true)
    #expect(overlay.testOverlayStatus == .transcribing)

    overlay.stopTracking()
  }

  @Test("finishAndDismiss works after processing completes via forceFinishAndDismiss")
  func forceFinishDismissesAfterProcessing() {
    let overlay = MicIndicatorOverlay()
    overlay.startTracking()

    overlay.updateStatus(.transcribing)
    // Simulate processing complete
    overlay.forceFinishAndDismiss()

    #expect(overlay.testOverlayStatus == .idle)
  }

  @Test("level history updates are main-actor isolated")
  func levelHistoryUpdatesOnMainActor() {
    let overlay = MicIndicatorOverlay()
    overlay.startTracking()

    overlay.updateLevel(0.5)
    overlay.updateLevel(0.8)
    overlay.updateLevel(0.3)

    #expect(overlay.testLevelHistory.count == 3)
    #expect(overlay.testLevelHistory[0] == 0.5)
    #expect(overlay.testLevelHistory[1] == 0.8)
    #expect(overlay.testLevelHistory[2] == 0.3)

    overlay.stopTracking()
  }

  @Test("waveform bar weights produce center-high sides-low pattern with 9 bars")
  func waveformBarWeightsCenterHigh() {
    let weights: [CGFloat] = [0.28, 0.42, 0.58, 0.78, 1.0, 0.82, 0.64, 0.46, 0.30]
    // Center bar (index 4) is highest
    #expect(weights[4] == 1.0)
    // Symmetric-ish falloff from center
    #expect(weights[3] > weights[2])
    #expect(weights[2] > weights[1])
    #expect(weights[1] > weights[0])
    #expect(weights[5] > weights[6])
    #expect(weights[6] > weights[7])
    #expect(weights[7] > weights[8])
    // 9 bars total
    #expect(weights.count == 9)
  }

  @Test("smoothedBarLevels has 9 elements matching bar count")
  func smoothedBarLevelsMatchesBarCount() {
    let overlay = MicIndicatorOverlay()
    overlay.startTracking()
    #expect(overlay.testSmoothedBarLevels.count == 9)
    overlay.stopTracking()
  }

  @Test("time display area hidden after processing completes — recordingStartDate cleared on dismiss")
  func timeDisplayHiddenAfterProcessing() {
    let overlay = MicIndicatorOverlay()
    overlay.startTracking()

    // recordingStartDate is set on startTracking
    #expect(overlay.testRecordingStartDate != nil)

    // Enter transcribing state (spinner shows)
    overlay.updateStatus(.transcribing)
    #expect(overlay.testHasEnteredProcessing == true)

    // Processing completes — force dismiss
    overlay.forceFinishAndDismiss()

    // After dismiss, recordingStartDate should be cleared
    #expect(overlay.testRecordingStartDate == nil)
  }

  @Test("time display stays visible when transcript appears")
  func timeDisplayVisibleWithTranscript() {
    let overlay = MicIndicatorOverlay()
    overlay.startTracking()

    // recordingStartDate is set
    #expect(overlay.testRecordingStartDate != nil)

    // Transcript appears
    overlay.updateTranscript("Hello world")
    #expect(overlay.testHasTranscript == true)

    // recordingStartDate should still be set (time stays visible)
    #expect(overlay.testRecordingStartDate != nil)

    overlay.stopTracking()
  }

  @Test("waveform layout keeps the visualizer centered between matching side slots")
  func waveformLayoutUsesFixedCenterSlots() {
    let overlay = MicIndicatorOverlay()

    #expect(overlay.testPanelWidth > 180)
    #expect(overlay.testWaveformLeadingSlotWidth == overlay.testWaveformTrailingSlotWidth)
    #expect(overlay.testWaveformLeadingSlotWidth >= 32)
  }

  @Test("overlay styling uses graphite HUD surface instead of liquid glass")
  func overlayStylingUsesGraphiteHudSurface() {
    let overlay = MicIndicatorOverlay()

    #expect(overlay.testUsesGraphiteHudSurface == true)
    #expect(overlay.testPrefersLiquidGlassStyling == false)
    #expect(overlay.testUsesUltraThinMaterialFallback == false)
  }

  @Test("overlay accessories use minimal chrome instead of floating chips")
  func overlayAccessoriesUseMinimalChrome() {
    let overlay = MicIndicatorOverlay()

    #expect(overlay.testAccessoryUsesMinimalChrome == true)
    #expect(overlay.testAccessoryUsesFloatingChipBackground == false)
  }

  @Test("transcript styling keeps a readable support surface and contrast shadow")
  func transcriptStylingUsesReadableSupportSurface() {
    let overlay = MicIndicatorOverlay()

    #expect(overlay.testTranscriptUsesReadableSupportSurface == true)
    #expect(overlay.testUsesContrastShadowForForeground == true)
  }

  @Test("overlay styling uses fully transparent corners with a more distinct main panel")
  func overlayStylingUsesTransparentCornersAndDistinctPanel() {
    let overlay = MicIndicatorOverlay()

    #expect(overlay.testUsesTransparentCorners == true)
    #expect(overlay.testUsesHardCornerCutout == false)
    #expect(overlay.testUsesHigherBackgroundTransparency == true)
    #expect(overlay.testUsesContrastShadowForForeground == true)
  }

  @Test("overlay panel host view stays transparent outside the rounded HUD")
  func overlayPanelHostViewUsesTransparentBackground() throws {
    let overlay = MicIndicatorOverlay()
    overlay.startTracking()
    defer { overlay.stopTracking() }

    let mirror = Mirror(reflecting: overlay)
    let panel = try #require(mirror.descendant("panel") as? NSPanel)
    let contentView = try #require(panel.contentView)

    #expect(String(describing: type(of: contentView)).contains("TransparentHostingView"))
    #expect(contentView.layer?.cornerRadius == 22)
    #expect(contentView.layer?.masksToBounds == true)
  }

  @Test("envelope attack responds faster than release")
  func envelopeAttackFasterThanRelease() {
    let attack: CGFloat = 0.55
    let release: CGFloat = 0.15

    var level: CGFloat = 0.0
    let targetHigh: CGFloat = 1.0
    level = attack * targetHigh + (1 - attack) * level
    let afterAttack = level

    let targetLow: CGFloat = 0.0
    level = release * targetLow + (1 - release) * level
    let afterRelease = level

    // Attack should jump to 0.55 from 0.0
    #expect(afterAttack == 0.55)
    // Release should decay slowly
    #expect(afterRelease > 0.46)
    #expect(afterRelease < 0.48)
  }

  @Test("waveform styling uses brighter tech accents")
  func waveformStylingUsesTechAccentPalette() {
    let overlay = MicIndicatorOverlay()

    #expect(overlay.testWaveformUsesRestrainedHudAccentPalette == false)
    #expect(overlay.testWaveformBarCount == 9)
  }

  @Test("processing dots animate left to right with a hard reset")
  func processingDotsAnimateLeftToRightWithReset() {
    #expect(MicIndicatorOverlay.testEllipsisFrame(step: 0) == ".")
    #expect(MicIndicatorOverlay.testEllipsisFrame(step: 1) == "..")
    #expect(MicIndicatorOverlay.testEllipsisFrame(step: 2) == "...")
    #expect(MicIndicatorOverlay.testEllipsisFrame(step: 3) == ".")
    #expect(MicIndicatorOverlay.testEllipsisFrame(step: 4) == "..")
    #expect(MicIndicatorOverlay.testEllipsisFrame(step: 5) == "...")
  }

  @Test("processing status keeps the compact single-row panel height")
  func processingStatusKeepsCompactHeight() {
    let overlay = MicIndicatorOverlay()
    overlay.startTracking()

    overlay.updateStatus(.transcribing)

    #expect(overlay.testCurrentPanelHeight == 52)

    overlay.stopTracking()
  }

  @Test("processing status reserves a fixed ellipsis slot")
  func processingStatusReservesFixedEllipsisSlot() {
    let overlay = MicIndicatorOverlay()

    #expect(overlay.testProcessingStatusUsesReservedEllipsisSlot == true)
  }

  @Test("pending dismiss from an older session does not close a restarted overlay")
  func staleDismissDoesNotCloseRestartedOverlay() {
    let overlay = MicIndicatorOverlay()
    overlay.startTracking()

    let token = overlay.testScheduleDismissForRestartRace()
    overlay.startTracking()
    overlay.testCompleteScheduledDismiss(token: token)

    #expect(overlay.testIsActive == true)

    overlay.stopTracking()
  }

  @Test("entering aiEnhance cancels a pending post-transcription dismiss")
  func aiEnhanceCancelsPendingDismiss() {
    let overlay = MicIndicatorOverlay()
    overlay.startTracking()

    // Simulate what happens after transcription completes: forceFinishAndDismiss schedules dismiss
    let preDismissToken = overlay.testScheduleDismissForRestartRace()
    #expect(overlay.testIsActive == true)

    // AI enhance kicks in — should cancel the pending dismiss
    overlay.updateStatus(.aiEnhance)
    #expect(overlay.testOverlayStatus == .aiEnhance)

    // The old dismiss token is now stale; completing it should be a no-op
    overlay.testCompleteScheduledDismiss(token: preDismissToken)
    #expect(overlay.testIsActive == true)

    overlay.stopTracking()
  }
}
