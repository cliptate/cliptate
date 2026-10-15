import CliptateCore
import AVFoundation
import AVKit
import SwiftAssRenderer  // 恢复 ASS 字幕功能
import SwiftUI

// 使用 ViewModel 保证所有 UI 状态更新在主线程，避免并发导致的 SwiftUI/AVKit 元数据崩溃
final class VideoPlayerViewModel: ObservableObject, @unchecked Sendable {
  @Published var player: AVPlayer?
  @Published var isBuildingComposition = false
  @Published var errorMessage: String?

  private let url: URL
  private var segments: [Segment]
  private var compressSilence: Bool
  private var compositionTask: Task<Void, Never>?
  private weak var playback: VideoPlaybackCoordinator?

  init(url: URL, segments: [Segment], compressSilence: Bool, playback: VideoPlaybackCoordinator?) {
    self.url = url
    self.segments = segments
    self.compressSilence = compressSilence
    self.playback = playback
  }

  deinit {
    compositionTask?.cancel()
  }

  func cleanup() {
    // 停止并清理播放器
    player?.pause()
    player?.replaceCurrentItem(with: nil)
    player = nil
  }

  @discardableResult
  func start() -> AVPlayer {
    // 先用原始视频快速展示，避免长时间空白 & 提前触发 AVKit 元数据准备
    if let existing = player {
      buildCompositionIfNeeded()
      return existing
    }

    let newPlayer = AVPlayer(url: url)
    player = newPlayer
    buildCompositionIfNeeded()
    return newPlayer
  }

  private func buildCompositionIfNeeded() {
    guard compressSilence, !segments.isEmpty else { return }
    // 如果 segments 覆盖全部内容意义不大，直接跳过
    // 仅当裁剪段总时长 < 原视频时执行（避免不必要重建）
    compositionTask = Task { @MainActor [weak self] in
      guard let self else { return }
      let needsStop = self.url.startAccessingSecurityScopedResource()
      defer { if needsStop { self.url.stopAccessingSecurityScopedResource() } }

      self.isBuildingComposition = true
      self.errorMessage = nil
      defer { self.isBuildingComposition = false }

      do {
        let asset = AVURLAsset(
          url: self.url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard let audioTrack = audioTracks.first else {
          self.errorMessage = "No audio track"
          return
        }
        let videoTrack = videoTracks.first

        // 使用 SegmentCompressor 生成压缩映射，确保与 ASSGenerator 使用相同的压缩逻辑
        let compression = SegmentCompressor.compress(self.segments)
        let mappings = compression.mappings

        // 计算压缩后的总时长
        let totalCompressedSeconds = mappings.reduce(0.0) {
          $0 + ($1.originalEnd - $1.originalStart)
        }
        if abs(totalCompressedSeconds - duration.seconds) / max(1, duration.seconds) < 0.01 {
          // 几乎等于整段，不必构建裁剪合成
          return
        }

        let composition = AVMutableComposition()
        let videoCompTrack: AVMutableCompositionTrack?
        if videoTrack != nil {
          videoCompTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        } else {
          videoCompTrack = nil
        }

        if videoTrack != nil && videoCompTrack == nil {
          self.errorMessage = "Cannot create video track"
          return
        }

        guard
          let audioCompTrack = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
          self.errorMessage = "Cannot create audio track"
          return
        }

        // 使用压缩映射来构建 composition
        // 这样确保视频剪辑和字幕时间完全一致
        for mapping in mappings {
          do {
            // 从原始时间剪辑
            let sourceRange = CMTimeRange(
              start: CMTime(seconds: mapping.originalStart, preferredTimescale: 60000),
              end: CMTime(seconds: mapping.originalEnd, preferredTimescale: 60000)
            )
            // 放到压缩后的时间
            let targetTime = CMTime(seconds: mapping.compressedStart, preferredTimescale: 60000)
            if let videoTrack, let videoCompTrack {
              try videoCompTrack.insertTimeRange(sourceRange, of: videoTrack, at: targetTime)
            }
            try audioCompTrack.insertTimeRange(sourceRange, of: audioTrack, at: targetTime)
          } catch {
            print("[VideoPlayerViewModel] insert failed mapping=\(mapping) error=\(error)")
          }
        }

        // 构建完成后替换播放内容（保持同一个 AVPlayer 避免 SwiftUI/AVKit 状态错乱）
        if Task.isCancelled { return }
        if let currentPlayer = self.player {
          let item = AVPlayerItem(asset: composition)
          currentPlayer.replaceCurrentItem(with: item)
          if let playback = self.playback { playback._updateCompressedTimeline(true) }
        }
      } catch {
        self.errorMessage = error.localizedDescription
      }
    }
  }

  func updateSegments(_ new: [Segment]) {
    // 若内容未变化（按时间戳与文本）则跳过
    if new.count == segments.count,
      zip(new, segments).allSatisfy({
        $0.startTime == $1.startTime && $0.endTime == $1.endTime && $0.text == $1.text
      })
    {
      return
    }
    compositionTask?.cancel()
    segments = new
    buildCompositionIfNeeded()
  }

  func setCompressSilence(_ enabled: Bool, segments newSegments: [Segment]) {
    // 若状态未变化且段相同则跳过
    if enabled == compressSilence,
      newSegments.count == segments.count,
      zip(newSegments, segments).allSatisfy({
        $0.startTime == $1.startTime && $0.endTime == $1.endTime
      })
    {
      return
    }
    compositionTask?.cancel()
    compressSilence = enabled
    segments = newSegments
    if enabled {
      buildCompositionIfNeeded()
    } else {
      // 恢复原始播放
      Task { @MainActor in
        isBuildingComposition = false
        if let player {
          let originalItem = AVPlayerItem(url: url)
          player.replaceCurrentItem(with: originalItem)
          playback?._updateCompressedTimeline(false)
        } else {
          player = AVPlayer(url: url)
          playback?._updateCompressedTimeline(false)
        }
      }
    }
  }

  var debugSegmentsSnapshot: [Segment] { segments }
}

struct VideoPlayerView: View {
  let url: URL
  @ObservedObject var videoState: VideoState
  let segments: [Segment]
  let filterSilentSegments: Bool
  let effects: [String: SegmentEffectState]
  let translationPlacement: SubtitleTranslationPlacement
  let styleConfiguration: SubtitleStylesConfiguration
  @ObservedObject var playback: VideoPlaybackCoordinator
  var activeURL: URL?  // 当前激活的视频 URL（用于切换时自动暂停/播放）
  var onSegmentDelete: ((Segment) -> Void)?

  @StateObject private var viewModel: VideoPlayerViewModel
  @State private var ass: String
  @State private var assRenderer: AssSubtitlesRenderer = .init(
    fontConfig: FontConfig(fontsPath: URL(fileURLWithPath: "/System/Library/Fonts")),
    logOutput: .console(.verbose)
  )
  @State private var timeObserverToken: Any?
  @State private var observedPlayer: AVPlayer?
  @State private var segmentUpdateTask: Task<Void, Never>?  // 用于防抖segment更新
  @State private var detectedOrientation: SubtitleOrientation
  @State private var presentationSize: CGSize?
  @State private var layoutResult: VideoOrientationLayout.Result?
  @State private var subtitlePreviewMode: SubtitlePreviewMode = .nativeTextOverlay
  @State private var isScrubbing = false
  @State private var scrubbedTime: TimeInterval?
  @State private var wasPlayingBeforeScrub = false
  @State private var lastWaveformWidth: CGFloat = 0
  @State private var selectedWaveformSegmentID: SegmentIdentifier?

  static func resolvedDisplayedSegments(
    passedSegments: [Segment],
    processedSegments: [Segment]
  ) -> [Segment] {
    processedSegments.isEmpty ? passedSegments : processedSegments
  }

  private var effectiveSegments: [Segment] {
    Self.resolvedDisplayedSegments(
      passedSegments: segments,
      processedSegments: videoState.processedSegments
    )
  }

  // 通过哈希跟踪段变化，避免要求 Segment: Equatable
  private var segmentsHash: Int {
    Self.makeSegmentsSignature(for: effectiveSegments)
  }

  private var effectsHash: Int {
    Self.makeEffectsSignature(for: effects)
  }

  private var translationsHash: Int {
    Self.makeTranslationsSignature(for: effectiveSegments)
  }

  private var styleSignature: Int {
    Self.makeStyleSignature(for: styleConfiguration)
  }

  private var activeLayout: VideoOrientationLayout.Result {
    if let layoutResult {
      return layoutResult
    }

    let fallbackSize = presentationSize ?? Self.defaultVideoSize(for: detectedOrientation)
    return VideoOrientationLayout.layout(for: fallbackSize, targetOrientation: detectedOrientation)
  }

  private var sliderRange: ClosedRange<Double> {
    let duration = playback.duration
    if duration.isFinite, duration > 0 {
      return 0...duration
    }
    let segmentsDuration = effectiveSegments.last?.endTime ?? 1
    return 0...max(segmentsDuration, 1)
  }

  private var displayedTime: TimeInterval {
    scrubbedTime ?? playback.currentTime
  }

  private var waveformDuration: TimeInterval {
    if playback.duration.isFinite, playback.duration > 0 {
      return playback.duration
    }
    if let duration = playback.waveformSnapshot?.duration {
      return duration
    }
    if let cached = videoState.audioDuration {
      return cached
    }
    return effectiveSegments.last?.endTime ?? 0
  }

  private var waveformProgress: Double {
    let duration = waveformDuration
    guard duration > 0 else { return 0 }
    let time = scrubbedTime ?? playback.currentTime
    return max(0, min(1, time / duration))
  }

  static func makeSegmentsSignature(for segments: [Segment]) -> Int {
    segments.reduce(into: 17) { partial, seg in
      partial = partial &* 31 &+ Int(seg.startTime * 1000)
      partial = partial &* 31 &+ Int(seg.endTime * 1000)
      partial = partial &* 31 &+ seg.text.hashValue
      if let words = seg.words {
        partial = partial &* 31 &+ words.count
      }
    }
  }

  static func makeEffectsSignature(for effects: [String: SegmentEffectState]) -> Int {
    guard !effects.isEmpty else { return 0 }
    let sorted = effects.sorted { $0.key < $1.key }
    return sorted.reduce(into: 23) { partial, entry in
      let (key, state) = entry
      partial = partial &* 37 &+ key.hashValue
      if !state.keywords.isEmpty {
        partial = partial &* 37 &+ state.keywords.joined(separator: "|").hashValue
      }
      if let scale = state.appliedScale {
        partial = partial &* 37 &+ Int((scale * 1000).rounded())
      }
      if let zoom = state.appliedZoom {
        partial = partial &* 37 &+ Int((zoom * 1000).rounded())
      }
      partial = partial &* 37 &+ Int((state.highlightCoverage * 1000).rounded())
    }
  }

  static func makeTranslationsSignature(for segments: [Segment]) -> Int {
    let translations = segments.compactMap { $0.translation }
    guard !translations.isEmpty else { return 0 }
    return translations.reduce(into: 41) { partial, value in
      partial = partial &* 43 &+ value.text.hashValue
      partial = partial &* 43 &+ value.language.rawValue.hashValue
      let timestamp = Int((value.translatedAt.timeIntervalSinceReferenceDate * 1000).rounded())
      partial = partial &* 43 &+ timestamp
    }
  }

  static func makeStyleSignature(for configuration: SubtitleStylesConfiguration) -> Int {
    var hasher = Hasher()
    hashStyleSet(configuration.landscape, into: &hasher)
    hashStyleSet(configuration.portrait, into: &hasher)
    return hasher.finalize()
  }

  private static func defaultVideoSize(for orientation: SubtitleOrientation) -> CGSize {
    switch orientation {
    case .landscape:
      return CGSize(width: 1920, height: 1080)
    case .portrait:
      return CGSize(width: 1080, height: 1920)
    }
  }

  private static func orientation(for size: CGSize) -> SubtitleOrientation {
    size.height >= size.width ? .portrait : .landscape
  }

  private static func displaySize(for naturalSize: CGSize, transform: CGAffineTransform) -> CGSize {
    let width = abs(naturalSize.width * transform.a) + abs(naturalSize.height * transform.c)
    let height = abs(naturalSize.width * transform.b) + abs(naturalSize.height * transform.d)
    if width > 0.5 && height > 0.5 {
      return CGSize(width: width, height: height)
    }
    return naturalSize
  }

  private static func hashStyleSet(_ styles: SubtitleStyleSet, into hasher: inout Hasher) {
    hashStyle(styles.primary, into: &hasher)
    hashStyle(styles.translation, into: &hasher)
    hashStyle(styles.highlight, into: &hasher)
  }

  private static func hashStyle(_ style: SubtitleStyle, into hasher: inout Hasher) {
    hasher.combine(style.fontName)
    hasher.combine(style.fontSize)
    hasher.combine(style.bold)
    hasher.combine(style.italic)
    hashColor(style.fillColor, into: &hasher)
    hashColor(style.outlineColor, into: &hasher)
    hashColor(style.backColor, into: &hasher)
    hashColor(style.shadowColor, into: &hasher)
    hasher.combine(style.outlineWidth)
    hasher.combine(style.shadowRadius)
    hasher.combine(style.shadowAngle)
    hasher.combine(style.kerning)
  }

  private static func hashColor(_ color: SubtitleColor, into hasher: inout Hasher) {
    hasher.combine(color.red)
    hasher.combine(color.green)
    hasher.combine(color.blue)
    hasher.combine(color.alpha)
  }

  init(
    url: URL,
    videoState: VideoState,
    segments: [Segment],
    filterSilentSegments: Bool,
    playback: VideoPlaybackCoordinator,
    activeURL: URL? = nil,
    effects: [String: SegmentEffectState] = [:],
    translationPlacement: SubtitleTranslationPlacement = .below,
    styleConfiguration: SubtitleStylesConfiguration? = nil,
    onSegmentDelete: ((Segment) -> Void)? = nil
  ) {
    let resolvedStyles = styleConfiguration ?? defaultSubtitleStyles
    let initialSegments = Self.resolvedDisplayedSegments(
      passedSegments: segments,
      processedSegments: videoState.processedSegments
    )
    self.url = url
    self.videoState = videoState
    self.segments = segments
    self.filterSilentSegments = filterSilentSegments
    self.effects = effects
    self.translationPlacement = translationPlacement
    self.styleConfiguration = resolvedStyles
    self.playback = playback
    self.activeURL = activeURL
    self.onSegmentDelete = onSegmentDelete
    let initialPresentationSize = videoState.presentationSize
    let initialDetectedOrientation: SubtitleOrientation
    if let presentationSize = initialPresentationSize, presentationSize.width > 0,
      presentationSize.height > 0
    {
      initialDetectedOrientation = Self.orientation(for: presentationSize)
    } else {
      initialDetectedOrientation = .landscape
    }
    let initialLayout = initialPresentationSize.map {
      VideoOrientationLayout.layout(for: $0, targetOrientation: initialDetectedOrientation)
    }
    _ass = State(
      initialValue: ASSGenerator.makeASS(
        segments: initialSegments,
        orientation: initialDetectedOrientation,
        filterSilentSegments: filterSilentSegments,
        effects: effects,
        translationPlacement: translationPlacement,
        styleConfiguration: resolvedStyles
      )
    )
    _detectedOrientation = State(initialValue: initialDetectedOrientation)
    _presentationSize = State(initialValue: initialPresentationSize)
    _layoutResult = State(initialValue: initialLayout)
    _viewModel = StateObject(
      wrappedValue: VideoPlayerViewModel(
        url: url,
        segments: initialSegments,
        compressSilence: filterSilentSegments,
        playback: playback
      ))
  }

  var body: some View {
    VStack(spacing: 0) {
      ZStack {
        EditorVideoCanvas(player: viewModel.player, layout: activeLayout) { player, canvasSize in
          subtitlesOverlay(player: player, canvasSize: canvasSize)
        }

        VStack(spacing: 4) {
          if viewModel.isBuildingComposition {
            ProgressView()
              .frame(width: 20, height: 20)
            Text("Building selection…")
              .font(.caption2)
              .foregroundColor(.orange)
          }
          if let error = viewModel.errorMessage {
            Text(error)
              .font(.caption2)
              .foregroundColor(.red)
              .padding(.horizontal, 8)
          }
        }
        .padding(.horizontal, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      controlsStack
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 18)
    }
    .contentShape(Rectangle())
    .onAppear {
      print(
        "🎬 [ASS] onAppear: segments=\(effectiveSegments.count) filter=\(filterSilentSegments) initialASS=\(ass.count)chars"
      )
      let player = viewModel.start()
      setupPlaybackSync(with: player)
      updateASS(force: true)
      loadASSTrack()
      playback._updateCompressedTimeline(filterSilentSegments)
      if playback.isPlaying {
        player.play()
      } else {
        player.pause()
        playback._updatePlaying(false)
      }
      triggerWaveformLoadIfNeeded(width: lastWaveformWidth)
    }
    .onDisappear {
      print("🗑️ [VideoPlayerView] onDisappear for \(url.lastPathComponent) - cleaning up player")
      // 移除时间观察器
      if let token = timeObserverToken, let observedPlayer {
        observedPlayer.removeTimeObserver(token)
        timeObserverToken = nil
      }
      observedPlayer = nil
      // 取消防抖任务
      segmentUpdateTask?.cancel()
      segmentUpdateTask = nil
      if RuntimeEnvironment.isRunningTests {
        return
      }
      viewModel.cleanup()
      playback.cancelWaveformLoad()
    }
    .background(
      // Use a hidden view to establish subscription regardless of opacity
      Color.clear.onAppear {
        // Subscribe to playback commands
        Task {
          for await command in playback.commandSubject.values {
            guard let player = viewModel.player else { continue }

            await MainActor.run {
              switch command {
              case .seek(let time):
                let cmTime = CMTime(seconds: time, preferredTimescale: 600)
                player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)

              case .play:
                player.play()

              case .pause:
                player.pause()

              case .seekAndPlay(let time):
                let cmTime = CMTime(seconds: time, preferredTimescale: 600)
                player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                  if finished {
                    player.play()
                  }
                }
              }
            }
          }
        }
      }
    )
    .onChange(of: segmentsHash) { _, _ in
      // 防抖优化：延迟更新segments，避免转录过程中频繁刷新
      segmentUpdateTask?.cancel()
      segmentUpdateTask = Task { @MainActor in
        // 等待500ms后再更新，如果这期间有新的更新会取消此任务
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard !Task.isCancelled else { return }

        let currentSegments = effectiveSegments
        viewModel.updateSegments(currentSegments)
        updateASS(force: false)
        loadASSTrack()
        // Update compressed timeline state when segments change
        playback._updateCompressedTimeline(filterSilentSegments)
        if let selection = selectedWaveformSegmentID {
          let stillExists = currentSegments.contains { SegmentIdentifier(segment: $0) == selection }
          if !stillExists {
            selectedWaveformSegmentID = nil
          }
        }
      }
    }
    .onChange(of: effectsHash) { _, _ in
      updateASS(force: false)
    }
    .onChange(of: translationsHash) { _, _ in
      updateASS(force: false)
    }
    .onChange(of: translationPlacement) { _, _ in
      updateASS(force: true)
    }
    .onChange(of: styleSignature) { _, _ in
      updateASS(force: true)
    }
    .onChange(of: filterSilentSegments) { _, newValue in
      viewModel.setCompressSilence(newValue, segments: effectiveSegments)
      updateASS(force: true)
      // Update compressed timeline state when filter changes
      playback._updateCompressedTimeline(newValue)
      triggerWaveformLoadIfNeeded(width: lastWaveformWidth, force: true)
    }
    .onChange(of: activeURL) { oldVal, newVal in
      selectedWaveformSegmentID = nil
      guard let player = viewModel.player else { return }
      if newVal == url {
        if playback.isPlaying {
          player.play()
        } else {
          player.pause()
          playback._updatePlaying(false)
        }
        triggerWaveformLoadIfNeeded(width: lastWaveformWidth, force: true)
      } else if oldVal == url {
        player.pause()
        playback._updatePlaying(false)
      }
    }
    .onChange(of: ass) { _, _ in
      loadASSTrack()
    }
  }

  @ViewBuilder
  private func subtitlesOverlay(player: AVPlayer, canvasSize: CGSize) -> some View {
    if subtitlePreviewMode == .nativeTextOverlay {
      nativeTextOverlay(canvasSize: canvasSize)
    } else {
      // Do NOT use .attach(player:) here. That modifier applies .fixedSize() internally,
      // which prevents the outer .frame() from propagating to the NSView bounds.
      // When the container grows, AssSubtitlesView.layout() would never be called with
      // the new size, so subtitles would stay at their original scale.
      // Instead, drive time offsets manually via a Timer and let SwiftUI's .frame()
      // directly control the NSView bounds so layout() rescales correctly.
      AssSubtitles(renderer: assRenderer)
        .onImageChanged { _, _, image, dialogues in
          if let image {
            print("🎬 [ASS] Frame rendered: rect=\(image.imageRect) dialogues=\(dialogues)")
          }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .onReceive(
          Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
        ) { _ in
          assRenderer.setTimeOffset(player.currentTime().seconds)
        }
        .onReceive(
          player.publisher(for: \.currentItem, options: [.new])
        ) { item in
          if item == nil { assRenderer.freeTrack() }
        }
        .allowsHitTesting(false)
    }
  }

  @ViewBuilder
  private func nativeTextOverlay(canvasSize: CGSize) -> some View {
    let snapshot = AudioSubtitlePreviewResolver.snapshot(
      segments: effectiveSegments,
      placement: translationPlacement,
      filterSilentSegments: filterSilentSegments,
      time: displayedTime
    )
    let logicalCanvas = activeLayout.canvasSize
    let scaleFactor =
      logicalCanvas.width > 0 && canvasSize.width > 0
      ? canvasSize.width / logicalCanvas.width
      : 1
    let styleSet = styleConfiguration[detectedOrientation]

    ZStack(alignment: .bottom) {
      if let snapshot {
        VStack(spacing: max(4, 10 * scaleFactor)) {
          if snapshot.placement == .above, let translation = snapshot.translationText {
            subtitleTextLine(
              translation,
              style: styleSet.translation,
              scaleFactor: scaleFactor
            )
          }

          subtitleTextLine(
            snapshot.primaryText,
            style: styleSet.primary,
            scaleFactor: scaleFactor
          )

          if snapshot.placement == .below, let translation = snapshot.translationText {
            subtitleTextLine(
              translation,
              style: styleSet.translation,
              scaleFactor: scaleFactor
            )
          }
        }
        .padding(.horizontal, max(24, canvasSize.width * 0.08))
        .padding(.bottom, max(24, canvasSize.height * 0.06))
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .bottom)
      }
    }
    .frame(width: canvasSize.width, height: canvasSize.height)
    .allowsHitTesting(false)
  }

  private func subtitleTextLine(
    _ text: String,
    style: SubtitleStyle,
    scaleFactor: CGFloat
  ) -> some View {
    let fontSize = max(14.0, style.fontSize * Double(scaleFactor))
    let horizontalPadding = max(8.0, 16.0 * Double(scaleFactor))
    let verticalPadding = max(4.0, 8.0 * Double(scaleFactor))
    let outlineRadius = max(1.0, style.outlineWidth * Double(scaleFactor))
    let shadowRadius = max(1.0, style.shadowRadius * Double(scaleFactor))
    let shadowYOffset = max(1.0, style.shadowRadius * Double(scaleFactor) * 0.5)
    let fillColor = style.fillColor.swiftUIColor
    let backgroundColor = style.backColor.swiftUIColor.opacity(style.backColor.alpha)
    let outlineColor = style.outlineColor.swiftUIColor.opacity(max(style.outlineColor.alpha, 0.9))
    let shadowColor = style.shadowColor.swiftUIColor.opacity(style.shadowColor.alpha)

    return Text(text)
      .font(.custom(style.fontName, size: fontSize))
      .fontWeight(style.bold ? .bold : .regular)
      .foregroundStyle(fillColor)
      .multilineTextAlignment(.center)
      .lineLimit(3)
      .padding(.horizontal, horizontalPadding)
      .padding(.vertical, verticalPadding)
      .background(backgroundColor)
      .shadow(color: outlineColor, radius: outlineRadius, x: 0, y: 0)
      .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowYOffset)
  }

  private func updateASS(force: Bool, overrideSegments: [Segment]? = nil) {
    Task { @MainActor in
      let segsToUse = overrideSegments ?? effectiveSegments
      let needsStop = url.startAccessingSecurityScopedResource()
      defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
      let asset = AVURLAsset(url: url)
      let targetOrientation: SubtitleOrientation
      if let track = try? await asset.loadTracks(withMediaType: .video).first,
        let naturalSize = try? await track.load(.naturalSize)
      {
        let preferredTransform = (try? await track.load(.preferredTransform)) ?? .identity
        let displaySize = Self.displaySize(for: naturalSize, transform: preferredTransform)
        presentationSize = displaySize
        videoState.presentationSize = displaySize
        let actualOrientation = Self.orientation(for: displaySize)
        detectedOrientation = actualOrientation
        targetOrientation = detectedOrientation
        let layout = VideoOrientationLayout.layout(
          for: displaySize, targetOrientation: targetOrientation)
        layoutResult = layout
        subtitlePreviewMode = SubtitlePreviewMode.resolve(hasVideoTrack: true)
        print("🎬 [ASS] updateASS: force=\(force) segments=\(segsToUse.count) orientation=\(targetOrientation) displaySize=\(displaySize)")
      } else {
        presentationSize = nil
        videoState.presentationSize = nil
        layoutResult = nil
        targetOrientation = detectedOrientation
        subtitlePreviewMode = SubtitlePreviewMode.resolve(hasVideoTrack: false)
        print("🎬 [ASS] updateASS: audio-only mode for \(url.lastPathComponent) orientation=\(targetOrientation)")
      }

      let generated = ASSGenerator.makeASS(
        segments: segsToUse,
        orientation: targetOrientation,
        filterSilentSegments: filterSilentSegments,
        effects: effects,
        translationPlacement: translationPlacement,
        styleConfiguration: styleConfiguration
      )
      print("🎬 [ASS] updateASS: generatedLength=\(generated.count) changed=\(generated != ass)")
      if force || generated != ass {
        ass = generated
      }
      if force {
        loadASSTrack()
      }
    }
  }

  private func loadASSTrack() {
    Task { @MainActor in
      let dialogueCount = ass.components(separatedBy: "\n").filter { $0.hasPrefix("Dialogue:") }.count
      let firstDialogue = ass.components(separatedBy: "\n").first { $0.hasPrefix("Dialogue:") } ?? "(none)"
      print("🎬 [ASS] loadASSTrack: length=\(ass.count) dialogues=\(dialogueCount) first=\(firstDialogue)")
      // Write ASS to temp file for inspection
      let tmpPath = NSTemporaryDirectory() + "debug_subtitle.ass"
      try? ass.write(toFile: tmpPath, atomically: true, encoding: .utf8)
      print("🎬 [ASS] Written to: \(tmpPath)")
      assRenderer.loadTrack(content: ass)
      // Ensure a frame is rendered immediately after track loading.
      // loadTrack only loads the track into memory but doesn't render;
      // reloadFrame queues a render on the same serial work queue,
      // guaranteeing it runs after the track is fully loaded.
      assRenderer.reloadFrame()
    }
  }

  private var controlsStack: some View {
    VStack(spacing: 12) {
      GeometryReader { proxy in
        WaveformView(
          snapshot: playback.waveformSnapshot,
          state: playback.waveformState,
          duration: waveformDuration,
          progress: waveformProgress,
          accentColor: .accentColor,
          backgroundColor: AppSurface.inputBackground,
          mixToMono: true,
          segments: effectiveSegments,
          filterSilentSegments: filterSilentSegments,
          onScrubBegin: { beginScrubbing() },
          onScrubUpdate: { time in updateScrubbedTime(time) },
          onScrubCommit: { time in commitScrub(to: time) },
          verticalGain: 1.6,
          dynamicRangeExponent: 0.72,
          silenceFloor: 0.02,
          selectedSegmentID: selectedWaveformSegmentID,
          onSegmentSelectionChange: { newSelection in
            selectedWaveformSegmentID = newSelection
          }
        )
        .frame(height: proxy.size.height)
        .onAppear { triggerWaveformLoadIfNeeded(width: proxy.size.width, force: true) }
        .onChange(of: proxy.size.width) { _, newWidth in
          triggerWaveformLoadIfNeeded(width: newWidth)
        }
      }
      .frame(height: 96)

      Button(action: handleWaveformSegmentDeletion) {
        EmptyView()
      }
      .keyboardShortcut(.delete, modifiers: [])
      .disabled(selectedWaveformSegmentID == nil || onSegmentDelete == nil)
      .frame(width: 0, height: 0)
      .opacity(0)

      playbackControls
    }
  }

  private var playbackControls: some View {
    let hasDuration = playback.duration.isFinite && playback.duration > 0
    return EditorPlaybackControls(
      isPlaying: playback.isPlaying && !isScrubbing,
      hasDuration: hasDuration,
      currentTimeLabel: formatTime(displayedTime),
      durationLabel: hasDuration ? formatTime(playback.duration) : "--:--",
      range: sliderRange,
      time: Binding(
        get: { scrubbedTime ?? playback.currentTime },
        set: { updateScrubbedTime($0) }
      ),
      onTogglePlayback: togglePlayback,
      onSeekBackward: { seek(by: -5) },
      onSeekForward: { seek(by: 5) },
      onScrubbingChange: handleScrubbingChange
    )
  }

  private func handleScrubbingChange(_ editing: Bool) {
    if editing {
      beginScrubbing()
    } else {
      commitScrub(to: scrubbedTime ?? playback.currentTime)
    }
  }

  private func togglePlayback() {
    if isScrubbing {
      let target = scrubbedTime ?? playback.currentTime
      commitScrub(to: target)
      return
    }
    if playback.isPlaying {
      playback.pause()
    } else {
      playback.play()
    }
  }

  private func seek(by delta: TimeInterval) {
    let range = sliderRange
    let newTime = min(max(displayedTime + delta, range.lowerBound), range.upperBound)
    scrubbedTime = nil
    if playback.isPlaying {
      playback.seekAndPlay(to: newTime)
    } else {
      playback.seek(to: newTime)
    }
  }

  private func formatTime(_ time: TimeInterval) -> String {
    guard time.isFinite else { return "--:--" }
    let totalSeconds = max(0, Int(time.rounded()))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%02d:%02d", minutes, seconds)
    }
  }

  private func beginScrubbing() {
    if isScrubbing { return }
    wasPlayingBeforeScrub = playback.isPlaying
    if wasPlayingBeforeScrub {
      playback.pause()
    }
    isScrubbing = true
  }

  private func updateScrubbedTime(_ time: TimeInterval) {
    scrubbedTime = max(0, min(waveformDuration, time))
  }

  private func commitScrub(to target: TimeInterval) {
    let clamped = max(0, min(waveformDuration, target))
    scrubbedTime = nil
    isScrubbing = false
    if wasPlayingBeforeScrub {
      playback.seekAndPlay(to: clamped)
    } else {
      playback.seek(to: clamped)
    }
  }

  private func handleWaveformSegmentDeletion() {
    guard
      let selection = selectedWaveformSegmentID,
      let onSegmentDelete,
      let segmentToDelete = effectiveSegments.first(where: {
        SegmentIdentifier(segment: $0) == selection
      })
    else { return }

    onSegmentDelete(segmentToDelete)
    selectedWaveformSegmentID = nil
  }

  private func triggerWaveformLoadIfNeeded(width: CGFloat, force: Bool = false) {
    guard width.isFinite, width > 0 else { return }
    let effectiveWidth = max(width, 320)
    if force || playback.waveformSnapshot == nil || abs(effectiveWidth - lastWaveformWidth) > 32 {
      lastWaveformWidth = effectiveWidth
      let targetPoints = max(800, Int(effectiveWidth * 6))
      playback.requestWaveform(
        for: url,
        targetPointCount: targetPoints,
        mixToMono: true,
        force: force
      )
    }
  }

  private func setupPlaybackSync(with player: AVPlayer) {
    if observedPlayer === player, timeObserverToken != nil {
      return
    }

    if let token = timeObserverToken, let observedPlayer {
      observedPlayer.removeTimeObserver(token)
      timeObserverToken = nil
    }

    // 使用 CADisplayLink / Timer 方式，这里用 SwiftUI Timer publisher 简化
    let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
    timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
      t in
      let durationSeconds = player.currentItem?.duration.seconds
      let isPlaying = player.rate > 0.01

      Task { @MainActor in
        guard activeURL == url else { return }

        playback._updateTime(t.seconds)
        if let durationSeconds, durationSeconds.isFinite {
          playback._updateDuration(durationSeconds)
        }
        playback._updatePlaying(isPlaying)
      }
    }
    observedPlayer = player
  }
}
