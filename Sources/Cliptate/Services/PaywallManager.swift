import CliptateCore
import Combine
import Foundation
import OSLog
import RevenueCat

/// Result returned by a purchasing client when attempting to buy a plan.
struct PaywallPurchaseResult: Sendable, Equatable {
    let userCancelled: Bool
}

/// Errors surfaced when the paywall cannot progress purchases.
enum PaywallPurchaseError: LocalizedError, Equatable {
    case contextMissing
    case packageUnavailable

    var errorDescription: String? {
        switch self {
        case .contextMissing:
            return NSLocalizedString(
                "Unable to get payment information, please reopen the paywall.",
                comment: "missing paywall context")
        case .packageUnavailable:
            return NSLocalizedString(
                "No purchasable subscription options found.", comment: "package unavailable")
        }
    }
}

/// Minimal purchasing surface that PaywallManager depends on.
protocol PaywallPurchasing: AnyObject, Sendable {
    func purchasePlan(withIdentifier identifier: String) async throws -> PaywallPurchaseResult
    func restorePurchases() async throws -> CustomerInfo
}

/// Observable controller that orchestrates paywall presentation and purchase flow.
@MainActor
final class PaywallManager: ObservableObject {
    static let shared = PaywallManager()

    @Published private(set) var isPresented: Bool = false
    @Published private(set) var context: PaywallContext?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isPurchasing: Bool = false
    @Published private(set) var isRestoring: Bool = false
    @Published private(set) var latestPurchaseEvent: PurchaseEvent?
    @Published var errorMessage: String?

    private let modelAccessController: ModelAccessController
    private let purchasingClient: PaywallPurchasing
    private let logger = Logger(subsystem: "com.Cliptate", category: "PaywallManager")

    private let maxDailyPresentations = 2
    private let presentationInterval: TimeInterval = 24 * 3600
    private var presentationCount: Int {
        get { userDefaults.integer(forKey: SubscriptionKeys.subscriptionRejectionCountKey) }
        set { userDefaults.set(newValue, forKey: SubscriptionKeys.subscriptionRejectionCountKey) }
    }
    private var lastPresentationDate: Date? {
        get { userDefaults.object(forKey: SubscriptionKeys.paywallLastPresentedDateKey) as? Date }
        set { userDefaults.set(newValue, forKey: SubscriptionKeys.paywallLastPresentedDateKey) }
    }

    private let userDefaults: UserDefaults

    init(
        modelAccessController: ModelAccessController = .shared,
        purchasingClient: PaywallPurchasing = RevenueCatManager.shared,
        userDefaults: UserDefaults = .standard
    ) {
        self.modelAccessController = modelAccessController
        self.purchasingClient = purchasingClient
        self.userDefaults = userDefaults
    }

    /// Attempts to present the paywall for a specific model. Returns `true` if presented.
    @discardableResult
    func showPaywall(
        for model: ModelVariant, reason: PaywallContext.PaywallReason = .attemptedPaidModelDownload
    ) async -> Bool {
        guard SubscriptionPolicy.isBillingEnabled else { return false }
        await resetIfNeeded()

        let isManualPresentation = reason == .userInitiated

        if !isManualPresentation {
            let requiresProAccess = await modelAccessController.requiresProAccess(model: model)
            if !requiresProAccess {
                logger.debug("Paywall not required for model \(model.rawValue, privacy: .public)")
                return false
            }

            do {
                let canDownload = try await modelAccessController.canDownloadModel(model)
                guard !canDownload else {
                    logger.debug("Model already downloadable, skipping paywall")
                    return false
                }
            } catch {
                logger.warning(
                    "Permission check failed: \(error.localizedDescription, privacy: .public). Proceeding with paywall display as fallback."
                )
            }
        }

        guard canPresentPaywall() else {
            logger.info("Paywall frequency limit reached")
            errorMessage = NSLocalizedString(
                "Daily paywall display limit reached, please try again later.",
                comment: "paywall frequency limit")
            return false
        }

        // Present the sheet immediately so the user sees it open without delay.
        // Context/plan fetching continues in the background while isLoading drives the
        // loading indicator inside PaywallView.
        isLoading = true
        isPresented = true
        errorMessage = nil

        do {
            let generatedContext = try await modelAccessController.getPaywallContext(for: model)
            context = PaywallContext(
                model: generatedContext.model,
                accessLevel: generatedContext.accessLevel,
                availablePlans: try await fetchPlansIfEmpty(using: generatedContext.availablePlans),
                currentSubscription: generatedContext.currentSubscription,
                reason: reason
            )
            isLoading = false
            registerPresentation()
            if let activeContext = context {
                emitAnalyticsEvent(
                    PaywallAnalyticsEvent(
                        kind: .presented,
                        context: activeContext,
                        subscriptionStatus: activeContext.currentSubscription
                    )
                )
            }
            return true
        } catch {
            isLoading = false
            // Keep the sheet open to show the error; dismiss only if nothing to display.
            if context == nil {
                isPresented = false
            }
            logger.error(
                "Failed to build paywall context: \(error.localizedDescription, privacy: .public)")
            errorMessage = localizedMessage(from: error)
            return false
        }
    }

    /// Dismisses the currently presented paywall.
    func dismissPaywall() {
        let previousContext = context
        isPresented = false
        context = nil
        isLoading = false
        isPurchasing = false
        isRestoring = false
        emitAnalyticsEvent(
            PaywallAnalyticsEvent(
                kind: .dismissed,
                context: previousContext,
                subscriptionStatus: previousContext?.currentSubscription
            )
        )
    }

    /// Refreshes the current paywall context without affecting presentation limits.
    @discardableResult
    func refreshContext() async -> Bool {
        guard let currentContext = context else { return false }

        isLoading = true
        defer { isLoading = false }

        do {
            let updatedContext = try await modelAccessController.getPaywallContext(
                for: currentContext.model)
            context = PaywallContext(
                model: updatedContext.model,
                accessLevel: updatedContext.accessLevel,
                availablePlans: try await fetchPlansIfEmpty(using: updatedContext.availablePlans),
                currentSubscription: updatedContext.currentSubscription,
                reason: currentContext.reason
            )
            errorMessage = nil
            return true
        } catch {
            logger.error(
                "Failed to refresh paywall context: \(error.localizedDescription, privacy: .public)"
            )
            errorMessage = localizedMessage(from: error)
            return false
        }
    }

    /// Processes a purchase for the selected plan.
    @discardableResult
    func processPurchase(plan: SubscriptionPlan) async throws -> Bool {
        guard let currentContext = context else { throw PaywallPurchaseError.contextMissing }

        isPurchasing = true
        clearError()

        defer { isPurchasing = false }

        do {
            let result = try await purchasingClient.purchasePlan(withIdentifier: plan.id)
            if result.userCancelled {
                recordPurchaseEvent(
                    outcome: .cancelled,
                    plan: plan,
                    context: currentContext,
                    message: NSLocalizedString("Purchase cancelled.", comment: "purchase cancelled")
                )
                return false
            }

            let refreshedStatus = try await modelAccessController.getCurrentSubscriptionStatus(
                forceRefresh: true)
            context = PaywallContext(
                model: currentContext.model,
                accessLevel: currentContext.accessLevel,
                availablePlans: currentContext.availablePlans,
                currentSubscription: refreshedStatus,
                reason: currentContext.reason
            )

            recordPurchaseEvent(
                outcome: .success(status: refreshedStatus),
                plan: plan,
                context: currentContext,
                message: NSLocalizedString(
                    "Pro permission activated, you can download all models.",
                    comment: "purchase success")
            )

            dismissPaywall()
            return true
        } catch {
            let message = purchaseErrorMessage(from: error)
            errorMessage = message
            recordPurchaseEvent(
                outcome: .failure(message: message),
                plan: plan,
                context: currentContext,
                message: message
            )
            throw error
        }
    }

    @discardableResult
    func restorePurchases() async -> RestorationResult {
        guard !isRestoring else {
            return RestorationResult(success: false, status: nil, errorMessage: nil)
        }

        isRestoring = true
        defer { isRestoring = false }

        do {
            _ = try await purchasingClient.restorePurchases()
            let refreshedStatus = try await modelAccessController.getCurrentSubscriptionStatus(
                forceRefresh: true)

            var updatedContext: PaywallContext?
            if let currentContext = context {
                let refreshedContext = PaywallContext(
                    model: currentContext.model,
                    accessLevel: currentContext.accessLevel,
                    availablePlans: currentContext.availablePlans,
                    currentSubscription: refreshedStatus,
                    reason: currentContext.reason
                )
                context = refreshedContext
                updatedContext = refreshedContext
            }

            if updatedContext == nil {
                updatedContext = context
            }

            errorMessage = nil
            emitAnalyticsEvent(
                PaywallAnalyticsEvent(
                    kind: .restoreSucceeded,
                    context: updatedContext,
                    subscriptionStatus: refreshedStatus
                )
            )
            return RestorationResult(success: true, status: refreshedStatus, errorMessage: nil)
        } catch {
            let message = purchaseErrorMessage(from: error)
            errorMessage = message
            emitAnalyticsEvent(
                PaywallAnalyticsEvent(
                    kind: .restoreFailed,
                    context: context,
                    subscriptionStatus: context?.currentSubscription,
                    message: message
                )
            )
            return RestorationResult(success: false, status: nil, errorMessage: message)
        }
    }

    func consumeLatestPurchaseEvent(_ id: UUID) {
        if latestPurchaseEvent?.id == id {
            latestPurchaseEvent = nil
        }
    }

    /// Clears any recorded errors.
    func clearError() {
        errorMessage = nil
    }

    /// Resets frequency limiting counters.
    func resetPresentationLimits() {
        presentationCount = 0
        lastPresentationDate = nil
    }

    // MARK: - Helpers

    private func canPresentPaywall() -> Bool {
        // Removed frequency limit - always allow paywall presentation
        return true
    }

    private func registerPresentation() {
        presentationCount = min(maxDailyPresentations, presentationCount + 1)
        lastPresentationDate = Date()
        userDefaults.set(true, forKey: SubscriptionKeys.hasSeenPaywallKey)
    }

    private func fetchPlansIfEmpty(using plans: [SubscriptionPlan]) async throws
        -> [SubscriptionPlan]
    {
        do {
            let refreshed =
                try await modelAccessController.getAvailableSubscriptionPlans(forceRefresh: true)
            if refreshed.isEmpty {
                return plans
            }
            return refreshed
        } catch {
            logger.error(
                "Failed to refresh subscription plans: \(error.localizedDescription, privacy: .public)"
            )
            if !plans.isEmpty {
                return plans
            }
            throw error
        }
    }

    private func localizedMessage(from error: Error) -> String {
        if let localizedError = error as? LocalizedError,
            let description = localizedError.errorDescription
        {
            return description
        }
        return NSLocalizedString(
            "Failed to get subscription information, please try again later.",
            comment: "generic paywall error")
    }

    private func purchaseErrorMessage(from error: Error) -> String {
        switch error {
        case PaywallPurchaseError.packageUnavailable:
            return NSLocalizedString(
                "No purchasable subscription plan found, please try again later.",
                comment: "missing package error")
        case PaywallPurchaseError.contextMissing:
            return NSLocalizedString(
                "Payment information missing, please reopen the paywall.",
                comment: "missing context error")
        case let subscriptionError as SubscriptionError:
            return subscriptionError.errorDescription
                ?? NSLocalizedString(
                    "Operation not completed, please try again later.",
                    comment: "subscription error fallback")
        case ErrorCode.paymentPendingError:
            return NSLocalizedString(
                "Payment is being processed, please check subscription status later.",
                comment: "payment pending")
        case ErrorCode.productAlreadyPurchasedError:
            return NSLocalizedString(
                "You already own this subscription.", comment: "already purchased")
        case ErrorCode.purchaseCancelledError:
            return NSLocalizedString("Purchase cancelled.", comment: "purchase cancelled")
        default:
            if let localized = (error as NSError).localizedFailureReason {
                return localized
            }
            return NSLocalizedString(
                "Purchase failed, please try again later.", comment: "generic purchase error")
        }
    }

    private func recordPurchaseEvent(
        outcome: PurchaseEvent.Outcome,
        plan: SubscriptionPlan,
        context: PaywallContext,
        message: String?
    ) {
        latestPurchaseEvent = PurchaseEvent(
            id: UUID(),
            model: context.model,
            plan: plan,
            outcome: outcome,
            message: message,
            timestamp: Date()
        )
        switch outcome {
        case .success(let status):
            emitAnalyticsEvent(
                PaywallAnalyticsEvent(
                    kind: .purchaseSucceeded,
                    context: context,
                    plan: plan,
                    subscriptionStatus: status,
                    message: message
                )
            )
        case .cancelled:
            emitAnalyticsEvent(
                PaywallAnalyticsEvent(
                    kind: .purchaseCancelled,
                    context: context,
                    plan: plan,
                    subscriptionStatus: context.currentSubscription,
                    message: message
                )
            )
        case .failure(let failureMessage):
            emitAnalyticsEvent(
                PaywallAnalyticsEvent(
                    kind: .purchaseFailed,
                    context: context,
                    plan: plan,
                    subscriptionStatus: context.currentSubscription,
                    message: failureMessage
                )
            )
        }
    }

    private func emitAnalyticsEvent(_ event: PaywallAnalyticsEvent) {
        NotificationCenter.default.post(
            name: .paywallEventDidOccur,
            object: self,
            userInfo: [PaywallAnalyticsPayloadKey.event: event]
        )
        logger.debug("Paywall analytics event \(event.kind.rawValue, privacy: .public)")
    }

    private func resetIfNeeded() async {
        guard let last = lastPresentationDate else {
            presentationCount = 0
            return
        }

        if Date().timeIntervalSince(last) >= presentationInterval {
            presentationCount = 0
            lastPresentationDate = nil
        }
    }
}

extension PaywallManager {
    struct PurchaseEvent: Identifiable, Equatable {
        enum Outcome: Equatable {
            case success(status: SubscriptionStatus)
            case cancelled
            case failure(message: String)
        }

        let id: UUID
        let model: ModelVariant
        let plan: SubscriptionPlan
        let outcome: Outcome
        let message: String?
        let timestamp: Date
    }
}

extension PaywallManager {
    struct RestorationResult {
        let success: Bool
        let status: SubscriptionStatus?
        let errorMessage: String?
    }
}

extension PaywallManager {
    /// Loads a synthetic context for SwiftUI previews.
    func loadPreviewContext(_ context: PaywallContext, errorMessage: String? = nil) {
        self.context = context
        self.errorMessage = errorMessage
        isPresented = true
        isLoading = false
    }
}
