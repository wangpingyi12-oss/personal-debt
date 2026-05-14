import Foundation
import Testing
@testable import personal_debt

struct personal_debtTests {
    @Test func appExternalLinksCoverPrivacySupportAndSubscriptionEntrypoints() {
        #expect(AppExternalLinks.subscriptionLinks.map(\.id) == ["manage-subscriptions"])
        #expect(AppExternalLinks.privacyLinks.count == 4)
        #expect(AppExternalLinks.supportLinks.count == 3)
        #expect(AppExternalLinks.supportLinks.contains(where: { $0.url.absoluteString == "mailto:wangpingyi12@outlook.com" }))
        #expect(AppExternalLinks.privacyLinks.contains(where: { $0.url.absoluteString.contains("privacy-policy-zh-CN") }))
        #expect(AppExternalLinks.privacyLinks.contains(where: { $0.url.absoluteString.contains("terms.html") }))
    }

    @Test func subscriptionCatalogKeepsKnownProductsOrdered() {
        let catalog = SubscriptionCatalogService.catalog.sorted { $0.sortOrder < $1.sortOrder }

        #expect(catalog.map(\.id) == [
            SubscriptionAppStoreConfig.monthlyProductID,
            SubscriptionAppStoreConfig.yearlyProductID
        ])
        #expect(SubscriptionCatalogService.knownProductIDs == Set(catalog.map(\.id)))
    }

    @Test func subscriptionStatusResolverTreatsKeyStatesCorrectly() {
        let now = Date()
        let future = Calendar.current.date(byAdding: .day, value: 10, to: now) ?? now
        let past = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now

        #expect(
            SubscriptionStatusResolver.resolveStatus(
                renewalPhase: .active,
                expirationDate: future,
                gracePeriodExpirationDate: nil,
                revokedDate: nil,
                willAutoRenew: true,
                isVerified: true,
                isTrialPeriod: true,
                now: now
            ) == .trial
        )

        #expect(
            SubscriptionStatusResolver.resolveStatus(
                renewalPhase: .inGracePeriod,
                expirationDate: future,
                gracePeriodExpirationDate: future,
                revokedDate: nil,
                willAutoRenew: true,
                isVerified: true,
                isTrialPeriod: false,
                now: now
            ) == .gracePeriod
        )

        #expect(
            SubscriptionStatusResolver.resolveStatus(
                renewalPhase: .expired,
                expirationDate: past,
                gracePeriodExpirationDate: nil,
                revokedDate: nil,
                willAutoRenew: false,
                isVerified: true,
                isTrialPeriod: false,
                now: now
            ) == .expired
        )
    }
}
