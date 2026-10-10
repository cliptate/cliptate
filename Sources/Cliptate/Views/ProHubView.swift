import SwiftUI

#if os(macOS)
    import AppKit
#endif

struct ProHubView: View {
    @StateObject private var paywallManager = PaywallManager.shared
    @StateObject private var subscriptionStatusViewModel = SubscriptionStatusViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                mainCard
                    .frame(maxWidth: 820)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: paywallPresentationBinding) {
            PaywallView()
                .environmentObject(paywallManager)
        }
        .onChange(of: paywallManager.latestPurchaseEvent) { _, event in
            guard let event else { return }
            Task { await subscriptionStatusViewModel.refresh(force: true) }
            paywallManager.consumeLatestPurchaseEvent(event.id)
        }
    }

    // MARK: - Main Card

    private var mainCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

            Divider()
                .padding(.horizontal, 20)

            statusAndPlanContent
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

            Divider()
                .padding(.horizontal, 20)

            featureHighlightsRow
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

            Divider()
                .padding(.horizontal, 20)

            planTiersSection
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    // MARK: - Header Row

    private var headerRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                headerIdentity
                Spacer()
                primaryCTAButton
            }
            VStack(alignment: .leading, spacing: 12) {
                headerIdentity
                primaryCTAButton
            }
        }
    }

    private var headerIdentity: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Cliptate Pro")
                    .font(.headline)
                Text("Manage your plan, billing, and purchases.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var primaryCTAButton: some View {
        Button(action: presentPaywall) {
            Label(
                hasActiveProAccess ? "Manage or Upgrade" : "Unlock Cliptate",
                systemImage: hasActiveProAccess ? "arrow.up.right.circle" : "sparkles"
            )
            .font(.system(size: 14, weight: .semibold))
            .frame(minHeight: 36)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .disabled(paywallManager.isLoading || paywallManager.isPresented)
    }

    // MARK: - Status + Plan Content

    private var statusAndPlanContent: some View {
        SubscriptionStatusView(viewModel: subscriptionStatusViewModel)
            // Skip card wrapping inside our unified card surface.
            .environment(\.proHubEmbedded, true)
    }

    // MARK: - Feature Highlights

    private var featureHighlightsRow: some View {
        ViewThatFits(in: .horizontal) {
            // Wide: 3-column horizontal strip with dividers
            HStack(spacing: 0) {
                featureCell(
                    systemImage: "waveform.badge.magnifyingglass",
                    title: "Unlimited Transcriptions",
                    description: "No free-tier quotas"
                )
                featureDivider
                featureCell(
                    systemImage: "cpu",
                    title: "Priority Models",
                    description: "Latest Whisper & Parakeet"
                )
                featureDivider
                featureCell(
                    systemImage: "film.stack",
                    title: "Premium Exports",
                    description: "4K, FCPXML & subtitles"
                )
            }

            // Narrow: vertical list
            VStack(alignment: .leading, spacing: 10) {
                featureRow(
                    systemImage: "waveform.badge.magnifyingglass",
                    title: "Unlimited Transcriptions",
                    description: "No free-tier quotas"
                )
                featureRow(
                    systemImage: "cpu",
                    title: "Priority Models",
                    description: "Latest Whisper & Parakeet"
                )
                featureRow(
                    systemImage: "film.stack",
                    title: "Premium Exports",
                    description: "4K, FCPXML & subtitles"
                )
            }
        }
    }

    private var featureDivider: some View {
        Divider()
            .frame(height: 40)
            .padding(.horizontal, 8)
    }

    private func featureCell(
        systemImage: String,
        title: LocalizedStringKey,
        description: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .center, spacing: 6) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.accentColor.opacity(0.1)))
            Text(title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func featureRow(
        systemImage: String,
        title: LocalizedStringKey,
        description: LocalizedStringKey
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor.opacity(0.1)))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Plan Tiers

    private var planTiersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Available Plans")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            // Equal-width 3-column grid so chips align cleanly at any width
            HStack(spacing: 10) {
                planChip(
                    title: "Monthly",
                    systemImage: "calendar.badge.clock",
                    description: "Flexible, cancel anytime"
                )
                planChip(
                    title: "Annual",
                    systemImage: "rosette",
                    description: "Best long-term value"
                )
                planChip(
                    title: "Lifetime",
                    systemImage: "infinity.circle",
                    description: "One purchase, forever"
                )
            }
        }
    }

    private func planChip(
        title: LocalizedStringKey,
        systemImage: String,
        description: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            Text(description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private var hasActiveProAccess: Bool {
        subscriptionStatusViewModel.status?.isActive ?? false
    }

    private func presentPaywall() {
        let targetModel = ModelVariant.proModels.first ?? .parakeetV3
        Task { await paywallManager.showPaywall(for: targetModel, reason: .userInitiated) }
    }

    private var paywallPresentationBinding: Binding<Bool> {
        Binding(
            get: { paywallManager.isPresented },
            set: { newValue in
                if !newValue {
                    paywallManager.dismissPaywall()
                }
            }
        )
    }
}

#Preview {
    ProHubView()
        .frame(width: 900, height: 700)
}
