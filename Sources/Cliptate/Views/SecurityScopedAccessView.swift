import SwiftUI

#if os(macOS)
  struct SecurityScopedAccessView<Content: View>: View {
    let url: URL
    let securityScopeManager: SecurityScopedURLAccessManager
    @ViewBuilder var content: () -> Content

    var body: some View {
      content()
        .task(id: url) {
          securityScopeManager.startAccess(for: url)
        }
    }
  }
#endif
