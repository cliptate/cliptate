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
      return (requiresGettingStarted ? [.permissions] : [])
        + (SubscriptionPolicy.isBillingEnabled ? [.pro] : []) + [.setting]
    }
  }
}

struct AppSidebar: View {
  @Binding var selection: AppSection?
  let requiresGettingStarted: Bool
  @ObservedObject private var updates = AppUpdateManager.shared

  var body: some View {
    VStack(spacing: 0) {
      List(selection: $selection) {
        ForEach([AppSidebarGroup.create, .library]) { group in
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
        if requiresGettingStarted {
          AppSidebarRow(section: .permissions, isSelected: selection == .permissions)
            .tag(AppSection.permissions)
            .listRowSeparator(.hidden)
        }
      }
      .listStyle(.sidebar)

      VStack(spacing: 4) {
        Divider()
          .padding(.horizontal, 8)
          .padding(.bottom, 8)
        ForEach(AppSidebarGroup.app.sections(requiresGettingStarted: false)) { section in
          HStack(spacing: 4) {
            AppSidebarFooterButton(section: section, isSelected: selection == section) {
              selection = section
            }
            if section == .setting, let update = updates.availableUpdate {
              AvailableAppUpdateButton(update: update)
            }
          }
        }
      }
      .padding(12)
    }
    .navigationSplitViewColumnWidth(min: 210, ideal: 224, max: 300)
  }
}

private struct AppSidebarFooterButton: View {
  let section: AppSection
  let isSelected: Bool
  let action: () -> Void
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      AppSidebarRow(section: section, isSelected: isSelected)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .foregroundStyle(Color.primary)
        .background {
          RoundedRectangle(cornerRadius: 8)
            .fill(
              isSelected ? AppSurface.selectedFill
                : (isHovered ? AppSurface.hoverFill : Color.clear)
            )
        }
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
  }
}

private struct AppSidebarRow: View {
  let section: AppSection
  let isSelected: Bool

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: section.icon)
        .font(.system(size: 16, weight: .medium))
        .symbolRenderingMode(isSelected ? .monochrome : .hierarchical)
        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
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
