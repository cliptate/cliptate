import Foundation
import Observation
import ServiceManagement

/// ServiceManagement uses synchronous IPC. Keep it off the main actor, including
/// the status reads that SwiftUI would otherwise repeat during layout.
actor LoginItemService {
  private let readEnabled: @Sendable () -> Bool
  private let writeEnabled: @Sendable (Bool) throws -> Void

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

  func isEnabled() -> Bool { readEnabled() }

  func setEnabled(_ enabled: Bool) -> (enabled: Bool, errorMessage: String?) {
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
