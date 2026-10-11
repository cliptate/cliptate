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
  private let requests = CLIRequestServer { request, progress in
    try await CLIRequestHandler(config: AppConfiguration.shared).execute(
      request, progress: progress)
  }

  func connect(url: URL) {
    #if !APP_STORE
      guard let endpoint = CLIEndpoint(url: url) else { return }
      guard requests.register(endpoint) else { return }
      guard listener == nil else { return }
      do {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
          host: "127.0.0.1", port: NWEndpoint.Port(rawValue: CLIEndpoint.port)!)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { connection in
          Task { @MainActor in await self.requests.serve(CLIChannel(connection: connection)) }
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
