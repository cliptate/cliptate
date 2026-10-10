import Foundation
import RevenueCat

@testable import Cliptate

actor TestRevenueCatManager {
    enum TestError: Error { case failure }

    var offerings: [SubscriptionPlan]
    var currentStatus: SubscriptionStatus
    var shouldFailStatusFetch: Bool = false

    private var statusContinuation: AsyncStream<SubscriptionStatus>.Continuation?

    init(offerings: [SubscriptionPlan], currentStatus: SubscriptionStatus) {
        self.offerings = offerings
        self.currentStatus = currentStatus
    }

    func getOfferings() async throws -> [SubscriptionPlan] {
        offerings
    }

    func subscriptionStatus() async throws -> SubscriptionStatus {
        if shouldFailStatusFetch {
            throw TestError.failure
        }
        return currentStatus
    }

    func subscriptionStatusStream() async -> AsyncStream<SubscriptionStatus> {
        AsyncStream { continuation in
            statusContinuation = continuation
            continuation.yield(currentStatus)
        }
    }

    func push(status: SubscriptionStatus) {
        currentStatus = status
        statusContinuation?.yield(status)
    }

    func setShouldFailStatusFetch(_ flag: Bool) {
        shouldFailStatusFetch = flag
    }
}

actor MockPaywallPurchaser: PaywallPurchasing {
    enum Behavior {
        case success
        case cancelled
        case failure(Error)
    }

    var behavior: Behavior = .success
    let statusManager: TestRevenueCatManager
    var successStatus: SubscriptionStatus

    init(statusManager: TestRevenueCatManager, successStatus: SubscriptionStatus) {
        self.statusManager = statusManager
        self.successStatus = successStatus
    }

    func purchasePlan(withIdentifier _: String) async throws -> PaywallPurchaseResult {
        switch behavior {
        case .success:
            await statusManager.push(status: successStatus)
            return PaywallPurchaseResult(userCancelled: false)
        case .cancelled:
            return PaywallPurchaseResult(userCancelled: true)
        case .failure(let error):
            throw error
        }
    }

    func restorePurchases() async throws -> CustomerInfo {
        throw MockPaywallPurchaserError.notImplemented
    }

    enum MockPaywallPurchaserError: Error {
        case notImplemented
    }
}

extension RevenueCatInterface {
    static func test(using manager: TestRevenueCatManager) -> RevenueCatInterface {
        RevenueCatInterface(
            getOfferings: { try await manager.getOfferings() },
            subscriptionStatus: { try await manager.subscriptionStatus() },
            subscriptionStatusStream: { await manager.subscriptionStatusStream() }
        )
    }
}

extension SubscriptionPlan {
    static func testPlan(id: String, type: SubscriptionPlan.PlanType) -> SubscriptionPlan {
        let duration: SubscriptionPlan.PlanDuration
        switch type {
        case .monthly:
            duration = .months(1)
        case .annual:
            duration = .years(1)
        case .lifetime:
            duration = .lifetime
        }

        return SubscriptionPlan(
            id: id,
            name: "Pro \(id.capitalized)",
            type: type,
            productIdentifier: "com.voicepinkpro.sub.\(id)",
            duration: duration,
            priceText: "$9.99"
        )
    }
}

extension SubscriptionStatus {
    static func testInactive() -> SubscriptionStatus {
        SubscriptionStatus(
            isProSubscribed: false,
            currentPlan: nil,
            expirationDate: nil,
            isInTrialPeriod: false,
            lastUpdated: Date(),
            isSandbox: false
        )
    }

    static func testActive(plan: SubscriptionPlan? = nil, expiration: Date? = nil)
        -> SubscriptionStatus
    {
        SubscriptionStatus(
            isProSubscribed: true,
            currentPlan: plan,
            expirationDate: expiration,
            isInTrialPeriod: false,
            lastUpdated: Date(),
            isSandbox: false
        )
    }

    static func testStatus(
        isProSubscribed: Bool,
        currentPlan: SubscriptionPlan? = nil,
        expirationDate: Date? = nil,
        isInTrialPeriod: Bool = false,
        lastUpdated: Date = Date(),
        isSandbox: Bool = false
    ) -> SubscriptionStatus {
        SubscriptionStatus(
            isProSubscribed: isProSubscribed,
            currentPlan: currentPlan,
            expirationDate: expirationDate,
            isInTrialPeriod: isInTrialPeriod,
            lastUpdated: lastUpdated,
            isSandbox: isSandbox
        )
    }
}

enum RevenueCatPackageStubs {
    private final class DummyPackage: NSObject {}

    static let dummy: Package = {
        let placeholder = DummyPackage()
        return unsafeBitCast(placeholder, to: Package.self)
    }()
}
