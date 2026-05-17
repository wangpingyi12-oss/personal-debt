import Foundation

enum SubscriptionAccessState: Equatable {
    case loading
    case trialActive(expiresAt: Date, daysRemaining: Int)
    case subscribed(productID: String, renewalDate: Date?)
    case readOnly(trialExpiredAt: Date)

    var allowsFullAccess: Bool {
        switch self {
        case .trialActive, .subscribed:
            return true
        case .loading, .readOnly:
            return false
        }
    }

    var isReadOnly: Bool {
        if case .readOnly = self {
            return true
        }

        return false
    }

    var statusTitle: String {
        switch self {
        case .loading:
            return String(localized: "subscription.status.checking", defaultValue: "Checking access")
        case .trialActive:
            return String(localized: "subscription.status.trial", defaultValue: "Free trial active")
        case .subscribed:
            return String(localized: "subscription.status.active", defaultValue: "Subscription active")
        case .readOnly:
            return String(localized: "subscription.status.readOnly", defaultValue: "Read-only mode")
        }
    }

    var statusDetail: String {
        switch self {
        case .loading:
            return String(localized: "subscription.detail.checking", defaultValue: "Your subscription status is being refreshed.")
        case .trialActive(_, let daysRemaining):
            let format = daysRemaining == 1
                ? String(localized: "subscription.detail.trial.one", defaultValue: "%d day remaining in your free trial.")
                : String(localized: "subscription.detail.trial.many", defaultValue: "%d days remaining in your free trial.")
            return String.localizedStringWithFormat(format, daysRemaining)
        case .subscribed(_, let renewalDate):
            guard let renewalDate else {
                return String(localized: "subscription.detail.activeNoDate", defaultValue: "Full access is unlocked by your App Store subscription.")
            }

            let format = String(localized: "subscription.detail.activeUntil", defaultValue: "Full access is unlocked until %@.")
            return String.localizedStringWithFormat(format, renewalDate.formatted(date: .abbreviated, time: .omitted))
        case .readOnly:
            return String(localized: "subscription.detail.readOnly", defaultValue: "Your free trial has ended. Existing data remains available to view.")
        }
    }
}

struct ActiveSubscription: Equatable {
    let productID: String
    let renewalDate: Date?
}

struct SubscriptionAccessEvaluator {
    var trialPolicy: TrialAccessPolicy

    init(trialPolicy: TrialAccessPolicy = TrialAccessPolicy()) {
        self.trialPolicy = trialPolicy
    }

    func evaluate(
        trialStartDate: Date?,
        activeSubscription: ActiveSubscription?,
        now: Date
    ) -> SubscriptionAccessState {
        if let activeSubscription {
            return .subscribed(
                productID: activeSubscription.productID,
                renewalDate: activeSubscription.renewalDate
            )
        }

        switch trialPolicy.status(startDate: trialStartDate, now: now) {
        case .notStarted:
            return .loading
        case .active(_, let expiresAt, let daysRemaining):
            return .trialActive(expiresAt: expiresAt, daysRemaining: daysRemaining)
        case .expired(_, let expiredAt):
            return .readOnly(trialExpiredAt: expiredAt)
        }
    }
}

enum SubscriptionAccessError: LocalizedError, Equatable {
    case readOnly

    var errorDescription: String? {
        switch self {
        case .readOnly:
            return String(localized: "subscription.error.readOnly", defaultValue: "A subscription is required to make changes after the free trial ends.")
        }
    }
}

@MainActor
protocol WriteAccessAuthorizing: AnyObject {
    func requireWriteAccess() throws
}

@MainActor
final class UnrestrictedWriteAccessAuthorizer: WriteAccessAuthorizing {
    static let shared = UnrestrictedWriteAccessAuthorizer()

    private init() {}

    func requireWriteAccess() throws {}
}
