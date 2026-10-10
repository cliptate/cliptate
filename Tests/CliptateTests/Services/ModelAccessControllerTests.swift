import Foundation
import Testing

@testable import Cliptate

private actor MockRevenueCatManager {
    enum MockError: Error { case failure }

    var offerings: [SubscriptionPlan]
    var currentStatus: SubscriptionStatus
    var shouldFailStatusFetch: Bool = false
    var shouldFailOfferings: Bool = false
    var offeringsFetchCount: Int = 0

    private var streamContinuation: AsyncStream<SubscriptionStatus>.Continuation?

    init(
        offerings: [SubscriptionPlan] = [],
        currentStatus: SubscriptionStatus
    ) {
        self.offerings = offerings
        self.currentStatus = currentStatus
    }

    func getOfferings() async throws -> [SubscriptionPlan] {
        offeringsFetchCount += 1
        if shouldFailOfferings {
            throw MockError.failure
        }
        return offerings
    }

    func subscriptionStatus() async throws -> SubscriptionStatus {
        if shouldFailStatusFetch {
            throw MockError.failure
        }
        return currentStatus
    }

    func subscriptionStatusStream() async -> AsyncStream<SubscriptionStatus> {
        AsyncStream { continuation in
            streamContinuation = continuation
            continuation.yield(currentStatus)
        }
    }

    func push(status: SubscriptionStatus) {
        currentStatus = status
        streamContinuation?.yield(status)
    }

    func setShouldFailStatusFetch(_ flag: Bool) {
        shouldFailStatusFetch = flag
    }

    func setShouldFailOfferings(_ flag: Bool) {
        shouldFailOfferings = flag
    }

    func currentOfferingsFetchCount() -> Int {
        offeringsFetchCount
    }
}

extension RevenueCatInterface {
    fileprivate static func mock(using manager: MockRevenueCatManager) -> RevenueCatInterface {
        RevenueCatInterface(
            getOfferings: { try await manager.getOfferings() },
            subscriptionStatus: { try await manager.subscriptionStatus() },
            subscriptionStatusStream: { await manager.subscriptionStatusStream() }
        )
    }
}

extension SubscriptionPlan {
    fileprivate static func mock(id: String = "monthly") -> SubscriptionPlan {
        SubscriptionPlan(
            id: id,
            name: "Pro Plan",
            type: .monthly,
            productIdentifier: SubscriptionProductIDs.monthlyProID,
            duration: .months(1),
            priceText: "$4.99"
        )
    }
}

extension SubscriptionStatus {
    fileprivate static func inactive() -> SubscriptionStatus {
        SubscriptionStatus(
            isProSubscribed: false,
            currentPlan: nil,
            expirationDate: nil,
            isInTrialPeriod: false,
            lastUpdated: Date(),
            isSandbox: false
        )
    }

    fileprivate static func active(plan: SubscriptionPlan = .mock(), expiration: Date? = nil)
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
}

private func makeDefaults(suite: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

private func clearDefaults(suite: String) {
    UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
}

@Suite("ModelAccessController permission checks")
struct ModelAccessControllerPermissionTests {
    @Test
    func freeModelsAlwaysAllowed() async throws {
        let suite = "ModelAccessControllerTests.free"
        let defaults = makeDefaults(suite: suite)
        defer { clearDefaults(suite: suite) }

        let mock = MockRevenueCatManager(currentStatus: .inactive())
        let controller = ModelAccessController(
            revenueCat: .mock(using: mock),
            userDefaults: defaults
        )

        #expect(try await controller.canDownloadModel(.parakeetV2))
        #expect(try await controller.canDownloadModel(.parakeetV2))
        #expect(try await controller.canDownloadModel(.qwen3ASR))
        #expect(try await controller.canDownloadModel(.sileroVAD))
    }

    @Test
    func premiumModelsRequireActiveSubscription() async throws {
        let suite = "ModelAccessControllerTests.allFree"
        let defaults = makeDefaults(suite: suite)
        defer { clearDefaults(suite: suite) }

        let mock = MockRevenueCatManager(currentStatus: .inactive())
        let controller = ModelAccessController(
            revenueCat: .mock(using: mock),
            userDefaults: defaults
        )

        #expect(try await controller.canDownloadModel(.parakeetV2))
        #expect(try await controller.canDownloadModel(.parakeetV3) == false)
        #expect(try await controller.canDownloadModel(.fireRedASR2) == false)
        #expect(try await controller.canDownloadModel(.sortformerStreaming) == false)
        let cohereModel = try #require(ModelVariant(rawValue: "cohere-transcribe-03-2026-mlx-8bit"))
        #expect(try await controller.canDownloadModel(cohereModel) == false)
    }

    @Test
    func offlineFallsBackToCachedStatus() async throws {
        let suite = "ModelAccessControllerTests.offline"
        let defaults = makeDefaults(suite: suite)
        defer { clearDefaults(suite: suite) }

        let mock = MockRevenueCatManager(currentStatus: .active())
        let controller = ModelAccessController(
            revenueCat: .mock(using: mock),
            userDefaults: defaults
        )

        #expect(try await controller.canDownloadModel(.parakeetV2))

        await mock.setShouldFailStatusFetch(true)

        #expect(try await controller.canDownloadModel(.parakeetV2))
    }

    @Test
    func cachedPlansUsedWhenOffline() async throws {
        let suite = "ModelAccessControllerTests.planCache"
        let defaults = makeDefaults(suite: suite)
        defer { clearDefaults(suite: suite) }

        let plans: [SubscriptionPlan] = [
            .mock(id: "monthly"), .mock(id: "annual"),
        ]
        let onlineManager = MockRevenueCatManager(offerings: plans, currentStatus: .inactive())
        let onlineController = ModelAccessController(
            revenueCat: .mock(using: onlineManager),
            userDefaults: defaults
        )

        let initialPlans = try await onlineController.getAvailableSubscriptionPlans(
            forceRefresh: true)
        #expect(initialPlans == plans)

        let offlineDefaults = UserDefaults(suiteName: suite)!
        let offlineManager = MockRevenueCatManager(offerings: [], currentStatus: .inactive())
        await offlineManager.setShouldFailOfferings(true)
        let offlineController = ModelAccessController(
            revenueCat: .mock(using: offlineManager),
            userDefaults: offlineDefaults
        )

        let cachedPlans = try await offlineController.getAvailableSubscriptionPlans(
            forceRefresh: true)
        #expect(cachedPlans == plans)
    }

    @Test
    func partialCachedPlansDoNotForceStartupRefresh() async throws {
        let suite = "ModelAccessControllerTests.partialCache"
        let defaults = makeDefaults(suite: suite)
        defer { clearDefaults(suite: suite) }

        let partialPlans: [SubscriptionPlan] = [.mock(id: "lifetime")]
        let seedManager = MockRevenueCatManager(offerings: partialPlans, currentStatus: .inactive())
        let seedController = ModelAccessController(
            revenueCat: .mock(using: seedManager),
            userDefaults: defaults
        )

        let seededPlans = try await seedController.getAvailableSubscriptionPlans(forceRefresh: true)
        #expect(seededPlans == partialPlans)

        let startupDefaults = UserDefaults(suiteName: suite)!
        let startupManager = MockRevenueCatManager(offerings: partialPlans, currentStatus: .inactive())
        let startupController = ModelAccessController(
            revenueCat: .mock(using: startupManager),
            userDefaults: startupDefaults
        )

        let startupPlans = try await startupController.getAvailableSubscriptionPlans(forceRefresh: false)
        #expect(startupPlans == partialPlans)
        #expect(await startupManager.currentOfferingsFetchCount() == 0)
    }
}

@Suite("ModelAccessController utilities")
struct ModelAccessControllerUtilityTests {
    @Test
    func subscriptionStatusStreamPublishesUpdates() async throws {
        let suite = "ModelAccessControllerTests.stream"
        let defaults = makeDefaults(suite: suite)
        defer { clearDefaults(suite: suite) }

        let initialStatus = SubscriptionStatus.inactive()
        let mock = MockRevenueCatManager(currentStatus: initialStatus)
        let controller = ModelAccessController(
            revenueCat: .mock(using: mock),
            userDefaults: defaults
        )

        let stream = await controller.subscriptionStatusStream()
        let task = Task {
            var iterator = stream.makeAsyncIterator()
            if let first = await iterator.next() {
                #expect(first == initialStatus)
            }

            let updatedStatus = SubscriptionStatus.active()
            await mock.push(status: updatedStatus)

            if let second = await iterator.next() {
                #expect(second == updatedStatus)
            }
        }

        await task.value
    }

    @Test
    func getPaywallContextProvidesAvailablePlans() async throws {
        let suite = "ModelAccessControllerTests.context"
        let defaults = makeDefaults(suite: suite)
        defer { clearDefaults(suite: suite) }

        let plans = [
            SubscriptionPlan.mock(id: "monthly"), .mock(id: "annual"), .mock(id: "lifetime"),
        ]
        let status = SubscriptionStatus.inactive()
        let mock = MockRevenueCatManager(offerings: plans, currentStatus: status)
        let controller = ModelAccessController(
            revenueCat: .mock(using: mock),
            userDefaults: defaults
        )

        let context = try await controller.getPaywallContext(for: .parakeetV3)
        #expect(context.model == .parakeetV3)
        #expect(context.availablePlans == plans)
        #expect(context.currentSubscription == status)
        #expect(context.reason == .attemptedPaidModelDownload)
    }
}
