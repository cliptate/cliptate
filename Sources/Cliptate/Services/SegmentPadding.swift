import Foundation

/// 已废弃：请使用 `SegmentProcess.process(operations: [.padding(...)])`
@available(*, deprecated, message: "Use SegmentProcess.process with .padding instead")
enum SegmentPadding {
  struct Options {
    var leftPadMs: Int = 0
    var rightPadMs: Int = 0
  }

  static func apply(segments: [Segment], totalDuration: TimeInterval, options: Options) -> [Segment]
  {
    SegmentProcess.process(
      segments: segments,
      totalDuration: totalDuration,
      operations: [.padding(leftMs: options.leftPadMs, rightMs: options.rightPadMs)]
    )
  }
}
