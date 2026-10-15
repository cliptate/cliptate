import Foundation

/// 提供对 Segment 进行拆分的工具。
/// 基于 words 之间的空白间隔进行智能分割。
/// 设计目标：输入一组 segments，输出拆分后的新 segments（保持时间连续且不重叠）。
public enum SegmentSplit {
  public struct Options {
    /// 空白间隔阈值（秒）：当两个连续 word 之间的间隔超过此阈值时，在该位置分割 segment。
    /// <= 0 表示不启用分割。
    public var splitThreshold: TimeInterval = 0

    public init(splitThreshold: TimeInterval = 0) {
      self.splitThreshold = splitThreshold
    }
  }

  /// 执行拆分：
  /// 检测 segment 中 words 之间的空白间隔，如果间隔超过阈值则在该位置分割。
  public static func apply(segments: [Segment], options: Options) -> [Segment] {
    guard !segments.isEmpty else { return [] }
    guard options.splitThreshold > 0 else { return segments }
    
    var result: [Segment] = []
    result.reserveCapacity(segments.count * 2)
    
    for segment in segments.sorted(by: { $0.startTime < $1.startTime }) {
      let split = splitSegmentByGap(segment, threshold: options.splitThreshold)
      result.append(contentsOf: split)
    }
    
    return result
  }
  
  /// 根据 words 之间的间隔拆分单个 segment
  private static func splitSegmentByGap(_ segment: Segment, threshold: TimeInterval) -> [Segment] {
    guard let words = segment.words, !words.isEmpty else {
      return [segment]
    }
    
    guard words.count > 1 else {
      return [segment]
    }
    
    // 找到所有需要分割的位置（gap 超过阈值的地方）
    var splitIndices: [Int] = []
    for i in 0..<(words.count - 1) {
      let currentWord = words[i]
      let nextWord = words[i + 1]
      let gap = nextWord.startTime - currentWord.endTime
      
      if gap > threshold {
        splitIndices.append(i + 1) // 在下一个 word 之前分割
      }
    }
    
    // 如果没有找到分割点，返回原 segment
    guard !splitIndices.isEmpty else {
      return [segment]
    }
    
    // 根据分割点生成新的 segments
    var segments: [Segment] = []
    var startIndex = 0
    
    for splitIndex in splitIndices {
      let wordSlice = Array(words[startIndex..<splitIndex])
      if let newSegment = createSegment(
        from: segment,
        words: wordSlice,
        originalStart: segment.startTime,
        originalEnd: segment.endTime
      ) {
        segments.append(newSegment)
      }
      startIndex = splitIndex
    }
    
    // 添加最后一个分段
    let lastWordSlice = Array(words[startIndex...])
    if let lastSegment = createSegment(
      from: segment,
      words: lastWordSlice,
      originalStart: segment.startTime,
      originalEnd: segment.endTime
    ) {
      segments.append(lastSegment)
    }
    
    if segments.isEmpty { return [segment] }
    if segments.count == 1 {
      let s = segments[0]
      return [Segment(id: segment.id, startTime: s.startTime, endTime: s.endTime,
                      text: s.text, words: s.words, confidence: s.confidence,
                      speakerId: s.speakerId, translation: s.translation)]
    }
    return segments
  }
  
  /// 从 word 列表创建新的 segment
  private static func createSegment(
    from original: Segment,
    words: [WordTiming],
    originalStart: TimeInterval,
    originalEnd: TimeInterval
  ) -> Segment? {
    guard !words.isEmpty else { return nil }
    
    let text = WordTimingTextComposer.composeText(from: words)
    let startTime = words.first?.startTime ?? originalStart
    let endTime = words.last?.endTime ?? originalEnd
    
    return Segment(
      id: Segment.deterministicChildId(parentId: original.id, startTime: startTime, endTime: endTime),
      startTime: startTime,
      endTime: endTime,
      text: text,
      words: words,
      confidence: original.confidence,
      speakerId: original.speakerId
    )
  }
}
