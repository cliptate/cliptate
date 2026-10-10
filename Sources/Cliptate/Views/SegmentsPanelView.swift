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

  private var headerControlState: SegmentsPanelHeaderControlState {
    SegmentsPanelHeaderControlState(
      hasSegments: !computedSegments.isEmpty,
      showTimes: showTimes
    )
  }

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
    VStack(spacing: 12) {
      headerView(displayCount: currentDisplaySegments.count)
      searchView
      segmentsListView(currentDisplaySegments)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.top, 16)
    .padding(.bottom, 18)
    .frame(maxHeight: .infinity)
    .background(.ultraThinMaterial)
    .onChange(of: playback.isPlaying) { _, isPlaying in
      handlePlaybackStateChange(isPlaying: isPlaying)
    }
    .onChange(of: playback.currentTime) { _, newTime in
      Task { @MainActor in
        updateActiveIndex(currentTime: newTime)
      }
    }
  }


  private func headerView(displayCount: Int) -> some View {
    HStack(spacing: 6) {
      Text("Segments")
        .font(.headline)
      if !computedSegments.isEmpty {
        Text("\(displayCount)")
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Capsule().fill(Color.secondary.opacity(0.5)))
      }
      // Show a diarization badge when any segment carries a speaker ID
      if hasDiarization {
        Label("Speaker", systemImage: "person.2.wave.2")
          .font(.caption2.weight(.medium))
          .foregroundStyle(Color.accentColor)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(
            Capsule().fill(Color.accentColor.opacity(0.12))
          )
          .help(
            String(
              localized: "Diarization active – speaker badges are shown per segment",
              comment: "Tooltip shown when any segment has a speaker ID"))
      }
      Spacer()
      Button(action: { showTimes.toggle() }) {
        Image(systemName: headerControlState.timeSymbolName)
          .foregroundStyle(
            headerControlState.isTimeHighlighted ? Color.accentColor : Color.secondary
          )
          .frame(
            width: headerControlState.controlSize.width,
            height: headerControlState.controlSize.height
          )
          .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
              .fill(
                headerControlState.isTimeHighlighted
                  ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06)
              )
          )
      }
      .buttonStyle(.borderless)
      .contentShape(Rectangle())
      .accessibilityIdentifier("segments.toggle-times")
      .help(
        headerControlState.showTimes
          ? String(localized: "Hide times", comment: "Tooltip to hide time labels in segments panel")
          : String(localized: "Show times", comment: "Tooltip to show time labels in segments panel")
      )
    }
    .padding(.horizontal, 4)
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
        LazyVStack(alignment: .leading, spacing: 8) {
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
          }
        }
        .padding(.vertical, 4)
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

  private func timeLabel(_ t: TimeInterval) -> String {
    // 精确到毫秒 mm:ss.SSS
    let msTotal = Int((t * 1000).rounded())
    let m = msTotal / 60000
    let s = (msTotal % 60000) / 1000
    let ms = msTotal % 1000
    return String(format: "%02d:%02d.%03d", m, s, ms)
  }
}

struct SegmentsPanelHeaderControlState {
  let hasSegments: Bool
  let showTimes: Bool

  let timeSymbolName = "clock"
  var isTimeHighlighted: Bool { showTimes }
  let controlSize = CGSize(width: 30, height: 28)
}

// MARK: - Row Subview
private struct SegmentRowView: View {
  @EnvironmentObject private var config: AppConfiguration
  let item: SegmentsPanelView.DisplaySeg
  let showTimes: Bool
  let active: Bool
  let compressTimeline: Bool
  let effect: SegmentEffectState?
  let translation: SegmentTranslation?
  let playAction: () -> Void
  let deleteAction: (() -> Void)?
  let onCommit: (String) -> Void
  let onTranslationCommit: (String?) -> Void

  // Local editing buffers — initialized from segment data.
  // Because the parent uses .id(contentIdentity), this view is RECREATED
  // whenever segment text changes externally (AI correction, etc.),
  // so @State is always fresh. No complex onChange sync needed.
  @State private var editedText: String
  @State private var editedTranslation: String
  @State private var isHovered: Bool = false
  @FocusState private var isFocused: Bool
  @FocusState private var isTranslationFocused: Bool

  private static let durationFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = ","
    formatter.maximumFractionDigits = 0
    formatter.minimumFractionDigits = 0
    return formatter
  }()

  init(
    item: SegmentsPanelView.DisplaySeg, showTimes: Bool, active: Bool, compressTimeline: Bool,
    effect: SegmentEffectState?, translation: SegmentTranslation?, playAction: @escaping () -> Void,
    deleteAction: (() -> Void)? = nil,
    onCommit: @escaping (String) -> Void,
    onTranslationCommit: @escaping (String?) -> Void
  ) {
    self.item = item
    self.showTimes = showTimes
    self.active = active
    self.compressTimeline = compressTimeline
    self.effect = effect
    self.translation = translation
    self.playAction = playAction
    self.deleteAction = deleteAction
    self.onCommit = onCommit
    self.onTranslationCommit = onTranslationCommit
    self._editedText = State(initialValue: item.segment.text)
    self._editedTranslation = State(initialValue: translation?.text ?? "")
  }

  var body: some View {
    let highlightCoverage = Self.normalizedCoverage(effect?.highlightCoverage ?? 0)
    let hasHighlights = !(effect?.keywords.isEmpty ?? true) && highlightCoverage > 0
    let zoomScale = Self.deriveZoomScale(from: effect?.appliedZoom)
    let baseBackground =
      active
      ? Color.accentColor.opacity(0.18)
      : Color.primary.opacity(0.05)
    let highlightOverlayOpacity =
      hasHighlights
      ? 0.12 + (highlightCoverage * 0.25)
      : 0
    let resolvedTranslation = normalizedTranslation

    return panelBody(
      highlightCoverage: highlightCoverage,
      zoomScale: zoomScale,
      baseBackground: baseBackground,
      highlightOverlayOpacity: highlightOverlayOpacity,
      resolvedTranslation: resolvedTranslation
    )
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.15)) {
        isHovered = hovering
      }
    }
  }

  @ViewBuilder
  private func panelBody(
    highlightCoverage: Double,
    zoomScale: CGFloat,
    baseBackground: Color,
    highlightOverlayOpacity: Double,
    resolvedTranslation: SegmentTranslation?
  ) -> some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 6) {
        if let resolvedTranslation, config.translationPlacement == .above {
          translationEditor(for: resolvedTranslation)
        }

        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text("#\(item.id + 1)")
            .font(.caption2)
            .foregroundColor(active ? .accentColor : .secondary)

          if let sid = item.segment.speakerId {
            Text(speakerBadgeText(id: sid))
              .font(.caption.weight(.semibold))
              .foregroundStyle(Color.white)
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background(
                Capsule().fill(speakerBadgeColor(id: sid))
              )
              .help(String(format: String(localized: "Speaker %lld", comment: "Speaker badge tooltip showing speaker number"), Int64(sid + 1)))
          }

          ZStack(alignment: .topLeading) {
            HighlightedSegmentText(
              text: editedText,
              effect: effect,
              isActive: active
            )
            .opacity(isFocused ? 0 : 1)
            .onTapGesture { isFocused = true }

            TextField("Segment text", text: $editedText, axis: .vertical)
              .textFieldStyle(.plain)
              .font(.subheadline)
              .foregroundColor(active ? .accentColor : .primary)
              .lineLimit(3...6)
              .focused($isFocused)
              .opacity(isFocused ? 1 : 0)
              .allowsHitTesting(isFocused)
              .onSubmit { commitIfNeeded() }
          }
          .scaleEffect(zoomScale, anchor: .topLeading)
          .animation(
            .spring(response: 0.35, dampingFraction: 0.78, blendDuration: 0.15),
            value: zoomScale
          )
        }

        if let resolvedTranslation, config.translationPlacement == .below {
          translationEditor(for: resolvedTranslation)
        }

        if showTimes {
          HStack(spacing: 6) {
            Text(timeLabel(item.displayStart))
            Text("→").foregroundColor(.secondary)
            Text(timeLabel(item.displayEnd))
            Text("(\(formatDuration(item.displayEnd - item.displayStart)))")
              .foregroundColor(.secondary.opacity(0.7))
          }
          .font(.caption2)
          .foregroundColor(active ? .accentColor : .secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if isHovered || active || isFocused {
        HStack(spacing: 4) {
          Button(action: playAction) {
            Image(systemName: "play.circle.fill")
              .font(.title3)
              .foregroundColor(.accentColor)
          }
          .buttonStyle(.plain)
          .help(String(localized: "Play this segment", comment: "Tooltip for play segment button"))

          if let deleteAction {
            Button(role: .destructive, action: deleteAction) {
              Image(systemName: "trash")
                .font(.body)
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Delete this segment", comment: "Tooltip for delete segment button"))
          }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.85)))
      }
    }
    .padding(10)
    .background(
      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(baseBackground)
        if highlightOverlayOpacity > 0 {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.yellow.opacity(highlightOverlayOpacity))
            .transition(.opacity)
        }
      }
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(
          active ? Color.accentColor.opacity(0.4) : Color.clear,
          lineWidth: 2
        )
    )
    .overlay(alignment: .topTrailing) {
      if let zoomLabel = effect?.appliedZoom, zoomLabel > 1.0 {
        ZoomBadgeView(scale: zoomLabel, coverage: highlightCoverage)
          .padding(6)
      }
    }
    .onChange(of: isFocused) { _, focused in
      if !focused { commitIfNeeded() }
    }
    .onChange(of: isTranslationFocused) { _, focused in
      if !focused { commitTranslationIfNeeded() }
    }
    .onDisappear {
      commitIfNeeded()
      commitTranslationIfNeeded()
    }
  }

  private func timeLabel(_ t: TimeInterval) -> String {
    let msTotal = Int((t * 1000).rounded())
    let m = msTotal / 60000
    let s = (msTotal % 60000) / 1000
    let ms = msTotal % 1000
    return String(format: "%02d:%02d.%03d", m, s, ms)
  }

  private func formatDuration(_ duration: TimeInterval) -> String {
    let milliseconds = Int((duration * 1000).rounded())
    let formatted =
      Self.durationFormatter.string(from: NSNumber(value: milliseconds))
      ?? String(milliseconds)
    return String(localized: "\(formatted) ms", comment: "Segment duration in milliseconds")
  }

  private var normalizedTranslation: SegmentTranslation? {
    guard let translation, !translation.isEmpty else { return nil }
    return translation
  }

  @ViewBuilder
  private func translationEditor(for translation: SegmentTranslation) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Image(systemName: "globe")
          .font(.caption2)
          .foregroundColor(.secondary)
        Text(translation.language.displayName)
          .font(.caption2)
          .foregroundColor(.secondary)
      }

      ZStack(alignment: .topLeading) {
        Text(editedTranslation)
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.leading)
          .lineLimit(3...6)
          .fixedSize(horizontal: false, vertical: true)
          .opacity(isTranslationFocused ? 0 : 1)
          .onTapGesture { isTranslationFocused = true }

        TextField("Translation", text: $editedTranslation, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .font(.callout)
          .focused($isTranslationFocused)
          .lineLimit(3...6)
          .opacity(isTranslationFocused ? 1 : 0)
          .allowsHitTesting(isTranslationFocused)
          .onSubmit { commitTranslationIfNeeded() }
      }
    }
    .padding(.vertical, 2)
    .transition(.opacity.combined(with: .move(edge: .top)))
  }
}

extension SegmentRowView {
  fileprivate func commitIfNeeded() {
    let newValue = editedText
    guard newValue != item.segment.text else { return }
    onCommit(newValue)
  }

  fileprivate func commitTranslationIfNeeded() {
    guard translation != nil else { return }
    let trimmed = editedTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
    let current = translation?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard trimmed != current else { return }
    onTranslationCommit(trimmed.isEmpty ? nil : trimmed)
  }
}

// MARK: - Highlight Rendering

private struct HighlightedSegmentText: View {
  let text: String
  let effect: SegmentEffectState?
  let isActive: Bool

  private let baseHighlightFontSize: CGFloat = 13

  var body: some View {
    buildText()
      .font(.subheadline)
      .foregroundColor(isActive ? .accentColor : .primary)
      .lineLimit(6)
      .fixedSize(horizontal: false, vertical: true)
      .multilineTextAlignment(.leading)
      .animation(nil, value: effect?.keywords)  // 避免频繁更新导致闪烁
  }

  private func buildText() -> Text {
    let keywords = effect?.keywords ?? []
    guard !keywords.isEmpty else {
      return Text(text)
    }

    let matches = keywordRanges(in: text, keywords: keywords)
    guard !matches.isEmpty else {
      return Text(text)
    }

    var components: [Text] = []
    var cursor = text.startIndex

    for range in matches {
      if range.lowerBound > cursor {
        let prefix = String(text[cursor..<range.lowerBound])
        if !prefix.isEmpty {
          components.append(Text(prefix))
        }
      }

      let keyword = String(text[range])
      var highlight = Text(keyword)
        .bold()
        .foregroundColor(.yellow)
      if let scale = effect?.appliedScale, scale > 0 {
        let fontSize = baseHighlightFontSize * scale
        highlight = highlight.font(.system(size: fontSize, weight: .bold))
      }
      components.append(highlight)

      cursor = range.upperBound
    }

    if cursor < text.endIndex {
      let suffix = String(text[cursor...])
      if !suffix.isEmpty {
        components.append(Text(suffix))
      }
    }

    guard let first = components.first else {
      return Text(text)
    }

    return components.dropFirst().reduce(first) { $0 + $1 }
  }

  private func keywordRanges(in text: String, keywords: [String]) -> [Range<String.Index>] {
    guard !text.isEmpty else { return [] }

    let lowercasedText = text.lowercased()
    var collected: [Range<String.Index>] = []

    for keyword in keywords {
      let normalized = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !normalized.isEmpty else { continue }
      let lowerKeyword = normalized.lowercased()

      var searchRange: Range<String.Index> = lowercasedText.startIndex..<lowercasedText.endIndex
      while let found = lowercasedText.range(of: lowerKeyword, options: [], range: searchRange) {
        let lowerStartOffset = lowercasedText.distance(
          from: lowercasedText.startIndex, to: found.lowerBound)
        let lowerEndOffset = lowercasedText.distance(
          from: lowercasedText.startIndex, to: found.upperBound)

        guard
          let start = text.index(
            text.startIndex, offsetBy: lowerStartOffset, limitedBy: text.endIndex),
          let end = text.index(text.startIndex, offsetBy: lowerEndOffset, limitedBy: text.endIndex)
        else {
          break
        }

        let candidate = start..<end
        if !collected.contains(where: { $0 == candidate }) {
          collected.append(candidate)
        }

        searchRange = found.upperBound..<lowercasedText.endIndex
      }
    }

    return collected.sorted { $0.lowerBound < $1.lowerBound }
  }
}

extension SegmentRowView {
  fileprivate static func normalizedCoverage(_ coverage: Double) -> Double {
    if coverage.isNaN || coverage.isInfinite { return 0 }
    return min(max(coverage, 0), 1)
  }

  fileprivate static func deriveZoomScale(from rawZoom: Double?) -> CGFloat {
    guard let rawZoom else { return 1 }
    if rawZoom.isNaN || rawZoom.isInfinite { return 1 }
    return CGFloat(min(max(rawZoom, 1), 2.6))
  }
}

private struct ZoomBadgeView: View {
  let scale: Double
  let coverage: Double

  private var displayText: String {
    if scale >= 2.0 {
      return String(format: "×%.1f", scale)
    } else {
      return String(format: "×%.2f", scale)
    }
  }

  private var accentOpacity: Double {
    let normalized = min(max(coverage, 0), 1)
    return 0.35 + (normalized * 0.25)
  }

  var body: some View {
    Label {
      Text(displayText)
        .fontWeight(.semibold)
    } icon: {
      Image(systemName: "viewfinder")
        .font(.caption2)
    }
    .font(.caption2)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(
      Capsule(style: .continuous)
        .fill(Color.accentColor.opacity(0.16))
        .overlay(
          Capsule(style: .continuous)
            .stroke(Color.accentColor.opacity(accentOpacity), lineWidth: 1)
        )
    )
    .foregroundColor(.accentColor)
  }
}

// MARK: - State Change Handlers

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
