import Foundation
import Testing
@testable import Cliptate

@MainActor
struct AnalyticsRuntimeTests {
  @Test func configurationChangesDisableTheDestinationAndDoNotReplayDroppedEvents() {
    let config = AppConfiguration()
    var events: [AnalyticsEvent] = []
    var collectionChanges: [Bool] = []
    let runtime = AnalyticsRuntime(
      deliver: { events.append($0) },
      updateCollection: { collectionChanges.append($0) }
    )
    runtime.bind(to: config)
    config.analyticsCollectionEnabled = false
    runtime.record(.featureOpened(.aiCut))
    config.analyticsCollectionEnabled = true
    runtime.record(.featureOpened(.models))
    #expect(collectionChanges == [true, false, true])
    #expect(events == [.featureOpened(.models)])
  }

  @Test func workflowFailureEmitsOnlyFixedMetadataAndElapsedTime() throws {
    var events: [AnalyticsEvent] = []
    let runtime = AnalyticsRuntime(deliver: { events.append($0) })
    runtime.start(collectionEnabled: true)
    runtime.record(.operationFinished(.transcription, outcome: .failed, durationSeconds: 1.25))
    let event = try #require(events.first)
    #expect(event.name == "transcription_finished")
    #expect(NSDictionary(dictionary: event.parameters).isEqual(to: [
      "outcome": "failed", "duration_ms": 1250.0, "failure_category": "processing"
    ]))
  }

  @Test func disablingCollectionStopsSubsequentEvents() {
    var events: [AnalyticsEvent] = []
    let runtime = AnalyticsRuntime(deliver: { events.append($0) })
    runtime.start(collectionEnabled: true)
    runtime.record(.appLaunched)
    runtime.setCollectionEnabled(false)
    runtime.record(.appLaunched)
    #expect(events == [.appLaunched])
  }
}
