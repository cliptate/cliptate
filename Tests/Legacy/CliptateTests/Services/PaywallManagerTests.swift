import Foundation
import Testing

@testable import Cliptate

@Suite("PaywallManager state management")
@MainActor
struct PaywallManagerStateTests {
    @Test
    func showPaywallUpdatesPresentationState() async {
        let (manager, mock, defaults) = await makeManager(suite: "PaywallManagerTests.show")
        defer { defaults.removePersistentDomain(forName: "PaywallManagerTests.show") }

        let presented = await manager.showPaywall(for: .parakeetV2, reason: .userInitiated)

        #expect(presented)
        #expect(manager.isPresented)
        #expect(manager.context?.model == .parakeetV2)
        #expect(manager.context?.availablePlans == (await mock.offerings))
        #expect(manager.context?.currentSubscription == (await mock.currentStatus))
        #expect(manager.context?.reason == .userInitiated)
        #expect(manager.errorMessage == nil)
    }

    @Test
    func dismissPaywallClearsState() async {
        let (manager, _, defaults) = await makeManager(suite: "PaywallManagerTests.dismiss")
        defer { defaults.removePersistentDomain(forName: "PaywallManagerTests.dismiss") }

        let presented = await manager.showPaywall(for: .parakeetV2, reason: .userInitiated)
        #expect(presented)
        manager.dismissPaywall()

        #expect(manager.isPresented == false)
        #expect(manager.context == nil)
        #expect(manager.errorMessage == nil)
    }

    @Test
    func frequencyLimitPreventsThirdPresentationWithinADay() async {
        let (manager, _, defaults) = await makeManager(suite: "PaywallManagerTests.limit")
        defer { defaults.removePersistentDomain(forName: "PaywallManagerTests.limit") }

        if let restrictedModel = ModelVariant.proModels.first {
            let first = await manager.showPaywall(for: restrictedModel)
            #expect(first)
            manager.dismissPaywall()

            let second = await manager.showPaywall(for: restrictedModel)
            #expect(second)
            manager.dismissPaywall()

            let third = await manager.showPaywall(for: restrictedModel)
            #expect(third == false)
            #expect(manager.isPresented == false)
            #expect(manager.errorMessage != nil)
        } else {
            #expect(ModelVariant.proModels.isEmpty)
            let first = await manager.showPaywall(for: .parakeetV2, reason: .userInitiated)
            #expect(first)
            manager.dismissPaywall()

            let second = await manager.showPaywall(for: .base, reason: .userInitiated)
            #expect(second)
            manager.dismissPaywall()

            let third = await manager.showPaywall(for: .baseEn, reason: .userInitiated)
            #expect(third)
            #expect(manager.isPresented)
            #expect(manager.errorMessage == nil)
        }
    }

    private func makeManager(suite: String) async -> (
        PaywallManager, TestRevenueCatManager, UserDefaults
    ) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let plans: [SubscriptionPlan] = [
            .testPlan(id: "monthly", type: .monthly),
            .testPlan(id: "annual", type: .annual),
            .testPlan(id: "lifetime", type: .lifetime),
        ]
        let mockStatus = SubscriptionStatus.testInactive()
        let mock = TestRevenueCatManager(offerings: plans, currentStatus: mockStatus)

        let accessController = ModelAccessController(
            revenueCat: .test(using: mock),
            userDefaults: defaults
        )

        let manager = PaywallManager(
            modelAccessController: accessController,
            userDefaults: defaults
        )
        manager.resetPresentationLimits()

        return (manager, mock, defaults)
    }
}
