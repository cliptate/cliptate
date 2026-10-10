import Foundation

@MainActor
protocol ConfigurationSnapshotPersisting: AnyObject {
  func bind(to config: AppConfiguration)
  func loadSnapshot() -> AppConfiguration.Snapshot?
  func clearSnapshot()
  func flush(using config: AppConfiguration) throws
}

extension AppConfigurationPersistence: ConfigurationSnapshotPersisting {}

@MainActor
protocol ConfigurationPresetManaging: AnyObject {
  var presets: [ConfigPreset] { get }
  func load() throws
  func apply(id: UUID, to config: AppConfiguration) throws
  func ensureDefaultPreset(using config: AppConfiguration) throws -> ConfigPreset
}

extension ConfigPresetStore: ConfigurationPresetManaging {}

@MainActor
final class ConfigurationRuntime: ObservableObject {
  struct BootstrapResult: Equatable {
    let appliedStoredSnapshot: Bool
  }

  static let shared = ConfigurationRuntime()

  private let persistence: any ConfigurationSnapshotPersisting
  private let presetStore: any ConfigurationPresetManaging
  private let modelRuntime: any ModelRuntimeControlling
  private let migrate: @MainActor (AppConfiguration) -> Void

  init(
    persistence: (any ConfigurationSnapshotPersisting)? = nil,
    presetStore: (any ConfigurationPresetManaging)? = nil,
    modelRuntime: (any ModelRuntimeControlling)? = nil,
    migrate: @escaping @MainActor (AppConfiguration) -> Void = { config in
      let migrationKey = "filter-punctuation-default-false-v1"
      guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
      config.keepPunctuationOnExport = true
      UserDefaults.standard.set(true, forKey: migrationKey)
    }
  ) {
    self.persistence = persistence ?? AppConfigurationPersistence.shared
    self.presetStore = presetStore ?? ConfigPresetStore.shared
    self.modelRuntime = modelRuntime ?? ModelRuntime.shared
    self.migrate = migrate
  }

  @discardableResult
  func bootstrap(using config: AppConfiguration) -> BootstrapResult {
    persistence.bind(to: config)
    try? presetStore.load()

    let appliedStoredSnapshot: Bool
    if let storedSnapshot = persistence.loadSnapshot() {
      config.applySnapshot(storedSnapshot)
      appliedStoredSnapshot = true
    } else {
      if let defaultPresetID = resolvedDefaultPresetID(using: config) {
        try? presetStore.apply(id: defaultPresetID, to: config)
      }
      appliedStoredSnapshot = false
    }

    migrate(config)
    modelRuntime.prepare(using: config)

    return BootstrapResult(appliedStoredSnapshot: appliedStoredSnapshot)
  }

  func applyPreset(id: UUID, to config: AppConfiguration) throws {
    try presetStore.apply(id: id, to: config)
    migrate(config)
    modelRuntime.prepare(using: config)
  }

  func resetToDefaults(using config: AppConfiguration) {
    config.resetToDefaults()
    migrate(config)
    modelRuntime.prepare(using: config)
  }

  func flush(using config: AppConfiguration) throws {
    try persistence.flush(using: config)
  }

  private func resolvedDefaultPresetID(using config: AppConfiguration) -> UUID? {
    if let existingDefault = presetStore.presets.first(where: { $0.isDefault }) {
      return existingDefault.id
    }

    return try? presetStore.ensureDefaultPreset(using: config).id
  }
}
