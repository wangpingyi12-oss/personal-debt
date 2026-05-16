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
            productLoadingError = "App Store prices could not be loaded. Fallback prices are shown until the store responds."
        }
    }

    func purchase(_ option: SubscriptionProductOption) async {
        if storeProducts[option.id] == nil {
            await loadProducts()
        }

        guard let product = storeProducts[option.id] else {
            message = SubscriptionMessage(
                title: "Purchase unavailable",
                detail: "This subscription is not available from the App Store right now. Please try again later."
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
                        title: "Purchase not verified",
                        detail: "The App Store transaction could not be verified, so access was not unlocked."
                    )
                    return
                }

                await transaction.finish()
                await refreshEntitlements()
                message = SubscriptionMessage(
                    title: "Subscription active",
                    detail: "Full access is now unlocked on this device."
                )
            case .pending:
                message = SubscriptionMessage(
                    title: "Purchase pending",
                    detail: "The App Store is still processing this purchase. Access will update when it completes."
                )
            case .userCancelled:
                message = SubscriptionMessage(
                    title: "Purchase cancelled",
                    detail: "No subscription was purchased."
                )
            @unknown default:
                message = SubscriptionMessage(
                    title: "Purchase incomplete",
                    detail: "The App Store returned an unknown purchase result."
                )
            }
        } catch {
            message = SubscriptionMessage(
                title: "Purchase failed",
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
                    title: "Subscription restored",
                    detail: "Your App Store subscription is active again in the app."
                )
            } else {
                message = SubscriptionMessage(
                    title: "No subscription found",
                    detail: "No active subscription was found for the current App Store account."
                )
            }
        } catch {
            message = SubscriptionMessage(
                title: "Restore failed",
                detail: error.localizedDescription
            )
        }
    }

    func refreshEntitlements() async {
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
