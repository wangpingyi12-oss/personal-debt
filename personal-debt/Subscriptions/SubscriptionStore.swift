import Combine
import Foundation
import StoreKit

@MainActor
final class SubscriptionStore: ObservableObject, WriteAccessAuthorizing {
    @Published private(set) var accessState: SubscriptionAccessState = .loading
    @Published private(set) var products: [SubscriptionProductOption] = SubscriptionCatalog.fallbackOptions
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    @Published private(set) var productLoadingError: String?
    @Published var message: SubscriptionMessage?

    private let trialStore: TrialAccessStoring
    private let trialPolicy: TrialAccessPolicy
    private let accessEvaluator: SubscriptionAccessEvaluator
    private let now: () -> Date
    private var storeProducts: [String: Product] = [:]
    private var transactionUpdatesTask: Task<Void, Never>?
    private var hasStarted = false

    init(
        trialStore: TrialAccessStoring? = nil,
        trialPolicy: TrialAccessPolicy? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        let resolvedTrialStore = trialStore ?? UserDefaultsTrialAccessStore()
        let resolvedTrialPolicy = trialPolicy ?? TrialAccessPolicy()
        self.trialStore = resolvedTrialStore
        self.trialPolicy = resolvedTrialPolicy
        self.accessEvaluator = SubscriptionAccessEvaluator(trialPolicy: resolvedTrialPolicy)
        self.now = now
    }

    var hasFullAccess: Bool {
        accessState.allowsFullAccess
    }

    var isReadOnly: Bool {
        accessState.isReadOnly
    }

    func start() async {
        guard !hasStarted else {
            return
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestFullAccess") {
            hasStarted = true
            accessState = .subscribed(productID: "ui.test.fullAccess", renewalDate: nil)
            products = SubscriptionCatalog.fallbackOptions
            return
        }
        #endif

        hasStarted = true
        ensureTrialStarted()
        refreshAccessState(activeSubscription: nil)
        listenForTransactionUpdates()

        await refreshEntitlements()
        await loadProducts()
    }

    func loadProducts() async {
        isLoadingProducts = true
        productLoadingError = nil
        defer { isLoadingProducts = false }

        do {
            let loadedProducts = try await Product.products(for: SubscriptionCatalog.productIDs)
            storeProducts = Dictionary(uniqueKeysWithValues: loadedProducts.map { ($0.id, $0) })
            let loadedOptions = loadedProducts.map(SubscriptionProductOption.init(product:))
            products = SubscriptionCatalog.resolvedOptions(from: loadedOptions)
        } catch {
            products = SubscriptionCatalog.fallbackOptions
            productLoadingError = String(localized: "subscription.error.productsUnavailable", defaultValue: "App Store prices could not be loaded. Fallback prices are shown until the store responds.")
        }
    }

    func purchase(_ option: SubscriptionProductOption) async {
        if storeProducts[option.id] == nil {
            await loadProducts()
        }

        guard let product = storeProducts[option.id] else {
            message = SubscriptionMessage(
                title: String(localized: "subscription.purchaseUnavailable.title", defaultValue: "Purchase unavailable"),
                detail: String(localized: "subscription.purchaseUnavailable.detail", defaultValue: "This subscription is not available from the App Store right now. Please try again later.")
            )
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    message = SubscriptionMessage(
                        title: String(localized: "subscription.purchaseUnverified.title", defaultValue: "Purchase not verified"),
                        detail: String(localized: "subscription.purchaseUnverified.detail", defaultValue: "The App Store transaction could not be verified, so access was not unlocked.")
                    )
                    return
                }

                await transaction.finish()
                await refreshEntitlements()
                message = SubscriptionMessage(
                    title: String(localized: "subscription.purchaseActive.title", defaultValue: "Subscription active"),
                    detail: String(localized: "subscription.purchaseActive.detail", defaultValue: "Full access is now unlocked on this device.")
                )
            case .pending:
                message = SubscriptionMessage(
                    title: String(localized: "subscription.purchasePending.title", defaultValue: "Purchase pending"),
                    detail: String(localized: "subscription.purchasePending.detail", defaultValue: "The App Store is still processing this purchase. Access will update when it completes.")
                )
            case .userCancelled:
                message = SubscriptionMessage(
                    title: String(localized: "subscription.purchaseCancelled.title", defaultValue: "Purchase cancelled"),
                    detail: String(localized: "subscription.purchaseCancelled.detail", defaultValue: "No subscription was purchased.")
                )
            @unknown default:
                message = SubscriptionMessage(
                    title: String(localized: "subscription.purchaseIncomplete.title", defaultValue: "Purchase incomplete"),
                    detail: String(localized: "subscription.purchaseIncomplete.detail", defaultValue: "The App Store returned an unknown purchase result.")
                )
            }
        } catch {
            message = SubscriptionMessage(
                title: String(localized: "subscription.purchaseFailed.title", defaultValue: "Purchase failed"),
                detail: error.localizedDescription
            )
        }
    }

    func restorePurchases() async {
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()

            if hasFullAccess, case .subscribed = accessState {
                message = SubscriptionMessage(
                    title: String(localized: "subscription.restoreActive.title", defaultValue: "Subscription restored"),
                    detail: String(localized: "subscription.restoreActive.detail", defaultValue: "Your App Store subscription is active again in the app.")
                )
            } else {
                message = SubscriptionMessage(
                    title: String(localized: "subscription.restoreMissing.title", defaultValue: "No subscription found"),
                    detail: String(localized: "subscription.restoreMissing.detail", defaultValue: "No active subscription was found for the current App Store account.")
                )
            }
        } catch {
            message = SubscriptionMessage(
                title: String(localized: "subscription.restoreFailed.title", defaultValue: "Restore failed"),
                detail: error.localizedDescription
            )
        }
    }

    func refreshEntitlements() async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            refreshAccessState(activeSubscription: nil)
            return
        }
        #endif

        var activeSubscription: ActiveSubscription?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                continue
            }

            guard isActiveSubscriptionTransaction(transaction, now: now()) else {
                continue
            }

            let candidate = ActiveSubscription(
                productID: transaction.productID,
                renewalDate: transaction.expirationDate
            )

            if shouldReplaceActiveSubscription(current: activeSubscription, candidate: candidate) {
                activeSubscription = candidate
            }
        }

        refreshAccessState(activeSubscription: activeSubscription)
    }

    func requireWriteAccess() throws {
        guard hasFullAccess else {
            throw SubscriptionAccessError.readOnly
        }
    }

    static func preview(accessState: SubscriptionAccessState) -> SubscriptionStore {
        let store = SubscriptionStore(trialStore: InMemoryTrialAccessStore(trialStartDate: Date()))
        store.accessState = accessState
        store.products = SubscriptionCatalog.fallbackOptions
        return store
    }

    private func ensureTrialStarted() {
        if trialStore.trialStartDate == nil {
            trialStore.trialStartDate = now()
        }
    }

    private func refreshAccessState(activeSubscription: ActiveSubscription?) {
        accessState = accessEvaluator.evaluate(
            trialStartDate: trialStore.trialStartDate,
            activeSubscription: activeSubscription,
            now: now()
        )
    }

    private func listenForTransactionUpdates() {
        transactionUpdatesTask?.cancel()
        transactionUpdatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else {
                    return
                }

                if case .verified(let transaction) = result {
                    await transaction.finish()
                }

                await self.refreshEntitlements()
            }
        }
    }

    private func isActiveSubscriptionTransaction(_ transaction: Transaction, now: Date) -> Bool {
        guard SubscriptionCatalog.productIDs.contains(transaction.productID) else {
            return false
        }

        guard transaction.revocationDate == nil else {
            return false
        }

        if let expirationDate = transaction.expirationDate {
            return expirationDate > now
        }

        return true
    }

    private func shouldReplaceActiveSubscription(
        current: ActiveSubscription?,
        candidate: ActiveSubscription
    ) -> Bool {
        guard let current else {
            return true
        }

        let currentDate = current.renewalDate ?? .distantFuture
        let candidateDate = candidate.renewalDate ?? .distantFuture
        return candidateDate > currentDate
    }
}

struct SubscriptionMessage: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

#if DEBUG
extension SubscriptionStore {
    func debugShouldReplaceActiveSubscription(
        current: ActiveSubscription?,
        candidate: ActiveSubscription
    ) -> Bool {
        shouldReplaceActiveSubscription(current: current, candidate: candidate)
    }
}
#endif
