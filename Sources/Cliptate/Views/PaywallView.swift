import AppKit
import SwiftUI

/// SwiftUI paywall surface driven by `PaywallManager` state.
struct PaywallView: View {
    @EnvironmentObject private var paywallManager: PaywallManager
    @State private var selectedPlanID: SubscriptionPlan.ID?
    @State private var purchaseStatusMessage: String?
    @State private var purchaseStatusIsError = false

    private var benefits: [String] {
        [
            String(
                localized: "Unlimited downloads for premium models",
                comment: "Paywall benefit: unlimited premium model downloads"
            ),
            String(
                localized: "Batch workflows and export tools stay unlocked",
                comment: "Paywall benefit: batch workflows and export tools remain available"
            ),
            String(
                localized: "Priority access to new model releases",
                comment: "Paywall benefit: early access to newly released models"
            ),
        ]
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 20) {
                if let context = paywallManager.context {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            headerSection(for: context)
                            if context.showsModelSummaryCard {
                                summarySection(for: context)
                            }
                            planSection(for: context)
                            benefitSection
                            legalSection(for: context)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    placeholderSection
                }

                statusAndErrorSection
                actionSection
            }
            .padding(.vertical, 28)
            .padding(.horizontal, 32)
            .frame(minWidth: 480, idealWidth: 520, maxWidth: 600, minHeight: 520)
        }
        .overlay(loadingOverlay)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: paywallManager.isLoading)
        .animation(.default, value: paywallManager.errorMessage)
        .onChange(of: paywallManager.isPresented) { _, presented in
            if !presented {
                selectedPlanID = nil
                purchaseStatusMessage = nil
                purchaseStatusIsError = false
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.18),
                        Color.accentColor.opacity(0.05),
                        Color(nsColor: .windowBackgroundColor),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(color: Color.black.opacity(0.15), radius: 24, x: 0, y: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .ignoresSafeArea()
    }

    private func headerSection(for context: PaywallContext) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(reasonLabel(for: context.reason), systemImage: reasonIcon(for: context.reason))
                .font(.caption.weight(.semibold))
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel(
                    String(
                        localized: "Subscription Recommendation",
                        comment: "Accessibility label for paywall recommendation badge"
                    )
                )

            Text(headline(for: context))
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Text(detailMessage(for: context))
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func summarySection(for context: PaywallContext) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(context.model.displayName)
                        .font(.title3.weight(.semibold))
                    Text(context.model.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                if let recommendedPlan = context.recommendedPlan {
                    savingsBadge(text: String(localized: "Recommended"))
                        .accessibilityLabel(
                            String(
                                localized: "Recommended plan: \(recommendedPlan.name)",
                                comment: "Accessibility: recommended plan badge"
                            )
                        )
                }
            }

            HStack(spacing: 10) {
                Image(systemName: context.currentSubscription.isActive ? "checkmark.shield" : "lock.shield")
                    .foregroundStyle(context.currentSubscription.isActive ? Color.green : Color.orange)
                    .accessibilityHidden(true)
                Text(context.currentSubscription.statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06))
        )
    }

    private var benefitSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(benefits, id: \.self) { benefit in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.title3)
                        .accessibilityHidden(true)

                    Text(benefit)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private func currentSelectionID(in context: PaywallContext) -> SubscriptionPlan.ID? {
        let selectable = context.selectablePlans
        if let selectedPlanID,
            selectable.contains(where: { $0.id == selectedPlanID })
        {
            return selectedPlanID
        }
        return context.recommendedPlan?.id ?? selectable.first?.id
    }

    private func ensureSelection(for context: PaywallContext) {
        let selectable = context.selectablePlans
        if let selectedPlanID,
            selectable.contains(where: { $0.id == selectedPlanID })
        {
            return
        }
        selectedPlanID = context.recommendedPlan?.id ?? selectable.first?.id
    }

    private func selectedPlan(for context: PaywallContext) -> SubscriptionPlan? {
        guard let selectionID = currentSelectionID(in: context) else { return nil }
        return context.selectablePlans.first(where: { $0.id == selectionID })
    }

    private func upgradeButtonTitle() -> String {
        guard let context = paywallManager.context else {
            return NSLocalizedString(
                "Select Subscription Plan", comment: "select plan button title")
        }

        if let plan = selectedPlan(for: context) {
            if let price = plan.priceText, !price.isEmpty {
                switch plan.type {
                case .lifetime:
                    return String(
                        format: NSLocalizedString(
                            "Unlock Lifetime for %@", comment: "lifetime upgrade button title"),
                        price)
                case .annual, .monthly:
                    return String(
                        format: NSLocalizedString(
                            "Continue for %@", comment: "subscription upgrade button title"),
                        price)
                }
            }
            return String(
                format: NSLocalizedString("Upgrade with %@", comment: "upgrade button title"),
                plan.name
            )
        }

        if let currentPlan = context.currentSubscription.currentPlan {
            if currentPlan.type == .lifetime {
                return NSLocalizedString(
                    "Lifetime access active", comment: "lifetime active button title")
            }
            return String(
                format: NSLocalizedString(
                    "%@ already active", comment: "current subscription active title"),
                currentPlan.name
            )
        }

        return NSLocalizedString(
            "Select Subscription Plan", comment: "select plan button title")
    }

    private func attemptPurchase() {
        guard !paywallManager.isPurchasing,
            let context = paywallManager.context,
            let plan = selectedPlan(for: context)
        else { return }

        purchaseStatusMessage = nil
        purchaseStatusIsError = false

        Task {
            do {
                let success = try await paywallManager.processPurchase(plan: plan)
                purchaseStatusIsError = !success
                purchaseStatusMessage =
                    success
                    ? NSLocalizedString(
                        "Thank you for subscribing! Pro features unlocked.",
                        comment: "purchase success short")
                    : NSLocalizedString("Purchase cancelled.", comment: "purchase cancelled short")
            } catch {
                purchaseStatusIsError = true
                purchaseStatusMessage = paywallManager.errorMessage ?? error.localizedDescription
            }
        }
    }

    private func planSection(for context: PaywallContext) -> some View {
        let plans = context.renderablePlans
        let activeSelection = currentSelectionID(in: context)
        let recommendedPlanID = context.recommendedPlan?.id

        return VStack(alignment: .leading, spacing: 14) {
            Text("Subscription Plans")
                .font(.headline)

            VStack(spacing: 12) {
                if plans.isEmpty {
                    noPlanPlaceholder
                } else {
                    ForEach(plans) { plan in
                        let disabled = !context.selectablePlans.contains(where: { $0.id == plan.id })
                        planCard(
                            for: plan,
                            currentPlan: context.currentSubscription.currentPlan,
                            isSelected: plan.id == activeSelection,
                            isDisabled: disabled,
                            isRecommended: plan.id == recommendedPlanID
                        )
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }
        .onAppear {
            ensureSelection(for: context)
        }
        .onChange(of: context.availablePlans) { _, _ in
            ensureSelection(for: context)
        }
        .onChange(of: context.currentSubscription.currentPlan?.id) { _, _ in
            ensureSelection(for: context)
        }
    }

    private var noPlanPlaceholder: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Loading subscription plans...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func planCard(
        for plan: SubscriptionPlan,
        currentPlan: SubscriptionPlan?,
        isSelected: Bool,
        isDisabled: Bool,
        isRecommended: Bool
    ) -> some View {
        Button {
            guard !isDisabled else { return }
            performHaptic()
            selectedPlanID = plan.id
            purchaseStatusMessage = nil
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text(plan.name)
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 8) {
                            Text(plan.duration.displayName)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)

                            if let currentPlan, currentPlan.id == plan.id {
                                savingsBadge(
                                    text: String(
                                        localized: "Current",
                                        comment: "Paywall badge for the active subscription plan"
                                    )
                                )
                            }
                        }

                        HStack(alignment: .center, spacing: 10) {
                            if isRecommended && currentPlan?.id != plan.id {
                                savingsBadge(text: String(localized: "Recommended"))
                            }

                            if plan.type == .annual {
                                savingsBadge(
                                    text: String(
                                        localized: "Save 17%",
                                        comment: "Paywall badge highlighting annual savings"
                                    )
                                )
                            } else if plan.type == .monthly {
                                savingsBadge(
                                    text: String(
                                        localized: "Popular",
                                        comment: "Paywall badge highlighting the monthly plan"
                                    )
                                )
                            } else if plan.type == .lifetime {
                                savingsBadge(
                                    text: String(
                                        localized: "Best Value",
                                        comment: "Paywall badge highlighting the lifetime plan"
                                    )
                                )
                            }

                            if isSelected {
                                savingsBadge(
                                    text: String(
                                        localized: "Selected",
                                        comment: "Paywall badge for the selected subscription plan"
                                    ),
                                    tint: Color.accentColor.opacity(0.35)
                                )
                            }
                        }
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(priceLabel(for: plan))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        if let caption = priceCaption(for: plan) {
                            Text(caption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minWidth: 96)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .font(.title3)
                            .accessibilityLabel(
                                String(
                                    localized: "Currently Selected",
                                    comment: "Accessibility label for selected paywall plan"
                                )
                            )
                    }
                }

                Divider()

                Text(planDescription(for: plan, isRecommended: isRecommended))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.accentColor.opacity(0.08))
                } else {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(nsColor: .controlBackgroundColor).opacity(0.95),
                                    Color(nsColor: .controlBackgroundColor).opacity(0.8),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        planBorderColor(
                            for: plan,
                            currentPlan: currentPlan,
                            isSelected: isSelected
                        ),
                        lineWidth: isSelected ? 2.0 : 1.5
                    )
            )
            .opacity(isDisabled ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(planAccessibilityLabel(for: plan, price: priceLabel(for: plan)))
    }

    private func planBorderColor(
        for plan: SubscriptionPlan,
        currentPlan: SubscriptionPlan?,
        isSelected: Bool
    ) -> Color {
        if isSelected {
            return Color.accentColor
        }
        if let currentPlan, currentPlan.id == plan.id {
            return Color.accentColor
        }
        switch plan.type {
        case .monthly:
            return Color.accentColor.opacity(0.4)
        case .annual:
            return Color.accentColor.opacity(0.6)
        case .lifetime:
            return Color.orange.opacity(0.6)
        }
    }

    private func planAccessibilityLabel(for plan: SubscriptionPlan, price: String?) -> String {
        let base = "\(plan.name)，\(plan.duration.displayName)"
        if let price {
            return base + ", price \(price)"
        }
        return base
    }

    private func priceLabel(for plan: SubscriptionPlan) -> String {
        if let text = plan.priceText, !text.isEmpty { return text }
        return NSLocalizedString("See price", comment: "missing price placeholder")
    }

    private func priceCaption(for plan: SubscriptionPlan) -> String? {
        switch plan.type {
        case .monthly:
            return NSLocalizedString("per month", comment: "monthly price caption")
        case .annual:
            return NSLocalizedString("per year", comment: "annual price caption")
        case .lifetime:
            return NSLocalizedString("one-time", comment: "lifetime price caption")
        }
    }

    private func planDescription(for plan: SubscriptionPlan, isRecommended: Bool) -> String {
        if isRecommended && plan.type == .annual {
            return String(
                localized: "Balanced annual pricing with the simplest long-term upgrade path.",
                comment: "Recommended annual plan description in paywall"
            )
        }
        switch plan.type {
        case .monthly:
            return String(localized: "Flexible monthly subscription, cancel anytime.", comment: "Monthly plan description in paywall")
        case .annual:
            return String(localized: "Annual plan saves 17%, perfect for long-term creators.", comment: "Annual plan description in paywall")
        case .lifetime:
            return String(localized: "One-time payment for permanent Pro features unlock.", comment: "Lifetime plan description in paywall")
        }
    }

    private func legalSection(for context: PaywallContext) -> some View {
        let pendingPlan = selectedPlan(for: context)
        return VStack(alignment: .leading, spacing: 8) {
            if let plan = pendingPlan {
                Text(selectedPlanLegalSummary(for: plan))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let currentPlan = context.currentSubscription.currentPlan,
                context.currentSubscription.isActive
            {
                Text(
                    "You're currently on \(currentPlan.name). Manage downgrades from Apple ID settings."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Text(
                "Payment is charged to your Apple ID account. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel anytime in Settings."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                if let termsURL = LegalLinks.termsOfUse {
                    Link(
                        String(localized: "Terms of Use", comment: "Legal terms link title"),
                        destination: termsURL
                    )
                }
                if let privacyURL = LegalLinks.privacyPolicy {
                    Link(
                        String(localized: "Privacy Policy", comment: "Legal privacy link title"),
                        destination: privacyURL
                    )
                }
                Button {
                    performHaptic()
                    restorePurchasesTapped()
                } label: {
                    if paywallManager.isRestoring {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Restore Purchases")
                    }
                }
                .buttonStyle(.link)
                .disabled(paywallManager.isRestoring)
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(.top, 8)
    }

    private func selectedPlanLegalSummary(for plan: SubscriptionPlan) -> String {
        let price =
            plan.priceText ?? NSLocalizedString("See price in app", comment: "price fallback")
        switch plan.type {
        case .monthly:
            return String(
                format: NSLocalizedString(
                    "%@ renews every month for %@. Cancel anytime in Settings.",
                    comment: "monthly legal summary"),
                plan.name, price)
        case .annual:
            return String(
                format: NSLocalizedString(
                    "%@ renews every year for %@. Cancel anytime before renewal.",
                    comment: "annual legal summary"),
                plan.name, price)
        case .lifetime:
            return String(
                format: NSLocalizedString(
                    "%@ is a one-time purchase for %@ with permanent access.",
                    comment: "lifetime legal summary"),
                plan.name, price)
        }
    }

    private func restorePurchasesTapped() {
        guard !paywallManager.isRestoring else { return }
        purchaseStatusIsError = false
        purchaseStatusMessage = nil
        Task {
            let result = await paywallManager.restorePurchases()
            purchaseStatusIsError = !result.success
            if result.success {
                purchaseStatusMessage = NSLocalizedString(
                    "Restored purchases successfully. Your subscription status has been refreshed.",
                    comment: "restore success message")
            } else {
                purchaseStatusMessage =
                    result.errorMessage
                    ?? NSLocalizedString(
                        "Restore failed. Please try again later or contact support.",
                        comment: "restore failure message")
            }
        }
    }

    private func savingsBadge(text: String, tint: Color = Color.accentColor.opacity(0.15))
        -> some View
    {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(tint, in: Capsule())
            .foregroundStyle(Color.accentColor)
    }

    @ViewBuilder
    private var statusAndErrorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let errorMessage = paywallManager.errorMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.orange)
                        .accessibilityHidden(true)
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button(
                        String(
                            localized: "Retry",
                            comment: "Paywall button to retry loading subscription information"
                        )
                    ) {
                        performHaptic()
                        Task { await paywallManager.refreshContext() }
                    }
                    .buttonStyle(.link)
                    .accessibilityLabel(
                        String(
                            localized: "Retry getting subscription information",
                            comment: "Accessibility label for paywall retry button"
                        )
                    )
                }
                .padding(12)
                .background(
                    Color.orange.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if let purchaseStatusMessage {
                HStack(spacing: 10) {
                    Image(
                        systemName: purchaseStatusIsError
                            ? "xmark.octagon.fill" : "checkmark.circle.fill"
                    )
                    .foregroundStyle(purchaseStatusIsError ? Color.red : Color.green)
                    .accessibilityHidden(true)
                    Text(purchaseStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(purchaseStatusIsError ? Color.red : Color.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(
                    (purchaseStatusIsError ? Color.red.opacity(0.08) : Color.green.opacity(0.12)),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
        }
    }

    private var actionSection: some View {
        HStack(spacing: 16) {
            Button {
                performHaptic()
                paywallManager.dismissPaywall()
            } label: {
                Text("Maybe Later")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                performHaptic()
                attemptPurchase()
            } label: {
                HStack {
                    if paywallManager.isPurchasing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(upgradeButtonTitle())
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(
                paywallManager.isPurchasing
                    || paywallManager.context.flatMap { selectedPlan(for: $0) } == nil
            )
            .accessibilityHint(
                String(
                    localized: "Continue after selecting subscription plan",
                    comment: "Accessibility hint for paywall primary action"
                )
            )
        }
    }

    private var loadingOverlay: some View {
        Group {
            if paywallManager.isLoading {
                ZStack {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                    ProgressView(
                        String(
                            localized: "Loading...",
                            comment: "Paywall progress indicator title"
                        )
                    )
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 16).fill(
                                Color(nsColor: .windowBackgroundColor)))
                }
                .transition(.opacity)
            }
        }
    }

    private var placeholderSection: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Preparing subscription information...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    private func reasonLabel(for reason: PaywallContext.PaywallReason) -> LocalizedStringKey {
      switch reason {
      case .attemptedPaidModelDownload: return "Unlock Professional Models"
      case .subscriptionExpired: return "Subscription Expired"
      case .userInitiated: return "Manage Subscription"
      }
    }

    private func reasonIcon(for reason: PaywallContext.PaywallReason) -> String {
        switch reason {
        case .attemptedPaidModelDownload: return "sparkles"
        case .subscriptionExpired: return "exclamationmark.triangle.fill"
        case .userInitiated: return "gearshape"
        }
    }

    private func headline(for context: PaywallContext) -> String {
        switch context.reason {
        case .attemptedPaidModelDownload:
            return String(
                format: NSLocalizedString(
                    "Unlock %@ in Cliptate", comment: "paywall headline model upgrade"),
                context.model.displayName
            )
        case .subscriptionExpired:
            return NSLocalizedString(
                "Reactivate Cliptate", comment: "paywall headline subscription expired")
        case .userInitiated:
            return NSLocalizedString(
                "Manage Your Cliptate Plan", comment: "paywall headline manage")
        }
    }

    private func detailMessage(for context: PaywallContext) -> String {
        switch context.reason {
        case .attemptedPaidModelDownload:
            let additionalCount = max(ModelVariant.proModels.count - 1, 0)
            if additionalCount > 0 {
                return String(
                    format: NSLocalizedString(
                        "Upgrade now to use %@ and %d other premium models with priority processing and unlimited downloads.",
                        comment: "paywall detail attempted download"),
                    context.model.displayName, additionalCount
                )
            } else {
                return String(
                    format: NSLocalizedString(
                        "Upgrade now to unlock %@ with priority processing and unlimited downloads.",
                        comment: "paywall detail attempted download single"),
                    context.model.displayName
                )
            }
        case .subscriptionExpired:
            if let expiration = context.currentSubscription.expirationDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                return String(
                    format: NSLocalizedString(
                        "Your access ended on %@. Restore Pro to keep premium exports, batch processing, and fast model updates.",
                        comment: "paywall detail subscription expired"),
                    formatter.string(from: expiration)
                )
            }
            return NSLocalizedString(
                "Your Pro access is inactive. Restore now to keep premium exports, batch processing, and fast model updates.",
                comment: "paywall detail subscription expired fallback")
        case .userInitiated:
            return NSLocalizedString(
                "Choose the plan that fits your workflow, manage billing, or restore previous purchases in seconds.",
                comment: "paywall detail manage")
        }
    }

    private func performHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

private struct PaywallViewPreview: View {
    @StateObject private var manager: PaywallManager

    init() {
        let previewContext = PaywallContext(
            model: .parakeetV3,
            accessLevel: .pro,
            availablePlans: [
                .init(
                    id: "monthly",
                    name: "Monthly Subscription",
                    type: .monthly,
                    productIdentifier: SubscriptionProductIDs.monthlyProID,
                    duration: .months(1),
                    priceText: nil
                ),
                .init(
                    id: "annual",
                    name: "Annual Subscription",
                    type: .annual,
                    productIdentifier: SubscriptionProductIDs.annualProID,
                    duration: .years(1),
                    priceText: nil
                ),
                .init(
                    id: "lifetime",
                    name: "Lifetime Unlock",
                    type: .lifetime,
                    productIdentifier: SubscriptionProductIDs.lifetimeProID,
                    duration: .lifetime,
                    priceText: nil
                ),
            ],
            currentSubscription: SubscriptionStatus(
                isProSubscribed: false,
                currentPlan: nil,
                expirationDate: nil,
                isInTrialPeriod: false,
                lastUpdated: Date(),
                isSandbox: true
            ),
            reason: .attemptedPaidModelDownload
        )

        let previewManager = PaywallManager()
        previewManager.loadPreviewContext(previewContext)
        _manager = StateObject(wrappedValue: previewManager)
    }

    var body: some View {
        PaywallView()
            .environmentObject(manager)
            .frame(width: 560, height: 620)
            .padding()
    }
}

#Preview {
    PaywallViewPreview()
}
