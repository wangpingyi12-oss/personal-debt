import Foundation
import StoreKit

enum SubscriptionCatalog {
    static let monthlyProductID = "com.personaldebt.premium.monthly"
    static let yearlyProductID = "com.personaldebt.premium.yearly"
    static let productIDs = [monthlyProductID, yearlyProductID]

    static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyPolicyURL = URL(string: "https://wangpingyi12-oss.github.io/personal-debt/privacy-policy-en-US.html")!
    static let applePrivacyURL = URL(string: "https://www.apple.com/legal/privacy/")!
    static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    static let fallbackOptions: [SubscriptionProductOption] = [
        SubscriptionProductOption(
            id: monthlyProductID,
            title: String(localized: "subscription.premium", defaultValue: "Premium"),
            durationText: String(localized: "subscription.monthly.duration", defaultValue: "1 month"),
            priceText: "$1.99",
            calloutText: String.localizedStringWithFormat(
                String(localized: "subscription.autoRenewsEvery", defaultValue: "Auto-renews every %@"),
                String(localized: "subscription.monthly.duration", defaultValue: "1 month")
            ),
            isFallbackPrice: true
        ),
        SubscriptionProductOption(
            id: yearlyProductID,
            title: String(localized: "subscription.premium", defaultValue: "Premium"),
            durationText: String(localized: "subscription.yearly.duration", defaultValue: "1 year"),
            priceText: "$17.99",
            calloutText: String.localizedStringWithFormat(
                String(localized: "subscription.autoRenewsEvery", defaultValue: "Auto-renews every %@"),
                String(localized: "subscription.yearly.duration", defaultValue: "1 year")
            ),
            isFallbackPrice: true
        )
    ]

    static func resolvedOptions(from loadedOptions: [SubscriptionProductOption]) -> [SubscriptionProductOption] {
        productIDs.compactMap { productID in
            loadedOptions.first { $0.id == productID }
                ?? fallbackOptions.first { $0.id == productID }
        }
    }

    static func fallbackOption(for productID: String) -> SubscriptionProductOption? {
        fallbackOptions.first { $0.id == productID }
    }
}

struct SubscriptionProductOption: Identifiable, Equatable {
    let id: String
    let title: String
    let durationText: String
    let priceText: String
    let calloutText: String
    let isFallbackPrice: Bool

    var isYearly: Bool {
        id == SubscriptionCatalog.yearlyProductID
    }

    init(
        id: String,
        title: String,
        durationText: String,
        priceText: String,
        calloutText: String,
        isFallbackPrice: Bool
    ) {
        self.id = id
        self.title = title
        self.durationText = durationText
        self.priceText = priceText
        self.calloutText = calloutText
        self.isFallbackPrice = isFallbackPrice
    }

    init(product: Product) {
        let fallback = SubscriptionCatalog.fallbackOption(for: product.id)
        let durationText = product.subscription?.subscriptionPeriod.displayText
            ?? fallback?.durationText
            ?? "Subscription"

        self.init(
            id: product.id,
            title: product.displayName.isEmpty ? (fallback?.title ?? String(localized: "subscription.premium", defaultValue: "Premium")) : product.displayName,
            durationText: durationText,
            priceText: product.displayPrice,
            calloutText: String.localizedStringWithFormat(
                String(localized: "subscription.autoRenewsEvery", defaultValue: "Auto-renews every %@"),
                durationText
            ),
            isFallbackPrice: false
        )
    }
}

extension Product.SubscriptionPeriod {
    var displayText: String {
        let unitText: String
        switch unit {
        case .day:
            unitText = value == 1 ? String(localized: "duration.day.one", defaultValue: "day") : String(localized: "duration.day.many", defaultValue: "days")
        case .week:
            unitText = value == 1 ? String(localized: "duration.week.one", defaultValue: "week") : String(localized: "duration.week.many", defaultValue: "weeks")
        case .month:
            unitText = value == 1 ? String(localized: "duration.month.one", defaultValue: "month") : String(localized: "duration.month.many", defaultValue: "months")
        case .year:
            unitText = value == 1 ? String(localized: "duration.year.one", defaultValue: "year") : String(localized: "duration.year.many", defaultValue: "years")
        @unknown default:
            unitText = String(localized: "duration.period", defaultValue: "period")
        }

        let format = String(localized: "duration.value", defaultValue: "%d %@")
        return String.localizedStringWithFormat(format, value, unitText)
    }
}
