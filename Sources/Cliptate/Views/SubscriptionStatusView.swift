import SwiftUI

#if os(macOS)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

/// Displays the user's current subscription status and management actions.
@MainActor
struct SubscriptionStatusView: View {
  @StateObject private var viewModel: SubscriptionStatusViewModel
  @Environment(\.proHubEmbedded) private var isEmbedded

  init(viewModel: SubscriptionStatusViewModel? = nil) {
    let vm = viewModel ?? SubscriptionStatusViewModel()
    _viewModel = StateObject(wrappedValue: vm)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header
      statusSummary
      if let message = viewModel.message {
        StatusMessageView(message: message)
      }
      actionRow
      legalLinksRow
    }
    .modifier(OptionalCardModifier(apply: !isEmbedded))
    .task {
      await viewModel.refresh(force: false)
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 12) {

      Image(systemName: "person.crop.rectangle.stack")
        .font(.title2)
        .foregroundStyle(Color.accentColor)
        .frame(width: 40, height: 40)
        .background(
          RoundedRectangle(cornerRadius: 10)
            .fill(Color.accentColor.opacity(0.15))
        )

      VStack(alignment: .leading, spacing: 4) {
        Text("Subscription Status")
          .font(.headline)
        Text("Manage your Cliptate entitlement and purchases.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      if viewModel.isLoading {
        ProgressView()
      } else {
        Button {
          Task { await viewModel.refresh(force: true) }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
    }
  }

  @ViewBuilder
  private var statusSummary: some View {
    if let status = viewModel.status {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .center, spacing: 10) {
          statusBadge(for: status)
          if let plan = status.currentPlan {
            Label(plan.name, systemImage: "tag.fill")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          } else {
            Text("Free tier")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          Spacer()
        }

        VStack(alignment: .leading, spacing: 6) {
          if let expirationText = expirationDescription(for: status) {
            Label(expirationText, systemImage: "calendar")
              .font(.callout)
              .foregroundStyle(.primary)
          }

          if status.isInTrialPeriod {
            Label("Trial period active", systemImage: "clock.arrow.circlepath")
              .font(.callout)
              .foregroundStyle(.orange)
          }

          if let refreshed = viewModel.lastRefreshed {
            Label(
              "Last updated \(formatted(date: refreshed))",
              systemImage: "arrow.triangle.2.circlepath"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
        }
      }
    } else if viewModel.isLoading {
      HStack(spacing: 8) {
        ProgressView()
        Text("Fetching subscription status…")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    } else {
      Text("Subscription data is unavailable. Refresh to try again.")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
  }

  private func statusBadge(for status: SubscriptionStatus) -> some View {
    let isActive = status.isActive
    return HStack(spacing: 8) {
      Image(systemName: isActive ? "checkmark.seal.fill" : "lock.slash")
        .foregroundStyle(isActive ? Color.green : Color.secondary)
      Text(isActive ? "Pro Active" : "Free Access")
        .font(.headline)
        .foregroundStyle(isActive ? Color.primary : .secondary)
    }
    .padding(.vertical, 6)
    .padding(.horizontal, 12)
    .background(
      Capsule()
        .fill(
          isActive ? Color.green.opacity(0.15) : Color.secondary.opacity(0.1)
        )
    )
  }

  private func expirationDescription(for status: SubscriptionStatus) -> String? {
    if let expirationDate = status.expirationDate {
      let formatter = DateFormatter()
      formatter.dateStyle = .medium
      formatter.timeStyle = .none
      if Date() < expirationDate {
        return String(localized: "Active until \(formatter.string(from: expirationDate))", comment: "Subscription status: active with expiry date; %@ is the date string")
      } else {
        return String(localized: "Expired on \(formatter.string(from: expirationDate))", comment: "Subscription status: expired; %@ is the expiry date string")
      }
    }
    if status.isActive {
      return String(localized: "Lifetime access currently active", comment: "Subscription status: lifetime purchase is active")
    }
    return nil
  }

  private func formatted(date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: date, relativeTo: Date())
  }

  private var actionRow: some View {
    ViewThatFits(in: .horizontal) {
      actionButtons
      VStack(alignment: .leading, spacing: 12) {
        actionButtons
      }
    }
  }

  private var actionButtons: some View {
    HStack(spacing: 12) {
      Button {
        openManageSubscriptions()
      } label: {
        Label("Manage Subscription", systemImage: "gearshape")
      }
      .buttonStyle(.bordered)

      Button {
        Task { await viewModel.restorePurchases() }
      } label: {
        if viewModel.isRestoring {
          HStack(spacing: 8) {
            ProgressView()
              .controlSize(.small)
            Text("Restoring…")
          }
        } else {
          Label("Restore Purchases", systemImage: "arrow.triangle.2.circlepath")
        }
      }
      .buttonStyle(.bordered)
      .controlSize(.regular)
      .disabled(viewModel.isRestoring)
    }
  }

  private var legalLinksRow: some View {
    HStack(spacing: 12) {
      if let termsURL = LegalLinks.termsOfUse {
        Link("Terms of Use", destination: termsURL)
      }
      if let privacyURL = LegalLinks.privacyPolicy {
        Link("Privacy Policy", destination: privacyURL)
      }
    }
    .font(.footnote)
    .foregroundStyle(.secondary)
  }

  private func openManageSubscriptions() {
    guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
    #if os(macOS)
      NSWorkspace.shared.open(url)
    #elseif canImport(UIKit)
      UIApplication.shared.open(url)
    #endif
  }
}

// MARK: - View Model

@MainActor
final class SubscriptionStatusViewModel: ObservableObject {
  struct StatusMessage: Identifiable, Equatable {
    enum Kind {
      case success
      case info
      case error

      var tint: Color {
        switch self {
        case .success: return .green
        case .info: return .blue
        case .error: return .red
        }
      }

      var background: Color {
        tint.opacity(0.12)
      }

      var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
      }
    }

    let id = UUID()
    let kind: Kind
    let text: String
  }

  @Published private(set) var status: SubscriptionStatus?
  @Published private(set) var isLoading = false
  @Published private(set) var isRestoring = false
  @Published private(set) var message: StatusMessage?
  @Published private(set) var lastRefreshed: Date?

  private let accessController: ModelAccessController
  private let revenueCatManager: RevenueCatManager

  init(
    accessController: ModelAccessController = .shared,
    revenueCatManager: RevenueCatManager = .shared
  ) {
    self.accessController = accessController
    self.revenueCatManager = revenueCatManager
  }

  func refresh(force: Bool) async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      let currentStatus = try await accessController.getCurrentSubscriptionStatus(
        forceRefresh: force
      )
      status = currentStatus
      lastRefreshed = Date()
      if !force {
        message = nil
      }
    } catch {
      message = StatusMessage(kind: .error, text: error.localizedDescription)
    }
  }

  func restorePurchases() async {
    guard !isRestoring else { return }
    isRestoring = true
    defer { isRestoring = false }

      do {
        _ = try await revenueCatManager.restorePurchases()
        await refresh(force: true)
        message = StatusMessage(
          kind: .success,
          text: String(
            localized: "Purchases restored successfully.",
            comment: "Subscription status: restore purchases success message"
          )
        )
      } catch {
        message = StatusMessage(kind: .error, text: error.localizedDescription)
      }
  }
}

// MARK: - Supporting Views

private struct StatusMessageView: View {
  let message: SubscriptionStatusViewModel.StatusMessage

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: message.kind.icon)
        .foregroundStyle(message.kind.tint)
      Text(message.text)
        .font(.callout)
        .foregroundStyle(.primary)
      Spacer()
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(message.kind.background)
    )
  }
}
