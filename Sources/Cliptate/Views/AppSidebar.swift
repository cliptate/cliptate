import SwiftUI

enum AppSidebarGroup: String, CaseIterable, Identifiable {
  case create
  case library
  case app

  var id: String { rawValue }

  var title: LocalizedStringKey {
    switch self {
    case .create: return "Create"
    case .library: return "Library"
    case .app: return "App"
    }
  }

  func sections(requiresGettingStarted: Bool) -> [AppSection] {
    switch self {
    case .create:
      return [.aiCut, .voiceToText, .ttsStudio]
    case .library:
      return [.history, .models, .dictionary]
    case .app:
      return (requiresGettingStarted ? [.permissions] : []) + [.pro, .setting]
    }
  }
}

struct AppSidebar: View {
  @Binding var selection: AppSection?
  let requiresGettingStarted: Bool

  var body: some View {
    List(selection: $selection) {
      ForEach(AppSidebarGroup.allCases) { group in
        Section {
          ForEach(group.sections(requiresGettingStarted: requiresGettingStarted)) { section in
            AppSidebarRow(section: section, isSelected: selection == section)
              .tag(section)
              .listRowSeparator(.hidden)
          }
        } header: {
          Text(group.title)
            .font(.caption.weight(.semibold))
            .textCase(nil)
        }
      }
    }
    .listStyle(.sidebar)
    .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
  }
}

private struct AppSidebarRow: View {
  let section: AppSection
  let isSelected: Bool

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: section.icon)
        .font(.system(size: 16, weight: .medium))
        .symbolRenderingMode(.hierarchical)
        .frame(width: 24)
        .accessibilityHidden(true)

      Text(section.label)
        .font(.body.weight(isSelected ? .semibold : .regular))
        .lineLimit(1)

      Spacer(minLength: 0)
    }
    .frame(minHeight: 34)
    .contentShape(Rectangle())
    .help(section.description)
    .accessibilityElement(children: .combine)
    .accessibilityHint(section.description)
  }
}
