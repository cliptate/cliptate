import CliptateCore
import AVFoundation
import CoreGraphics
import SwiftAssRenderer

  public class VideoExporter {
    public init() {}

    private static func displaySize(for naturalSize: CGSize, transform: CGAffineTransform) -> CGSize
    {
      let width = abs(naturalSize.width * transform.a) + abs(naturalSize.height * transform.c)
      let height = abs(naturalSize.width * transform.b) + abs(naturalSize.height * transform.d)
      if width > 0.5 && height > 0.5 {
        return CGSize(width: width, height: height)
      }
      return naturalSize
    }

    @MainActor
    public func exportVideoWithSubtitles(
      videoURL: URL,
      segments: [Segment],
      outputURL: URL,
      filterSilentSegments: Bool,
      effects: [String: SegmentEffectState] = [:],
      translationPlacement: SubtitleTranslationPlacement = .below,
      styleConfiguration: SubtitleStylesConfiguration? = nil,
      dubbedAudioURL: URL? = nil,
      burnInSubtitles: Bool = true,
      quality: VideoExportQuality
    ) async throws {
      let resolvedStyles = styleConfiguration ?? defaultSubtitleStyles
      try Task.checkCancellation()
      let sourceAccess = videoURL.startAccessingSecurityScopedResource()
      defer { if sourceAccess { videoURL.stopAccessingSecurityScopedResource() } }

      let asset = AVURLAsset(
        url: videoURL,
        options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
      )

      let track = try await asset.loadTracks(withMediaType: .video).first
      let naturalSize = try await track?.load(.naturalSize) ?? .zero
      let preferredTransform = try await track?.load(.preferredTransform) ?? .identity
      let displaySize = Self.displaySize(for: naturalSize, transform: preferredTransform)
      let actualOrientation: SubtitleOrientation =
        displaySize.height >= displaySize.width ? .portrait : .landscape

      let ass = ASSGenerator.makeASS(
        segments: segments,
        orientation: actualOrientation,
        filterSilentSegments: filterSilentSegments,
        effects: effects,
        translationPlacement: translationPlacement,
        styleConfiguration: resolvedStyles
      )

      let (composition, videoComposition) = try await VideoCompositionBuilder.build(
        asset: asset,
        ass: burnInSubtitles ? ass : nil,
        filterSilentSegments: filterSilentSegments,
        segments: segments,
        dubbedAudioURL: dubbedAudioURL
      )

      let allPresets = AVAssetExportSession.allExportPresets()
      let availablePresets = allPresets.filter {
        AVAssetExportSession(asset: composition, presetName: $0) != nil
      }
      guard !availablePresets.isEmpty else {
        throw NSError(
          domain: "VideoExporter",
          code: 10,
          userInfo: [NSLocalizedDescriptionKey: "No compatible export presets for composition."]
        )
      }

      let presetName = quality.resolvedPreset(from: availablePresets, burnIn: burnInSubtitles || dubbedAudioURL != nil)

      guard let exportSession = AVAssetExportSession(asset: composition, presetName: presetName)
      else {
        throw NSError(
          domain: "VideoExporter",
          code: 12,
          userInfo: [NSLocalizedDescriptionKey: "Could not create export session for preset."]
        )
      }

      exportSession.videoComposition = videoComposition

      let ext = outputURL.pathExtension.lowercased()
      let supported = exportSession.supportedFileTypes
      let preferredMap: [String: AVFileType] = ["mp4": .mp4, "mov": .mov, "m4v": .m4v]

      let targetType: AVFileType
      if let mapped = preferredMap[ext], supported.contains(mapped) {
        targetType = mapped
      } else if let mov = supported.first(where: { $0 == AVFileType.mov }) {
        targetType = mov
      } else if let first = supported.first {
        targetType = first
      } else {
        throw NSError(
          domain: "VideoExporter",
          code: 11,
          userInfo: [NSLocalizedDescriptionKey: "No supported file types for export session"]
        )
      }

      do {
        let staging = outputURL.deletingLastPathComponent()
          .appendingPathComponent("\(UUID().uuidString).\(outputURL.pathExtension)")
        defer { try? FileManager.default.removeItem(at: staging) }
        try await exportSession.export(to: staging, as: targetType)
        try Task.checkCancellation()
        try FileManager.default.replaceOrMoveFile(at: staging, to: outputURL)
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        throw NSError(
          domain: "VideoExporter",
          code: 4,
          userInfo: [NSLocalizedDescriptionKey: "Export failed: \(error.localizedDescription)"]
        )
      }
    }
  }
