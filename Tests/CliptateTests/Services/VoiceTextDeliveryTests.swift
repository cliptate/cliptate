import Foundation
import Testing

@testable import Cliptate

@Suite("Voice text delivery")
@MainActor
struct VoiceTextDeliveryTests {
  @Test("a focused session target receives text without using the clipboard")
  func focusedTarget() async throws {
    var inserted: [String] = []
    var copied: [String] = []
    let delivery = VoiceTextDelivery(
      canInject: { true }, activate: { _ in }, targetIsFocused: { $0 == 42 },
      waitForActivation: {}, inject: { inserted.append($0); return true },
      copy: { copied.append($0); return true }
    )
    try await delivery.deliver("ready answer", to: 42)

    #expect(inserted == ["ready answer"])
    #expect(copied.isEmpty)
  }

  @Test("unavailable injection or a changed target copies retained text instead", arguments: [false, true])
  func clipboardFallback(injectionAvailable: Bool) async throws {
    var copied: [String] = []
    var injected: [String] = []
    var activated: [Int32] = []
    let delivery = VoiceTextDelivery(
      canInject: { injectionAvailable }, activate: { activated.append($0) },
      targetIsFocused: { _ in false }, waitForActivation: {},
      inject: { injected.append($0); return true },
      copy: { copied.append($0); return true }
    )
    try await delivery.deliver("retained words", to: 42)

    #expect(copied == ["retained words"])
    #expect(injected.isEmpty)
    #expect(activated == (injectionAvailable ? [42] : []))
  }

  @Test("cancelling while the target activates prevents queued input")
  func cancelQueuedInput() async {
    var injected: [String] = []
    var resumeActivation: CheckedContinuation<Void, Never>?
    var activated: CheckedContinuation<Void, Never>?
    let delivery = VoiceTextDelivery(
      canInject: { true }, activate: { _ in }, targetIsFocused: { _ in true },
      waitForActivation: {
        await withCheckedContinuation { continuation in
          resumeActivation = continuation
          activated?.resume()
          activated = nil
        }
      },
      inject: { injected.append($0); return true }, copy: { _ in false }
    )
    let operation = Task { try await delivery.deliver("queued words", to: 42) }
    if resumeActivation == nil {
      await withCheckedContinuation { activated = $0 }
    }
    operation.cancel()
    resumeActivation?.resume()
    let result = await operation.result

    #expect(injected.isEmpty)
    #expect(throws: CancellationError.self) { try result.get() }
  }
}
