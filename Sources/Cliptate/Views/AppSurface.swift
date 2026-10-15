import SwiftUI

/// Native macOS surfaces shared by pages, editing panels, and custom presentations.
enum AppSurface {
  static let pageBackground = Color(nsColor: .windowBackgroundColor)
  static let cardBackground = Color(nsColor: .controlBackgroundColor)
  static let inputBackground = Color(nsColor: .textBackgroundColor)
  static let subtleFill = Color.primary.opacity(0.04)
  static let hoverFill = Color.primary.opacity(0.06)
  static let border = Color(nsColor: .separatorColor).opacity(0.5)
  static let selectedFill = Color.accentColor.opacity(0.12)
  static let selectedBorder = Color.accentColor.opacity(0.40)
}

extension View {
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
