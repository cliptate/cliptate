import Foundation

/// Identifies a type of export operation.
public enum ExportPhaseType: String, Sendable, Equatable, Identifiable {
  case fcpxml
  case subtitle
  case video
  case audio

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .fcpxml: return String(localized: "FCPXML", comment: "Export phase type: Final Cut Pro XML")
    case .subtitle: return String(localized: "Subtitles", comment: "Export phase type: subtitle files")
    case .video: return String(localized: "Video", comment: "Export phase type: video files")
    case .audio: return String(localized: "Audio", comment: "Export phase type: audio files")
    }
  }

  public var iconName: String {
    switch self {
    case .fcpxml: return "doc.text"
    case .subtitle: return "captions.bubble"
    case .video: return "film"
    case .audio: return "waveform"
    }
  }
}

/// Status of an individual export phase.
public enum ExportPhaseStatus: Sendable, Equatable {
  case pending
  case inProgress
  case completed
  case failed
}

/// Tracks progress for a single export phase.
public struct ExportPhase: Sendable, Equatable, Identifiable {
  public let type: ExportPhaseType
  public var progress: Double
  public var status: ExportPhaseStatus
  public var failureMessage: String?

  public var id: String { type.rawValue }

  public init(type: ExportPhaseType) {
    self.type = type
    self.progress = 0.0
    self.status = .inProgress
  }
}

/// Observable state object tracking multi-phase export progress.
public struct ExportProgressState: Sendable, Equatable {
  public var phases: [ExportPhase] = []

  public init() {}

  /// Whether any phase is currently in progress.
  public var isActive: Bool {
    phases.contains { $0.status == .inProgress }
  }

  /// Average progress across all phases (0.0–1.0).
  public var overallProgress: Double {
    guard !phases.isEmpty else { return 0.0 }
    let total = phases.reduce(0.0) { $0 + $1.progress }
    return total / Double(phases.count)
  }

  /// Display label of the currently in-progress phase.
  public var currentPhaseLabel: String? {
    phases.first(where: { $0.status == .inProgress })?.type.displayName
  }

  /// Begin tracking a new export phase.
  public mutating func startPhase(_ type: ExportPhaseType) {
    phases.append(ExportPhase(type: type))
  }

  /// Update fractional progress for a phase.
  public mutating func updateProgress(for type: ExportPhaseType, current: Int, total: Int) {
    guard let idx = phases.firstIndex(where: { $0.type == type }), total > 0 else { return }
    phases[idx].progress = Double(current) / Double(total)
  }

  /// Mark a phase as completed.
  public mutating func completePhase(_ type: ExportPhaseType) {
    guard let idx = phases.firstIndex(where: { $0.type == type }) else { return }
    phases[idx].progress = 1.0
    phases[idx].status = .completed
  }

  /// Mark a phase as failed.
  public mutating func failPhase(_ type: ExportPhaseType, message: String) {
    guard let idx = phases.firstIndex(where: { $0.type == type }) else { return }
    phases[idx].status = .failed
    phases[idx].failureMessage = message
  }

  /// Clear all phases.
  public mutating func reset() {
    phases.removeAll()
  }
}
