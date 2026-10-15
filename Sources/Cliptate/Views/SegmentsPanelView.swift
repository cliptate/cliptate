import CliptateCore
import SwiftUI

struct SegmentsPanelView: View {
  /// Optional direct observation of VideoState — when set, segments are
  /// computed internally via SegmentComputer, bypassing the AnyView chain.
  @ObservedObject var videoState: VideoState
  /// AI Enhance 产生的效果信息（按 segment id 存储）
  let effects: [String: SegmentEffectState]
  @ObservedObject var playback: VideoPlaybackCoordinator
  @State private var search: String = ""
  @State private var showTimes: Bool = true
  @EnvironmentObject private var config: AppConfiguration
  var onSegmentUpdate: (DisplaySeg, String) -> Void = { _, _ in }
  var onTranslationUpdate: (DisplaySeg, String?) -> Void = { _, _ in }
  var onSegmentDelete: ((DisplaySeg) -> Void)? = nil

  // 用于稳定高亮状态，避免闪烁
  @State private var stableActiveIndex: Int? = nil
  @State private var lastUpdateTime: TimeInterval = 0

  /// Segments computed from VideoState + config via SegmentComputer.
  /// This reacts to any @Published change on videoState or config.
  private var computedSegments: [Segment] {
    let input = SegmentComputer.Input(
      segments: videoState.segments,
      totalDuration: videoState.audioDuration ?? (videoState.segments.last?.endTime ?? 0),
      filterSilent: config.filterSilent,
      splitBySentence: config.splitBySentence,
      maxCharsPerSegment: config.maxCharsPerSegment,
      leftPadMs: config.leftPadMs,
      rightPadMs: config.rightPadMs,
      effectFilterFillerWords: config.effectFilterFillerWords,
      fillerWords: config.effectFillerWords,
      dictionaryEntries: config.voiceToTextCustomDictionary,
      removedSegmentIDs: videoState.removedProcessedSegmentIDs,
      processedTranslations: videoState.processedTranslations
    )
    return SegmentComputer.compute(input)
  }

  /// Whether to compress timeline display (based on filterSilent config).
  private var compressTimeline: Bool {
    config.filterSilent
  }

  // 显示用结构：保留原始时间，计算压缩后显示时间
  struct DisplaySeg: Identifiable {
    let id: Int
    let segment: Segment
    let displayStart: TimeInterval
    let displayEnd: TimeInterval
    let originalStart: TimeInterval
    let originalEnd: TimeInterval

    /// Stable identity that changes when segment content changes,
    /// forcing SwiftUI to recreate the row view and reinitialize @State.
    var contentIdentity: String {
      "\(segment.id)_\(segment.text.hashValue)_\(segment.translation?.text.hashValue ?? 0)"
    }
  }

  // Segments are already computed by SegmentComputer; just sort and optionally filter by search.
  private var sortedSegments: [Segment] {
    computedSegments.sorted { $0.startTime < $1.startTime }
  }

  private var baseFiltered: [Segment] {
    guard !search.isEmpty else { return sortedSegments }
    return sortedSegments.filter { $0.text.localizedCaseInsensitiveContains(search) }
  }

  private var displaySegments: [DisplaySeg] {
    if !compressTimeline {
      return buildNonCompressedSegments()
    } else {
      return buildCompressedSegments()
    }
  }

  // 拆分函数：非压缩路径
  private func buildNonCompressedSegments() -> [DisplaySeg] {
    let enumeratedList: [(offset: Int, element: Segment)] = Array(baseFiltered.enumerated())
    var out: [DisplaySeg] = []
    out.reserveCapacity(enumeratedList.count)
    for pair in enumeratedList {
      let seg = pair.element
      out.append(
        DisplaySeg(
          id: pair.offset,
          segment: seg,
          displayStart: seg.startTime,
          displayEnd: seg.endTime,
          originalStart: seg.startTime,
          originalEnd: seg.endTime
        ))
    }
    return out
  }

  // 拆分函数：压缩路径
  private func buildCompressedSegments() -> [DisplaySeg] {
    let sortedSegs = baseFiltered.sorted { $0.startTime < $1.startTime }
    guard !sortedSegs.isEmpty else { return [] }

    let mappings = SegmentCompressor.compress(sortedSegs).mappings

    var out: [DisplaySeg] = []
    out.reserveCapacity(sortedSegs.count)

    for (idx, pair) in zip(sortedSegs, mappings).enumerated() {
      let segment = pair.0
      let mapping = pair.1
      out.append(
        DisplaySeg(
          id: idx,
          segment: segment,
          displayStart: mapping.compressedStart,
          displayEnd: mapping.compressedEnd,
          originalStart: mapping.originalStart,
          originalEnd: mapping.originalEnd
        )
      )
    }

    return out
  }

  var body: some View {
    let currentDisplaySegments = displaySegments
    VStack(spacing: 0) {
      VStack(spacing: 10) {
        SegmentsPanelHeader(
          displayCount: currentDisplaySegments.count,
          hasSegments: !computedSegments.isEmpty,
          hasDiarization: hasDiarization,
          showTimes: $showTimes
        )
        searchView
      }
      .padding(12)
      Divider()
      segmentsListView(currentDisplaySegments)
    }
    .frame(maxHeight: .infinity)
    .background(AppSurface.inputBackground)
    .onChange(of: playback.isPlaying) { _, isPlaying in
      handlePlaybackStateChange(isPlaying: isPlaying)
    }
    .onChange(of: playback.currentTime) { _, newTime in
      Task { @MainActor in
        updateActiveIndex(currentTime: newTime)
      }
    }
  }


  private var hasDiarization: Bool {
    computedSegments.contains { $0.speakerId != nil }
  }

  private var searchView: some View {
    TextField("Search…", text: $search)
      .textFieldStyle(.roundedBorder)
      .padding(.horizontal, 4)
  }


  private func segmentsListView(_ displaySegs: [DisplaySeg]) -> some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(displaySegs) { item in
            SegmentRowView(
              item: item,
              showTimes: showTimes,
              active: item.id == stableActiveIndex,
              compressTimeline: compressTimeline,
              effect: effects[item.segment.id],
              translation: item.segment.translation,
              playAction: {
                let targetTime = compressTimeline ? item.displayStart : item.originalStart
                playback.seekAndPlay(to: targetTime)
              },
              deleteAction: onSegmentDelete.map { handler in
                { handler(item) }
              },
              onCommit: { updatedText in
                onSegmentUpdate(item, updatedText)
              },
              onTranslationCommit: { updatedTranslation in
                onTranslationUpdate(item, updatedTranslation)
              }
            )
            // Key insight: include text hash in the view identity so SwiftUI
            // recreates the row (reinitializing @State) when text changes externally.
            // Local edits don't change this identity until commit propagates back.
            .id(item.contentIdentity)
            Divider().padding(.leading, 16)
          }
        }
      }
      .onChange(of: stableActiveIndex) { _, newIndex in
        if let activeIndex = newIndex {
          withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(displaySegs.first { $0.id == activeIndex }?.contentIdentity, anchor: .center)
          }
        }
      }
    }
  }


}

extension SegmentsPanelView {

  private func handlePlaybackStateChange(isPlaying: Bool) {
    let timelineIsCompressed = playback.isCompressedTimeline
    if isPlaying {
      // 开始播放时立即更新活跃索引
      stableActiveIndex = activeIndexForCurrentTime(
        playTime: playback.currentTime, compressedPlayback: timelineIsCompressed)
    }
    // 停止播放时不再清除高亮，保持蓝色直到播放结束
  }

  // 检查播放是否到达末尾，清除高亮
  private func checkPlaybackEnd() {
    guard playback.duration > 0 else { return }
    // 如果当前时间接近或超过视频时长，认为播放结束
    if playback.currentTime >= playback.duration - 0.1 {
      stableActiveIndex = nil
    }
  }
}

// MARK: - Active index helper

extension SegmentsPanelView {
  /// 更新活跃索引（不需要 ScrollViewProxy）
  @MainActor
  fileprivate func updateActiveIndex(currentTime: TimeInterval) {
    // 防抖：限制更新频率，避免过于频繁的状态变化
    let now = Date().timeIntervalSince1970
    guard now - lastUpdateTime > 0.15 else { return }  // 150ms 防抖
    lastUpdateTime = now

    let timelineIsCompressed = playback.isCompressedTimeline
    let newActiveIndex =
      playback.isPlaying
      ? activeIndexForCurrentTime(playTime: currentTime, compressedPlayback: timelineIsCompressed)
      : nil

    // 检查播放是否结束
    checkPlaybackEnd()

    // 稳定化：只在活跃段真正变化时才更新
    if newActiveIndex != stableActiveIndex {
      withAnimation(.easeInOut(duration: 0.3)) {
        stableActiveIndex = newActiveIndex
      }
    }
  }

  /// 带防抖的活跃索引更新方法（保留用于手动调用）
  @MainActor
  fileprivate func updateActiveIndexWithDebounce(
    currentTime: TimeInterval, proxy: ScrollViewProxy
  ) {
    updateActiveIndex(currentTime: currentTime)

    // 自动滚动到当前活跃段
    if let activeIndex = stableActiveIndex {
      withAnimation(.easeInOut(duration: 0.3)) {
        proxy.scrollTo(activeIndex, anchor: .center)
      }
    }
  }

  /// 统一的高亮计算：
  /// - compressedPlayback: 播放器自身时间是否已裁剪（与 displaySegments 的 displayStart/displayEnd 对齐）
  /// 算法：
  /// 1. 选择待搜索的时间数组 (starts / ends)
  /// 2. 二分定位 start <= t 的最大索引
  /// 3. 校验 t 是否落在对应 end + 容差内，否则返回 nil
  /// 4. 可选线性回退（处理潜在微小排序/浮点误差）
  fileprivate func activeIndexForCurrentTime(playTime: TimeInterval, compressedPlayback: Bool)
    -> Int?
  {
    let list = displaySegments
    guard !list.isEmpty else { return nil }

    // 增加容差范围，减少边界闪烁
    let tolerance: TimeInterval = 0.15
    let starts: [TimeInterval] =
      compressedPlayback ? list.map { $0.displayStart } : list.map { $0.segment.startTime }
    let ends: [TimeInterval] =
      compressedPlayback ? list.map { $0.displayEnd } : list.map { $0.segment.endTime }

    // 快速边界检查
    if playTime < starts[0] - tolerance || playTime > ends.last! + tolerance { return nil }

    // 找到第一个 start 大于 playTime+tolerance 的位置，然后回退一位
    var low = 0
    var high = starts.count
    let pivot = playTime + tolerance
    while low < high {
      let mid = (low + high) >> 1
      if starts[mid] > pivot { high = mid } else { low = mid + 1 }
    }
    let idx = max(0, low - 1)

    // 验证时间是否在有效范围内
    if playTime >= starts[idx] - tolerance && playTime <= ends[idx] + tolerance {
      return idx
    }

    return nil
  }
}
