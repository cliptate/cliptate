import Foundation
import OSLog

struct RevenueCatInterface {
    var getOfferings: () async throws -> [SubscriptionPlan]
    var subscriptionStatus: () async throws -> SubscriptionStatus
    var subscriptionStatusStream: () async -> AsyncStream<SubscriptionStatus>

    static func live(manager: RevenueCatManager = .shared) -> RevenueCatInterface {
        RevenueCatInterface(
            getOfferings: { try await manager.getOfferings() },
            subscriptionStatus: { try await manager.subscriptionStatus() },
            subscriptionStatusStream: { await manager.subscriptionStatusStream() }
        )
    }
}

protocol ModelAccessControlling: Sendable {
    func canDownloadModel(_ model: ModelVariant) async throws -> Bool
    func checkPermission(for model: ModelVariant) async throws -> ModelDownloadPermission
}

/// Coordinates subscription-aware access control for downloadable models.
actor ModelAccessController {
    static let shared = ModelAccessController()

    private let revenueCat: RevenueCatInterface
    private var cachedStatus: SubscriptionStatus?
    private var cachedPlans: [SubscriptionPlan] = []
    private var cachedPlansTimestamp: Date?
    private var statusContinuations: [UUID: AsyncStream<SubscriptionStatus>.Continuation] = [:]

    private let logger = Logger(subsystem: "com.Cliptate", category: "ModelAccessController")
    private let userDefaults: UserDefaults
    private let planCacheTTL: TimeInterval = SubscriptionPlansCacheData.cacheLifetime

    init(
        revenueCat: RevenueCatInterface = .live(),
        userDefaults: UserDefaults = .standard
    ) {
        self.revenueCat = revenueCat
        self.userDefaults = userDefaults
        if let stored = Self.decodeCachedStatus(from: userDefaults), stored.isValid {
            cachedStatus = stored.status
        }
        if let storedPlans = Self.decodeCachedPlans(from: userDefaults),
            !storedPlans.plans.isEmpty
        {
            cachedPlans = storedPlans.plans
            if storedPlans.timestamp != .distantPast {
                cachedPlansTimestamp = storedPlans.timestamp
            }
        }
        Task { await observeRevenueCatChanges() }
    }

    func canDownloadModel(_ model: ModelVariant) async throws -> Bool {
        if !model.requiresProSubscription { return true }
        let permission = try await checkPermission(for: model)
        return permission.isAllowed
    }

    func checkPermission(for model: ModelVariant) async throws -> ModelDownloadPermission {
        if !model.requiresProSubscription {
            return ModelDownloadPermission(model: model, isAllowed: true, reason: nil)
        }

        do {
            let status = try await fetchSubscriptionStatus()
            if status.isActive {
                return ModelDownloadPermission(model: model, isAllowed: true, reason: nil)
            }
            let reason: ModelDownloadPermission.PermissionDenialReason =
                status.isProSubscribed ? .subscriptionExpired : .requiresProSubscription
            return ModelDownloadPermission(model: model, isAllowed: false, reason: reason)
        } catch {
            logger.error(
                "Permission check failed due to error: \(error.localizedDescription, privacy: .public)"
            )
            if let cached = cachedStatus {
                if cached.isActive {
                    return ModelDownloadPermission(model: model, isAllowed: true, reason: nil)
                }
                let reason: ModelDownloadPermission.PermissionDenialReason =
                    cached.isProSubscribed ? .subscriptionExpired : .requiresProSubscription
                return ModelDownloadPermission(model: model, isAllowed: false, reason: reason)
            }
            return ModelDownloadPermission(model: model, isAllowed: false, reason: .offline)
        }
    }

    func getCurrentSubscriptionStatus(forceRefresh: Bool = false) async throws
        -> SubscriptionStatus
    {
        if !forceRefresh, let status = cachedStatus { return status }
        return try await fetchSubscriptionStatus(forceRefresh: forceRefresh)
    }

    func getAvailableSubscriptionPlans(forceRefresh: Bool = false) async throws
        -> [SubscriptionPlan]
    {
        let shouldFetchRemotely: Bool = {
            if forceRefresh { return true }
            guard !cachedPlans.isEmpty else { return true }
            if plansRequireRefresh(cachedPlans) { return true }
            return !plansCacheIsValid()
        }()

        var remoteError: Error?

        if shouldFetchRemotely {
            do {
                let plans = try await revenueCat.getOfferings()
                cachedPlans = plans
                cachePlansToDisk(plans)
                return plans
            } catch {
                logger.error(
                    "Failed to fetch subscription plans: \(error.localizedDescription, privacy: .public)"
                )
                remoteError = error
            }
        }

        if !cachedPlans.isEmpty, !plansRequireRefresh(cachedPlans) {
            return cachedPlans
        }

        if let storedPlans = loadCachedPlansFromDisk(), !storedPlans.plans.isEmpty {
            cachedPlans = storedPlans.plans
            if storedPlans.timestamp != .distantPast {
                cachedPlansTimestamp = storedPlans.timestamp
            }
            if !plansRequireRefresh(storedPlans.plans), storedPlans.isValid {
                return storedPlans.plans
            }
        }

        if !cachedPlans.isEmpty {
            return cachedPlans
        }

        if let remoteError {
            throw remoteError
        }

        throw SubscriptionError.offeringsUnavailable
    }

    func subscriptionStatusStream() -> AsyncStream<SubscriptionStatus> {
        AsyncStream { continuation in
            Task { await self.registerContinuation(continuation) }
        }
    }

    func getModelStatus(for model: ModelVariant) async throws -> ModelAccessLevel {
        model.accessLevel
    }

    func accessLevel(for model: ModelVariant) -> ModelAccessLevel {
        model.accessLevel
    }

    func getFreeModels() async -> [ModelVariant] {
        ModelVariant.freeModels
    }

    func getPaidModels() async -> [ModelVariant] {
        ModelVariant.proModels
    }

    func requiresProAccess(model: ModelVariant) -> Bool {
        model.requiresProSubscription
    }

    func shouldShowPaywall(for model: ModelVariant) async -> Bool {
        guard model.requiresProSubscription else { return false }
        do {
            return try await !canDownloadModel(model)
        } catch {
            logger.error(
                "Failed to determine paywall necessity: \(error.localizedDescription, privacy: .public)"
            )
            return true
        }
    }

    func getPaywallContext(for model: ModelVariant) async throws -> PaywallContext {
        let plans = try await getAvailableSubscriptionPlans(forceRefresh: true)
        let status = try await fetchSubscriptionStatus(forceRefresh: true)
        return PaywallContext(
            model: model,
            accessLevel: model.accessLevel,
            availablePlans: plans,
            currentSubscription: status,
            reason: .attemptedPaidModelDownload
        )
    }

    private func fetchSubscriptionStatus(forceRefresh: Bool = false) async throws
        -> SubscriptionStatus
    {
        if !forceRefresh, let cached = cachedStatus { return cached }

        do {
            let status = try await revenueCat.subscriptionStatus()
            await cache(status: status)
            return status
        } catch {
            logger.error(
                "Fetching subscription status failed: \(error.localizedDescription, privacy: .public)"
            )
            if let cached = cachedStatus {
                logger.debug("Returning in-memory cached subscription status")
                return cached
            }
            if let stored = loadCachedStatusFromDisk(), stored.isValid {
                cachedStatus = stored.status
                notify(status: stored.status)
                return stored.status
            }
            throw error
        }
    }

    private func loadCachedStatusFromDisk() -> SubscriptionCacheData? {
        Self.decodeCachedStatus(from: userDefaults)
    }

    private func cache(status: SubscriptionStatus) async {
        cachedStatus = status
        notify(status: status)
        let cacheData = SubscriptionCacheData(status: status, timestamp: Date())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(cacheData) {
            userDefaults.set(data, forKey: SubscriptionKeys.subscriptionCacheKey)
        }
    }

    private func notify(status: SubscriptionStatus) {
        for continuation in statusContinuations.values {
            continuation.yield(status)
        }
    }

    private func cachePlansToDisk(_ plans: [SubscriptionPlan]) {
        let cacheData = SubscriptionPlansCacheData(plans: plans, timestamp: Date())
        cachedPlansTimestamp = cacheData.timestamp
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(cacheData) {
            userDefaults.set(data, forKey: SubscriptionKeys.subscriptionPlansCacheKey)
        }
    }

    private func plansRequireRefresh(_ plans: [SubscriptionPlan]) -> Bool {
        guard !plans.isEmpty else { return true }
        return !plans.contains { SubscriptionProductIDs.allProductIDs.contains($0.productIdentifier) }
    }

    private func plansCacheIsValid() -> Bool {
        guard let timestamp = cachedPlansTimestamp else { return false }
        return Date().timeIntervalSince(timestamp) < planCacheTTL
    }

    private func loadCachedPlansFromDisk() -> SubscriptionPlansCacheData? {
        Self.decodeCachedPlans(from: userDefaults)
    }

    private static func decodeCachedStatus(from defaults: UserDefaults)
        -> SubscriptionCacheData?
    {
        guard let data = defaults.data(forKey: SubscriptionKeys.subscriptionCacheKey) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SubscriptionCacheData.self, from: data)
    }

    private static func decodeCachedPlans(from defaults: UserDefaults)
        -> SubscriptionPlansCacheData?
    {
        guard let data = defaults.data(forKey: SubscriptionKeys.subscriptionPlansCacheKey) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let cacheData = try? decoder.decode(SubscriptionPlansCacheData.self, from: data) {
            return cacheData
        }
        let legacyDecoder = JSONDecoder()
        legacyDecoder.dateDecodingStrategy = .iso8601
        if let legacyPlans = try? legacyDecoder.decode([SubscriptionPlan].self, from: data) {
            return SubscriptionPlansCacheData(plans: legacyPlans, timestamp: .distantPast)
        }
        return nil
    }

    private func observeRevenueCatChanges() async {
        let stream = await revenueCat.subscriptionStatusStream()
        for await status in stream {
            await cache(status: status)
        }
    }

    private func registerContinuation(_ continuation: AsyncStream<SubscriptionStatus>.Continuation)
        async
    {
        let id = UUID()
        statusContinuations[id] = continuation

        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(withID: id) }
        }

        if let status = cachedStatus {
            continuation.yield(status)
        } else if let stored = loadCachedStatusFromDisk(), stored.isValid {
            cachedStatus = stored.status
            continuation.yield(stored.status)
        }
    }

    private func removeContinuation(withID id: UUID) async {
        statusContinuations[id] = nil
    }
}

extension ModelAccessController: ModelAccessControlling {}
