import Foundation
@preconcurrency import Network

/// Length-prefixed JSON. Each connection carries one authenticated request.
public final class CLIChannel: @unchecked Sendable {
  public static let maximumFrameSize = 16 * 1024 * 1024
  private let connection: NWConnection
  private let queue = DispatchQueue(label: "com.cliptate.cli.channel")

  public init(connection: NWConnection) { self.connection = connection }
  public convenience init() {
    self.init(
      connection: NWConnection(
        host: "127.0.0.1", port: NWEndpoint.Port(rawValue: CLIEndpoint.port)!, using: .tcp))
  }

  public func cancel() { connection.cancel() }

  public func start() async throws {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        let completion = CLICompletion(continuation)
        connection.stateUpdateHandler = { state in
          switch state {
          case .ready: completion.finish(.success(()))
          case .failed(let error): completion.finish(.failure(error))
          case .cancelled: completion.finish(.failure(CancellationError()))
          default: break
          }
        }
        connection.start(queue: queue)
        if Task.isCancelled { connection.cancel() }
      }
    } onCancel: {
      self.cancel()
    }
  }

  public func send<T: Encodable & Sendable>(_ value: T) async throws {
    try Task.checkCancellation()
    let data = try JSONEncoder().encode(value)
    guard data.count <= Self.maximumFrameSize else { throw Self.protocolError() }
    var size = UInt32(data.count).bigEndian
    let frame = withUnsafeBytes(of: &size) { Data($0) } + data
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        connection.send(
          content: frame,
          completion: .contentProcessed { error in
            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
          })
      }
    } onCancel: {
      self.cancel()
    }
  }

  public func receive<T: Decodable & Sendable>(_ type: T.Type) async throws -> T {
    let header = try await read(count: 4)
    let size = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    guard size > 0, size <= Self.maximumFrameSize else { throw Self.protocolError() }
    return try JSONDecoder().decode(type, from: await read(count: Int(size)))
  }

  private func read(count: Int) async throws -> Data {
    var result = Data()
    while result.count < count {
      try Task.checkCancellation()
      let remaining = count - result.count
      let chunk: Data = try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) {
            data, _, complete, error in
            if let error {
              continuation.resume(throwing: error)
            } else if let data, !data.isEmpty {
              continuation.resume(returning: data)
            } else if complete {
              continuation.resume(throwing: Self.protocolError())
            } else {
              continuation.resume(throwing: Self.protocolError())
            }
          }
        }
      } onCancel: {
        self.cancel()
      }
      result.append(chunk)
    }
    return result
  }

  public static func protocolError() -> CLIError {
    CLIError(
      String(
        localized: "The CLI connection closed or returned invalid data.",
        bundle: CLILocalization.bundle))
  }
}

private final class CLICompletion: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Error>?
  init(_ continuation: CheckedContinuation<Void, Error>) { self.continuation = continuation }
  func finish(_ result: Result<Void, Error>) {
    lock.lock()
    let pending = continuation
    continuation = nil
    lock.unlock()
    pending?.resume(with: result)
  }
}
