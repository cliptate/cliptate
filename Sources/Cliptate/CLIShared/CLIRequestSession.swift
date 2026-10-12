import Foundation
import os

/// Owns one CLI request session, including launch, authenticated retries, and cleanup.
@MainActor
public struct CLIRequestClient {
  private let identity: AppIdentity
  private let launch: @MainActor (CLIEndpoint) async throws -> Void
  private let makeChannel: @MainActor () -> CLIChannel
  private let now: @MainActor () -> ContinuousClock.Instant
  private let sleep: @MainActor (Duration) async throws -> Void

  public init(
    launch: @escaping @MainActor (CLIEndpoint) async throws -> Void,
    identity: AppIdentity = .current,
    makeChannel: (@MainActor () -> CLIChannel)? = nil,
    now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now },
    sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.launch = launch
    self.identity = identity
    self.makeChannel = makeChannel ?? { CLIChannel(identity: identity) }
    self.now = now
    self.sleep = sleep
  }

  public func execute(
    _ request: CLIRequest, progress: @MainActor (String) -> Void = { _ in }
  ) async throws -> CLIEvent {
    let endpoint = CLIEndpoint(identity: identity)
    try await launch(endpoint)
    let deadline = now() + .seconds(30)
    var channel: CLIChannel?
    while now() < deadline {
      try Task.checkCancellation()
      let candidate = makeChannel()
      do {
        let timeout = Task {
          try? await sleep(.seconds(2))
          if !Task.isCancelled { candidate.cancel() }
        }
        defer { timeout.cancel() }
        try await candidate.start()
        try await candidate.send(CLIEvent(.hello, token: endpoint.id))
        let hello = try await candidate.receive(CLIEvent.self)
        guard hello.kind == .hello, hello.token == endpoint.proof(for: "server") else {
          throw CLIChannel.protocolError()
        }
        channel = candidate
        break
      } catch {
        candidate.cancel()
        try Task.checkCancellation()
        try await sleep(.milliseconds(150))
      }
    }
    guard let channel else {
      throw CLIError(
        String(
          localized:
            "Could not connect to Cliptate within 30 seconds. Check that it is a direct-download build and the CLI port is available.",
          bundle: CLILocalization.bundle))
    }
    defer { channel.cancel() }
    var authorized = request
    authorized.authorization = endpoint.proof(for: "client")
    do {
      try await channel.send(authorized)
      while true {
        let event = try await channel.receive(CLIEvent.self)
        try Task.checkCancellation()
        switch event.kind {
        case .progress: if let message = event.message { progress(message) }
        case .result: return event
        case .failure:
          throw CLIError(event.message ?? CLIChannel.protocolError().localizedDescription)
        case .hello: throw CLIChannel.protocolError()
        }
      }
    } catch {
      try Task.checkCancellation()
      throw error
    }
  }
}

/// Owns authentication and execution of CLI request sessions for one application.
@MainActor
public final class CLIRequestServer {
  private var endpoints: [String: (CLIEndpoint, Date)] = [:]
  private var transcribing = false
  private let now: @MainActor () -> Date
  private let sleep: @Sendable (Duration) async throws -> Void
  private let execute:
    @MainActor (CLIRequest, @escaping @Sendable (String) -> Void) async throws -> CLIEvent

  public init(
    now: @escaping @MainActor () -> Date = { Date() },
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    execute:
      @escaping @MainActor (
        CLIRequest, @escaping @Sendable (String) -> Void
      ) async throws -> CLIEvent
  ) {
    self.now = now
    self.sleep = sleep
    self.execute = execute
  }

  @discardableResult
  public func register(_ endpoint: CLIEndpoint) -> Bool {
    endpoints = endpoints.filter { $0.value.1 > now() }
    guard endpoints.count < 100 else { return false }
    endpoints[endpoint.id] = (endpoint, now().addingTimeInterval(60))
    return true
  }

  public func serve(_ channel: CLIChannel) async {
    let timeout = Task {
      try? await sleep(.seconds(5))
      if !Task.isCancelled { channel.cancel() }
    }
    defer {
      timeout.cancel()
      channel.cancel()
    }
    do {
      try await channel.start()
      let hello = try await channel.receive(CLIEvent.self)
      guard hello.kind == .hello, let id = hello.token,
        let (endpoint, expiry) = endpoints[id], expiry > now()
      else { return }
      try await channel.send(CLIEvent(.hello, token: endpoint.proof(for: "server")))
      let request = try await channel.receive(CLIRequest.self)
      guard request.authorization == endpoint.proof(for: "client"),
        endpoints.removeValue(forKey: id) != nil, expiry > now()
      else { return }
      timeout.cancel()
      if request.operation == .transcribe && transcribing {
        try await channel.send(
          CLIEvent(
            .failure,
            message: String(
              localized: "Another CLI transcription is running. Try again when it finishes.",
              bundle: CLILocalization.bundle)))
        return
      }
      if request.operation == .transcribe { transcribing = true }
      defer { if request.operation == .transcribe { transcribing = false } }
      await run(request, on: channel)
    } catch {}
  }

  private func run(_ request: CLIRequest, on channel: CLIChannel) async {
    let events = CLIRequestEvents()
    let work = Task {
      do {
        let response = try await execute(request, { events.progress($0) })
        try Task.checkCancellation()
        events.finish(with: response)
      } catch {
        events.finish(
          with: Task.isCancelled ? nil : CLIEvent(.failure, message: error.localizedDescription))
      }
    }
    let sender = Task {
      do {
        for await event in events.stream { try await channel.send(event) }
      } catch {
        events.finish(with: nil)
        work.cancel()
        channel.cancel()
      }
    }
    let disconnect = Task {
      _ = try? await channel.receive(CLIEvent.self)
      events.finish(with: nil)
      work.cancel()
      sender.cancel()
    }
    await withTaskCancellationHandler {
      // Keep transcription admission occupied until inference and its sender have exited.
      await work.value
      await sender.value
      disconnect.cancel()
      await disconnect.value
    } onCancel: {
      events.finish(with: nil)
      channel.cancel()
      work.cancel()
      sender.cancel()
      disconnect.cancel()
    }
  }
}

/// Synchronous progress callbacks and the terminal event enter one ordered stream.
private final class CLIRequestEvents: Sendable {
  let stream: AsyncStream<CLIEvent>
  private let state: OSAllocatedUnfairLock<State>

  private struct State {
    let continuation: AsyncStream<CLIEvent>.Continuation
    var finished = false
  }

  init() {
    let events = AsyncStream<CLIEvent>.makeStream()
    stream = events.stream
    state = OSAllocatedUnfairLock(initialState: State(continuation: events.continuation))
  }

  func progress(_ message: String) {
    state.withLock { state in
      guard !state.finished else { return }
      state.continuation.yield(CLIEvent(.progress, message: message))
    }
  }

  func finish(with terminal: CLIEvent?) {
    state.withLock { state in
      guard !state.finished else { return }
      state.finished = true
      if let terminal { state.continuation.yield(terminal) }
      state.continuation.finish()
    }
  }
}
