import Foundation
import Testing
@testable import personal_debt

@MainActor
struct SubscriptionAccessTests {
    private let startDate = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test
    func localTrialAllowsAccessForFifteenDaysThenExpires() {
        let policy = TrialAccessPolicy(durationDays: 15)

        let activeStatus = policy.status(
            startDate: startDate,
            now: startDate.addingTimeInterval((15 * 86_400) - 1)
        )
        #expect(activeStatus.isActive)

        let expiredStatus = policy.status(
            startDate: startDate,
            now: startDate.addingTimeInterval(15 * 86_400)
        )

        if case .expired(_, let expiredAt) = expiredStatus {
            #expect(expiredAt == startDate.addingTimeInterval(15 * 86_400))
        } else {
            #expect(Bool(false))
        }
    }

    @Test
    func activeSubscriptionOverridesExpiredTrial() {
        let evaluator = SubscriptionAccessEvaluator()
        let renewalDate = startDate.addingTimeInterval(45 * 86_400)

        let state = evaluator.evaluate(
            trialStartDate: startDate,
            activeSubscription: ActiveSubscription(
                productID: SubscriptionCatalog.yearlyProductID,
                renewalDate: renewalDate
            ),
            now: startDate.addingTimeInterval(20 * 86_400)
        )

        #expect(state == .subscribed(productID: SubscriptionCatalog.yearlyProductID, renewalDate: renewalDate))
        #expect(state.allowsFullAccess)
    }

    @Test
    func expiredTrialWithoutSubscriptionIsReadOnly() {
        let evaluator = SubscriptionAccessEvaluator()

        let state = evaluator.evaluate(
            trialStartDate: startDate,
            activeSubscription: nil,
            now: startDate.addingTimeInterval(16 * 86_400)
        )

        #expect(state == .readOnly(trialExpiredAt: startDate.addingTimeInterval(15 * 86_400)))
        #expect(state.isReadOnly)
        #expect(state.allowsFullAccess == false)
    }

    @Test
    func missingTrialStartWithoutSubscriptionStaysInLoadingState() {
        let evaluator = SubscriptionAccessEvaluator()

        let state = evaluator.evaluate(
            trialStartDate: nil,
            activeSubscription: nil,
            now: startDate
        )

        #expect(state == .loading)
        #expect(state.allowsFullAccess == false)
        #expect(state.isReadOnly == false)
    }

    @Test
    func trialReportsOneDayRemainingOnFinalActiveSecond() {
        let policy = TrialAccessPolicy(durationDays: 15)

        let status = policy.status(
            startDate: startDate,
            now: startDate.addingTimeInterval((14 * 86_400) + 1)
        )

        if case .active(_, _, let daysRemaining) = status {
            #expect(daysRemaining == 1)
        } else {
            #expect(Bool(false))
        }
    }

    @Test
    func resolvedPricingUsesStorePriceAndFallbackForMissingProducts() {
        let monthly = SubscriptionProductOption(
            id: SubscriptionCatalog.monthlyProductID,
            title: "Premium",
            durationText: "1 month",
            priceText: "$2.49",
            calloutText: "Auto-renews every 1 month",
            isFallbackPrice: false
        )

        let options = SubscriptionCatalog.resolvedOptions(from: [monthly])

        #expect(options.count == 2)
        #expect(options[0].id == SubscriptionCatalog.monthlyProductID)
        #expect(options[0].priceText == "$2.49")
        #expect(options[0].isFallbackPrice == false)
        #expect(options[1].id == SubscriptionCatalog.yearlyProductID)
        #expect(options[1].priceText == "$17.99")
        #expect(options[1].isFallbackPrice)
    }

    @Test
    func writeAccessGateRejectsReadOnlyState() {
        let store = SubscriptionStore.preview(
            accessState: .readOnly(
                trialExpiredAt: startDate.addingTimeInterval(15 * 86_400)
            )
        )

        do {
            try store.requireWriteAccess()
            #expect(Bool(false))
        } catch {
            let accessError = error as? SubscriptionAccessError
            #expect(accessError == .readOnly)
        }
    }

    @Test
    func writeAccessGateRejectsDebtServiceWritesInReadOnlyMode() {
        let store = SubscriptionStore.preview(
            accessState: .readOnly(
                trialExpiredAt: startDate.addingTimeInterval(15 * 86_400)
            )
        )
        let service = CreditCardDebtService(writeAccessAuthorizer: store)

        do {
            _ = try service.createDebt(CreditCardDebtInput(name: "Card", billingDay: 1, dueDay: 20))
            #expect(Bool(false))
        } catch {
            let accessError = error as? SubscriptionAccessError
            #expect(accessError == .readOnly)
        }
    }

    @Test
    func writeAccessGateAllowsSubscribedState() throws {
        let store = SubscriptionStore.preview(
            accessState: .subscribed(
                productID: SubscriptionCatalog.monthlyProductID,
                renewalDate: startDate.addingTimeInterval(30 * 86_400)
            )
        )

        try store.requireWriteAccess()
    }

    @Test
    func subscriptionStoreStartsTrialRefreshesEntitlementsAndReportsReadOnlyState() async {
        let trialStore = InMemoryTrialAccessStore()
        let store = SubscriptionStore(
            trialStore: trialStore,
            trialPolicy: TrialAccessPolicy(durationDays: 15),
            now: { startDate }
        )

        await store.refreshEntitlements()
        #expect(store.accessState == .loading)
        #expect(store.hasFullAccess == false)
        #expect(store.isReadOnly == false)

        await store.start()
        #expect(trialStore.trialStartDate == startDate)
        #expect(store.hasFullAccess)
        #expect(store.isReadOnly == false)

        let stateAfterFirstStart = store.accessState
        await store.start()
        #expect(store.accessState == stateAfterFirstStart)
    }

    @Test
    func resolvedPricingKeepsCatalogOrderAndIgnoresUnknownProducts() {
        let yearly = SubscriptionProductOption(
            id: SubscriptionCatalog.yearlyProductID,
            title: "Premium",
            durationText: "1 year",
            priceText: "$15.99",
            calloutText: "Auto-renews every 1 year",
            isFallbackPrice: false
        )
        let unknown = SubscriptionProductOption(
            id: "com.personaldebt.premium.legacy",
            title: "Legacy",
            durationText: "1 month",
            priceText: "$0.99",
            calloutText: "Legacy",
            isFallbackPrice: false
        )

        let options = SubscriptionCatalog.resolvedOptions(from: [unknown, yearly])

        #expect(options.count == 2)
        #expect(options[0].id == SubscriptionCatalog.monthlyProductID)
        #expect(options[0].isFallbackPrice)
        #expect(options[1].id == SubscriptionCatalog.yearlyProductID)
        #expect(options[1].priceText == "$15.99")
        #expect(options.contains(where: { $0.id == unknown.id }) == false)
    }

    @Test
    func accessStateTextAndSubscriptionReplacementPreferLongerEntitlement() {
        #expect(SubscriptionAccessState.loading.statusTitle.isEmpty == false)
        #expect(SubscriptionAccessState.loading.statusDetail.isEmpty == false)
        #expect(SubscriptionAccessState.trialActive(expiresAt: startDate, daysRemaining: 1).statusDetail.contains("1"))
        #expect(SubscriptionAccessState.trialActive(expiresAt: startDate, daysRemaining: 3).statusDetail.contains("3"))
        #expect(SubscriptionAccessState.subscribed(productID: "monthly", renewalDate: nil).statusDetail.isEmpty == false)
        #expect(SubscriptionAccessState.subscribed(productID: "yearly", renewalDate: startDate).statusDetail.isEmpty == false)
        #expect(SubscriptionAccessState.readOnly(trialExpiredAt: startDate).statusTitle.isEmpty == false)

        let store = SubscriptionStore.preview(accessState: .loading)
        let monthly = ActiveSubscription(
            productID: SubscriptionCatalog.monthlyProductID,
            renewalDate: startDate.addingTimeInterval(30 * 86_400)
        )
        let yearly = ActiveSubscription(
            productID: SubscriptionCatalog.yearlyProductID,
            renewalDate: startDate.addingTimeInterval(365 * 86_400)
        )
        let lifetimeLike = ActiveSubscription(
            productID: SubscriptionCatalog.yearlyProductID,
            renewalDate: nil
        )

        #expect(store.debugShouldReplaceActiveSubscription(current: nil, candidate: monthly))
        #expect(store.debugShouldReplaceActiveSubscription(current: monthly, candidate: yearly))
        #expect(store.debugShouldReplaceActiveSubscription(current: yearly, candidate: monthly) == false)
        #expect(store.debugShouldReplaceActiveSubscription(current: yearly, candidate: lifetimeLike))
    }
}
