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
    func resolvedPricingUsesStorePriceAndFallbackForMissingProducts() {
        let monthly = SubscriptionProductOption(
            id: SubscriptionCatalog.monthlyProductID,
            title: "Monthly Premium",
            durationText: "1 month",
            priceText: "$2.49/month",
            calloutText: "Auto-renews monthly",
            isFallbackPrice: false
        )

        let options = SubscriptionCatalog.resolvedOptions(from: [monthly])

        #expect(options.count == 2)
        #expect(options[0].id == SubscriptionCatalog.monthlyProductID)
        #expect(options[0].priceText == "$2.49/month")
        #expect(options[0].isFallbackPrice == false)
        #expect(options[1].id == SubscriptionCatalog.yearlyProductID)
        #expect(options[1].priceText == "$17.99/year")
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
}
