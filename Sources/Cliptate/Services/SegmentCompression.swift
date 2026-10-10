import Foundation

/// 提供对过滤静音（压缩时间轴）后的片段与时间映射的统一实现。
public struct SegmentCompression: Sendable {
  public struct Mapping: Sendable, Codable {
    public let originalStart: TimeInterval
    public let originalEnd: TimeInterval
    public let compressedStart: TimeInterval
    public let compressedEnd: TimeInterval
  }

  public let compressedSegments: [Segment]
  public let mappings: [Mapping]

  /// 原始时间 -> 压缩时间（若在静音区间内，则落在前一个片段结束处）
  public func compressTime(_ original: TimeInterval) -> TimeInterval {
    var lastEnd: TimeInterval = 0
    for m in mappings {
      if original < m.originalStart { return lastEnd }  // 静音落点
      if original >= m.originalStart && original <= m.originalEnd {
        return m.compressedStart + (original - m.originalStart)
      }
      lastEnd = m.compressedEnd
    }
    return lastEnd
  }

  /// 压缩时间 -> 原始时间（若超过最后一段结束，则钳制到最后一段末尾）
  public func expandTime(_ compressed: TimeInterval) -> TimeInterval {
    var lastEnd: TimeInterval = 0
    for m in mappings {
      if compressed < m.compressedStart { return lastEnd }
      if compressed >= m.compressedStart && compressed <= m.compressedEnd {
        return m.originalStart + (compressed - m.compressedStart)
      }
      lastEnd = m.originalEnd
    }
    return lastEnd
  }
}

public enum SegmentCompressor {
  /// 传入已经“保留”的语音片段（静音已在外部过滤）。生成连续压缩后的片段以及原始/压缩映射。
  public static func compress(_ segments: [Segment]) -> SegmentCompression {
    let sorted = segments.sorted { $0.startTime < $1.startTime }
    var compressed: [Segment] = []
    var mappings: [SegmentCompression.Mapping] = []
    // 使用 Decimal 进行高精度累积，避免浮点数误差
    var cursorDecimal = Decimal(0)
    for seg in sorted {
      let duration = max(0, seg.endTime - seg.startTime)
      guard duration > 0 else { continue }
      let compStart = Double(truncating: cursorDecimal as NSNumber)
      // 使用 Decimal 精确累积
      let durationDecimal = Decimal(duration)
      let compEndDecimal = cursorDecimal + durationDecimal
      let compEnd = Double(truncating: compEndDecimal as NSNumber)
      cursorDecimal = compEndDecimal
      // 平移 word timing（如果存在）
      let shiftedWords = seg.words.map { ws in
        ws.map { w in
          let shift = compStart - seg.startTime
          return WordTiming(
            word: w.word,
            startTime: w.startTime + shift,
            endTime: w.endTime + shift,
            confidence: w.confidence,
            punctuation: w.punctuation)
        }
      }
      compressed.append(
        Segment(
          id: seg.id,
          startTime: compStart,
          endTime: compEnd,
          text: seg.text,
          words: shiftedWords,
          confidence: seg.confidence,
          speakerId: seg.speakerId,
          translation: seg.translation))
      mappings.append(
        .init(
          originalStart: seg.startTime,
          originalEnd: seg.endTime,
          compressedStart: compStart,
          compressedEnd: compEnd))
    }
    return SegmentCompression(compressedSegments: compressed, mappings: mappings)
  }
}

/// 封装 Segment 展示所需的时间线（原始或压缩）。
public struct SegmentTimeline: Sendable {
  public let segments: [Segment]
  public let compression: SegmentCompression?

  public init(segments: [Segment], compression: SegmentCompression? = nil) {
    self.segments = segments
    self.compression = compression
  }

  /// 原始时间 -> 展示时间（压缩后）。
  public func compressedTime(forOriginal original: TimeInterval) -> TimeInterval {
    guard let compression else { return original }
    return compression.compressTime(original)
  }

  /// 展示时间（压缩后）-> 原始时间。
  public func originalTime(forCompressed compressed: TimeInterval) -> TimeInterval {
    guard let compression else { return compressed }
    return compression.expandTime(compressed)
  }

  /// 根据是否过滤静默段，构建展示用时间线。
  public static func prepare(
    segments: [Segment],
    filterSilentSegments: Bool
  ) -> SegmentTimeline {
    guard filterSilentSegments else {
      return SegmentTimeline(segments: segments, compression: nil)
    }
    let compression = SegmentCompressor.compress(segments)
    return SegmentTimeline(segments: compression.compressedSegments, compression: compression)
  }
}
