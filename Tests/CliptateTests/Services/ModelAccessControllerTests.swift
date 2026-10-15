import CliptateCore
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
    var statusFetchCount: Int = 0
    var statusStreamCount: Int = 0

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
        statusFetchCount += 1
        if shouldFailStatusFetch {
            throw MockError.failure
        }
        return currentStatus
    }

    func subscriptionStatusStream() async -> AsyncStream<SubscriptionStatus> {
        statusStreamCount += 1
        return AsyncStream { continuation in
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

    func billingCallCount() -> Int {
        offeringsFetchCount + statusFetchCount + statusStreamCount
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
    @Test("direct builds allow every model offline without reading or persisting billing status")
    func directBuildsAllowAllModelsWithoutBilling() async throws {
        guard !SubscriptionPolicy.isBillingEnabled else { return }
        let suite = "ModelAccessControllerTests.direct.\(UUID().uuidString)"
        let defaults = makeDefaults(suite: suite)
        defer { clearDefaults(suite: suite) }

        let status = SubscriptionStatus.inactive()
        let cached = SubscriptionCacheData(status: status, timestamp: Date())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let originalCache = try encoder.encode(cached)
        defaults.set(originalCache, forKey: SubscriptionKeys.subscriptionCacheKey)

        let mock = MockRevenueCatManager(currentStatus: status)
        await mock.setShouldFailStatusFetch(true)
        await mock.setShouldFailOfferings(true)
        let controller = ModelAccessController(
            revenueCat: .mock(using: mock), userDefaults: UserDefaults(suiteName: suite)!)

        for model in ModelVariant.allCases {
            let permission = try await controller.checkPermission(for: model)
            #expect(permission.isAllowed)
            #expect(permission.reason == nil)
            #expect(try await controller.canDownloadModel(model))
            #expect(await controller.shouldShowPaywall(for: model) == false)
        }
        #expect(ModelVariant.freeModels == ModelVariant.allCases)
        #expect(ModelVariant.proModels.isEmpty)
        let stream = await controller.subscriptionStatusStream()
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == nil)
        #expect(await mock.billingCallCount() == 0)
        #expect(defaults.data(forKey: SubscriptionKeys.subscriptionCacheKey) == originalCache)
    }

    @Test("direct builds suppress automatic and manual paywalls without contacting billing")
    @MainActor
    func directBuildsNeverPresentPaywalls() async throws {
        guard !SubscriptionPolicy.isBillingEnabled else { return }
        let suite = "ModelAccessControllerTests.directPaywall.\(UUID().uuidString)"
        let defaults = makeDefaults(suite: suite)
        defer { clearDefaults(suite: suite) }
        let mock = MockRevenueCatManager(currentStatus: .inactive())
        let controller = ModelAccessController(
            revenueCat: .mock(using: mock), userDefaults: makeDefaults(suite: suite + ".access"))
        defer { clearDefaults(suite: suite + ".access") }
        let manager = PaywallManager(modelAccessController: controller, userDefaults: defaults)

        for reason in [PaywallContext.PaywallReason.attemptedPaidModelDownload, .userInitiated, .subscriptionExpired] {
            #expect(await manager.showPaywall(for: .parakeetV3, reason: reason) == false)
        }
        #expect(!manager.isPresented)
        #expect(!manager.isLoading)
        #expect(manager.context == nil)
        #expect(manager.errorMessage == nil)
        #expect(await mock.billingCallCount() == 0)
        #expect(defaults.object(forKey: SubscriptionKeys.paywallLastPresentedDateKey) == nil)
    }

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
        #expect(try await controller.canDownloadModel(.parakeetV3) == !SubscriptionPolicy.isBillingEnabled)
        #expect(try await controller.canDownloadModel(.fireRedASR2) == !SubscriptionPolicy.isBillingEnabled)
        #expect(try await controller.canDownloadModel(.sortformerStreaming) == !SubscriptionPolicy.isBillingEnabled)
        let cohereModel = try #require(ModelVariant(rawValue: "cohere-transcribe-03-2026-mlx-8bit"))
        #expect(try await controller.canDownloadModel(cohereModel) == !SubscriptionPolicy.isBillingEnabled)
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
        guard SubscriptionPolicy.isBillingEnabled else { return }
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
