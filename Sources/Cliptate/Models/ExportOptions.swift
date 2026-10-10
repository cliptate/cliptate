import Foundation

#if canImport(AVFoundation)
  import AVFoundation
#endif

public enum ExportMode: String, CaseIterable, Identifiable, Codable, Sendable {
  case merge
  case separate

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .merge: return String(localized: "Merge", comment: "Export mode: combine all videos into shared folders")
    case .separate: return String(localized: "Separate", comment: "Export mode: one folder per video")
    }
  }

  public var description: String {
    switch self {
    case .merge:
      return String(localized: "Combine all transcribed videos and assets into shared folders with a single timeline.", comment: "Merge export mode description")
    case .separate:
      return String(localized: "Create per-video folders containing their own timeline, subtitles, and media exports.", comment: "Separate export mode description")
    }
  }
}

public enum VideoExportFormat: String, CaseIterable, Identifiable, Codable, Sendable {
  case mp4
  case mov
  case m4v

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .mp4: return "MP4 (H.264)"
    case .mov: return "MOV"
    case .m4v: return "M4V"
    }
  }

  public var fileExtension: String { rawValue }

  public var description: String {
    switch self {
    case .mp4:
      return String(localized: "Balanced compatibility and size using H.264.", comment: "MP4 export format description")
    case .mov:
      return String(localized: "Apple QuickTime container in highest quality.", comment: "MOV export format description")
    case .m4v:
      return String(localized: "iTunes-friendly container similar to MP4.", comment: "M4V export format description")
    }
  }
}

public enum VideoExportQuality: String, CaseIterable, Identifiable, Codable, Sendable {
  case original
  case high
  case medium
  case low

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .original: return String(localized: "Original", comment: "Video export quality: preserve source resolution")
    case .high: return String(localized: "High (1080p)", comment: "Video export quality: 1080p")
    case .medium: return String(localized: "Medium (720p)", comment: "Video export quality: 720p")
    case .low: return String(localized: "Efficient (540p)", comment: "Video export quality: 540p")
    }
  }

  public var description: String {
    switch self {
    case .original:
      return String(localized: "Preserve source quality. Uses passthrough when copying videos.", comment: "Original video quality description")
    case .high:
      return String(localized: "Render at 1080p for crystal-clear playback.", comment: "High video quality description")
    case .medium:
      return String(localized: "Balance quality and size by rendering at 720p.", comment: "Medium video quality description")
    case .low:
      return String(localized: "Smaller files optimized for reviews (540p).", comment: "Low video quality description")
    }
  }

  public func presetName(forBurnIn burnIn: Bool) -> String {
    #if canImport(AVFoundation)
      switch self {
      case .original:
        return burnIn ? AVAssetExportPresetHighestQuality : AVAssetExportPresetPassthrough
      case .high:
        return AVAssetExportPreset1920x1080
      case .medium:
        return AVAssetExportPreset1280x720
      case .low:
        return AVAssetExportPreset960x540
      }
    #else
      switch self {
      case .original:
        return burnIn ? "AVAssetExportPresetHighestQuality" : "AVAssetExportPresetPassthrough"
      case .high:
        return "AVAssetExportPreset1920x1080"
      case .medium:
        return "AVAssetExportPreset1280x720"
      case .low:
        return "AVAssetExportPreset960x540"
      }
    #endif
  }

  public func resolvedPreset(from availablePresets: [String], burnIn: Bool) -> String {
    let desired = presetName(forBurnIn: burnIn)
    if availablePresets.contains(desired) {
      return desired
    }

    let fallbacks = fallbackPresets(forBurnIn: burnIn)
    for candidate in fallbacks where availablePresets.contains(candidate) {
      return candidate
    }

    return availablePresets.first ?? desired
  }

  private func fallbackPresets(forBurnIn burnIn: Bool) -> [String] {
    #if canImport(AVFoundation)
      if burnIn {
        return [
          AVAssetExportPresetHighestQuality,
          AVAssetExportPreset1920x1080,
          AVAssetExportPreset1280x720,
          AVAssetExportPreset960x540,
        ]
      } else {
        return [
          AVAssetExportPresetPassthrough,
          AVAssetExportPresetHighestQuality,
          AVAssetExportPreset1920x1080,
          AVAssetExportPreset1280x720,
        ]
      }
    #else
      if burnIn {
        return [
          "AVAssetExportPresetHighestQuality",
          "AVAssetExportPreset1920x1080",
          "AVAssetExportPreset1280x720",
          "AVAssetExportPreset960x540",
        ]
      } else {
        return [
          "AVAssetExportPresetPassthrough",
          "AVAssetExportPresetHighestQuality",
          "AVAssetExportPreset1920x1080",
          "AVAssetExportPreset1280x720",
        ]
      }
    #endif
  }
}

public enum AudioExportFormat: String, CaseIterable, Identifiable, Codable, Sendable {
  case m4a
  case wav

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .m4a: return String(localized: "M4A (AAC)", comment: "Audio export format: M4A with AAC codec")
    case .wav: return String(localized: "WAV (PCM)", comment: "Audio export format: WAV with PCM codec")
    }
  }

  public var description: String {
    switch self {
    case .m4a:
      return String(localized: "Compressed AAC audio in an M4A container for broad compatibility.", comment: "M4A audio format description")
    case .wav:
      return String(localized: "Uncompressed PCM waveform audio for highest fidelity.", comment: "WAV audio format description")
    }
  }

  public var fileExtension: String {
    switch self {
    case .m4a: return "m4a"
    case .wav: return "wav"
    }
  }
}

public struct ExportAllRequest: Equatable, Sendable {
  public var includeFCPXML: Bool
  public var exportMode: ExportMode
  public var includeSubtitleFiles: Bool
  public var includeVideos: Bool
  public var includeAudio: Bool
  public var burnSubtitlesIntoVideo: Bool
  public var videoQuality: VideoExportQuality
  public var audioFormat: AudioExportFormat

  public init(
    includeFCPXML: Bool,
    exportMode: ExportMode,
    includeSubtitleFiles: Bool,
    includeVideos: Bool,
    includeAudio: Bool,
    burnSubtitlesIntoVideo: Bool,
    videoQuality: VideoExportQuality = .original,
    audioFormat: AudioExportFormat = .m4a
  ) {
    self.includeFCPXML = includeFCPXML
    self.exportMode = exportMode
    self.includeSubtitleFiles = includeSubtitleFiles
    self.includeVideos = includeVideos
    self.includeAudio = includeAudio
    self.burnSubtitlesIntoVideo = burnSubtitlesIntoVideo
    self.videoQuality = videoQuality
    self.audioFormat = audioFormat
  }
}
