import Darwin
import Foundation

import CliptateCore

/// Copies legacy sandbox data once; never removes originals or replaces direct-build data.
enum DirectAppDataMigration {
  static func run() throws {
    #if !APP_STORE
      guard let identifier = Bundle.main.bundleIdentifier,
        let passwd = getpwuid(getuid())
      else { return }
      let home = URL(fileURLWithPath: String(cString: passwd.pointee.pw_dir))
      let legacyLibrary = home.appendingPathComponent(
        "Library/Containers/\(identifier)/Data/Library")
      let support = home.appendingPathComponent("Library/Application Support")
      let identity = AppIdentity(bundleIdentifier: identifier)
      for name in identity.sandboxDataDirectoryNames {
        try copyMissingData(
          from: legacyLibrary.appendingPathComponent("Application Support/\(name)"),
          to: support.appendingPathComponent(name))
      }
      let preferences = legacyLibrary.appendingPathComponent("Preferences/\(identifier).plist")
      let preferenceMarker = support.appendingPathComponent(identity.sandboxPreferencesMigrationMarker)
      if FileManager.default.fileExists(atPath: preferences.path),
        !FileManager.default.fileExists(atPath: preferenceMarker.path),
        let stored = try PropertyListSerialization.propertyList(
          from: Data(contentsOf: preferences), format: nil) as? [String: Any]
      {
        var current = UserDefaults.standard.persistentDomain(forName: identifier) ?? [:]
        let originalCount = current.count
        for (key, value) in stored where current[key] == nil { current[key] = value }
        if current.count != originalCount {
          UserDefaults.standard.setPersistentDomain(current, forName: identifier)
        }
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try Data().write(to: preferenceMarker, options: .atomic)
      }
    #endif
  }

  static func copyMissingData(
    from source: URL, to destination: URL, fileManager: FileManager = .default
  ) throws {
    let marker = destination.appendingPathComponent(".sandbox-migration-v1")
    guard fileManager.fileExists(atPath: source.path), !fileManager.fileExists(atPath: marker.path)
    else { return }
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
    try copy(source, destination)
    try Data().write(to: marker, options: .atomic)
  }
}
