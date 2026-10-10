import SwiftUI

struct SidebarSection<Content: View>: View {
  let title: LocalizedStringKey
  let systemImage: String?
  let content: Content

  init(_ title: LocalizedStringKey, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
    self.title = title
    self.systemImage = systemImage
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        if let systemImage {
          Image(systemName: systemImage).font(.caption).foregroundColor(.accentColor)
        }
        Text(title)
          .textCase(.uppercase)
          .font(.caption2).fontWeight(.semibold)
          .foregroundColor(.secondary)
          .tracking(1)
      }
      .padding(.horizontal, 4)
      content
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .padding(.horizontal, 4)
  }
}
