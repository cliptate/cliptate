import CliptateCore
import SwiftUI

struct SegmentRowView: View {
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
    let zoomScale = Self.deriveZoomScale(from: effect?.appliedZoom)
    let baseBackground =
      active
      ? AppSurface.selectedFill
      : (isHovered ? AppSurface.hoverFill : Color.clear)
    let resolvedTranslation = normalizedTranslation

    return panelBody(
      highlightCoverage: highlightCoverage,
      zoomScale: zoomScale,
      baseBackground: baseBackground,
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
    resolvedTranslation: SegmentTranslation?
  ) -> some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 6) {
        if let resolvedTranslation, config.translationPlacement == .above {
          SegmentTranslationEditor(
            translation: resolvedTranslation,
            text: $editedTranslation,
            onCommit: commitTranslationIfNeeded
          )
        }

        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text("#\(item.id + 1)")
            .font(.caption2)
            .foregroundColor(.secondary)

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
              effect: effect
            )
            .opacity(isFocused ? 0 : 1)
            .onTapGesture { isFocused = true }

            TextField("Segment text", text: $editedText, axis: .vertical)
              .textFieldStyle(.plain)
              .font(.subheadline)
              .foregroundColor(.primary)
              .lineLimit(1...6)
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
          SegmentTranslationEditor(
            translation: resolvedTranslation,
            text: $editedTranslation,
            onCommit: commitTranslationIfNeeded
          )
        }

        if showTimes {
          HStack(spacing: 6) {
            Text(timeLabel(item.displayStart))
            Text("→").foregroundColor(.secondary)
            Text(timeLabel(item.displayEnd))
            Text("(\(formatDuration(item.displayEnd - item.displayStart)))")
              .foregroundColor(.secondary)
          }
          .font(.caption2)
          .foregroundColor(.secondary)
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
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(baseBackground)
    .overlay(alignment: .leading) {
      if active {
        Rectangle()
          .fill(Color.accentColor)
          .frame(width: 3)
      }
    }
    .overlay(alignment: .topTrailing) {
      if let zoomLabel = effect?.appliedZoom, zoomLabel > 1.0 {
        ZoomBadgeView(scale: zoomLabel, coverage: highlightCoverage)
          .padding(6)
      }
    }
    .onChange(of: isFocused) { _, focused in
      if !focused { commitIfNeeded() }
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
