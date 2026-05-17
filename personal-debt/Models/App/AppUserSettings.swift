import Foundation
import SwiftData

enum AppLanguagePreference: String, Codable, CaseIterable, Identifiable {
    case system
    case zhHans
    case english

    var id: String { rawValue }

    var localeIdentifier: String? {
        switch self {
        case .system:
            return nil
        case .zhHans:
            return "zh-Hans"
        case .english:
            return "en"
        }
    }

    var displayName: String {
        switch self {
        case .system:
            return String(localized: "settings.language.system", defaultValue: "Follow System")
        case .zhHans:
            return String(localized: "settings.language.zhHans", defaultValue: "Simplified Chinese")
        case .english:
            return String(localized: "settings.language.english", defaultValue: "English")
        }
    }
}

@Model
final class AppUserSettings {
    var id: UUID
    var onboardingCompleted: Bool
    var monthlyRepaymentBudget: Decimal
    var currencyCode: String
    var languagePreferenceRawValue: String
    var remindersEnabled: Bool
    var strategyDataChanged: Bool
    var createdAt: Date
    var updatedAt: Date

    var languagePreference: AppLanguagePreference {
        get { AppLanguagePreference(rawValue: languagePreferenceRawValue) ?? .system }
        set {
            languagePreferenceRawValue = newValue.rawValue
            updatedAt = Date()
        }
    }

    var preferredLocale: Locale {
        if let localeIdentifier = languagePreference.localeIdentifier {
            return Locale(identifier: localeIdentifier)
        }
        return .autoupdatingCurrent
    }

    init(
        id: UUID = UUID(),
        onboardingCompleted: Bool = false,
        monthlyRepaymentBudget: Decimal = 0,
        currencyCode: String = Locale.current.currency?.identifier ?? "USD",
        languagePreference: AppLanguagePreference = .system,
        remindersEnabled: Bool = false,
        strategyDataChanged: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.onboardingCompleted = onboardingCompleted
        self.monthlyRepaymentBudget = monthlyRepaymentBudget
        self.currencyCode = currencyCode
        self.languagePreferenceRawValue = languagePreference.rawValue
        self.remindersEnabled = remindersEnabled
        self.strategyDataChanged = strategyDataChanged
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
