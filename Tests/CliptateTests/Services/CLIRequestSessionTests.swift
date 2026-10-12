@preconcurrency import Network
import XCTest

#if canImport(CliptateCLIKit)
  import CliptateCLIKit
#else
  @testable import Cliptate
#endif

@MainActor
final class CLIRequestSessionTests: XCTestCase {
  func testClientSelectsDevelopmentLaunchCredentialsForDevelopmentRequests() async throws {
    let server = CLIRequestServer { _, _ in CLIEvent(.result, entries: ["Development only"]) }
    let loopback = try await SessionLoopback(server: server)
    defer { loopback.close() }
    let client = CLIRequestClient(
      launch: { endpoint in
        XCTAssertNotNil(CLIEndpoint(url: endpoint.url, identity: .development))
        XCTAssertNil(CLIEndpoint(url: endpoint.url, identity: .production))
        server.register(endpoint)
      }, identity: .development, makeChannel: loopback.makeChannel)
    let response = try await client.execute(CLIRequest(operation: .dictionaryList))
    XCTAssertEqual(response.entries, ["Development only"])
  }

  func testAuthenticatedRequestReturnsResult() async throws {
    let server = CLIRequestServer { request, _ in
      XCTAssertEqual(request.operation, .dictionaryList)
      return CLIEvent(.result, entries: ["你好", "Café"])
    }
    let loopback = try await SessionLoopback(server: server)
    defer { loopback.close() }

    let response = try await loopback.client.execute(CLIRequest(operation: .dictionaryList))

    XCTAssertEqual(response.kind, .result)
    XCTAssertEqual(response.entries, ["你好", "Café"])
  }

  func testSpeechPayloadAndMetadataCrossAuthenticatedTransport() async throws {
    let server = CLIRequestServer { request, progress in
      XCTAssertEqual(request.operation, .tts)
      XCTAssertEqual(request.tts?.text, "你好")
      XCTAssertEqual(request.tts?.referenceText, "reference")
      XCTAssertEqual(request.outputBookmark, Data([1, 2]))
      progress("Generating")
      return CLIEvent(
        .result,
        audio: CLIAudioResult(file: "/tmp/private.wav", model: "tts-model", bytes: 17_000_000))
    }
    let loopback = try await SessionLoopback(server: server)
    defer { loopback.close() }
    let response = try await loopback.client.execute(
      CLIRequest(
        operation: .tts, tts: CLITTSParameters(text: "你好", referenceText: "reference"),
        outputBookmark: Data([1, 2])))
    XCTAssertEqual(response.audio?.model, "tts-model")
    XCTAssertEqual(response.audio?.bytes, 17_000_000)
  }

  func testProgressIsDeliveredInOrderBeforeTerminalResult() async throws {
    let server = CLIRequestServer { _, progress in
      progress("Preparing model")
      progress("Transcribing audio")
      return CLIEvent(.result, entries: ["Finished"])
    }
    let loopback = try await SessionLoopback(server: server)
    defer { loopback.close() }
    var messages: [String] = []

    let response = try await loopback.client.execute(
      CLIRequest(operation: .dictionaryList), progress: { messages.append($0) })

    XCTAssertEqual(messages, ["Preparing model", "Transcribing audio"])
    XCTAssertEqual(response.entries, ["Finished"])
  }

  func testBusySpeechRejectsTranscriptionButAllowsDictionaryRequests() async throws {
    let started = SessionGate()
    let release = SessionGate()
    let server = CLIRequestServer { request, _ in
      if request.model == "held" {
        started.open()
        await release.wait()
      }
      return CLIEvent(.result, entries: ["Available"])
    }
    let loopback = try await SessionLoopback(server: server)
    defer {
      release.open()
      loopback.close()
    }
    let active = Task {
      try await loopback.client.execute(CLIRequest(operation: .tts, model: "held"))
    }
    await started.wait()

    do {
      _ = try await loopback.client.execute(CLIRequest(operation: .transcribe))
      XCTFail("A second transcription must be rejected while the first is running")
    } catch let error as CLIError {
      XCTAssertEqual(
        error.message,
        "Another CLI transcription or speech generation is running. Try again when it finishes.")
    }
    let dictionary = try await loopback.client.execute(CLIRequest(operation: .dictionaryList))
    XCTAssertEqual(dictionary.entries, ["Available"])

    release.open()
    _ = try await active.value
  }

  func testBusyTranscriptionRejectsSpeech() async throws {
    let started = SessionGate()
    let release = SessionGate()
    let server = CLIRequestServer { request, _ in
      if request.operation == .transcribe {
        started.open()
        await release.wait()
      } else {
        XCTFail("Speech must not be admitted during transcription")
      }
      return CLIEvent(.result)
    }
    let loopback = try await SessionLoopback(server: server)
    defer {
      release.open()
      loopback.close()
    }
    let active = Task { try await loopback.client.execute(CLIRequest(operation: .transcribe)) }
    await started.wait()
    do {
      _ = try await loopback.client.execute(CLIRequest(operation: .tts))
      XCTFail("Expected busy failure")
    } catch let error as CLIError {
      XCTAssertEqual(
        error.message,
        "Another CLI transcription or speech generation is running. Try again when it finishes.")
    }
    release.open()
    _ = try await active.value
  }

  func testDisconnectCancelsWorkButKeepsAdmissionUntilWorkExits() async throws {
    let started = SessionGate()
    let release = SessionGate()
    let cancelled = XCTestExpectation(description: "Disconnected request work is cancelled")
    let server = CLIRequestServer { request, _ in
      if request.model == "held" {
        return await withTaskCancellationHandler {
          started.open()
          // Deliberately hold cleanup after cancellation, as a slow inference adapter can.
          await release.wait()
          return CLIEvent(.result, entries: ["Old request"])
        } onCancel: {
          cancelled.fulfill()
        }
      }
      return CLIEvent(.result, entries: ["New request"])
    }
    let loopback = try await SessionLoopback(server: server)
    defer {
      release.open()
      loopback.close()
    }
    let active = Task {
      try await loopback.client.execute(CLIRequest(operation: .tts, model: "held"))
    }
    await started.wait()
    active.cancel()
    let cancellation = await XCTWaiter.fulfillment(of: [cancelled], timeout: 3)
    XCTAssertEqual(cancellation, .completed)

    do {
      _ = try await loopback.client.execute(CLIRequest(operation: .transcribe))
      XCTFail("Cancellation must not release admission while the old work is still exiting")
    } catch let error as CLIError {
      XCTAssertEqual(
        error.message,
        "Another CLI transcription or speech generation is running. Try again when it finishes.")
    }
    release.open()
    await loopback.drain()
    do {
      _ = try await active.value
      XCTFail("An interrupted client must not receive a result")
    } catch is CancellationError {}

    let next = try await loopback.client.execute(CLIRequest(operation: .transcribe))
    XCTAssertEqual(next.entries, ["New request"])
  }

  func testCredentialExpiresWhileClientIsCompletingAuthentication() async throws {
    var now = Date(timeIntervalSince1970: 100)
    let server = CLIRequestServer(
      now: { now },
      execute: { _, _ in
        XCTFail("An expired credential must not execute work")
        return CLIEvent(.result)
      })
    let loopback = try await SessionLoopback(server: server)
    defer { loopback.close() }
    let endpoint = CLIEndpoint()
    server.register(endpoint)
    let channel = try await loopback.authenticate(endpoint)
    defer { channel.cancel() }

    now = Date(timeIntervalSince1970: 160)
    var request = CLIRequest(operation: .dictionaryList)
    request.authorization = endpoint.proof(for: "client")
    try await channel.send(request)
    await expectClosed(channel)
  }

  func testBadProofDoesNotConsumeCredentialAndOnlyOnePeerCanExecuteIt() async throws {
    let server = CLIRequestServer { _, _ in CLIEvent(.result, entries: ["Accepted once"]) }
    let loopback = try await SessionLoopback(server: server)
    defer { loopback.close() }
    let endpoint = CLIEndpoint()
    server.register(endpoint)
    let bad = try await loopback.authenticate(endpoint)
    defer { bad.cancel() }
    var request = CLIRequest(operation: .dictionaryList)
    request.authorization = "invalid client proof"
    try await bad.send(request)
    await expectClosed(bad)

    // Both peers can receive the server proof, but only one can consume the credential.
    let first = try await loopback.authenticate(endpoint)
    let second = try await loopback.authenticate(endpoint)
    defer {
      first.cancel()
      second.cancel()
    }
    request.authorization = endpoint.proof(for: "client")
    try await first.send(request)
    let accepted = try await first.receive(CLIEvent.self)
    XCTAssertEqual(accepted.entries, ["Accepted once"])
    try await second.send(request)
    await expectClosed(second)

    let replay = loopback.makeChannel()
    defer { replay.cancel() }
    try await replay.start()
    try await replay.send(CLIEvent(.hello, token: endpoint.id))
    await expectClosed(replay)
  }

  private func expectClosed(_ channel: CLIChannel) async {
    do {
      _ = try await channel.receive(CLIEvent.self)
      XCTFail("A completed or rejected session must close its connection")
    } catch {}
  }

  func testUnauthenticatedConnectionIsClosedAtItsDeadline() async throws {
    let timerStarted = SessionGate()
    let expire = SessionGate()
    let server = CLIRequestServer(
      sleep: { delay in
        XCTAssertEqual(delay, .seconds(5))
        await timerStarted.open()
        await expire.wait()
      },
      execute: { _, _ in
        XCTFail("An unauthenticated connection must not execute work")
        return CLIEvent(.result)
      })
    let loopback = try await SessionLoopback(server: server)
    let channel = loopback.makeChannel()
    defer {
      expire.open()
      channel.cancel()
      loopback.close()
    }
    try await channel.start()
    await timerStarted.wait()

    expire.open()
    await expectClosed(channel)
  }

  func testAuthenticationDeadlineDoesNotLimitAuthenticatedWork() async throws {
    let started = SessionGate()
    let release = SessionGate()
    let expire = SessionGate()
    let timerCancelled = XCTestExpectation(description: "Authentication cancels its deadline")
    let server = CLIRequestServer(
      sleep: { _ in
        await withTaskCancellationHandler {
          await expire.wait()
        } onCancel: {
          timerCancelled.fulfill()
        }
      },
      execute: { _, _ in
        started.open()
        await release.wait()
        return CLIEvent(.result, entries: ["Long transcription"])
      })
    let loopback = try await SessionLoopback(server: server)
    defer {
      expire.open()
      release.open()
      loopback.close()
    }
    let active = Task {
      try await loopback.client.execute(CLIRequest(operation: .transcribe))
    }
    await started.wait()
    let cancelled = await XCTWaiter.fulfillment(of: [timerCancelled], timeout: 3)
    XCTAssertEqual(cancelled, .completed)
    expire.open()
    release.open()

    let response = try await active.value
    XCTAssertEqual(response.entries, ["Long transcription"])
  }

  func testClientRetriesInvalidServerProofBeforeSendingTheRequest() async throws {
    let server = CLIRequestServer { _, _ in CLIEvent(.result, entries: ["Authenticated app"]) }
    var firstConnection = true
    let loopback = try await SessionLoopback(
      server: server,
      serve: { channel in
        if firstConnection {
          firstConnection = false
          defer { channel.cancel() }
          do {
            try await channel.start()
            _ = try await channel.receive(CLIEvent.self)
            try await channel.send(CLIEvent(.hello, token: "wrong server proof"))
            // A peer without the proof must never receive request data.
            _ = try await channel.receive(CLIRequest.self)
            XCTFail("The client sent a request to an unauthenticated peer")
          } catch {}
        } else {
          await server.serve(channel)
        }
      })
    defer { loopback.close() }

    let response = try await loopback.client.execute(CLIRequest(operation: .dictionaryList))
    XCTAssertEqual(response.entries, ["Authenticated app"])
  }

  func testClientStopsRetryingAtTheStartupDeadline() async throws {
    let server = CLIRequestServer { _, _ in
      XCTFail("A peer with the wrong proof must not execute requests")
      return CLIEvent(.result)
    }
    let loopback = try await SessionLoopback(
      server: server,
      serve: { channel in
        defer { channel.cancel() }
        do {
          try await channel.start()
          _ = try await channel.receive(CLIEvent.self)
          try await channel.send(CLIEvent(.hello, token: "wrong server proof"))
        } catch {}
      })
    defer { loopback.close() }
    let start = ContinuousClock.now
    var now = start
    let client = CLIRequestClient(
      launch: { server.register($0) }, makeChannel: loopback.makeChannel,
      now: { now },
      sleep: { delay in
        if delay == .milliseconds(150) {
          now = start + .seconds(30)
        } else {
          try await Task.sleep(for: delay)
        }
      })

    do {
      _ = try await client.execute(CLIRequest(operation: .dictionaryList))
      XCTFail("The startup deadline must end retries")
    } catch let error as CLIError {
      XCTAssertEqual(
        error.message,
        "Could not connect to Cliptate within 30 seconds. Check that it is a direct-download build and the CLI port is available."
      )
    }
  }

  func testFailureFollowsProgressAndSuppressesLateProgress() async throws {
    var lateProgress: (@Sendable (String) -> Void)?
    let server = CLIRequestServer { _, progress in
      lateProgress = progress
      progress("Downloading model")
      throw CLIError("Model unavailable")
    }
    let loopback = try await SessionLoopback(server: server)
    defer { loopback.close() }
    let endpoint = CLIEndpoint()
    server.register(endpoint)
    let channel = try await loopback.authenticate(endpoint)
    defer { channel.cancel() }
    var request = CLIRequest(operation: .transcribe)
    request.authorization = endpoint.proof(for: "client")
    try await channel.send(request)

    let progress = try await channel.receive(CLIEvent.self)
    let failure = try await channel.receive(CLIEvent.self)
    XCTAssertEqual(progress.kind, .progress)
    XCTAssertEqual(progress.message, "Downloading model")
    XCTAssertEqual(failure.kind, .failure)
    XCTAssertEqual(failure.message, "Model unavailable")
    lateProgress?("Too late")
    await expectClosed(channel)
  }

  func testClientDoesNotRetryMutationWhenAuthenticatedConnectionCloses() async throws {
    var entries: [String] = []
    var activeChannel: CLIChannel?
    let server = CLIRequestServer { request, _ in
      if request.operation == .dictionaryAdd {
        entries.append(contentsOf: request.entries)
        // The mutation committed, but its response cannot reach the caller.
        activeChannel?.cancel()
      }
      return CLIEvent(.result, entries: entries)
    }
    let loopback = try await SessionLoopback(
      server: server,
      serve: { channel in
        activeChannel = channel
        await server.serve(channel)
      })
    defer { loopback.close() }
    do {
      _ = try await loopback.client.execute(
        CLIRequest(operation: .dictionaryAdd, entries: ["Cliptate"]))
      XCTFail("The client must report the lost response")
    } catch {}

    let dictionary = try await loopback.client.execute(CLIRequest(operation: .dictionaryList))
    XCTAssertEqual(dictionary.entries, ["Cliptate"])
  }

  func testExpiredCredentialsAreRejectedAndRegistrationReclaimsCapacity() async throws {
    var now = Date(timeIntervalSince1970: 100)
    let server = CLIRequestServer(
      now: { now }, execute: { _, _ in CLIEvent(.result, entries: ["Fresh"]) })
    let old = CLIEndpoint()
    XCTAssertTrue(server.register(old))
    for _ in 1..<100 { XCTAssertTrue(server.register(CLIEndpoint())) }
    XCTAssertFalse(server.register(CLIEndpoint()))
    let loopback = try await SessionLoopback(server: server)
    defer { loopback.close() }

    now = Date(timeIntervalSince1970: 160)
    let expired = loopback.makeChannel()
    defer { expired.cancel() }
    try await expired.start()
    try await expired.send(CLIEvent(.hello, token: old.id))
    await expectClosed(expired)

    let fresh = try await loopback.client.execute(CLIRequest(operation: .dictionaryList))
    XCTAssertEqual(fresh.entries, ["Fresh"])
  }
}

@MainActor
private final class SessionGate {
  private var isOpen = false
  private var waiting: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    if isOpen { return }
    await withCheckedContinuation { waiting.append($0) }
  }

  func open() {
    isOpen = true
    let continuations = waiting
    waiting.removeAll()
    for continuation in continuations { continuation.resume() }
  }
}

/// Real framed connections exercise the same request seam as the embedded command.
@MainActor
private final class SessionLoopback {
  let client: CLIRequestClient
  let makeChannel: @MainActor () -> CLIChannel
  private let listener: NWListener
  private let connections: AsyncStream<CLIChannel>.Continuation
  private var accepting: Task<Void, Never>?
  private var requests: [Task<Void, Never>] = []

  init(
    server: CLIRequestServer,
    serve: (@MainActor (CLIChannel) async -> Void)? = nil
  ) async throws {
    let listener = try NWListener(using: .tcp, on: .any)
    self.listener = listener
    let incoming = AsyncStream<CLIChannel>.makeStream()
    connections = incoming.continuation
    listener.newConnectionHandler = { connection in
      incoming.continuation.yield(CLIChannel(connection: connection))
    }
    let port: NWEndpoint.Port = try await withCheckedThrowingContinuation { continuation in
      listener.stateUpdateHandler = { state in
        if case .ready = state, let port = listener.port { continuation.resume(returning: port) }
        if case .failed(let error) = state { continuation.resume(throwing: error) }
      }
      listener.start(queue: DispatchQueue(label: "cli.session.test.listener"))
    }
    let makeChannel: @MainActor () -> CLIChannel = {
      CLIChannel(connection: NWConnection(host: "127.0.0.1", port: port, using: .tcp))
    }
    self.makeChannel = makeChannel
    client = CLIRequestClient(launch: { server.register($0) }, makeChannel: makeChannel)
    let serve: @MainActor (CLIChannel) async -> Void = serve ?? { await server.serve($0) }
    accepting = Task { [weak self] in
      for await channel in incoming.stream {
        guard let self else {
          channel.cancel()
          return
        }
        requests.append(Task { await serve(channel) })
      }
    }
  }

  func close() {
    listener.cancel()
    connections.finish()
    accepting?.cancel()
    for request in requests { request.cancel() }
  }

  func drain() async {
    let current = requests
    for request in current { await request.value }
  }

  func authenticate(_ endpoint: CLIEndpoint) async throws -> CLIChannel {
    let channel = makeChannel()
    try await channel.start()
    try await channel.send(CLIEvent(.hello, token: endpoint.id))
    let hello = try await channel.receive(CLIEvent.self)
    XCTAssertEqual(hello.kind, .hello)
    XCTAssertEqual(hello.token, endpoint.proof(for: "server"))
    return channel
  }
}
