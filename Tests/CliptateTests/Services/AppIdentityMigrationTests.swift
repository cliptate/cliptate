import CliptateCore
import Foundation
import Testing
@testable import Cliptate

struct AppIdentityMigrationTests {
  @Test(arguments: [AppIdentity.production.rawValue, AppIdentity.development.rawValue, "com.example.fork"])
  func migrationPreservesDataAndPreferencesWithoutCrossingIntoDev(bundleIdentifier: String) throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = "CliptateMigrationTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: home)
    }
    let legacyLibrary = home.appendingPathComponent("Library/Containers/com.voicepink.voicepinkpro/Data/Library")
    let legacyData = legacyLibrary.appendingPathComponent("Application Support/Cliptate")
    let directData = home.appendingPathComponent("Library/Application Support/Cliptate")
    let preferences = home.appendingPathComponent("Library/Preferences/com.voicepink.voicepinkpro.plist")
    for directory in [legacyData, directData, preferences.deletingLastPathComponent()] {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    try Data("history".utf8).write(to: legacyData.appendingPathComponent("history.json"))
    try Data("old".utf8).write(to: legacyData.appendingPathComponent("config.json"))
    try Data("current".utf8).write(to: directData.appendingPathComponent("config.json"))
    try PropertyListSerialization.data(fromPropertyList: ["appLanguageCode": "ja", "appearance": "dark"], format: .xml, options: 0).write(to: preferences)
    let sandboxPreferences = legacyLibrary.appendingPathComponent("Preferences/com.voicepink.voicepinkpro.plist")
    try FileManager.default.createDirectory(at: sandboxPreferences.deletingLastPathComponent(), withIntermediateDirectories: true)
    try PropertyListSerialization.data(fromPropertyList: ["appearance": "sandbox-stale"], format: .xml, options: 0).write(to: sandboxPreferences)
    defaults.set("de", forKey: "appLanguageCode")
    try DirectAppDataMigration.run(home: home, bundleIdentifier: bundleIdentifier, userDefaults: defaults)
    #expect(try String(contentsOf: directData.appendingPathComponent("config.json"), encoding: .utf8) == "current")
    #expect(defaults.string(forKey: "appLanguageCode") == "de")
    let migratedHistory = directData.appendingPathComponent("history.json")
    if bundleIdentifier == AppIdentity.production.rawValue {
      #expect(try Data(contentsOf: migratedHistory) == Data("history".utf8))
      #expect(defaults.string(forKey: "appearance") == "dark")
      try FileManager.default.removeItem(at: migratedHistory)
      defaults.removeObject(forKey: "appearance")
      try DirectAppDataMigration.run(home: home, bundleIdentifier: bundleIdentifier, userDefaults: defaults)
      #expect(!FileManager.default.fileExists(atPath: migratedHistory.path))
      #expect(defaults.string(forKey: "appearance") == nil)
    } else {
      #expect(!FileManager.default.fileExists(atPath: migratedHistory.path))
      #expect(defaults.string(forKey: "appearance") == nil)
    }
    #expect(FileManager.default.fileExists(atPath: legacyData.appendingPathComponent("history.json").path))
  }
}
