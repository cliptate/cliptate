import Foundation

public struct DubbedClip: Codable, Equatable, Sendable {
  public let segmentIdentifier: SegmentIdentifier
  public let fingerprint: String
  public let audioURL: URL
  public let duration: TimeInterval
  public let sampleRate: Int

  public init(
    segmentIdentifier: SegmentIdentifier, fingerprint: String, audioURL: URL,
    duration: TimeInterval, sampleRate: Int
  ) {
    self.segmentIdentifier = segmentIdentifier
    self.fingerprint = fingerprint
    self.audioURL = audioURL
    self.duration = duration
    self.sampleRate = sampleRate
  }
}
