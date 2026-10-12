@preconcurrency import Network
import XCTest

@testable import Cliptate

#if canImport(CliptateCLIKit)
  import CliptateCLIKit
#endif

final class CLIChannelTests: XCTestCase {
  func testLaunchCredentialsRoundTripAndSeparateClientServerProofs() throws {
    let endpoint = CLIEndpoint()
    let restored = try XCTUnwrap(CLIEndpoint(url: endpoint.url))
    XCTAssertEqual(restored.id, endpoint.id)
    XCTAssertEqual(restored.proof(for: "server"), endpoint.proof(for: "server"))
    XCTAssertNotEqual(endpoint.proof(for: "server"), endpoint.proof(for: "client"))
    XCTAssertNotEqual(endpoint.proof(for: "server"), CLIEndpoint().proof(for: "server"))
    XCTAssertNil(CLIEndpoint(url: URL(string: "cliptate-cli://connect?id=invalid&secret=invalid")!))
    XCTAssertNil(CLIEndpoint(url: URL(string: "https://connect?id=invalid&secret=invalid")!))
  }

  func testFramingPreservesUnicodeAndCancellingPendingReadTerminatesIt() async throws {
    let listener = try NWListener(using: .tcp, on: .any)
    defer { listener.cancel() }
    let incoming = AsyncStream<NWConnection>.makeStream()
    defer { incoming.continuation.finish() }
    listener.newConnectionHandler = { incoming.continuation.yield($0) }
    let peer = Task { () throws -> CLIChannel in
      var connections = incoming.stream.makeAsyncIterator()
      let received = await connections.next()
      let connection = try XCTUnwrap(received)
      let channel = CLIChannel(connection: connection)
      try await channel.start()
      return channel
    }
    let port: NWEndpoint.Port = try await withCheckedThrowingContinuation { continuation in
      listener.stateUpdateHandler = { state in
        if case .ready = state, let port = listener.port { continuation.resume(returning: port) }
        if case .failed(let error) = state { continuation.resume(throwing: error) }
      }
      listener.start(queue: DispatchQueue(label: "cli.test.listener"))
    }
    let client = CLIChannel(connection: NWConnection(host: "127.0.0.1", port: port, using: .tcp))
    defer { client.cancel() }
    try await client.start()
    let server = try await peer.value
    defer { server.cancel() }
    try await client.send(
      CLIRequest(operation: .dictionaryAdd, entries: ["你好", "Café", "\"quoted\""]))
    let request = try await server.receive(CLIRequest.self)
    XCTAssertEqual(request.entries, ["你好", "Café", "\"quoted\""])
    try await server.send(CLIEvent(.result, entries: request.entries))
    let event = try await client.receive(CLIEvent.self)
    XCTAssertEqual(event.entries, request.entries)
    let read = Task { try await server.receive(CLIEvent.self) }
    read.cancel()
    do {
      _ = try await read.value
      XCTFail("Cancelled read should end")
    } catch {}
  }
}
