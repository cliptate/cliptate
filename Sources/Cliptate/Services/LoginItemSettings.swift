import Foundation
import Observation
import ServiceManagement

/// ServiceManagement uses synchronous IPC. Keep it off both the main actor and
/// Swift's cooperative pool so a slow query cannot prevent callers from resuming.
actor LoginItemService {
  private let readEnabled: @Sendable () -> Bool
  private let writeEnabled: @Sendable (Bool) throws -> Void
  private let queue = DispatchQueue(label: "com.cliptate.login-item", qos: .userInitiated)

  init(
    readEnabled: @escaping @Sendable () -> Bool = { SMAppService.mainApp.status == .enabled },
    writeEnabled: @escaping @Sendable (Bool) throws -> Void = { enabled in
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    }
  ) {
    self.readEnabled = readEnabled
    self.writeEnabled = writeEnabled
  }

  func isEnabled() async -> Bool { await perform(readEnabled) }

  func setEnabled(_ enabled: Bool) async -> (enabled: Bool, errorMessage: String?) {
    let readEnabled = readEnabled
    let writeEnabled = writeEnabled
    return await perform {
      var errorMessage: String?
      do {
        try writeEnabled(enabled)
      } catch {
        errorMessage = error.localizedDescription
      }
      // Registration may fail or require system approval. Display the real state.
      return (readEnabled(), errorMessage)
    }
  }

  private func perform<Result: Sendable>(
    _ operation: @escaping @Sendable () -> Result
  ) async -> Result {
    await withCheckedContinuation { continuation in
      // Preserve read/write ordering while releasing the caller's cooperative worker.
      queue.async {
        continuation.resume(returning: operation())
      }
    }
  }
}

@MainActor
@Observable
final class LoginItemSettings {
  private(set) var isEnabled = false
  private(set) var hasLoaded = false
  private(set) var isBusy = false
  private(set) var errorMessage: String?
  private let service: LoginItemService

  init(service: LoginItemService = LoginItemService()) {
    self.service = service
  }

  func refresh() async {
    guard !isBusy, !Task.isCancelled else { return }
    isBusy = true
    defer { isBusy = false }
    let enabled = await service.isEnabled()
    guard !Task.isCancelled else { return }
    isEnabled = enabled
    hasLoaded = true
  }

  func setEnabled(_ enabled: Bool) async {
    guard hasLoaded, !isBusy, !Task.isCancelled else { return }
    isBusy = true
    defer { isBusy = false }
    let result = await service.setEnabled(enabled)
    isEnabled = result.enabled
    errorMessage = result.errorMessage
  }
}
