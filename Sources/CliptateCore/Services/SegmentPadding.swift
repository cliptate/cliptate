import Foundation

/// 已废弃：请使用 `SegmentProcess.process(operations: [.padding(...)])`
@available(*, deprecated, message: "Use SegmentProcess.process with .padding instead")
public enum SegmentPadding {
  public struct Options {
    public var leftPadMs: Int = 0
    public var rightPadMs: Int = 0

    public init(leftPadMs: Int = 0, rightPadMs: Int = 0) {
      self.leftPadMs = leftPadMs
      self.rightPadMs = rightPadMs
    }
  }

  public static func apply(segments: [Segment], totalDuration: TimeInterval, options: Options) -> [Segment]
  {
    SegmentProcess.process(
      segments: segments,
      totalDuration: totalDuration,
      operations: [.padding(leftMs: options.leftPadMs, rightMs: options.rightPadMs)]
    )
  }
}
