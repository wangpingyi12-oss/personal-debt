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
            return "Checking access"
        case .trialActive:
            return "Free trial active"
        case .subscribed:
            return "Subscription active"
        case .readOnly:
            return "Read-only mode"
        }
    }

    var statusDetail: String {
        switch self {
        case .loading:
            return "Your subscription status is being refreshed."
        case .trialActive(_, let daysRemaining):
            return "\(daysRemaining) day\(daysRemaining == 1 ? "" : "s") remaining in your free trial."
        case .subscribed(_, let renewalDate):
            guard let renewalDate else {
                return "Full access is unlocked by your App Store subscription."
            }

            return "Full access is unlocked until \(renewalDate.formatted(date: .abbreviated, time: .omitted))."
        case .readOnly:
            return "Your free trial has ended. Existing data remains available to view."
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
            return "A subscription is required to make changes after the free trial ends."
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
