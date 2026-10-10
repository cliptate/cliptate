import AVFoundation
import AudioKit
import CryptoKit
import Foundation
import OSLog

/// Waveform amplitude snapshot ready for rendering.
struct WaveformSnapshot: Codable, Sendable {
  /// Absolute amplitudes per channel in the range [0, 1].
  let channels: [[Float]]
  /// Number of source samples grouped into a single point.
  let samplesPerPixel: Int
  /// Total frame count of the underlying audio file.
  let totalFrames: Int
  /// Duration of the underlying audio in seconds.
  let duration: TimeInterval

  var channelCount: Int { channels.count }
  var pointCount: Int { channels.first?.count ?? 0 }
}

/// Repository responsible for extracting and caching waveform amplitudes using AudioKit.
actor WaveformRepository {
  static let shared = WaveformRepository()

  private struct CacheKey: Hashable {
    let url: URL
    let samplesPerPixel: Int
    let mixToMono: Bool
    let revisionToken: String
  }

  private let fileManager: FileManager
  private let cacheDirectory: URL
  private var memoryCache: [CacheKey: WaveformSnapshot] = [:]
  private let logger = Logger(subsystem: "com.Cliptate", category: "WaveformRepository")

  init(fileManager: FileManager = .default) {
    self.fileManager = fileManager
    let baseCache =
      fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    let directory = baseCache.appendingPathComponent("WaveformCache", isDirectory: true)
    if !fileManager.fileExists(atPath: directory.path) {
      try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    cacheDirectory = directory
  }

  /// Preload or return a cached waveform snapshot for the provided media URL.
  /// - Parameters:
  ///   - url: Media file location.
  ///   - targetPointCount: Desired horizontal resolution (usually view width * scale).
  ///   - mixToMono: Whether to average all channels to mono before rendering.
  func loadWaveform(
    for url: URL,
    targetPointCount: Int,
    mixToMono: Bool
  ) async throws -> WaveformSnapshot {
    let resolvedURL = url.standardizedFileURL
    let needsStop = resolvedURL.startAccessingSecurityScopedResource()
    defer { if needsStop { resolvedURL.stopAccessingSecurityScopedResource() } }

    let attributes = try fileManager.attributesOfItem(atPath: resolvedURL.path)
    let modificationDate =
      (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
    let revisionToken = Self.makeRevisionToken(modificationDate: modificationDate)

    let audioFile = try AVAudioFile(forReading: resolvedURL)
    let totalFrames = max(Int(audioFile.length), 1)
    let desiredPoints = max(targetPointCount, 1)
    let samplesPerPixel = max(1, totalFrames / desiredPoints)
    let cacheKey = CacheKey(
      url: resolvedURL,
      samplesPerPixel: samplesPerPixel,
      mixToMono: mixToMono,
      revisionToken: revisionToken
    )

    if let cached = memoryCache[cacheKey] {
      return cached
    }

    if let diskCached = try? loadFromDisk(for: cacheKey) {
      memoryCache[cacheKey] = diskCached
      return diskCached
    }

    let snapshot = try await extractSnapshot(
      audioFile: audioFile,
      totalFrames: totalFrames,
      samplesPerPixel: samplesPerPixel,
      mixToMono: mixToMono
    )
    memoryCache[cacheKey] = snapshot
    saveToDisk(snapshot, for: cacheKey)
    return snapshot
  }

  private func extractSnapshot(
    audioFile: AVAudioFile,
    totalFrames: Int,
    samplesPerPixel: Int,
    mixToMono: Bool
  ) async throws -> WaveformSnapshot {
    let request = WaveformDataRequest(audioFile: audioFile)
    guard let data = request.getData(with: samplesPerPixel) else {
      throw WaveformError.failedToDecode
    }

    let normalized = Self.normalize(channelData: data, mixToMono: mixToMono)
    let duration = Double(totalFrames) / audioFile.processingFormat.sampleRate
    return WaveformSnapshot(
      channels: normalized,
      samplesPerPixel: samplesPerPixel,
      totalFrames: totalFrames,
      duration: duration
    )
  }

  private func loadFromDisk(for key: CacheKey) throws -> WaveformSnapshot? {
    let url = cacheURL(for: key)
    guard fileManager.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    let decoder = PropertyListDecoder()
    return try decoder.decode(WaveformSnapshot.self, from: data)
  }

  private func saveToDisk(_ snapshot: WaveformSnapshot, for key: CacheKey) {
    let url = cacheURL(for: key)
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    do {
      let data = try encoder.encode(snapshot)
      try data.write(to: url, options: [.atomic])
    } catch {
      logger.error(
        "Failed to persist waveform snapshot: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func cacheURL(for key: CacheKey) -> URL {
    let identifier = "\(key.url.path)|\(key.samplesPerPixel)|\(key.mixToMono)|\(key.revisionToken)"
    let hash = SHA256.hash(data: Data(identifier.utf8)).map { String(format: "%02x", $0) }.joined()
    return cacheDirectory.appendingPathComponent("\(hash).waveform")
  }

  private static func normalize(channelData: [[Float]], mixToMono: Bool) -> [[Float]] {
    guard !channelData.isEmpty else { return [] }
    let pointCount = channelData.first?.count ?? 0
    if mixToMono || channelData.count == 1 {
      var mono = [Float](repeating: 0, count: pointCount)
      for channel in channelData {
        for index in 0..<min(pointCount, channel.count) {
          mono[index] += abs(channel[index])
        }
      }
      let scale = 1 / Float(max(1, channelData.count))
      for index in 0..<mono.count {
        mono[index] = min(1, mono[index] * scale)
      }
      return [mono]
    } else {
      return channelData.map { channel in
        channel.prefix(pointCount).map { value in
          min(1, abs(value))
        }
      }
    }
  }

  private static func makeRevisionToken(modificationDate: TimeInterval) -> String {
    String(format: "%.0f", modificationDate)
  }

  enum WaveformError: Error {
    case failedToDecode
  }
}
