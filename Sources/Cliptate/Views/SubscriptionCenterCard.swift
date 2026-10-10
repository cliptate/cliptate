import SwiftUI

#if os(macOS)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

// MARK: - Card modifier

private struct SubscriptionCenterCardModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(20)
      .background(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(Color(NSColor.controlBackgroundColor))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .stroke(Color.primary.opacity(0.08), lineWidth: 1)
      )
  }
}

extension View {
  func subscriptionCenterCard() -> some View {
    modifier(SubscriptionCenterCardModifier())
  }
}

// MARK: - Optional card modifier

/// Applies the subscription card styling only when `apply` is true.
/// Used by `SubscriptionStatusView` when embedded inside a unified card surface.
struct OptionalCardModifier: ViewModifier {
  let apply: Bool

  func body(content: Content) -> some View {
    if apply {
      content.subscriptionCenterCard()
    } else {
      content
    }
  }
}

// MARK: - Environment key for embedded rendering

struct ProHubEmbeddedKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  var proHubEmbedded: Bool {
    get { self[ProHubEmbeddedKey.self] }
    set { self[ProHubEmbeddedKey.self] = newValue }
  }
}
