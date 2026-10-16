import AVFoundation
import CliptateCore
import Foundation
import Testing

@testable import Cliptate

@Suite("Dubbed video export", .serialized)
@MainActor
struct DubbedVideoExportTests {
  @Test(
    "real model audio exports as a playable portrait video",
    .enabled(if: ProcessInfo.processInfo.environment["RUN_DUBBING_EXPORT_TESTS"] == "1"),
    arguments: [false, true])
  func realAudioSmoke(burnIn: Bool) async throws {
    let environment = ProcessInfo.processInfo.environment
    let source = URL(fileURLWithPath: try #require(environment["DUBBING_TEST_SOURCE_PATH"]))
    let audio = URL(fileURLWithPath: try #require(environment["DUBBING_TEST_OUTPUT_PATH"]))
    let duration = try await AVURLAsset(url: audio).load(.duration).seconds
    let output = audio.deletingPathExtension().appendingPathExtension(
      burnIn ? "subtitled.mp4" : "mp4")
    try await VideoExporter().exportVideoWithSubtitles(
      videoURL: source,
      segments: [
        Segment(
          startTime: 0, endTime: duration, text: "试错的过程很简单。",
          translation: .init(text: "Trial is simple.", language: .english))
      ],
      outputURL: output, filterSilentSegments: true, dubbedAudioURL: audio,
      burnInSubtitles: burnIn, quality: .original)
    let asset = AVURLAsset(url: output)
    #expect(abs(try await asset.load(.duration).seconds - duration) < 0.05)
    #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
    let tracks = try await asset.loadTracks(withMediaType: .video)
    #expect(tracks.count == 1)
    let track = try #require(tracks.first)
    let size = try await track.load(.naturalSize)
    let transform = try await track.load(.preferredTransform)
    let width = abs(size.width * transform.a) + abs(size.height * transform.c)
    let height = abs(size.width * transform.b) + abs(size.height * transform.d)
    #expect(height > width)
  }

  @Test(
    "dubbed video replaces the original voice with and without subtitles", arguments: [false, true])
  func replacesOriginalAudio(burnIn: Bool) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = try await makeSource(in: directory)
    let dub = directory.appendingPathComponent("dub.wav")
    try MLXTTSService.createWAVData(from: [Float](repeating: 0, count: 24_000), sampleRate: 24_000)
      .write(to: dub)
    let output = directory.appendingPathComponent("output.mp4")
    try await VideoExporter().exportVideoWithSubtitles(
      videoURL: source, segments: [Segment(startTime: 0, endTime: 1, text: "Hello")],
      outputURL: output, filterSilentSegments: false,
      dubbedAudioURL: dub, burnInSubtitles: burnIn, quality: .original)
    let asset = AVURLAsset(url: output)
    #expect(abs(try await asset.load(.duration).seconds - 1) < 0.05)
    #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
    let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
    let size = try await track.load(.naturalSize)
    let transform = try await track.load(.preferredTransform)
    let width = abs(size.width * transform.a) + abs(size.height * transform.c)
    let height = abs(size.width * transform.b) + abs(size.height * transform.d)
    #expect(height > width)
    let decoded = directory.appendingPathComponent("decoded.wav")
    try await AudioExporter().exportAudio(from: output, to: decoded, format: .wav)
    let samples = try DubbingService.samplesFromWAVData(Data(contentsOf: decoded))
    #expect(samples.map { abs($0) }.max() ?? 1 < 0.001)
  }

  private func makeSource(in directory: URL) async throws -> URL {
    let silentVideo = directory.appendingPathComponent("picture.mov")
    let writer = try AVAssetWriter(outputURL: silentVideo, fileType: .mov)
    let input = AVAssetWriterInput(
      mediaType: .video,
      outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 48, AVVideoHeightKey: 32,
      ])
    input.transform = CGAffineTransform(rotationAngle: .pi / 2)
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: 48, kCVPixelBufferHeightKey as String: 32,
      ])
    writer.add(input)
    #expect(writer.startWriting())
    writer.startSession(atSourceTime: .zero)
    var pixelBuffer: CVPixelBuffer?
    #expect(
      CVPixelBufferCreate(kCFAllocatorDefault, 48, 32, kCVPixelFormatType_32ARGB, nil, &pixelBuffer)
        == kCVReturnSuccess)
    let pixels = try #require(pixelBuffer)
    CVPixelBufferLockBaseAddress(pixels, [])
    memset(CVPixelBufferGetBaseAddress(pixels), 80, CVPixelBufferGetDataSize(pixels))
    CVPixelBufferUnlockBaseAddress(pixels, [])
    for frame in 0..<30 {
      while !input.isReadyForMoreMediaData {
        if let error = writer.error { throw error }
        try await Task.sleep(for: .milliseconds(1))
      }
      #expect(
        adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
    }
    input.markAsFinished()
    writer.endSession(atSourceTime: CMTime(seconds: 1, preferredTimescale: 30))
    await writer.finishWriting()
    if let error = writer.error { throw error }

    let originalAudio = directory.appendingPathComponent("original.wav")
    let tone = (0..<24_000).map { Float(sin(Double($0) * 2 * .pi * 1_000 / 24_000)) * 0.4 }
    try MLXTTSService.createWAVData(from: tone, sampleRate: 24_000).write(to: originalAudio)
    let videoAsset = AVURLAsset(url: silentVideo)
    let audioAsset = AVURLAsset(url: originalAudio)
    let composition = AVMutableComposition()
    let video = try #require(try await videoAsset.loadTracks(withMediaType: .video).first)
    let videoTrack = try #require(
      composition.addMutableTrack(
        withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid))
    let range = CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 30))
    try videoTrack.insertTimeRange(range, of: video, at: .zero)
    videoTrack.preferredTransform = try await video.load(.preferredTransform)
    let audio = try #require(try await audioAsset.loadTracks(withMediaType: .audio).first)
    let audioTrack = try #require(
      composition.addMutableTrack(
        withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
    try audioTrack.insertTimeRange(range, of: audio, at: .zero)
    let source = directory.appendingPathComponent("source.mov")
    let exporter = try #require(
      AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality))
    try await exporter.export(to: source, as: .mov)
    return source
  }
}
