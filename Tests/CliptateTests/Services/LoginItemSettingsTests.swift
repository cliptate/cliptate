import Foundation
import Testing
import os
@testable import Cliptate

@Suite("Login item settings")
@MainActor
struct LoginItemSettingsTests {
  @Test("slow status queries leave the main actor and cached toggle reads responsive")
  func slowStatusDoesNotBlockUI() async {
    let started = AsyncStream<Void>.makeStream()
    let release = DispatchSemaphore(value: 0)
    defer { release.signal() }
    let probe = OSAllocatedUnfairLock(initialState: Probe())
    let service = LoginItemService(readEnabled: {
      probe.withLock {
        $0.readCount += 1
        $0.queriedOnMainThread = Thread.isMainThread
      }
      started.continuation.yield()
      _ = release.wait(timeout: .now() + 5)
      return true
    }, writeEnabled: { _ in })
    let settings = LoginItemSettings(service: service)
    #expect(!settings.hasLoaded)
    #expect(probe.withLock { $0.readCount } == 0)

    let refresh = Task { await settings.refresh() }
    for await _ in started.stream { break }
    #expect(settings.isBusy)
    // Simulate the repeated binding reads from layout/accessibility while IPC waits.
    let cachedReads = (0..<100).map { _ in settings.isEnabled }
    #expect(cachedReads.allSatisfy { !$0 })
    await settings.refresh()
    await settings.setEnabled(true)
    #expect(probe.withLock { $0.readCount } == 1)
    #expect(!probe.withLock { $0.queriedOnMainThread })

    release.signal()
    await refresh.value
    #expect(settings.hasLoaded)
    #expect(settings.isEnabled)
    #expect(!settings.isBusy)
  }

  @Test("registration and external changes refresh the actual system state")
  func writesAndRefreshesActualState() async {
    let probe = OSAllocatedUnfairLock(initialState: Probe())
    let settings = LoginItemSettings(service: LoginItemService(
      readEnabled: { probe.withLock { $0.enabled } },
      writeEnabled: { enabled in
        probe.withLock {
          $0.enabled = enabled
          $0.queriedOnMainThread = Thread.isMainThread
        }
      }
    ))
    await settings.refresh()
    await settings.setEnabled(true)
    #expect(settings.isEnabled)
    #expect(!probe.withLock { $0.queriedOnMainThread })
    await settings.setEnabled(false)
    #expect(!settings.isEnabled)
    probe.withLock { $0.enabled = true }
    await settings.refresh()
    #expect(settings.isEnabled)
    #expect(settings.errorMessage == nil)
  }

  @Test("failed registration restores real state and reports the system error")
  func failedRegistrationDoesNotShowRequestedState() async {
    let settings = LoginItemSettings(service: LoginItemService(
      readEnabled: { false },
      writeEnabled: { _ in throw RegistrationError.rejected }
    ))
    await settings.refresh()
    await settings.setEnabled(true)
    #expect(!settings.isEnabled)
    #expect(!settings.isBusy)
    #expect(settings.errorMessage == "Registration rejected")
  }

  @Test("leaving settings cancels publication without blocking navigation")
  func cancelledRefreshDoesNotPublish() async {
    let started = AsyncStream<Void>.makeStream()
    let release = DispatchSemaphore(value: 0)
    defer { release.signal() }
    let settings = LoginItemSettings(service: LoginItemService(
      readEnabled: {
        started.continuation.yield()
        _ = release.wait(timeout: .now() + 5)
        return true
      }, writeEnabled: { _ in }
    ))
    let refresh = Task { await settings.refresh() }
    for await _ in started.stream { break }
    refresh.cancel()
    release.signal()
    await refresh.value
    #expect(!settings.hasLoaded)
    #expect(!settings.isEnabled)
    #expect(!settings.isBusy)
    release.signal()
    await settings.refresh()
    #expect(settings.hasLoaded)
    #expect(settings.isEnabled)
  }

  private struct Probe {
    var enabled = false
    var readCount = 0
    var queriedOnMainThread = false
  }

  private enum RegistrationError: LocalizedError {
    case rejected
    var errorDescription: String? { "Registration rejected" }
  }
}
