import Combine
import Foundation
import OSLog
import RevenueCat
import StoreKit

private enum RevenueCatManagerError: LocalizedError {
	case notInitialized
	case offeringsUnavailable

	var errorDescription: String? {
		switch self {
		case .notInitialized:
			return
				"RevenueCatManager has not been initialized. Please call initialize(apiKey:appUserID:) first."
		case .offeringsUnavailable:
			return "Unable to get available subscription plans, please try again later."
		}
	}
}

/// Actor wrapper responsible for interacting with the RevenueCat SDK.
actor RevenueCatManager {
	static let shared = RevenueCatManager()

	private(set) var isInitialized = false

	private let logger = Logger(subsystem: "com.Cliptate", category: "RevenueCatManager")
	private var delegateProxy: PurchasesDelegateProxy?
	private var cachedPlans: [SubscriptionPlan] = []
	private var latestCustomerInfo: CustomerInfo?
	private var latestStatus: SubscriptionStatus?
	private var continuations: [UUID: AsyncStream<CustomerInfo>.Continuation] = [:]
	private var statusContinuations: [UUID: AsyncStream<SubscriptionStatus>.Continuation] = [:]
	private let planDisplayOrder = ["monthly", "annual", "lifetime"]

	private nonisolated(unsafe) let infoSubject = PassthroughSubject<CustomerInfo, Never>()
	private let userDefaults: UserDefaults
	private let dateProvider: @Sendable () -> Date

	init(
		userDefaults: UserDefaults = .standard,
		dateProvider: @escaping @Sendable () -> Date = { Date() }
	) {
		self.userDefaults = userDefaults
		self.dateProvider = dateProvider
	}

	// MARK: - Initialization

	func initialize(apiKey: String, appUserID: String? = nil) async throws {
		guard !isInitialized else {
			logger.debug("RevenueCatManager already initialized.")
			return
		}

		logger.debug("Configuring RevenueCat SDK")
		let purchases = Purchases.configure(withAPIKey: apiKey)

		let delegate = PurchasesDelegateProxy { [weak self] info in
			Task { [weak self] in
				guard let self else { return }
				await self.handleCustomerInfoUpdate(info)
			}
		}
		purchases.delegate = delegate
		delegateProxy = delegate

		if let appUserID {
			logger.debug("Logging in RevenueCat user during initialization")
			let result = try await purchases.logIn(appUserID)
			await handleCustomerInfoUpdate(result.customerInfo)
		} else if let info = try? await purchases.customerInfo() {
			await handleCustomerInfoUpdate(info)
		}

		isInitialized = true
		logger.debug("RevenueCat SDK configured successfully")
	}

	func setAppUserID(_ userID: String) async throws {
		try await ensureInitialized()
		logger.debug("Setting RevenueCat App User ID to \(userID, privacy: .public)")
		let result = try await Purchases.shared.logIn(userID)
		await handleCustomerInfoUpdate(result.customerInfo)
	}

	func switchUser(to userID: String) async throws {
		try await ensureInitialized()
		logger.debug("Switching RevenueCat user to \(userID, privacy: .public)")
		_ = try await Purchases.shared.logOut()
		let result = try await Purchases.shared.logIn(userID)
		await handleCustomerInfoUpdate(result.customerInfo)
	}

	// MARK: - Plan Metadata

	private struct PlanMetadata {
		let id: String
		let name: String
		let type: SubscriptionPlan.PlanType
		let duration: SubscriptionPlan.PlanDuration
		let productIdentifier: String
	}

	private func planMetadata(forProductIdentifier identifier: String) -> PlanMetadata? {
		switch identifier {
		case SubscriptionProductIDs.monthlyProID:
			return PlanMetadata(
				id: "monthly",
				name: String(
					localized: "Pro Monthly",
					comment: "Subscription plan name: monthly Pro plan"
				),
				type: .monthly,
				duration: .months(1),
				productIdentifier: SubscriptionProductIDs.monthlyProID
			)
		case SubscriptionProductIDs.annualProID:
			return PlanMetadata(
				id: "annual",
				name: String(
					localized: "Pro Annual",
					comment: "Subscription plan name: annual Pro plan"
				),
				type: .annual,
				duration: .years(1),
				productIdentifier: SubscriptionProductIDs.annualProID
			)
		case SubscriptionProductIDs.lifetimeProID:
			return PlanMetadata(
				id: "lifetime",
				name: String(
					localized: "Pro Lifetime",
					comment: "Subscription plan name: lifetime Pro plan"
				),
				type: .lifetime,
				duration: .lifetime,
				productIdentifier: SubscriptionProductIDs.lifetimeProID
			)
		default:
			return nil
		}
	}

	private func planMetadata(forPlanIdentifier identifier: String) -> PlanMetadata? {
		switch identifier {
		case "monthly":
			return planMetadata(forProductIdentifier: SubscriptionProductIDs.monthlyProID)
		case "annual":
			return planMetadata(forProductIdentifier: SubscriptionProductIDs.annualProID)
		case "lifetime":
			return planMetadata(forProductIdentifier: SubscriptionProductIDs.lifetimeProID)
		default:
			return nil
		}
	}

	// MARK: - Products & Offerings

	func getOfferings() async throws -> [SubscriptionPlan] {
		try await ensureInitialized()
		logger.debug("Fetching RevenueCat offerings")

		do {
			let offerings = try await Purchases.shared.offerings()
			if let current = offerings.current, !current.availablePackages.isEmpty {
				var plans = current.availablePackages.map(makeSubscriptionPlan(from:))
				plans = await normalizePlans(plans)
				cachedPlans = plans
				logger.debug("Fetched \(plans.count) subscription plans")
				return plans
			}

			logger.warning(
				"RevenueCat offerings missing or empty. Falling back to direct StoreKit product lookup."
			)
			let fallbackPlans = await loadPlansViaStoreProducts()
			guard !fallbackPlans.isEmpty else {
				throw SubscriptionError.offeringsUnavailable
			}
			cachedPlans = fallbackPlans
			return fallbackPlans
		} catch {
			logger.error(
				"Failed to fetch offerings: \(error.localizedDescription, privacy: .public)"
			)
			throw mapSubscriptionError(error)
		}
	}

	private func loadPlansViaStoreProducts() async -> [SubscriptionPlan] {
		let products = await Purchases.shared.products(SubscriptionProductIDs.allProductIDs)
		guard !products.isEmpty else { return [] }

		let plans: [SubscriptionPlan] = products.compactMap { product in
			guard let metadata = planMetadata(forProductIdentifier: product.productIdentifier)
			else {
				return nil
			}
			return SubscriptionPlan(
				id: metadata.id,
				name: metadata.name,
				type: metadata.type,
				productIdentifier: metadata.productIdentifier,
				duration: metadata.duration,
				priceText: product.localizedPriceString
			)
		}

		return await normalizePlans(plans)
	}

	func getPackage(identifier: String) async throws -> Package? {
		try await ensureInitialized()
		do {
			let offerings = try await Purchases.shared.offerings()
			return offerings.current?.package(identifier: identifier)
		} catch {
			logger.error(
				"Failed to fetch package \(identifier, privacy: .public): \(error.localizedDescription, privacy: .public)"
			)
			throw mapSubscriptionError(error)
		}
	}

	func getCustomerInfo() async throws -> CustomerInfo {
		try await ensureInitialized()
		logger.debug("Fetching current CustomerInfo")
		do {
			return try await Purchases.shared.customerInfo()
		} catch {
			logger.error(
				"Failed to load CustomerInfo: \(error.localizedDescription, privacy: .public)"
			)
			throw mapSubscriptionError(error)
		}
	}

	// MARK: - Purchases

	func purchase(package: Package) async throws -> (
		transaction: StoreTransaction?,
		customerInfo: CustomerInfo,
		userCancelled: Bool
	) {
		try await ensureInitialized()
		do {
			logger.debug("Starting purchase for package \(package.identifier, privacy: .public)")
			let result = try await Purchases.shared.purchase(package: package)
			await handleCustomerInfoUpdate(result.customerInfo)
			logger.debug("Purchase finished for package \(package.identifier, privacy: .public)")
			return (result.transaction, result.customerInfo, result.userCancelled)
		} catch {
			logger.error(
				"Purchase failed: \(error.localizedDescription, privacy: .public)"
			)
			throw mapSubscriptionError(error)
		}
	}

	func restorePurchases() async throws -> CustomerInfo {
		try await ensureInitialized()
		logger.debug("Restoring purchases")
		do {
			let info = try await Purchases.shared.restorePurchases()
			await handleCustomerInfoUpdate(info)
			return info
		} catch {
			logger.error(
				"Restore purchases failed: \(error.localizedDescription, privacy: .public)"
			)
			throw mapSubscriptionError(error)
		}
	}

	func isSubscribed() async throws -> Bool {
		let status = try await subscriptionStatus()
		return status.isActive
	}

	// MARK: - Subscription Status & Caching

	func subscriptionStatus() async throws -> SubscriptionStatus {
		try await ensureInitialized()
		do {
			let status = try await fetchRemoteStatus()
			latestStatus = status
			await cache(status: status)
			broadcast(status: status)
			return status
		} catch {
			logger.error(
				"Failed to fetch subscription status: \(error.localizedDescription, privacy: .public)"
			)
			if let cached = loadCachedStatus(), cached.isValid {
				logger.debug("Returning cached subscription status")
				broadcast(status: cached.status)
				return cached.status
			}
			throw mapSubscriptionError(error)
		}
	}

	private func fetchRemoteStatus() async throws -> SubscriptionStatus {
		let info = try await getCustomerInfo()
		return await makeSubscriptionStatus(from: info)
	}

	func customerInfoStream() -> AsyncStream<CustomerInfo> {
		AsyncStream { continuation in
			Task { await self.registerContinuation(continuation) }
		}
	}

	func subscriptionStatusStream() -> AsyncStream<SubscriptionStatus> {
		AsyncStream { continuation in
			Task { await self.registerStatusContinuation(continuation) }
		}
	}

	func onSubscriptionStatusChanged(
		_ handler: @escaping (CustomerInfo) -> Void
	) -> AnyCancellable {
		infoSubject
			.receive(on: DispatchQueue.main)
			.sink(receiveValue: handler)
	}

	// MARK: - Helpers

	private func ensureInitialized() async throws {
		guard isInitialized else { throw RevenueCatManagerError.notInitialized }
	}

	private func mapSubscriptionError(_ error: Error) -> SubscriptionError {
		if let subscriptionError = error as? SubscriptionError {
			return subscriptionError
		}
		if let managerError = error as? RevenueCatManagerError {
			switch managerError {
			case .notInitialized:
				return .notInitialized
			case .offeringsUnavailable:
				return .offeringsUnavailable
			}
		}
		if let revenueCatError = error as? ErrorCode {
			switch revenueCatError {
			case .networkError:
				return .networkUnavailable
			case .receiptAlreadyInUseError:
				return .receiptAlreadyInUse
			case .paymentPendingError:
				return .paymentPending
			case .purchaseCancelledError:
				return .purchaseCancelled
			case .productAlreadyPurchasedError:
				return .productAlreadyPurchased
			default:
				return .sdkError(revenueCatError.localizedDescription)
			}
		}
		if let urlError = error as? URLError {
			if urlError.code == .notConnectedToInternet {
				return .networkUnavailable
			}
			return .networkError(urlError.localizedDescription)
		}
		return .sdkError(error.localizedDescription)
	}

	private func makeSubscriptionPlan(from package: Package) -> SubscriptionPlan {
		let productIdentifier = package.storeProduct.productIdentifier
		let metadata = planMetadata(forProductIdentifier: productIdentifier)

		let fallbackPlanType: SubscriptionPlan.PlanType
		let fallbackDuration: SubscriptionPlan.PlanDuration

		switch package.packageType {
		case .monthly, .twoMonth, .threeMonth, .sixMonth, .weekly:
			fallbackPlanType = .monthly
			fallbackDuration = .months(1)
		case .annual:
			fallbackPlanType = .annual
			fallbackDuration = .years(1)
		case .lifetime:
			fallbackPlanType = .lifetime
			fallbackDuration = .lifetime
		case .custom, .unknown:
			fallbackPlanType = .monthly
			fallbackDuration = .months(1)
		@unknown default:
			fallbackPlanType = .monthly
			fallbackDuration = .months(1)
		}

		return SubscriptionPlan(
			id: metadata?.id ?? package.identifier,
			name: metadata?.name ?? package.storeProduct.localizedTitle,
			type: metadata?.type ?? fallbackPlanType,
			productIdentifier: productIdentifier,
			duration: metadata?.duration ?? fallbackDuration,
			priceText: package.localizedPriceString
		)
	}

	private func normalizePlans(_ plans: [SubscriptionPlan]) async -> [SubscriptionPlan] {
		var planMap: [String: SubscriptionPlan] = [:]
		for plan in plans {
			planMap[plan.productIdentifier] = plan
		}

		let sortedPlans = planMap.values.sorted { lhs, rhs in
			let leftIndex = orderIndex(for: lhs)
			let rightIndex = orderIndex(for: rhs)
			if leftIndex == rightIndex {
				return lhs.name < rhs.name
			}
			return leftIndex < rightIndex
		}
		return sortedPlans
	}

	private func orderIndex(for plan: SubscriptionPlan) -> Int {
		if let index = planDisplayOrder.firstIndex(of: plan.id) {
			return index
		}
		if let metadata = planMetadata(forProductIdentifier: plan.productIdentifier),
			let index = planDisplayOrder.firstIndex(of: metadata.id)
		{
			return index
		}
		return planDisplayOrder.count
	}

	private func makeSubscriptionStatus(from info: CustomerInfo) async -> SubscriptionStatus {
		let entitlement = info.entitlements.all[SubscriptionEntitlements.proAccess]
		let isActive = entitlement?.isActive == true

		let plan: SubscriptionPlan? = await {
			guard let productIdentifier = entitlement?.productIdentifier else { return nil }
			if let cached = cachedPlans.first(where: { $0.productIdentifier == productIdentifier })
			{
				return cached
			}
			return await defaultPlan(for: productIdentifier)
		}()

		let isTrial = entitlement?.periodType == .trial
		let expiration = entitlement?.expirationDate
		let isSandbox = entitlement?.isSandbox ?? false

		return SubscriptionStatus(
			isProSubscribed: isActive,
			currentPlan: plan,
			expirationDate: expiration,
			isInTrialPeriod: isTrial,
			lastUpdated: dateProvider(),
			isSandbox: isSandbox
		)
	}

	private func defaultPlan(for productIdentifier: String) async -> SubscriptionPlan? {
		guard let metadata = planMetadata(forProductIdentifier: productIdentifier) else {
			return nil
		}
		let priceText = await getProductPriceText(for: productIdentifier)
		return SubscriptionPlan(
			id: metadata.id,
			name: metadata.name,
			type: metadata.type,
			productIdentifier: productIdentifier,
			duration: metadata.duration,
			priceText: priceText
		)
	}

	private func getProductPriceText(for productIdentifier: String) async -> String? {
		let products = await Purchases.shared.products([productIdentifier])
		guard let product = products.first else { return nil }
		return product.localizedPriceString
	}

	private func cache(status: SubscriptionStatus) async {
		let cacheData = SubscriptionCacheData(status: status, timestamp: dateProvider())
		do {
			let encoder = JSONEncoder()
			encoder.dateEncodingStrategy = .iso8601
			let data = try encoder.encode(cacheData)
			userDefaults.set(data, forKey: SubscriptionKeys.subscriptionCacheKey)
		} catch {
			logger.error(
				"Failed to encode subscription cache: \(error.localizedDescription, privacy: .public)"
			)
		}
	}

	private func loadCachedStatus() -> SubscriptionCacheData? {
		guard let data = userDefaults.data(forKey: SubscriptionKeys.subscriptionCacheKey) else {
			return nil
		}
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		do {
			return try decoder.decode(SubscriptionCacheData.self, from: data)
		} catch {
			logger.error(
				"Failed to decode subscription cache: \(error.localizedDescription, privacy: .public)"
			)
			return nil
		}
	}

	private func handleCustomerInfoUpdate(_ info: CustomerInfo) async {
		latestCustomerInfo = info
		let status = await makeSubscriptionStatus(from: info)
		latestStatus = status
		await cache(status: status)
		broadcast(status: status)
		infoSubject.send(info)
		for continuation in continuations.values {
			continuation.yield(info)
		}
	}

	private func registerContinuation(_ continuation: AsyncStream<CustomerInfo>.Continuation) async
	{
		let id = UUID()
		continuations[id] = continuation

		continuation.onTermination = { [weak self] _ in
			Task { await self?.removeContinuation(withID: id) }
		}

		if let info = latestCustomerInfo {
			continuation.yield(info)
		} else if let info = try? await fetchInitialCustomerInfo() {
			continuation.yield(info)
		}
	}

	private func removeContinuation(withID id: UUID) async {
		continuations[id] = nil
	}

	private func fetchInitialCustomerInfo() async throws -> CustomerInfo {
		do {
			let info = try await Purchases.shared.customerInfo()
			latestCustomerInfo = info
			let status = await makeSubscriptionStatus(from: info)
			latestStatus = status
			await cache(status: status)
			broadcast(status: status)
			return info
		} catch {
			throw error
		}
	}

	private func registerStatusContinuation(
		_ continuation: AsyncStream<SubscriptionStatus>.Continuation
	) async {
		let id = UUID()
		statusContinuations[id] = continuation

		continuation.onTermination = { [weak self] _ in
			Task { await self?.removeStatusContinuation(withID: id) }
		}

		if let status = latestStatus {
			continuation.yield(status)
		} else if let cached = loadCachedStatus(), cached.isValid {
			continuation.yield(cached.status)
		}
	}

	private func removeStatusContinuation(withID id: UUID) async {
		statusContinuations[id] = nil
	}

	private func broadcast(status: SubscriptionStatus) {
		for continuation in statusContinuations.values {
			continuation.yield(status)
		}
	}
}

extension RevenueCatManager: PaywallPurchasing {
	func purchasePlan(withIdentifier identifier: String) async throws -> PaywallPurchaseResult {
		if let package = try await getPackage(identifier: identifier) {
			let result = try await purchase(package: package)
			return PaywallPurchaseResult(userCancelled: result.userCancelled)
		}

		guard let metadata = planMetadata(forPlanIdentifier: identifier) else {
			throw PaywallPurchaseError.packageUnavailable
		}

		let products = await Purchases.shared.products([metadata.productIdentifier])
		guard let product = products.first else {
			throw PaywallPurchaseError.packageUnavailable
		}

		let result = try await Purchases.shared.purchase(product: product)
		await handleCustomerInfoUpdate(result.customerInfo)
		return PaywallPurchaseResult(userCancelled: result.userCancelled)
	}
}

private final class PurchasesDelegateProxy: NSObject, PurchasesDelegate {
	private let handler: @Sendable (CustomerInfo) -> Void

	init(handler: @escaping @Sendable (CustomerInfo) -> Void) {
		self.handler = handler
	}

	nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
		handler(customerInfo)
	}
}
