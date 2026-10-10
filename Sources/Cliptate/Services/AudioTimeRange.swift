import Foundation

/// App-owned speech segment type, independent of any third-party VAD library.
public struct AudioTimeRange: Sendable, Equatable {
  public let startTime: Double
  public let endTime: Double
  /// Speaker index from diarization (nil if speaker identity unknown).
  public let speakerId: Int?

  public init(startTime: Double, endTime: Double, speakerId: Int? = nil) {
    self.startTime = startTime
    self.endTime = endTime
    self.speakerId = speakerId
  }

  public var duration: Double { endTime - startTime }
}
