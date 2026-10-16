import AVFoundation
import Foundation

public class AudioProcessor {
  public static func loadAndConvertAudio(url: URL, timeRange: CMTimeRange? = nil) async throws -> [Float] {
    let asset = AVURLAsset(url: url)
    let assetAudioTrack = try await asset.loadTracks(withMediaType: .audio).first

    guard let audioTrack = assetAudioTrack else {
      throw NSError(
        domain: "AudioProcessing", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "No audio track found in the file."])
    }

    let assetReader = try AVAssetReader(asset: asset)
    if let timeRange { assetReader.timeRange = timeRange }

    let outputSettings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: 16000,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 32,
      AVLinearPCMIsFloatKey: true,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ]

    let assetReaderOutput = AVAssetReaderTrackOutput(
      track: audioTrack, outputSettings: outputSettings)
    assetReader.add(assetReaderOutput)
    assetReader.startReading()

    var samples: [Float] = []

    do {
      while let sampleBuffer = assetReaderOutput.copyNextSampleBuffer() {
        try Task.checkCancellation()
        let audioBuffer = try await aVAudioPCMBuffer(from: sampleBuffer)
        let channelData = audioBuffer.floatChannelData![0]
        let frameLength = Int(audioBuffer.frameLength)
        samples.append(contentsOf: (0..<frameLength).map { channelData[$0] })
      }
    } catch is CancellationError {
      assetReader.cancelReading()
      throw CancellationError()
    }

    try Task.checkCancellation()

    return samples
  }

  private static func aVAudioPCMBuffer(from sampleBuffer: CMSampleBuffer) async throws
    -> AVAudioPCMBuffer
  {
    var audioBufferList = AudioBufferList()
    var blockBuffer: CMBlockBuffer?
    CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: &audioBufferList,
      bufferListSize: MemoryLayout<AudioBufferList>.size, blockBufferAllocator: nil,
      blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &blockBuffer
    )
    let format = AVAudioFormat(cmAudioFormatDescription: sampleBuffer.formatDescription!)
    return AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: &audioBufferList)!
  }

  public static func saveToTemporaryFile(audioSamples: [Float]) throws -> URL {
    let temporaryDirectoryURL = FileManager.default.temporaryDirectory
    let temporaryFilename = UUID().uuidString + ".wav"
    let temporaryFileURL = temporaryDirectoryURL.appendingPathComponent(temporaryFilename)
    try save(audioSamples: audioSamples, to: temporaryFileURL)
    return temporaryFileURL
  }

  public static func save(audioSamples: [Float], to url: URL) throws {
    let outputFormatSettings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: 16000,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 32,
      AVLinearPCMIsFloatKey: true,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ]

    let audioFile = try AVAudioFile(
      forWriting: url,
      settings: outputFormatSettings,
      commonFormat: .pcmFormatFloat32,
      interleaved: false
    )

    guard
      let buffer = AVAudioPCMBuffer(
        pcmFormat: audioFile.processingFormat,
        frameCapacity: AVAudioFrameCount(audioSamples.count)
      )
    else {
      throw NSError(
        domain: "AudioProcessing", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
    }

    for i in 0..<audioSamples.count {
      buffer.floatChannelData?.pointee[i] = audioSamples[i]
    }
    buffer.frameLength = AVAudioFrameCount(audioSamples.count)

    try audioFile.write(from: buffer)
  }

  public static func extractSamples(
    samples: [Float],
    startTime: Double,
    endTime: Double,
    sampleRate: Double = 16_000
  ) -> [Float] {
    guard endTime > startTime else { return [] }
    let startIndex = max(0, Int(startTime * sampleRate))
    let endIndex = min(samples.count, Int(endTime * sampleRate))
    guard endIndex > startIndex else { return [] }
    return Array(samples[startIndex..<endIndex])
  }

  public static func saveSegmentToTemporaryFile(samples: [Float]) throws -> URL {
    try saveToTemporaryFile(audioSamples: samples)
  }
}
