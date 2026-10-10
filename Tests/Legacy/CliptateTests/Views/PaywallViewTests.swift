import Foundation
import SwiftUI
import Testing

@testable import Cliptate

#if os(macOS)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

@Suite("PaywallView display flow")
@MainActor
struct PaywallViewDisplayTests {
    @Test
    func presentingPaywallProvidesExpectedPlans() async {
        let (manager, mock, defaults) = await makeManager(suite: "PaywallViewTests.present")
        defer { defaults.removePersistentDomain(forName: "PaywallViewTests.present") }

        let presented = await manager.showPaywall(for: .parakeetV2, reason: .userInitiated)

        let mockOfferings = await mock.offerings
        let mockCurrentStatus = await mock.currentStatus
        #expect(presented)
        #expect(manager.isPresented)
        #expect(manager.context?.availablePlans == mockOfferings)
        #expect(manager.context?.model == .parakeetV2)
        #expect(manager.context?.currentSubscription == mockCurrentStatus)

        renderPaywall(using: manager)

        manager.dismissPaywall()

        #expect(manager.isPresented == false)
        #expect(manager.context == nil)
    }

    @Test
    func refreshContextKeepsSheetVisible() async {
        let (manager, mock, defaults) = await makeManager(suite: "PaywallViewTests.refresh")
        defer { defaults.removePersistentDomain(forName: "PaywallViewTests.refresh") }

        let presented = await manager.showPaywall(for: .parakeetV3, reason: .userInitiated)
        #expect(presented)

        renderPaywall(using: manager)

        let refreshed = await manager.refreshContext()
        let mockOfferingsCount = await mock.offerings.count
        #expect(refreshed)
        #expect(manager.isPresented)
        #expect(manager.context?.availablePlans.count == mockOfferingsCount)

        manager.dismissPaywall()
        #expect(manager.isPresented == false)
    }

    @Test
    func recommendedPlanPrefersAnnualForNewSubscriptions() {
        let context = PaywallContext(
            model: .parakeetV3,
            accessLevel: .pro,
            availablePlans: [
                .testPlan(id: "lifetime", type: .lifetime),
                .testPlan(id: "monthly", type: .monthly),
                .testPlan(id: "annual", type: .annual),
            ],
            currentSubscription: .testInactive(),
            reason: .attemptedPaidModelDownload
        )

        #expect(context.recommendedPlan?.type == .annual)
    }

    private func renderPaywall(using manager: PaywallManager) {
        #if os(macOS)
            let controller = NSHostingController(rootView: PaywallView().environmentObject(manager))
            controller.view.layoutSubtreeIfNeeded()
        #else
            let controller = UIHostingController(rootView: PaywallView().environmentObject(manager))
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
        #endif
        _ = controller
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
        let status = SubscriptionStatus.testInactive()
        let mock = TestRevenueCatManager(offerings: plans, currentStatus: status)

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
