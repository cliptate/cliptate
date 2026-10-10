import Foundation

/// Billing is available only in App Store builds. Direct distribution is fully free.
enum SubscriptionPolicy {
    static var isBillingEnabled: Bool {
        #if APP_STORE
        true
        #else
        false
        #endif
    }
}

/// Describes a purchasable subscription plan offered in the paywall.
public struct SubscriptionPlan: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let type: PlanType
    public let productIdentifier: String
    public let duration: PlanDuration
    public let priceText: String?

    public enum PlanType: String, Codable, Sendable {
        case monthly
        case annual
        case lifetime
    }

    public enum PlanDuration: Sendable, Codable, Equatable {
        case months(Int)
        case years(Int)
        case lifetime

        public var displayName: String {
            switch self {
            case .months(1): return String(localized: "Monthly", comment: "Subscription billing period: once per month")
            case .months(let value): return String(localized: "Every \(value) months", comment: "Subscription billing period: every N months")
            case .years(1): return String(localized: "Yearly", comment: "Subscription billing period: once per year")
            case .years(let value): return String(localized: "Every \(value) years", comment: "Subscription billing period: every N years")
            case .lifetime: return String(localized: "Lifetime", comment: "Subscription billing period: one-time lifetime purchase")
            }
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case value
        }

        private enum DurationType: String, Codable {
            case months
            case years
            case lifetime
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(DurationType.self, forKey: .type)
            switch type {
            case .months:
                let value = try container.decode(Int.self, forKey: .value)
                self = .months(value)
            case .years:
                let value = try container.decode(Int.self, forKey: .value)
                self = .years(value)
            case .lifetime:
                self = .lifetime
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .months(let value):
                try container.encode(DurationType.months, forKey: .type)
                try container.encode(value, forKey: .value)
            case .years(let value):
                try container.encode(DurationType.years, forKey: .type)
                try container.encode(value, forKey: .value)
            case .lifetime:
                try container.encode(DurationType.lifetime, forKey: .type)
            }
        }
    }
}

/// Represents the active subscription state for the current user.
public struct SubscriptionStatus: Codable, Sendable, Equatable {
    public let isProSubscribed: Bool
    public let currentPlan: SubscriptionPlan?
    public let expirationDate: Date?
    public let isInTrialPeriod: Bool
    public let lastUpdated: Date
    public let isSandbox: Bool

    public init(
        isProSubscribed: Bool,
        currentPlan: SubscriptionPlan?,
        expirationDate: Date?,
        isInTrialPeriod: Bool,
        lastUpdated: Date,
        isSandbox: Bool
    ) {
        self.isProSubscribed = isProSubscribed
        self.currentPlan = currentPlan
        self.expirationDate = expirationDate
        self.isInTrialPeriod = isInTrialPeriod
        self.lastUpdated = lastUpdated
        self.isSandbox = isSandbox
    }

    /// Indicates whether the subscription is currently active.
    public var isActive: Bool {
        guard !isProSubscribed else { return true }
        guard let expirationDate else { return false }
        return Date() < expirationDate
    }

    /// Localized status message describing the current subscription state.
    public var statusText: String {
        if isInTrialPeriod {
            if let expirationDate {
                let days =
                    Calendar.current
                    .dateComponents([.day], from: Date(), to: expirationDate).day ?? 0
                return String(localized: "Trial period remaining \(max(days, 0)) days", comment: "Subscription status: trial with remaining days count")
            }
            return String(localized: "In trial", comment: "Subscription status: in trial period, no expiry date")
        }

        if isProSubscribed {
            if let expirationDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                return String(localized: "Pro valid until \(formatter.string(from: expirationDate))", comment: "Subscription status: Pro active with expiration date")
            }
            return String(localized: "Pro activated", comment: "Subscription status: Pro active with no expiration")
        }

        return String(localized: "Free version", comment: "Subscription status: free tier, not subscribed")
    }
}

/// Result of evaluating whether a model download is permitted.
public struct ModelDownloadPermission: Sendable {
    public let model: ModelVariant
    public let isAllowed: Bool
    public let reason: PermissionDenialReason?

    public init(model: ModelVariant, isAllowed: Bool, reason: PermissionDenialReason? = nil) {
        self.model = model
        self.isAllowed = isAllowed
        self.reason = reason
    }

    public enum PermissionDenialReason: String, Codable, Sendable {
        case requiresProSubscription
        case subscriptionExpired
        case offline
        case loading

        public var message: String {
            switch self {
            case .requiresProSubscription:
                return String(localized: "This model requires Pro subscription", comment: "Model access restriction: requires Pro subscription")
            case .subscriptionExpired:
                return String(localized: "Pro subscription has expired", comment: "Model access restriction: subscription expired")
            case .offline:
                return String(localized: "Offline status, unable to verify permissions", comment: "Model access restriction: offline, cannot verify")
            case .loading:
                return String(localized: "Loading permission information...", comment: "Model access restriction: loading status")
            }
        }
    }
}

/// Context required when presenting the paywall.
public struct PaywallContext: Sendable, Equatable {
    public let model: ModelVariant
    public let accessLevel: ModelAccessLevel
    public let availablePlans: [SubscriptionPlan]
    public let currentSubscription: SubscriptionStatus
    public let reason: PaywallReason

    public init(
        model: ModelVariant,
        accessLevel: ModelAccessLevel,
        availablePlans: [SubscriptionPlan],
        currentSubscription: SubscriptionStatus,
        reason: PaywallReason
    ) {
        self.model = model
        self.accessLevel = accessLevel
        self.availablePlans = availablePlans
        self.currentSubscription = currentSubscription
        self.reason = reason
    }

    public enum PaywallReason: String, Codable, Sendable {
        case attemptedPaidModelDownload
        case subscriptionExpired
        case userInitiated
    }
}

extension SubscriptionPlan {
    var upgradeRank: Int {
        switch type {
        case .monthly:
            return 0
        case .annual:
            return 1
        case .lifetime:
            return 2
        }
    }

    func matches(_ other: SubscriptionPlan) -> Bool {
        id == other.id || productIdentifier == other.productIdentifier
    }

    fileprivate var recommendationPriority: Int {
        switch type {
        case .annual:
            return 0
        case .monthly:
            return 1
        case .lifetime:
            return 2
        }
    }
}

extension PaywallContext {
    var showsModelSummaryCard: Bool {
        reason != .userInitiated
    }

    var renderablePlans: [SubscriptionPlan] {
        guard let currentPlan = currentSubscription.currentPlan else {
            return availablePlans.sorted(by: sortPlansForDisplay)
        }

        var filtered = availablePlans.filter {
            $0.matches(currentPlan) || $0.upgradeRank > currentPlan.upgradeRank
        }

        if filtered.isEmpty {
            return [currentPlan]
        }

        if !filtered.contains(where: { $0.matches(currentPlan) }) {
            filtered.insert(currentPlan, at: 0)
        }

        return filtered.sorted(by: sortPlansForDisplay)
    }

    var selectablePlans: [SubscriptionPlan] {
        let plans = renderablePlans
        guard let currentPlan = currentSubscription.currentPlan else {
            return plans
        }

        return plans.filter {
            !$0.matches(currentPlan) && $0.upgradeRank > currentPlan.upgradeRank
        }
    }

    var recommendedPlan: SubscriptionPlan? {
        let plans = selectablePlans
        guard !plans.isEmpty else { return nil }

        if let currentPlan = currentSubscription.currentPlan,
            let lifetimeUpgrade = plans.first(where: {
                $0.type == .lifetime && $0.upgradeRank > currentPlan.upgradeRank
            })
        {
            return lifetimeUpgrade
        }

        return plans.min {
            if $0.recommendationPriority == $1.recommendationPriority {
                return $0.upgradeRank < $1.upgradeRank
            }
            return $0.recommendationPriority < $1.recommendationPriority
        }
    }

    private func sortPlansForDisplay(_ lhs: SubscriptionPlan, _ rhs: SubscriptionPlan) -> Bool {
        if let currentPlan = currentSubscription.currentPlan {
            let lhsCurrent = lhs.matches(currentPlan)
            let rhsCurrent = rhs.matches(currentPlan)
            if lhsCurrent != rhsCurrent {
                return lhsCurrent
            }
        }

        if lhs.recommendationPriority == rhs.recommendationPriority {
            return lhs.upgradeRank < rhs.upgradeRank
        }
        return lhs.recommendationPriority < rhs.recommendationPriority
    }
}

/// Cached subscription snapshot used for offline validation.
public struct SubscriptionCacheData: Codable, Sendable {
    public let status: SubscriptionStatus
    public let timestamp: Date

    public init(status: SubscriptionStatus, timestamp: Date) {
        self.status = status
        self.timestamp = timestamp
    }

    /// Cache remains valid for 12 hours.
    public var isValid: Bool {
        Date().timeIntervalSince(timestamp) < 12 * 3600
    }
}

/// Cached subscription plans snapshot used when the device is offline.
public struct SubscriptionPlansCacheData: Codable, Sendable {
    public static let cacheLifetime: TimeInterval = 30 * 60

    public let plans: [SubscriptionPlan]
    public let timestamp: Date

    public init(plans: [SubscriptionPlan], timestamp: Date) {
        self.plans = plans
        self.timestamp = timestamp
    }

    /// Cache remains valid for 30 minutes.
    public var isValid: Bool {
        Date().timeIntervalSince(timestamp) < Self.cacheLifetime
    }
}

/// Storage keys for subscription-related values.
public enum SubscriptionKeys {
    public static let subscriptionCacheKey = "com.voicepinkpro.subscription.cache"
    public static let lastKnownSubscriptionKey = "com.voicepinkpro.subscription.last"
    public static let hasSeenPaywallKey = "com.voicepinkpro.paywall.seen"
    public static let subscriptionRejectionCountKey = "com.voicepinkpro.subscription.reject_count"
    public static let paywallLastPresentedDateKey = "com.voicepinkpro.paywall.last_presented"
    public static let subscriptionPlansCacheKey = "com.voicepinkpro.subscription.plans"
}

/// Product identifiers registered in App Store Connect.
public enum SubscriptionProductIDs {
    public static let monthlyProID = "com.voicepinkpro.sub.monthly"
    public static let annualProID = "com.voicepinkpro.sub.annual"
    public static let lifetimeProID = "com.voicepinkpro.sub.lifetime"

    public static let allProductIDs: [String] = [monthlyProID, annualProID, lifetimeProID]
}

/// RevenueCat entitlement identifiers used for subscription access.
public enum SubscriptionEntitlements {
    public static let proAccess = "Pro"
}

/// Typed errors raised by subscription-related operations.
public enum SubscriptionError: LocalizedError {
    case notInitialized
    case initializationFailed(String)
    case offeringsUnavailable
    case networkUnavailable
    case networkError(String)
    case receiptAlreadyInUse
    case paymentPending
    case purchaseCancelled
    case productAlreadyPurchased
    case permissionCheckFailed(String)
    case sdkError(String)

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return String(localized: "Subscription services are not initialized yet.", comment: "Subscription error: services not ready")
        case .initializationFailed(let message):
            return String(localized: "RevenueCat initialization failed: \(message)", comment: "Subscription error: RevenueCat init failure with detail")
        case .offeringsUnavailable:
            return String(localized: "Unable to load subscription plans. Please try again later.", comment: "Subscription error: plans unavailable")
        case .networkUnavailable:
            return String(localized: "Network connection appears to be offline. Please reconnect and retry.", comment: "Subscription error: device offline")
        case .networkError(let detail):
            return detail
        case .receiptAlreadyInUse:
            return String(localized: "This purchase receipt is already associated with another account.", comment: "Subscription error: receipt already used by another account")
        case .paymentPending:
            return String(localized: "Your payment is pending. Please check again in a moment.", comment: "Subscription error: payment pending")
        case .purchaseCancelled:
            return String(localized: "Purchase was cancelled.", comment: "Subscription error: user cancelled purchase")
        case .productAlreadyPurchased:
            return String(localized: "You already own this subscription on this Apple ID.", comment: "Subscription error: already purchased on this account")
        case .permissionCheckFailed(let detail):
            return String(localized: "Unable to verify subscription permissions: \(detail)", comment: "Subscription error: permission check failed with detail")
        case .sdkError(let detail):
            return detail
        }
    }
}

extension SubscriptionError: Equatable {
    public static func == (lhs: SubscriptionError, rhs: SubscriptionError) -> Bool {
        switch (lhs, rhs) {
        case (.notInitialized, .notInitialized),
            (.offeringsUnavailable, .offeringsUnavailable),
            (.networkUnavailable, .networkUnavailable),
            (.receiptAlreadyInUse, .receiptAlreadyInUse),
            (.paymentPending, .paymentPending),
            (.purchaseCancelled, .purchaseCancelled),
            (.productAlreadyPurchased, .productAlreadyPurchased):
            return true
        case (.initializationFailed(let a), .initializationFailed(let b)):
            return a == b
        case (.networkError(let a), .networkError(let b)):
            return a == b
        case (.permissionCheckFailed(let a), .permissionCheckFailed(let b)):
            return a == b
        case (.sdkError(let a), .sdkError(let b)):
            return a == b
        default:
            return false
        }
    }
}
