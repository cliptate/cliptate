import Darwin
import Foundation

/// The installed application's identity selects its storage and local CLI namespace.
public enum AppIdentity: String, Sendable {
  case production = "com.cliptate.app"
  case development = "com.cliptate.dev"

  public init(bundleIdentifier: String?) {
    self = bundleIdentifier == Self.development.rawValue ? .development : .production
  }

  public static var current: Self {
    Self(bundleIdentifier: CLILocalization.bundle.bundleIdentifier)
  }

  public var dataDirectoryName: String {
    self == .development ? "Cliptate Dev" : "Cliptate"
  }

  public func applicationSupportDirectory(fileManager: FileManager = .default) -> URL {
    let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.temporaryDirectory
    return base.appendingPathComponent(dataDirectoryName, isDirectory: true)
  }

  public var sandboxDataDirectoryNames: [String] {
    self == .development ? [dataDirectoryName] : ["Cliptate", "VoiceFlowPro"]
  }

  public var sandboxPreferencesMigrationMarker: String {
    self == .development ? ".cliptate-dev-sandbox-preferences-v1" : ".cliptate-sandbox-preferences-v1"
  }

  public var cliURLScheme: String {
    self == .development ? "cliptate-dev-cli" : "cliptate-cli"
  }

  public func cliPort(userID: UInt32 = getuid()) -> UInt16 {
    // Preserve the production protocol's port; development uses a disjoint range.
    UInt16((self == .development ? 32768 : 49152) + userID % 16000)
  }
}
