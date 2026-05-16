import Foundation

enum TrialAccessStatus: Equatable {
    case notStarted
    case active(startDate: Date, expiresAt: Date, daysRemaining: Int)
    case expired(startDate: Date, expiredAt: Date)

    var isActive: Bool {
        if case .active = self {
            return true
        }

        return false
    }
}

struct TrialAccessPolicy {
    let durationDays: Int
    var calendar: Calendar

    init(durationDays: Int = 15, calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.durationDays = durationDays
        self.calendar = calendar
    }

    func status(startDate: Date?, now: Date) -> TrialAccessStatus {
        guard let startDate else {
            return .notStarted
        }

        let expiresAt = expirationDate(startDate: startDate)
        guard now < expiresAt else {
            return .expired(startDate: startDate, expiredAt: expiresAt)
        }

        let remainingSeconds = max(0, expiresAt.timeIntervalSince(now))
        let remainingDays = max(1, Int(ceil(remainingSeconds / 86_400)))
        return .active(
            startDate: startDate,
            expiresAt: expiresAt,
            daysRemaining: min(durationDays, remainingDays)
        )
    }

    func expirationDate(startDate: Date) -> Date {
        calendar.date(byAdding: .day, value: durationDays, to: startDate)
            ?? startDate.addingTimeInterval(TimeInterval(durationDays * 86_400))
    }
}

protocol TrialAccessStoring: AnyObject {
    var trialStartDate: Date? { get set }
}

final class UserDefaultsTrialAccessStore: TrialAccessStoring {
    private let userDefaults: UserDefaults
    private let key: String

    init(
        userDefaults: UserDefaults = .standard,
        key: String = "subscription.trialStartDate"
    ) {
        self.userDefaults = userDefaults
        self.key = key
    }

    var trialStartDate: Date? {
        get {
            userDefaults.object(forKey: key) as? Date
        }
        set {
            userDefaults.set(newValue, forKey: key)
        }
    }
}

final class InMemoryTrialAccessStore: TrialAccessStoring {
    var trialStartDate: Date?

    init(trialStartDate: Date? = nil) {
        self.trialStartDate = trialStartDate
    }
}
