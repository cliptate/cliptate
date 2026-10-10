import Testing

@testable import Cliptate

@Suite("ExportProgressState")
struct ExportProgressStateTests {

  @Test("Initial state has no phases and zero overall progress")
  func initialState() {
    let state = ExportProgressState()
    #expect(state.phases.isEmpty)
    #expect(state.overallProgress == 0.0)
    #expect(state.isActive == false)
    #expect(state.currentPhaseLabel == nil)
  }

  @Test("Starting a phase adds it with zero progress")
  func startPhase() {
    var state = ExportProgressState()
    state.startPhase(.fcpxml)
    #expect(state.phases.count == 1)
    #expect(state.phases[0].type == .fcpxml)
    #expect(state.phases[0].progress == 0.0)
    #expect(state.phases[0].status == .inProgress)
    #expect(state.isActive == true)
    #expect(state.currentPhaseLabel != nil)
  }

  @Test("Updating phase progress works correctly")
  func updateProgress() {
    var state = ExportProgressState()
    state.startPhase(.video)
    state.updateProgress(for: .video, current: 2, total: 4)
    #expect(state.phases[0].progress == 0.5)
  }

  @Test("Completing a phase sets progress to 1.0 and status to completed")
  func completePhase() {
    var state = ExportProgressState()
    state.startPhase(.subtitle)
    state.completePhase(.subtitle)
    #expect(state.phases[0].progress == 1.0)
    #expect(state.phases[0].status == .completed)
  }

  @Test("Failing a phase sets status to failed with message")
  func failPhase() {
    var state = ExportProgressState()
    state.startPhase(.audio)
    state.failPhase(.audio, message: "Disk full")
    #expect(state.phases[0].status == .failed)
    #expect(state.phases[0].failureMessage == "Disk full")
  }

  @Test("Overall progress is average of all phase progresses")
  func overallProgress() {
    var state = ExportProgressState()
    state.startPhase(.fcpxml)
    state.startPhase(.subtitle)
    state.startPhase(.video)
    state.completePhase(.fcpxml)
    state.updateProgress(for: .subtitle, current: 1, total: 2)
    // fcpxml=1.0, subtitle=0.5, video=0.0 → average = 0.5
    let expected = 0.5
    #expect(abs(state.overallProgress - expected) < 0.01)
  }

  @Test("currentPhaseLabel returns the label of the in-progress phase")
  func currentPhaseLabel() {
    var state = ExportProgressState()
    state.startPhase(.fcpxml)
    state.completePhase(.fcpxml)
    state.startPhase(.video)
    #expect(state.currentPhaseLabel != nil)
    // Should be the video phase label, not fcpxml
    let label = state.currentPhaseLabel!
    #expect(label.contains("video") || label.contains("Video") || label.contains("视频"))
  }

  @Test("ExportPhaseType covers all expected types")
  func phaseTypes() {
    let types: [ExportPhaseType] = [.fcpxml, .subtitle, .video, .audio]
    #expect(types.count == 4)
    // Each has a non-empty display name
    for t in types {
      #expect(!t.displayName.isEmpty)
    }
  }

  @Test("Reset clears all phases")
  func reset() {
    var state = ExportProgressState()
    state.startPhase(.fcpxml)
    state.startPhase(.video)
    state.reset()
    #expect(state.phases.isEmpty)
    #expect(state.isActive == false)
  }
}
