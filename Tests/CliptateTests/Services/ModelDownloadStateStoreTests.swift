import CliptateCore
import Combine
import Foundation
import Testing

@testable import Cliptate

@Suite("ModelDownloadStateStore")
@MainActor
struct ModelDownloadStateStoreTests {
  @Test("initial state has empty maps")
  func initialStateIsEmpty() {
    let store = ModelDownloadStateStore()
    #expect(store.progressMap.isEmpty)
    #expect(store.downloadedMap.isEmpty)
    #expect(store.errorMap.isEmpty)
  }

  @Test("setting progress is reflected immediately")
  func settingProgressReflectsImmediately() {
    let store = ModelDownloadStateStore()
    let progress = ModelDownloadProgress(currentStep: "Downloading", progress: 0.5)
    store.setProgress(progress, for: .parakeetV2)
    #expect(store.progressMap[.parakeetV2]?.progress == 0.5)
  }

  @Test("setProgress publishes objectWillChange for view updates")
  func setProgressPublishesObjectWillChange() {
    let store = ModelDownloadStateStore()
    var emissionCount = 0
    let cancellable = store.objectWillChange.sink {
      emissionCount += 1
    }

    store.setProgress(ModelDownloadProgress(currentStep: "Downloading", progress: 0.4), for: .parakeetV2)

    #expect(emissionCount == 1)
    withExtendedLifetime(cancellable) {}
  }

  @Test("progressMap is not cleared when downloadedMap is set to false (in-progress download must survive refresh)")
  func progressMapSurvivesDownloadedMapFalseUpdate() {
    let store = ModelDownloadStateStore()
    store.setProgress(ModelDownloadProgress(currentStep: "Downloading", progress: 0.4), for: .parakeetV2)

    // Simulate what refreshStatuses does: update downloadedMap without touching progressMap
    store.setDownloaded(false, for: .parakeetV2)

    // Progress must still be present — the active Task owns its own lifecycle
    #expect(store.progressMap[.parakeetV2] != nil)
    #expect(store.progressMap[.parakeetV2]?.progress == 0.4)
  }

  @Test("clearing progress removes the entry")
  func clearingProgressRemovesEntry() {
    let store = ModelDownloadStateStore()
    store.setProgress(ModelDownloadProgress(currentStep: "Done", progress: 1.0), for: .parakeetV2)
    store.clearProgress(for: .parakeetV2)
    #expect(store.progressMap[.parakeetV2] == nil)
  }
}
