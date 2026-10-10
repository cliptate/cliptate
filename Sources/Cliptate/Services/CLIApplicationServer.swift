import AppKit
import Foundation
@preconcurrency import Network

#if canImport(CliptateCLIKit)
  import CliptateCLIKit
#endif

/// Only direct builds create a listener. The App Store variant remains inert.
@MainActor
final class CLIApplicationServer {
  static let shared = CLIApplicationServer()
  private var listener: NWListener?
  private var endpoints: [String: (CLIEndpoint, Date)] = [:]
  private var transcribing = false

  func connect(url: URL) {
    #if !APP_STORE
      guard let endpoint = CLIEndpoint(url: url) else { return }
      endpoints = endpoints.filter { $0.value.1 > Date() }
      guard endpoints.count < 100 else { return }
      endpoints[endpoint.id] = (endpoint, Date().addingTimeInterval(60))
      guard listener == nil else { return }
      do {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
          host: "127.0.0.1", port: NWEndpoint.Port(rawValue: CLIEndpoint.port)!)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { connection in
          Task { @MainActor in await self.handle(CLIChannel(connection: connection)) }
        }
        listener.stateUpdateHandler = { state in
          if case .failed = state {
            Task { @MainActor in
              self.listener?.cancel()
              self.listener = nil
            }
          }
        }
        self.listener = listener
        listener.start(queue: DispatchQueue(label: "com.cliptate.cli.listener"))
      } catch {
        // The client has a bounded startup deadline and reports an unavailable port.
        listener = nil
      }
    #endif
  }

  private func handle(_ channel: CLIChannel) async {
    defer { channel.cancel() }
    // Bound unauthenticated connections without imposing a transcription timeout.
    let timeout = Task {
      try? await Task.sleep(for: .seconds(5))
      if !Task.isCancelled { channel.cancel() }
    }
    do {
      try await channel.start()
      let hello = try await channel.receive(CLIEvent.self)
      guard hello.kind == .hello, let id = hello.token,
        let (endpoint, expiry) = endpoints[id], expiry > Date()
      else { return }
      try await channel.send(CLIEvent(.hello, token: endpoint.proof(for: "server")))
      let request = try await channel.receive(CLIRequest.self)
      guard request.authorization == endpoint.proof(for: "client"),
        endpoints.removeValue(forKey: id) != nil, expiry > Date()
      else { return }
      timeout.cancel()
      if request.operation == .transcribe && transcribing {
        try await channel.send(
          CLIEvent(
            .failure,
            message: String(
              localized: "Another CLI transcription is running. Try again when it finishes.")))
        return
      }
      if request.operation == .transcribe { transcribing = true }
      defer { if request.operation == .transcribe { transcribing = false } }
      let work = Task {
        do {
          let handler = CLIRequestHandler(config: AppConfiguration.shared)
          let response = try await handler.execute(
            request,
            progress: { message in
              Task { try? await channel.send(CLIEvent(.progress, message: message)) }
            })
          try await channel.send(response)
        } catch {
          if !Task.isCancelled {
            try? await channel.send(CLIEvent(.failure, message: error.localizedDescription))
          }
        }
      }
      // EOF (including SIGINT, SIGTERM, or a killed CLI) cancels inference cooperatively.
      let disconnect = Task {
        _ = try? await channel.receive(CLIEvent.self)
        work.cancel()
      }
      await work.value
      disconnect.cancel()
    } catch {}
    timeout.cancel()
  }
}

@MainActor
final class CLIApplicationLifecycle: ObservableObject {
  static let shared = CLIApplicationLifecycle()
  @Published var backgroundLaunch = ProcessInfo.processInfo.arguments.contains("--cliptate-cli")
}

@MainActor
final class CLIApplicationDelegate: NSObject, NSApplicationDelegate {
  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls { CLIApplicationServer.shared.connect(url: url) }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    CLIApplicationLifecycle.shared.backgroundLaunch = false
    if !LightweightModeManager.shared.isActive { LightweightModeManager.shared.showMainWindow() }
    return true
  }
}
