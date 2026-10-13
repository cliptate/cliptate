import SwiftUI

/// A consistent title boundary above page content, including split layouts.
struct AppPageHeader<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
      .padding(.horizontal, 28)
      .padding(.vertical, 16)
      .background(AppSurface.pageBackground)
      .fixedSize(horizontal: false, vertical: true)
  }
}

extension View {
  /// Reserve layout space explicitly; native split views do not consume safe-area insets.
  func appPageHeader<Header: View>(@ViewBuilder _ header: () -> Header) -> some View {
    VStack(spacing: 0) {
      header()
        .zIndex(1)
      self.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(AppSurface.pageBackground)
  }
}

extension AppPageHeader where Content == AppPageTitle {
  init(_ section: AppSection) {
    self.init {
      AppPageTitle(title: section.label, subtitle: section.description)
    }
  }
}

struct AppPageTitle: View {
  let title: LocalizedStringKey
  let subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.title.weight(.semibold))
        .accessibilityAddTraits(.isHeader)
      Text(subtitle)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}
