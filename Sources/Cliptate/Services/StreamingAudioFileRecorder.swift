import AVFoundation
import Foundation

actor StreamingAudioFileRecorder {
  let outputURL: URL

  private var audioFile: AVAudioFile?
  private var hasWrittenFrames = false
  private var isFinished = false

  init(outputURL: URL) {
    self.outputURL = outputURL
  }

  func append(buffer: AVAudioPCMBuffer) throws {
    guard !isFinished, buffer.frameLength > 0 else { return }

    if audioFile == nil {
      audioFile = try AVAudioFile(
        forWriting: outputURL,
        settings: buffer.format.settings,
        commonFormat: buffer.format.commonFormat,
        interleaved: buffer.format.isInterleaved
      )
    }

    guard let audioFile else { return }
    try audioFile.write(from: buffer)
    hasWrittenFrames = true
  }

  func finish() throws {
    guard !isFinished else { return }
    isFinished = true
    audioFile = nil

    if !hasWrittenFrames, FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }
  }
}
