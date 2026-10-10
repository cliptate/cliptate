import Foundation
import Testing

@testable import Cliptate

@Suite("Purchase flow integration")
@MainActor
struct PurchaseFlowIntegrationTests {
    @Test
    func purchasingUnlocksModelAccess() async throws {
        let suiteName = "PurchaseFlowIntegrationTests.success"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let plans: [SubscriptionPlan] = [
            .testPlan(id: "monthly", type: .monthly),
            .testPlan(id: "annual", type: .annual),
        ]

        let inactiveStatus = SubscriptionStatus.testInactive()
        let activeStatus = SubscriptionStatus.testActive(
            plan: plans.first, expiration: Date().addingTimeInterval(3600))
        let revenueCatMock = TestRevenueCatManager(offerings: plans, currentStatus: inactiveStatus)

        let accessController = ModelAccessController(
            revenueCat: .test(using: revenueCatMock),
            userDefaults: defaults
        )

        let purchaser = MockPaywallPurchaser(
            statusManager: revenueCatMock,
            successStatus: activeStatus
        )

        let manager = PaywallManager(
            modelAccessController: accessController,
            purchasingClient: purchaser,
            userDefaults: defaults
        )
        manager.resetPresentationLimits()

        let presented = await manager.showPaywall(for: .parakeetV2, reason: .userInitiated)
        #expect(presented)

        guard let targetPlan = plans.first else {
            Issue.record("No plans available for purchase")
            return
        }

        let succeeded = try await manager.processPurchase(plan: targetPlan)
        #expect(succeeded)

        // Wait for ModelAccessController to receive the subscription status update.
        try await Task.sleep(nanoseconds: 50_000_000)

        let permission = try await accessController.checkPermission(for: .parakeetV2)
        #expect(permission.isAllowed)

        guard let event = manager.latestPurchaseEvent else {
            Issue.record("Expected purchase event to be recorded")
            return
        }

        #expect(event.plan == targetPlan)
        #expect(event.model == .parakeetV2)
        switch event.outcome {
        case .success(let status):
            #expect(status.isProSubscribed)
        default:
            Issue.record("Expected success status in purchase event outcome")
        }
    }

    @Test
    func subscriptionPersistsOfflineAndResyncs() async throws {
        let suiteName = "PurchaseFlowIntegrationTests.offline"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let plans: [SubscriptionPlan] = [
            .testPlan(id: "monthly", type: .monthly),
            .testPlan(id: "annual", type: .annual),
        ]

        let inactiveStatus = SubscriptionStatus.testInactive()
        let activeStatus = SubscriptionStatus.testActive(
            plan: plans.first,
            expiration: Date().addingTimeInterval(3600)
        )
        let revenueCatMock = TestRevenueCatManager(offerings: plans, currentStatus: inactiveStatus)

        let accessController = ModelAccessController(
            revenueCat: .test(using: revenueCatMock),
            userDefaults: defaults
        )

        let purchaser = MockPaywallPurchaser(
            statusManager: revenueCatMock,
            successStatus: activeStatus
        )

        let manager = PaywallManager(
            modelAccessController: accessController,
            purchasingClient: purchaser,
            userDefaults: defaults
        )
        manager.resetPresentationLimits()

        let presented = await manager.showPaywall(for: .parakeetV3, reason: .userInitiated)
        #expect(presented)

        guard let targetPlan = plans.first else {
            Issue.record("No plans available for purchase")
            return
        }

        let success = try await manager.processPurchase(plan: targetPlan)
        #expect(success)

        try await Task.sleep(nanoseconds: 50_000_000)

        await revenueCatMock.setShouldFailStatusFetch(true)

        let offlineStatus = try await accessController.getCurrentSubscriptionStatus(
            forceRefresh: true)
        #expect(offlineStatus.isProSubscribed)

        let offlinePermission = try await accessController.checkPermission(for: .parakeetV3)
        #expect(offlinePermission.isAllowed)

        let rehydratedController = ModelAccessController(
            revenueCat: .test(using: revenueCatMock),
            userDefaults: defaults
        )

        let cachedStatus = try await rehydratedController.getCurrentSubscriptionStatus()
        #expect(cachedStatus.isProSubscribed)

        await revenueCatMock.setShouldFailStatusFetch(false)
        await revenueCatMock.push(status: activeStatus)

        let refreshedStatus = try await rehydratedController.getCurrentSubscriptionStatus(
            forceRefresh: true)
        #expect(refreshedStatus.isProSubscribed)

        let refreshedPermission = try await rehydratedController.checkPermission(for: .parakeetV3)
        #expect(refreshedPermission.isAllowed)
    }
}
