import CliptateCore
import AppKit
import SwiftUI

struct WaveformView: View {
  let snapshot: WaveformSnapshot?
  let state: WaveformLoadingState
  let duration: TimeInterval
  let progress: Double
  var accentColor: Color = .accentColor
  var backgroundColor: Color = Color(nsColor: .textBackgroundColor).opacity(0.72)
  var mixToMono: Bool = true
  var segments: [Segment] = []
  var filterSilentSegments: Bool = false
  var onScrubBegin: (() -> Void)? = nil
  var onScrubUpdate: ((TimeInterval) -> Void)? = nil
  var onScrubCommit: ((TimeInterval) -> Void)? = nil
  var verticalGain: CGFloat = 1.85
  var dynamicRangeExponent: CGFloat = 0.72
  /// Amplitude values below this threshold are treated as silence and rendered with zero height.
  var silenceFloor: CGFloat = 0.02
  var selectedSegmentID: SegmentIdentifier?
  var onSegmentSelectionChange: (SegmentIdentifier?) -> Void = { _ in }

  private struct DisplaySegment: Identifiable {
    let id: String
    let segment: Segment
    let displayStart: TimeInterval
    let displayEnd: TimeInterval
    let identifier: SegmentIdentifier
  }

  @Environment(\.displayScale) private var displayScale
  @GestureState private var scrubbingProgress: Double?
  @State private var zoomScale: CGFloat = 2.0
  @State private var lastTapOnSegment: Bool = false

  private let minZoomScale: CGFloat = 1.0
  private let maxZoomScale: CGFloat = 8.0
  private let preciseScrollMultiplier: CGFloat = 0.04
  private let coarseScrollMultiplier: CGFloat = 0.15
  private let waveformBaseColor = Color(red: 0.16, green: 0.58, blue: 0.98)
  private let smoothingWindow: Int = 5

  var body: some View {
    let timeline = SegmentTimeline.prepare(
      segments: segments,
      filterSilentSegments: filterSilentSegments
    )
    let displaySegments = Self.makeDisplaySegments(segments: segments, timeline: timeline)
    let overlayDuration = displaySegments.last?.displayEnd ?? duration
    let effectiveSnapshot = makeDisplaySnapshot(source: snapshot, timeline: timeline)
    return GeometryReader { proxy in
      let width = max(proxy.size.width, 1)
      let height = max(proxy.size.height, 1)
      let effectiveZoom = clampZoom(zoomScale)
      let contentWidth = max(width * effectiveZoom, width)
      let focusProgress = scrubbingProgress ?? progress
      let pointerContentX = xPositionInContent(for: focusProgress, contentWidth: contentWidth)
      let maxOffset = max(contentWidth - width, 0)
      let desiredOffset = pointerContentX - width / 2
      let viewportOffset = min(max(desiredOffset, 0), maxOffset)
      let pointerX = xPositionInView(
        for: focusProgress,
        contentWidth: contentWidth,
        viewportOffset: viewportOffset,
        viewWidth: width
      )
      let timelineDuration = max(overlayDuration, 0)
      let activeTime =
        timelineDuration > 0
        ? timelineDuration * clamp(focusProgress)
        : 0

      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(backgroundColor)
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)

        Group {
          if let effectiveSnapshot, effectiveSnapshot.pointCount > 0 {
            Canvas(rendersAsynchronously: true) { context, size in
              context.translateBy(x: -viewportOffset, y: 0)
              let drawingSize = CGSize(width: contentWidth, height: size.height)
              renderWaveform(
                snapshot: effectiveSnapshot,
                into: &context,
                canvasSize: drawingSize,
                verticalGain: verticalGain,
                dynamicRangeExponent: dynamicRangeExponent
              )
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
          } else {
            placeholder
              .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
          }
        }

        if state == .loading && snapshot == nil {
          loadingOverlay
        } else if case .failed(let message) = state, snapshot == nil {
          errorOverlay(message: message)
        }

        if let pointerX, timelineDuration > 0 {
          playheadLine(at: pointerX, height: height)
        }
      }
      .contentShape(Rectangle())
      .overlay(
        segmentOverlay(
          segments: displaySegments,
          duration: timelineDuration,
          contentWidth: contentWidth,
          viewportOffset: viewportOffset,
          activeTime: activeTime
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
      )
      .overlay(
        segmentHitTargets(
          segments: displaySegments,
          duration: timelineDuration,
          contentWidth: contentWidth,
          viewportOffset: viewportOffset
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
      )
      .overlay(alignment: .topTrailing) {
        zoomBadge
          .padding(8)
      }
      #if os(macOS)
        .overlay {
          ScrollWheelCaptureView { event in
            handleScroll(event: event)
          }
        }
      #endif
      .gesture(
        scrubGesture(
          width: width,
          contentWidth: contentWidth,
          viewportOffset: viewportOffset,
          duration: timelineDuration
        )
      )
      .animation(.easeInOut(duration: 0.2), value: effectiveSnapshot?.pointCount ?? 0)
      .animation(.easeInOut(duration: 0.2), value: state)
      .onTapGesture {
        if lastTapOnSegment {
          lastTapOnSegment = false
        } else {
          onSegmentSelectionChange(nil)
        }
      }
    }
  }

  private func scrubGesture(
    width: CGFloat,
    contentWidth: CGFloat,
    viewportOffset: CGFloat,
    duration timelineDuration: TimeInterval
  ) -> some Gesture {
    let resolvedDuration = timelineDuration > 0 ? timelineDuration : duration
    return DragGesture(minimumDistance: 0)
      .updating($scrubbingProgress) { value, state, _ in
        let clamped = min(max(0, value.location.x), width)
        let position = viewportOffset + clamped
        let progress = clamp(Double(position / max(contentWidth, 1)))
        if state == nil {
          onScrubBegin?()
        }
        state = progress
        let time = max(0, min(resolvedDuration, progress * resolvedDuration))
        onScrubUpdate?(time)
      }
      .onEnded { value in
        let clamped = min(max(0, value.location.x), width)
        let position = viewportOffset + clamped
        let progress = clamp(Double(position / max(contentWidth, 1)))
        let time = max(0, min(resolvedDuration, progress * resolvedDuration))
        onScrubCommit?(time)
      }
  }

  private func xPositionInContent(for progress: Double, contentWidth: CGFloat) -> CGFloat {
    guard contentWidth.isFinite else { return 0 }
    return CGFloat(clamp(progress)) * contentWidth
  }

  private func xPositionInView(
    for progress: Double,
    contentWidth: CGFloat,
    viewportOffset: CGFloat,
    viewWidth: CGFloat
  ) -> CGFloat? {
    let x = xPositionInContent(for: progress, contentWidth: contentWidth) - viewportOffset
    guard x.isFinite else { return nil }
    if x < -12 || x > viewWidth + 12 { return nil }
    return x
  }

  private func playheadLine(at x: CGFloat, height: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: 1)
      .fill(Color.white.opacity(0.85))
      .frame(width: 2, height: height)
      .shadow(color: .black.opacity(0.2), radius: 2)
      .offset(x: x - 1)
  }

  private func renderWaveform(
    snapshot: WaveformSnapshot,
    into context: inout GraphicsContext,
    canvasSize: CGSize,
    verticalGain: CGFloat,
    dynamicRangeExponent: CGFloat
  ) {
    let channelCount = snapshot.channelCount
    guard channelCount > 0 else { return }

    let pointCount = snapshot.pointCount
    guard pointCount > 0 else { return }

    let step = max(canvasSize.width / CGFloat(max(pointCount - 1, 1)), 1 / displayScale)
    let centerY = canvasSize.height / 2

    let amplitudes = snapshot.channels.first ?? []
    let floor = Float(silenceFloor)
    let gated = amplitudes.map { $0 < floor ? Float(0) : $0 }
    let smoothed = smooth(gated, window: smoothingWindow)
    drawArea(
      amplitudes: smoothed,
      centerY: centerY,
      height: canvasSize.height,
      step: step,
      verticalGain: verticalGain,
      dynamicRangeExponent: dynamicRangeExponent,
      into: &context
    )
  }

  private func smooth(_ values: [Float], window: Int) -> [Float] {
    guard window > 1, values.count > 2 else { return values }
    let windowSize = min(window, values.count)
    var output = Array(repeating: Float(0), count: values.count)
    var sum: Float = 0
    var start = 0
    for index in 0..<values.count {
      sum += values[index]
      if index - start + 1 > windowSize {
        sum -= values[start]
        start += 1
      }
      let count = Float(index - start + 1)
      output[index] = sum / max(count, 1)
    }
    return output
  }

  private func drawArea(
    amplitudes: [Float],
    centerY: CGFloat,
    height: CGFloat,
    step: CGFloat,
    verticalGain: CGFloat,
    dynamicRangeExponent: CGFloat,
    into context: inout GraphicsContext
  ) {
    guard !amplitudes.isEmpty else { return }
    let maxHalfHeight = max(height / 2 - 1, 1)
    let minBarHeight = max(1.5 / displayScale, 1)
    // Bar width leaves a 1-pixel gap between bars for FCP-style spacing
    let barWidth = max(step * 0.7, 1 / displayScale)
    let cornerRadius = min(barWidth * 0.3, 1.5)

    // Top half: brighter; bottom half: more transparent
    let topGradient = Gradient(colors: [
      waveformBaseColor.opacity(0.9),
      waveformBaseColor.opacity(0.5),
    ])
    let bottomGradient = Gradient(colors: [
      waveformBaseColor.opacity(0.5),
      waveformBaseColor.opacity(0.25),
    ])

    var topBars = Path()
    var bottomBars = Path()

    for (index, value) in amplitudes.enumerated() {
      let clamped = CGFloat(min(1, max(0, value)))
      let shaped = pow(clamped, dynamicRangeExponent)
      let boosted = min(1, shaped * verticalGain)
      let halfH = max(boosted * maxHalfHeight, minBarHeight)
      let x = CGFloat(index) * step

      let topRect = CGRect(x: x, y: centerY - halfH, width: barWidth, height: halfH)
      let bottomRect = CGRect(x: x, y: centerY, width: barWidth, height: halfH)

      topBars.addRoundedRect(in: topRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
      bottomBars.addRoundedRect(in: bottomRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
    }

    let totalWidth = CGFloat(amplitudes.count) * step
    context.fill(
      topBars,
      with: .linearGradient(
        topGradient,
        startPoint: CGPoint(x: 0, y: 0),
        endPoint: CGPoint(x: 0, y: centerY)
      )
    )
    context.fill(
      bottomBars,
      with: .linearGradient(
        bottomGradient,
        startPoint: CGPoint(x: 0, y: centerY),
        endPoint: CGPoint(x: 0, y: height)
      )
    )

    // Subtle center line
    let midline = Path(CGRect(x: 0, y: centerY - 0.25, width: totalWidth, height: 0.5))
    context.stroke(
      midline,
      with: .color(Color.white.opacity(0.2)),
      lineWidth: max(0.5, 1 / displayScale)
    )
  }

  @ViewBuilder
  private var placeholder: some View {
    LinearGradient(
      colors: [accentColor.opacity(0.12), accentColor.opacity(0.04)],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }

  private var loadingOverlay: some View {
    ProgressView()
      .progressViewStyle(.circular)
      .scaleEffect(0.8)
      .tint(accentColor)
  }

  private func errorOverlay(message: String) -> some View {
    VStack(spacing: 4) {
      Image(systemName: "waveform.path.ecg")
        .font(.system(size: 18, weight: .medium))
        .foregroundColor(.orange)
      Text("Waveform unavailable")
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(message)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .multilineTextAlignment(.center)
    }
    .padding(8)
  }

  private func segmentOverlay(
    segments: [DisplaySegment],
    duration: TimeInterval,
    contentWidth: CGFloat,
    viewportOffset: CGFloat,
    activeTime: TimeInterval
  ) -> some View {
    Canvas { context, size in
      guard duration > 0, !segments.isEmpty else { return }
      context.translateBy(x: -viewportOffset, y: 0)
      let height = size.height
      let inset: CGFloat = 6

      for displaySegment in segments {
        let startRatio = clamp(displaySegment.displayStart / duration)
        let endRatio = clamp(displaySegment.displayEnd / duration)
        guard endRatio > startRatio else { continue }

        let startX = CGFloat(startRatio) * contentWidth
        let endX = CGFloat(endRatio) * contentWidth
        let segmentWidth = endX - startX
        guard segmentWidth > 2 else { continue }

        let isActive =
          activeTime >= displaySegment.displayStart && activeTime <= displaySegment.displayEnd
        let isSelected = selectedSegmentID == displaySegment.identifier
        let boxHeight = min(64, height - inset * 2)
        let rect = CGRect(
          x: startX + 1,
          y: max((height - boxHeight) / 2, inset),
          width: segmentWidth - 2,
          height: min(boxHeight, height - inset)
        )

        let rounded = Path(roundedRect: rect, cornerRadius: 8)
        let fillOpacity: Double
        let strokeOpacity: Double
        let strokeWidth: CGFloat

        if isSelected {
          fillOpacity = 0.32
          strokeOpacity = 1.0
          strokeWidth = 2.2
        } else if isActive {
          fillOpacity = 0.24
          strokeOpacity = 0.9
          strokeWidth = 1.8
        } else {
          fillOpacity = 0.12
          strokeOpacity = 0.45
          strokeWidth = 1.0
        }

        context.fill(rounded, with: .color(accentColor.opacity(fillOpacity)))
        context.stroke(
          rounded, with: .color(accentColor.opacity(strokeOpacity)), lineWidth: strokeWidth)

        if segmentWidth > 70 {
          var startAttr = AttributedString(formatTime(displaySegment.displayStart))
          startAttr.font = .system(size: 10, weight: .medium, design: .monospaced)
          startAttr.foregroundColor = .secondary
          context.draw(
            Text(startAttr), at: CGPoint(x: startX + 6, y: rect.minY - 6), anchor: .leading)

          var endAttr = AttributedString(formatTime(displaySegment.displayEnd))
          endAttr.font = .system(size: 10, weight: .medium, design: .monospaced)
          endAttr.foregroundColor = .secondary
          context.draw(Text(endAttr), at: CGPoint(x: endX - 6, y: rect.minY - 6), anchor: .trailing)
        }

        let snippet = displaySegment.segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !snippet.isEmpty && segmentWidth > 36 {
          let limited = snippet.count > 120 ? String(snippet.prefix(117)) + "…" : snippet
          var attributedSnippet = AttributedString(limited)
          attributedSnippet.font = .system(size: 12, weight: .medium)
          attributedSnippet.foregroundColor = Color.primary.opacity(0.92)
          context.draw(Text(attributedSnippet), in: rect.insetBy(dx: 8, dy: 6))
        }
      }
    }
  }

  private func segmentHitTargets(
    segments: [DisplaySegment],
    duration: TimeInterval,
    contentWidth: CGFloat,
    viewportOffset: CGFloat
  ) -> some View {
    GeometryReader { proxy in
      let viewSize = proxy.size
      let width = viewSize.width
      let height = viewSize.height
      let inset: CGFloat = 6
      let safeDuration = max(duration, .ulpOfOne)

      let filteredSegments = segments.filter { displaySegment in
        let startRatio = clamp(displaySegment.displayStart / safeDuration)
        let endRatio = clamp(displaySegment.displayEnd / safeDuration)
        guard endRatio > startRatio else { return false }

        let startX = CGFloat(startRatio) * contentWidth - viewportOffset
        let endX = CGFloat(endRatio) * contentWidth - viewportOffset
        let segmentWidth = endX - startX
        guard segmentWidth > 2 else { return false }
        if endX < 0 || startX > width { return false }
        return true
      }

      ForEach(filteredSegments) { displaySegment in
        let startRatio = clamp(displaySegment.displayStart / safeDuration)
        let endRatio = clamp(displaySegment.displayEnd / safeDuration)

        let startX = CGFloat(startRatio) * contentWidth - viewportOffset
        let endX = CGFloat(endRatio) * contentWidth - viewportOffset
        let segmentWidth = endX - startX

        let boxHeight = min(64, height - inset * 2)
        let rect = CGRect(
          x: startX + 1,
          y: max((height - boxHeight) / 2, inset),
          width: segmentWidth - 2,
          height: min(boxHeight, height - inset)
        )

        Color.clear
          .contentShape(Rectangle())
          .frame(width: rect.width, height: rect.height)
          .position(x: rect.midX, y: rect.midY)
          .highPriorityGesture(
            TapGesture()
              .onEnded {
                lastTapOnSegment = true
                onSegmentSelectionChange(displaySegment.identifier)
              }
          )
      }
    }
  }

  private static func makeDisplaySegments(
    segments: [Segment],
    timeline: SegmentTimeline
  ) -> [DisplaySegment] {
    if let compression = timeline.compression {
      var mappingIndex: [String: SegmentCompression.Mapping] = [:]
      for mapping in compression.mappings {
        mappingIndex[mappingKey(start: mapping.originalStart, end: mapping.originalEnd)] = mapping
      }
      return segments.map { segment in
        let key = mappingKey(start: segment.startTime, end: segment.endTime)
        if let mapping = mappingIndex[key] {
          return DisplaySegment(
            id: segment.id,
            segment: segment,
            displayStart: mapping.compressedStart,
            displayEnd: mapping.compressedEnd,
            identifier: SegmentIdentifier(segment: segment)
          )
        } else {
          return DisplaySegment(
            id: segment.id,
            segment: segment,
            displayStart: segment.startTime,
            displayEnd: segment.endTime,
            identifier: SegmentIdentifier(segment: segment)
          )
        }
      }
    } else {
      return segments.map { segment in
        DisplaySegment(
          id: segment.id,
          segment: segment,
          displayStart: segment.startTime,
          displayEnd: segment.endTime,
          identifier: SegmentIdentifier(segment: segment)
        )
      }
    }
  }

  private static func mappingKey(start: TimeInterval, end: TimeInterval) -> String {
    let startMillis = Int((start * 1000).rounded())
    let endMillis = Int((end * 1000).rounded())
    return "\(startMillis)-\(endMillis)"
  }

  private func makeDisplaySnapshot(
    source: WaveformSnapshot?,
    timeline: SegmentTimeline
  ) -> WaveformSnapshot? {
    guard filterSilentSegments, let source, let compression = timeline.compression else {
      return source
    }
    guard source.duration > 0, source.pointCount > 0 else { return source }

    let compressedChannels = makeCompressedChannels(from: source, using: compression)
    guard let firstChannel = compressedChannels.first, !firstChannel.isEmpty else {
      return source
    }

    let compressedDuration = timeline.segments.last?.endTime ?? source.duration
    let durationRatio = source.duration > 0 ? compressedDuration / source.duration : 1
    let estimatedFrames = max(1, Int(Double(source.totalFrames) * durationRatio))
    let samplesPerPixel = max(1, estimatedFrames / max(firstChannel.count, 1))

    return WaveformSnapshot(
      channels: compressedChannels,
      samplesPerPixel: samplesPerPixel,
      totalFrames: estimatedFrames,
      duration: max(compressedDuration, 0)
    )
  }

  private func makeCompressedChannels(
    from snapshot: WaveformSnapshot,
    using compression: SegmentCompression
  ) -> [[Float]] {
    let totalDuration = max(snapshot.duration, .ulpOfOne)
    let pointCount = max(snapshot.pointCount, 1)

    return snapshot.channels.map { channel in
      var compressed: [Float] = []
      compressed.reserveCapacity(pointCount)
      for mapping in compression.mappings {
        let (startIndex, endIndex) = sliceIndices(
          for: mapping,
          totalDuration: totalDuration,
          pointCount: pointCount
        )
        guard endIndex > startIndex else { continue }
        let boundedEnd = min(endIndex, channel.count)
        guard boundedEnd > startIndex else { continue }
        compressed.append(contentsOf: channel[startIndex..<boundedEnd])
      }
      if compressed.isEmpty {
        return channel
      }
      return compressed
    }
  }

  private func sliceIndices(
    for mapping: SegmentCompression.Mapping,
    totalDuration: TimeInterval,
    pointCount: Int
  ) -> (Int, Int) {
    guard totalDuration > 0, pointCount > 0 else { return (0, 0) }
    let startRatio = clamp(mapping.originalStart / totalDuration)
    let endRatio = clamp(mapping.originalEnd / totalDuration)
    var startIndex = Int((Double(pointCount) * startRatio).rounded(.down))
    var endIndex = Int((Double(pointCount) * endRatio).rounded(.up))
    if endIndex <= startIndex {
      endIndex = min(pointCount, startIndex + 1)
    }
    startIndex = min(max(startIndex, 0), max(pointCount - 1, 0))
    endIndex = min(max(endIndex, startIndex + 1), pointCount)
    return (startIndex, endIndex)
  }

  private func formatTime(_ value: TimeInterval) -> String {
    guard value.isFinite else { return "--:--" }
    let totalSeconds = max(0, Int(value.rounded()))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%02d:%02d", minutes, seconds)
    }
  }

  private func clamp(_ value: Double) -> Double {
    max(0, min(1, value))
  }

  private var zoomBadge: some View {
    Text(String(format: "%.1fx", zoomScale))
      .font(.system(size: 11, weight: .semibold, design: .rounded))
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(.thinMaterial, in: Capsule())
      .overlay(
        Capsule()
          .stroke(Color.primary.opacity(0.08), lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
  }

  private func clampZoom(_ value: CGFloat) -> CGFloat {
    min(max(value, minZoomScale), maxZoomScale)
  }

  #if os(macOS)
    private func handleScroll(event: ScrollWheelEventInformation) {
      guard event.deltaY != 0 else { return }
      let multiplier = event.isPrecise ? preciseScrollMultiplier : coarseScrollMultiplier
      let adjustment = -event.deltaY * multiplier
      let newZoom = clampZoom(zoomScale + adjustment)
      if abs(newZoom - zoomScale) < 0.0001 { return }
      withAnimation(.easeInOut(duration: 0.12)) {
        zoomScale = newZoom
      }
    }
  #endif
}

#if os(macOS)
  private struct ScrollWheelEventInformation {
    let deltaX: CGFloat
    let deltaY: CGFloat
    let location: CGPoint
    let isPrecise: Bool
  }

  private struct ScrollWheelCaptureView: NSViewRepresentable {
    var handler: (ScrollWheelEventInformation) -> Void

    func makeNSView(context: Context) -> ScrollWheelCaptureNSView {
      let view = ScrollWheelCaptureNSView()
      view.handler = handler
      return view
    }

    func updateNSView(_ nsView: ScrollWheelCaptureNSView, context: Context) {
      nsView.handler = handler
    }
  }

  private final class ScrollWheelCaptureNSView: NSView {
    var handler: ((ScrollWheelEventInformation) -> Void)?

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { self }
    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
      if let handler {
        let localPoint = convert(event.locationInWindow, from: nil)
        handler(
          ScrollWheelEventInformation(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            location: localPoint,
            isPrecise: event.hasPreciseScrollingDeltas
          )
        )
      }
      nextResponder?.scrollWheel(with: event)
    }

    override func mouseDown(with event: NSEvent) {
      nextResponder?.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
      nextResponder?.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
      nextResponder?.mouseUp(with: event)
    }
  }
#endif
