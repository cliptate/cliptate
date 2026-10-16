import SwiftUI

enum AppSidebarGroup: String, CaseIterable, Identifiable {
  case overview
  case create
  case library
  case app

  var id: String { rawValue }

  var title: LocalizedStringKey {
    switch self {
    case .overview: return "Home"
    case .create: return "Create"
    case .library: return "Library"
    case .app: return "App"
    }
  }

  func sections(requiresGettingStarted: Bool) -> [AppSection] {
    switch self {
    case .overview: return [.home] + (requiresGettingStarted ? [.permissions] : [])
    case .create:
      return [.aiCut, .voiceToText, .ttsStudio]
    case .library:
      return [.history, .models, .dictionary]
    case .app:
      return (SubscriptionPolicy.isBillingEnabled ? [.pro] : []) + [.setting]
    }
  }
}

struct AppSidebar: View {
  @Binding var selection: AppSection?
  let requiresGettingStarted: Bool
  @ObservedObject private var updates = AppUpdateManager.shared
  @FocusState private var focusedSection: AppSection?
  @State private var showsKeyboardFocus = false

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .frame(width: 28, height: 28)
        Text(verbatim: "Cliptate")
          .font(.system(size: 19, weight: .semibold))
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 18)
      .padding(.top, 48)
      .padding(.bottom, 12)
      .accessibilityHidden(true)

      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(AppSidebarGroup.overview.sections(requiresGettingStarted: requiresGettingStarted)) { section in
              navigationRow(section)
            }

            ForEach([AppSidebarGroup.create, .library]) { group in
              Text(group.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)

              ForEach(group.sections(requiresGettingStarted: requiresGettingStarted)) { section in
                navigationRow(section)
              }
            }
          }
          .padding(.horizontal, 8)
          .padding(.bottom, 8)
        }
        .onChange(of: focusedSection) { _, section in
          if let section { proxy.scrollTo(section) }
        }
      }

      VStack(spacing: 4) {
        ForEach(AppSidebarGroup.app.sections(requiresGettingStarted: false)) { section in
          HStack(spacing: 4) {
            AppSidebarButton(section: section, isSelected: selection == section) {
              selection = section
            }
            if section == .setting, let update = updates.availableUpdate {
              AvailableAppUpdateButton(update: update)
            }
          }
        }
      }
      .padding(8)
    }
    .frame(maxHeight: .infinity)
    .background {
      AppSurface.pageBackground
      AppSurface.subtleFill
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Sidebar")
    .simultaneousGesture(TapGesture().onEnded { showsKeyboardFocus = false })
    .onKeyPress(phases: [.down, .up]) { _ in
      showsKeyboardFocus = true
      return .ignored
    }
    .onChange(of: selection) { _, section in
      if focusedSection != section { focusedSection = nil }
    }
  }

  private func navigationRow(_ section: AppSection) -> some View {
    AppSidebarButton(section: section, isSelected: selection == section) {
      selection = section
      focusedSection = section
    }
    .focusable()
    .focused($focusedSection, equals: section)
    .focusEffectDisabled()
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(
          showsKeyboardFocus && focusedSection == section
            ? Color.primary.opacity(0.45) : Color.clear,
          lineWidth: 1.5
        )
        .allowsHitTesting(false)
    }
    .onKeyPress(keys: [.upArrow, .downArrow]) { press in
      showsKeyboardFocus = true
      moveSelection(by: press.key == .upArrow ? -1 : 1)
      return .handled
    }
    .id(section)
  }

  private func moveSelection(by offset: Int) {
    let sections = [AppSidebarGroup.overview, .create, .library]
      .flatMap { $0.sections(requiresGettingStarted: requiresGettingStarted) }
    guard !sections.isEmpty else { return }
    let nextIndex: Int
    if let selection, let index = sections.firstIndex(of: selection) {
      nextIndex = min(max(index + offset, 0), sections.count - 1)
    } else {
      nextIndex = 0
    }
    selection = sections[nextIndex]
    focusedSection = sections[nextIndex]
  }
}

private struct AppSidebarButton: View {
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
              isSelected ? Color.primary.opacity(0.08)
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
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(Color.secondary)
        .frame(width: 24)
        .accessibilityHidden(true)

      Text(section.label)
        .font(.body.weight(isSelected ? .semibold : .regular))
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
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
