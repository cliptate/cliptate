import AVFoundation
import AudioToolbox

public enum AudioExporterError: LocalizedError {
  case noAudioTrack
  case exportSessionUnavailable
  case exportFailed(String)
  case writerFailed(String)
  case readerFailed(String)

  public var errorDescription: String? {
    switch self {
    case .noAudioTrack:
      return "The selected media doesn't contain an audio track."
    case .exportSessionUnavailable:
      return "Unable to prepare an audio export session."
    case .exportFailed(let message):
      return "Audio export failed: \(message)"
    case .writerFailed(let message):
      return "Audio writer failed: \(message)"
    case .readerFailed(let message):
      return "Audio reader failed: \(message)"
    }
  }
}

public final class AudioExporter {
  public init() {}

  public func exportAudio(
    from mediaURL: URL,
    to outputURL: URL,
    format: AudioExportFormat
  ) async throws {
    if FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }

    let asset = AVURLAsset(
      url: mediaURL,
      options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
    )

    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    guard let track = audioTracks.first else {
      throw AudioExporterError.noAudioTrack
    }

    switch format {
    case .m4a:
      try await exportM4A(asset: asset, outputURL: outputURL)
    case .wav:
      try await exportWAV(asset: asset, track: track, outputURL: outputURL)
    }
  }

  private func exportM4A(asset: AVURLAsset, outputURL: URL) async throws {
    let preset = AVAssetExportPresetAppleM4A
    guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
      throw AudioExporterError.exportSessionUnavailable
    }

    let duration = try await asset.load(.duration)
    session.timeRange = CMTimeRange(start: .zero, duration: duration)

    do {
      try await session.export(to: outputURL, as: .m4a)
    } catch {
      throw AudioExporterError.exportFailed(error.localizedDescription)
    }
  }

  private func exportWAV(asset: AVURLAsset, track: AVAssetTrack, outputURL: URL) async throws {
    let configuration = await resolvedAudioConfiguration(for: track)

    let reader = try AVAssetReader(asset: asset)
    let readerOutputSettings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: configuration.sampleRate,
      AVNumberOfChannelsKey: configuration.channelCount,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ]

    let readerOutput = AVAssetReaderTrackOutput(
      track: track, outputSettings: readerOutputSettings)
    reader.add(readerOutput)

    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .wav)
    let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: readerOutputSettings)
    writerInput.expectsMediaDataInRealTime = false
    writer.add(writerInput)

    guard reader.startReading() else {
      throw AudioExporterError.readerFailed(reader.error?.localizedDescription ?? "Unknown error")
    }

    guard writer.startWriting() else {
      throw AudioExporterError.writerFailed(writer.error?.localizedDescription ?? "Unknown error")
    }

    writer.startSession(atSourceTime: .zero)

    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, Error>) in
      let queue = DispatchQueue(label: "com.Cliptate.audioexporter")
      writerInput.requestMediaDataWhenReady(on: queue) {
        while writerInput.isReadyForMoreMediaData {
          if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            let appended = writerInput.append(sampleBuffer)
            if !appended {
              reader.cancelReading()
              writerInput.markAsFinished()
              writer.cancelWriting()
              let message = writer.error?.localizedDescription ?? "Unknown writer error"
              continuation.resume(throwing: AudioExporterError.writerFailed(message))
              return
            }
          } else {
            writerInput.markAsFinished()
            writer.finishWriting {
              if let error = writer.error {
                continuation.resume(
                  throwing: AudioExporterError.writerFailed(error.localizedDescription))
              } else if reader.status == .failed {
                let message = reader.error?.localizedDescription ?? "Unknown reader error"
                continuation.resume(throwing: AudioExporterError.readerFailed(message))
              } else {
                continuation.resume(returning: ())
              }
            }
            break
          }
        }
      }
    }
  }

  private func resolvedAudioConfiguration(for track: AVAssetTrack) async -> (
    sampleRate: Double, channelCount: Int
  ) {
    do {
      let descriptions = try await track.load(.formatDescriptions)
      for descriptor in descriptions {
        let formatDescription = descriptor as CMFormatDescription
        guard CMFormatDescriptionGetMediaType(formatDescription) == kCMMediaType_Audio else {
          continue
        }
        if let asbd =
          CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee
        {
          let rate = asbd.mSampleRate > 0 ? asbd.mSampleRate : 48_000
          let channels = asbd.mChannelsPerFrame > 0 ? Int(asbd.mChannelsPerFrame) : 2
          return (rate, max(channels, 1))
        }
      }
    } catch {}
    return (48_000, 2)
  }

  /// Exports audio from a media file, optionally filtering to only include speech segments.
  /// When `segments` is provided, only the time ranges covered by those segments are included
  /// in the output (silence between segments is removed).
  public func exportAudio(
    from mediaURL: URL,
    to outputURL: URL,
    format: AudioExportFormat,
    segments: [Segment]?
  ) async throws {
    guard let segments, !segments.isEmpty else {
      try await exportAudio(from: mediaURL, to: outputURL, format: format)
      return
    }

    if FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }

    let asset = AVURLAsset(
      url: mediaURL,
      options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]
    )

    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    guard let audioTrack = audioTracks.first else {
      throw AudioExporterError.noAudioTrack
    }

    // Build a composition containing only the speech segments
    let composition = AVMutableComposition()
    guard
      let compositionTrack = composition.addMutableTrack(
        withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
    else {
      throw AudioExporterError.exportSessionUnavailable
    }

    let compressed = SegmentCompressor.compress(segments)
    var cursor = CMTime.zero
    for mapping in compressed.mappings {
      let sourceRange = CMTimeRange(
        start: CMTime(seconds: mapping.originalStart, preferredTimescale: 60000),
        end: CMTime(seconds: mapping.originalEnd, preferredTimescale: 60000))
      try compositionTrack.insertTimeRange(sourceRange, of: audioTrack, at: cursor)
      cursor = cursor + sourceRange.duration
    }

    switch format {
    case .m4a:
      try await exportCompositionM4A(composition: composition, outputURL: outputURL)
    case .wav:
      try await exportCompositionWAV(
        composition: composition, track: compositionTrack, outputURL: outputURL)
    }
  }

  private func exportCompositionM4A(composition: AVMutableComposition, outputURL: URL) async throws {
    let preset = AVAssetExportPresetAppleM4A
    guard let session = AVAssetExportSession(asset: composition, presetName: preset) else {
      throw AudioExporterError.exportSessionUnavailable
    }

    let duration = try await composition.load(.duration)
    session.timeRange = CMTimeRange(start: .zero, duration: duration)

    do {
      try await session.export(to: outputURL, as: .m4a)
    } catch {
      throw AudioExporterError.exportFailed(error.localizedDescription)
    }
  }

  private func exportCompositionWAV(
    composition: AVMutableComposition, track: AVAssetTrack, outputURL: URL
  ) async throws {
    let configuration = await resolvedAudioConfiguration(for: track)

    let reader = try AVAssetReader(asset: composition)
    let readerOutputSettings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: configuration.sampleRate,
      AVNumberOfChannelsKey: configuration.channelCount,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ]

    let readerOutput = AVAssetReaderTrackOutput(
      track: track, outputSettings: readerOutputSettings)
    reader.add(readerOutput)

    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .wav)
    let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: readerOutputSettings)
    writerInput.expectsMediaDataInRealTime = false
    writer.add(writerInput)

    guard reader.startReading() else {
      throw AudioExporterError.readerFailed(reader.error?.localizedDescription ?? "Unknown error")
    }

    guard writer.startWriting() else {
      throw AudioExporterError.writerFailed(writer.error?.localizedDescription ?? "Unknown error")
    }

    writer.startSession(atSourceTime: .zero)

    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, Error>) in
      let queue = DispatchQueue(label: "com.Cliptate.audioexporter.filtered")
      writerInput.requestMediaDataWhenReady(on: queue) {
        while writerInput.isReadyForMoreMediaData {
          if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            let appended = writerInput.append(sampleBuffer)
            if !appended {
              reader.cancelReading()
              writerInput.markAsFinished()
              writer.cancelWriting()
              let message = writer.error?.localizedDescription ?? "Unknown writer error"
              continuation.resume(throwing: AudioExporterError.writerFailed(message))
              return
            }
          } else {
            writerInput.markAsFinished()
            writer.finishWriting {
              if let error = writer.error {
                continuation.resume(
                  throwing: AudioExporterError.writerFailed(error.localizedDescription))
              } else if reader.status == .failed {
                let message = reader.error?.localizedDescription ?? "Unknown reader error"
                continuation.resume(throwing: AudioExporterError.readerFailed(message))
              } else {
                continuation.resume(returning: ())
              }
            }
            break
          }
        }
      }
    }
  }
}
