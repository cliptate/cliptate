import Foundation

struct PaywallAnalyticsEvent: Sendable {
    enum Kind: String, Sendable {
        case presented
        case dismissed
        case purchaseSucceeded
        case purchaseFailed
        case purchaseCancelled
        case restoreSucceeded
        case restoreFailed
    }

    let kind: Kind
    let context: PaywallContext?
    let plan: SubscriptionPlan?
    let subscriptionStatus: SubscriptionStatus?
    let message: String?
    let timestamp: Date

    init(
        kind: Kind,
        context: PaywallContext?,
        plan: SubscriptionPlan? = nil,
        subscriptionStatus: SubscriptionStatus? = nil,
        message: String? = nil,
        timestamp: Date = Date()
    ) {
        self.kind = kind
        self.context = context
        self.plan = plan
        self.subscriptionStatus = subscriptionStatus
        self.message = message
        self.timestamp = timestamp
    }
}

enum PaywallAnalyticsPayloadKey {
    static let event = "paywallEvent"
}

extension Notification.Name {
    static let paywallEventDidOccur = Notification.Name("PaywallEventDidOccur")
}
