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
            title: "Monthly Premium",
            durationText: "1 month",
            priceText: "$1.99/month",
            calloutText: "Auto-renews monthly",
            isFallbackPrice: true
        ),
        SubscriptionProductOption(
            id: yearlyProductID,
            title: "Yearly Premium",
            durationText: "1 year",
            priceText: "$17.99/year",
            calloutText: "Auto-renews yearly",
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
            title: product.displayName.isEmpty ? (fallback?.title ?? "Premium") : product.displayName,
            durationText: durationText,
            priceText: "\(product.displayPrice)/\(durationText.priceSuffix)",
            calloutText: "Auto-renews every \(durationText)",
            isFallbackPrice: false
        )
    }
}

extension Product.SubscriptionPeriod {
    var displayText: String {
        let unitText: String
        switch unit {
        case .day:
            unitText = value == 1 ? "day" : "days"
        case .week:
            unitText = value == 1 ? "week" : "weeks"
        case .month:
            unitText = value == 1 ? "month" : "months"
        case .year:
            unitText = value == 1 ? "year" : "years"
        @unknown default:
            unitText = "period"
        }

        return value == 1 ? "1 \(unitText)" : "\(value) \(unitText)"
    }
}

private extension String {
    var priceSuffix: String {
        if contains("month") {
            return "month"
        }

        if contains("year") {
            return "year"
        }

        if contains("week") {
            return "week"
        }

        if contains("day") {
            return "day"
        }

        return "period"
    }
}
