@preconcurrency import Foundation
import Testing

@testable import Cliptate

@Suite("Model artifact notifications")
struct ModelArtifactStatusNotifierTests {
  private final class ObserverBox: @unchecked Sendable {
    var token: NSObjectProtocol?
  }

  @Test("Model artifact change notifications are delivered on the main thread")
  func notificationsAreDeliveredOnMainThread() async {
    let observedOnMainThread = await withCheckedContinuation { continuation in
      let observer = ObserverBox()
      observer.token = NotificationCenter.default.addObserver(
        forName: .modelArtifactsDidChange,
        object: nil,
        queue: nil
      ) { _ in
        if let token = observer.token {
          NotificationCenter.default.removeObserver(token)
        }
        continuation.resume(returning: Thread.isMainThread)
      }

      Task.detached {
        ModelArtifactStatusNotifier.postChange(for: .sileroVAD)
      }
    }

    #expect(observedOnMainThread, "Model artifact notifications should always be posted on the main thread")
  }
}
