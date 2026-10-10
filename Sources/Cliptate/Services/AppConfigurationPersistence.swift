import Combine
import Foundation
import os.log

@MainActor
final class AppConfigurationPersistence: ObservableObject {
    static let shared = AppConfigurationPersistence()

    private let fileURL: URL
    private var cancellable: AnyCancellable?
    private var saveTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.Cliptate", category: "AppConfiguration")

    private init() {
        let support =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = support.appendingPathComponent("Cliptate", isDirectory: true)

        // Migrate from legacy VoiceFlowPro directory if it exists
        let legacyDirectory = support.appendingPathComponent("VoiceFlowPro", isDirectory: true)
        if FileManager.default.fileExists(atPath: legacyDirectory.path),
           !FileManager.default.fileExists(atPath: directory.path)
        {
            do {
                try FileManager.default.moveItem(at: legacyDirectory, to: directory)
                logger.info("Migrated config from VoiceFlowPro to Cliptate directory")
            } catch {
                logger.error("Failed to migrate config directory: \(error.localizedDescription)")
            }
        }

        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create config directory: \(error.localizedDescription)")
        }
        fileURL = directory.appendingPathComponent("app-configuration.json", isDirectory: false)
    }

    func bind(to config: AppConfiguration) {
        cancellable = config.objectWillChange.sink { [weak self, weak config] _ in
            guard let self, let config else { return }
            self.scheduleSave(for: config)
        }
    }

    func loadSnapshot() -> AppConfiguration.Snapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(AppConfiguration.Snapshot.self, from: data)
        } catch {
            logger.error("Failed to load configuration snapshot: \(error.localizedDescription)")
            return nil
        }
    }

    func clearSnapshot() {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            logger.error("Failed to clear configuration snapshot: \(error.localizedDescription)")
        }
    }

    private func scheduleSave(for config: AppConfiguration) {
        saveTask?.cancel()
        saveTask = Task { [weak self, weak config] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let config else { return }
            let snapshot = await MainActor.run { config.makeSnapshot() }
            self?.persist(snapshot: snapshot)
        }
    }

    nonisolated private func persist(snapshot: AppConfiguration.Snapshot) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save configuration snapshot: \(error.localizedDescription)")
        }
    }
}
