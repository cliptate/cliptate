import CliptateCore
import AVFoundation
import AVKit
import Combine
import CoreGraphics
import Foundation
import QuartzCore
import SwiftAssRenderer

public enum VideoCompositionBuilder {
    /// 构建带 ASS 字幕的视频合成。
    /// - Parameters:
    ///   - asset: 原始视频资产
    ///   - ass: ASS 字幕内容
    ///   - filterSilentSegments: 是否裁剪静默
    ///   - segments: 原始（未压缩）的有效片段
    /// - Returns: 包含 AVAsset 和 AVVideoComposition 的元组
    @MainActor
    public static func build(
      asset: AVURLAsset,
      ass: String?,
      filterSilentSegments: Bool,
      segments: [Segment],
      dubbedAudioURL: URL? = nil
    ) async throws -> (AVAsset, AVVideoComposition?) {
      let composition = AVMutableComposition()

      // 预取轨道
      guard let videoAssetTrack = try await asset.loadTracks(withMediaType: .video).first else {
        throw NSError(
          domain: "VideoCompositionBuilder", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "No video track found."])
      }
      let audioAssetTrack = dubbedAudioURL == nil ? try await asset.loadTracks(withMediaType: .audio).first : nil

      // 创建合成轨道
      guard
        let videoCompositionTrack = composition.addMutableTrack(
          withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
      else {
        throw NSError(
          domain: "VideoCompositionBuilder", code: 2,
          userInfo: [NSLocalizedDescriptionKey: "Cannot create video track."])
      }
      let audioCompositionTrack = audioAssetTrack.map { _ in
        composition.addMutableTrack(
          withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
      }

      let assetDuration = try await asset.load(.duration)
      let preferredTransform = try await videoAssetTrack.load(.preferredTransform)
      let naturalSize = try await videoAssetTrack.load(.naturalSize)
      let displaySize = renderSize(for: naturalSize, transform: preferredTransform)
      let transform = preferredTransform
      let canvasSize = displaySize
      let videoTrackID = videoCompositionTrack.trackID

      if filterSilentSegments {
        let comp = SegmentCompressor.compress(segments)
        var cursor = CMTime.zero
        for m in comp.mappings {
          // 使用高精度 timescale (60000) 减少舍入误差
          let sourceRange = CMTimeRange(
            start: CMTime(seconds: m.originalStart, preferredTimescale: 60000),
            end: CMTime(seconds: m.originalEnd, preferredTimescale: 60000))
          let duration = sourceRange.duration
          try videoCompositionTrack.insertTimeRange(sourceRange, of: videoAssetTrack, at: cursor)
          if let audioAssetTrack, let audioCompositionTrack {
            try audioCompositionTrack.insertTimeRange(sourceRange, of: audioAssetTrack, at: cursor)
          }
          cursor = cursor + duration
        }
      } else {
        let timeRange = CMTimeRange(start: .zero, duration: assetDuration)
        try videoCompositionTrack.insertTimeRange(timeRange, of: videoAssetTrack, at: .zero)
        if let audioAssetTrack, let audioCompositionTrack {
          try audioCompositionTrack.insertTimeRange(timeRange, of: audioAssetTrack, at: .zero)
        }
      }

      videoCompositionTrack.preferredTransform = transform

      if let dubbedAudioURL {
        let dubbedAsset = AVURLAsset(url: dubbedAudioURL)
        guard let dubbedTrack = try await dubbedAsset.loadTracks(withMediaType: .audio).first,
              let targetTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw AudioExporterError.noAudioTrack }
        let range = try await dubbedTrack.load(.timeRange)
        guard range.duration.seconds + 0.02 >= composition.duration.seconds else { throw VideoDubbingError.incomplete }
        try targetTrack.insertTimeRange(
          CMTimeRange(start: range.start, duration: min(range.duration, composition.duration)),
          of: dubbedTrack, at: .zero)
      }

      guard let ass else { return (composition, nil) }

      // 添加 ASS 字幕渲染
      let assRenderer = AssSubtitlesRenderer(
        fontConfig: .init(fontsPath: URL(fileURLWithPath: "/System/Library/Fonts")),
        logOutput: .console(.fatal)
      )
      assRenderer.loadTrack(content: ass)

      let playerItem = AVPlayerItem(asset: composition)
      assRenderer.attach(to: playerItem, asset: composition, scale: 1.0)

      let videoComposition = try await fetchVideoComposition(from: playerItem)
      if let mutable = videoComposition as? AVMutableVideoComposition {
        mutable.renderSize = canvasSize
        applyLetterbox(
          to: mutable,
          transform: transform,
          videoTrackID: videoTrackID
        )
        return (composition, mutable)
      } else if let copy = videoComposition.mutableCopy() as? AVMutableVideoComposition {
        copy.renderSize = canvasSize
        applyLetterbox(
          to: copy,
          transform: transform,
          videoTrackID: videoTrackID
        )
        return (composition, copy)
      }

      return (composition, videoComposition)
    }

    private static func renderSize(for naturalSize: CGSize, transform: CGAffineTransform) -> CGSize
    {
      let width = abs(naturalSize.width * transform.a) + abs(naturalSize.height * transform.c)
      let height = abs(naturalSize.width * transform.b) + abs(naturalSize.height * transform.d)
      if width > 0.5 && height > 0.5 {
        return CGSize(width: width, height: height)
      }
      return naturalSize
    }

    @MainActor
    private static func fetchVideoComposition(
      from playerItem: AVPlayerItem,
      pollIntervalNanoseconds: UInt64 = 50_000_000,
      timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async throws -> AVVideoComposition {
      if let existing = playerItem.videoComposition {
        return existing
      }

      let deadline = DispatchTime.now().uptimeNanoseconds &+ timeoutNanoseconds
      var now = DispatchTime.now().uptimeNanoseconds

      while playerItem.videoComposition == nil, now < deadline {
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        now = DispatchTime.now().uptimeNanoseconds
      }

      if let videoComposition = playerItem.videoComposition {
        return videoComposition
      }

      throw NSError(
        domain: "VideoCompositionBuilder", code: 5,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Failed to create video composition with subtitles within timeout."
        ])
    }

    private static func applyLetterbox(
      to composition: AVMutableVideoComposition,
      transform: CGAffineTransform,
      videoTrackID: CMPersistentTrackID
    ) {
      let black = CGColor(gray: 0, alpha: 1)
      for instruction in composition.instructions {
        guard let mutableInstruction = instruction as? AVMutableVideoCompositionInstruction else {
          continue
        }
        mutableInstruction.backgroundColor = black
        for layerInstruction in mutableInstruction.layerInstructions {
          guard
            let mutableLayerInstruction =
              layerInstruction as? AVMutableVideoCompositionLayerInstruction
          else {
            continue
          }
          guard mutableLayerInstruction.trackID == videoTrackID else { continue }
          let timeRange = mutableInstruction.timeRange
          mutableLayerInstruction.setTransformRamp(
            fromStart: transform,
            toEnd: transform,
            timeRange: timeRange
          )
        }
      }
    }
  }
