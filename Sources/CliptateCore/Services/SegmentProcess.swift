import Foundation

/// 统一的 Segment 处理管线，可扩展多种操作（padding / split / merge ...）。
/// 用法：SegmentProcess.process(segments:totalDuration:operations:)
/// 默认按 operations 顺序执行。
public enum SegmentProcess {
  /// 可用处理操作
  public enum Operation {
    case padding(leftMs: Int, rightMs: Int)
    case split(SegmentSplit.Options)
    case splitBySilence(SegmentSplitBySilence.Options)
    case splitBySentence
    case splitByCharCount(SegmentSplitByCharCount.Options)
    case splitByNatural(SegmentSplitByNatural.Options)
  }

  /// 主入口
  public static func process(segments: [Segment], totalDuration: TimeInterval?, operations: [Operation])
    -> [Segment]
  {
    guard !segments.isEmpty else { return [] }
    var current = segments
    var durationCache: TimeInterval? = totalDuration
    for op in operations {
      switch op {
      case .padding(let leftMs, let rightMs):
        let total = durationCache ?? (current.last?.endTime ?? 0)
        current = PaddingImpl.apply(
          segments: current, totalDuration: total, leftPadMs: leftMs, rightPadMs: rightMs)
        durationCache = max(durationCache ?? 0, total)
      case .split(let options):
        current = SegmentSplit.apply(segments: current, options: options)
      case .splitBySilence(let options):
        current = SegmentSplitBySilence.apply(segments: current, options: options)
      case .splitBySentence:
        current = SegmentSplitBySentence.apply(segments: current)
      case .splitByCharCount(let options):
        current = SegmentSplitByCharCount.apply(segments: current, options: options)
      case .splitByNatural(let options):
        current = SegmentSplitByNatural.apply(segments: current, options: options)
      }
    }
    return current
  }
}

// MARK: - 内部 Padding 实现（从原 SegmentPadding 迁移）
extension SegmentProcess {
  private enum PaddingImpl {
    static func apply(
      segments: [Segment], totalDuration: TimeInterval, leftPadMs: Int, rightPadMs: Int
    ) -> [Segment] {
      let leftPad = max(0, leftPadMs)
      let rightPad = max(0, rightPadMs)
      if leftPad == 0, rightPad == 0 { return segments.sorted { $0.startTime < $1.startTime } }

      let leftPadSec = TimeInterval(leftPad) / 1000.0
      let rightPadSec = TimeInterval(rightPad) / 1000.0

      let original = segments.sorted { $0.startTime < $1.startTime }
      let n = original.count
      var padLeft = Array(repeating: leftPadSec, count: n)
      var padRight = Array(repeating: rightPadSec, count: n)

      if n > 1 {
        for i in 0..<(n - 1) {
          let a = original[i]
          let b = original[i + 1]
          let gap = b.startTime - a.endTime
          if gap <= 0 {
            padRight[i] = 0
            padLeft[i + 1] = 0
            continue
          }
          let need = padRight[i] + padLeft[i + 1]
          if need <= gap { continue }
          let half = gap / 2
          var allocRight = min(padRight[i], half)
          var allocLeft = min(padLeft[i + 1], half)
          var used = allocRight + allocLeft
          if used < gap {
            let remain = gap - used
            let rightNeed = padRight[i] - allocRight
            let leftNeed = padLeft[i + 1] - allocLeft
            if rightNeed >= leftNeed, rightNeed > 0 {
              let extra = min(rightNeed, remain)
              allocRight += extra
              used += extra
            }
            if used < gap, leftNeed > 0 {
              let extra = min(leftNeed, gap - used)
              allocLeft += extra
            }
          }
          padRight[i] = allocRight
          padLeft[i + 1] = allocLeft
        }
      }

      var adjusted: [Segment] = []
      adjusted.reserveCapacity(n)
      for i in 0..<n {
        let base = original[i]
        var newStart = base.startTime - padLeft[i]
        var newEnd = base.endTime + padRight[i]
        if i > 0 { newStart = max(newStart, adjusted[i - 1].endTime) }
        if i < n - 1 {
          let nextBase = original[i + 1]
          let nextStartLimit = nextBase.startTime - padLeft[i + 1]
          newEnd = min(newEnd, nextStartLimit)
        } else {
          newEnd = min(newEnd, totalDuration)
        }
        newStart = max(0, newStart)
        newEnd = min(totalDuration, max(newEnd, base.endTime))
        if newEnd < newStart { newEnd = newStart }
        adjusted.append(
          Segment(
            id: base.id,
            startTime: newStart, endTime: newEnd, text: base.text, words: base.words,
            confidence: base.confidence, speakerId: base.speakerId,
            translation: base.translation))
      }
      return adjusted
    }
  }
}
