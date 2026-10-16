import Darwin
import Foundation

import CliptateCore

/// Copies missing data and preferences once while retaining originals and migration markers.
enum DirectAppDataMigration {
  static func run() throws {
    #if !APP_STORE
      guard let identifier = Bundle.main.bundleIdentifier,
        let passwd = getpwuid(getuid())
      else { return }
      let home = URL(fileURLWithPath: String(cString: passwd.pointee.pw_dir))
      try run(home: home, bundleIdentifier: identifier, userDefaults: .standard)
    #endif
  }

  static func run(home: URL, bundleIdentifier: String, userDefaults: UserDefaults) throws {
    let identity = AppIdentity(bundleIdentifier: bundleIdentifier)
    let legacyIdentifiers = bundleIdentifier == AppIdentity.production.rawValue
      ? ["com.voicepink.voicepinkpro"] : []
    let identifiers = [bundleIdentifier] + legacyIdentifiers
    let libraries = identifiers.map {
      home.appendingPathComponent("Library/Containers/\($0)/Data/Library")
    }
    let support = home.appendingPathComponent("Library/Application Support")
    for name in identity.sandboxDataDirectoryNames {
      try copyMissingData(
        from: libraries.map { $0.appendingPathComponent("Application Support/\(name)") },
        to: support.appendingPathComponent(name))
    }
    if !legacyIdentifiers.isEmpty {
      try copyMissingPreferences(
        from: legacyIdentifiers.map { home.appendingPathComponent("Library/Preferences/\($0).plist") },
        to: userDefaults,
        marker: support.appendingPathComponent(".cliptate-identity-preferences-v1"))
    }
    try copyMissingPreferences(
      from: zip(libraries, identifiers).map { library, identifier in
        library.appendingPathComponent("Preferences/\(identifier).plist")
      },
      to: userDefaults,
      marker: support.appendingPathComponent(identity.sandboxPreferencesMigrationMarker))
  }

  private static func copyMissingPreferences(from sources: [URL], to defaults: UserDefaults, marker: URL) throws {
    guard !FileManager.default.fileExists(atPath: marker.path) else { return }
    var foundSource = false
    for source in sources where FileManager.default.fileExists(atPath: source.path) {
      guard let stored = try PropertyListSerialization.propertyList(
        from: Data(contentsOf: source), format: nil) as? [String: Any] else { continue }
      foundSource = true
      for (key, value) in stored where defaults.object(forKey: key) == nil {
        defaults.set(value, forKey: key)
      }
    }
    if foundSource {
      try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data().write(to: marker, options: .atomic)
    }
  }

  static func copyMissingData(
    from source: URL, to destination: URL, fileManager: FileManager = .default
  ) throws {
    try copyMissingData(from: [source], to: destination, fileManager: fileManager)
  }

  private static func copyMissingData(
    from sources: [URL], to destination: URL, fileManager: FileManager = .default
  ) throws {
    let marker = destination.appendingPathComponent(".sandbox-migration-v1")
    let existingSources = sources.filter { fileManager.fileExists(atPath: $0.path) }
    guard !existingSources.isEmpty, !fileManager.fileExists(atPath: marker.path) else { return }
    func copy(_ source: URL, _ target: URL) throws {
      var directory: ObjCBool = false
      guard fileManager.fileExists(atPath: source.path, isDirectory: &directory) else { return }
      if directory.boolValue {
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        for child in try fileManager.contentsOfDirectory(
          at: source, includingPropertiesForKeys: nil)
        {
          try copy(child, target.appendingPathComponent(child.lastPathComponent))
        }
      } else if !fileManager.fileExists(atPath: target.path) {
        try fileManager.copyItem(at: source, to: target)
      }
    }
    for source in existingSources { try copy(source, destination) }
    try Data().write(to: marker, options: .atomic)
  }
}
