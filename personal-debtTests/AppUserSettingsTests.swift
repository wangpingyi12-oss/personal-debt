import Foundation
import Testing
@testable import personal_debt

@MainActor
struct AppUserSettingsTests {
    @Test
    func defaultLanguageFollowsSystem() {
        let settings = AppUserSettings()

        #expect(settings.languagePreference == .system)
        #expect(settings.languagePreference.localeIdentifier == nil)
        #expect(settings.preferredLocale.identifier == Locale.autoupdatingCurrent.identifier)
    }

    @Test
    func explicitLanguageStoresLocaleIdentifier() {
        let settings = AppUserSettings(languagePreference: .zhHans)

        #expect(settings.languagePreferenceRawValue == AppLanguagePreference.zhHans.rawValue)
        #expect(settings.languagePreference.localeIdentifier == "zh-Hans")

        settings.languagePreference = .english

        #expect(settings.languagePreferenceRawValue == AppLanguagePreference.english.rawValue)
        #expect(settings.languagePreference.localeIdentifier == "en")
    }
}
