import SwiftUI

/// Native macOS surfaces shared by pages, editing panels, and custom presentations.
enum AppSurface {
  static let pageBackground = Color(nsColor: .windowBackgroundColor)
  static let contentBackground = Color(nsColor: .textBackgroundColor)
  static let settingsBackground = Color.primary.opacity(0.035)
  static let cardBackground = Color(nsColor: .controlBackgroundColor)
  static let inputBackground = Color(nsColor: .textBackgroundColor)
  static let subtleFill = Color.primary.opacity(0.04)
  static let hoverFill = Color.primary.opacity(0.06)
  static let border = Color(nsColor: .separatorColor).opacity(0.5)
  static let selectedFill = Color.accentColor.opacity(0.12)
  static let selectedBorder = Color.accentColor.opacity(0.40)
}

extension View {
  func appSegmentedHover(selectedIndex: Int, count: Int) -> some View {
    modifier(AppSegmentedHover(selectedIndex: selectedIndex, count: count))
  }

  /// Give custom text editors the same surface and focus treatment as other inputs.
  func appInputSurface(isFocused: Bool = false, cornerRadius: CGFloat = 6) -> some View {
    background(AppSurface.inputBackground, in: RoundedRectangle(cornerRadius: cornerRadius))
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius)
          .strokeBorder(
            isFocused ? AppSurface.selectedBorder : AppSurface.border,
            lineWidth: isFocused ? 1.5 : 1
          )
          .allowsHitTesting(false)
      }
  }
}

private struct AppSegmentedHover: ViewModifier {
  let selectedIndex: Int
  let count: Int
  @State private var size: CGSize = .zero
  @State private var hoveredIndex: Int?

  func body(content: Content) -> some View {
    content
      .overlay(alignment: .topLeading) {
        if let index = hoveredIndex, index != selectedIndex, count > 0 {
          let segmentWidth = size.width / CGFloat(count)
          RoundedRectangle(cornerRadius: 4)
            .fill(AppSurface.hoverFill)
            .frame(width: max(0, segmentWidth - 4), height: max(0, size.height - 4))
            .offset(x: CGFloat(index) * segmentWidth + 2, y: 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
      }
      .onGeometryChange(for: CGSize.self) { proxy in
        proxy.size
      } action: { size = $0 }
      .onContinuousHover(coordinateSpace: .local) { phase in
        switch phase {
        case .active(let location):
          guard count > 0, size.width > 0 else { return }
          hoveredIndex = min(count - 1, max(0, Int(location.x / size.width * CGFloat(count))))
        case .ended:
          hoveredIndex = nil
        }
      }
  }
}
