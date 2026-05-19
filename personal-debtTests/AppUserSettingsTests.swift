import Foundation
import Testing
import SwiftUI
import UIKit
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

    @Test
    func enumIdentifiersAndTextHelpersCoverAllCases() {
        let identifiers = [
            DebtType.allCases.map(\.id),
            DebtStatus.allCases.map(\.id),
            PlanStatus.allCases.map(\.id),
            CreditCardStatementStatus.allCases.map(\.id),
            CreditCardOverdueRecordStatus.allCases.map(\.id),
            CreditCardOverdueRecordSource.allCases.map(\.id),
            StatementSource.allCases.map(\.id),
            BreakdownSource.allCases.map(\.id),
            StrategyType.allCases.map(\.id),
            LoanEntryMode.allCases.map(\.id),
            LoanRepaymentMethod.allCases.map(\.id),
            LoanPlanPeriodType.allCases.map(\.id),
            LoanPenaltyBaseType.allCases.map(\.id),
            LoanPenaltyCalculationMode.allCases.map(\.id),
            LoanOverdueBaseType.allCases.map(\.id),
            LoanOverdueFeeMode.allCases.map(\.id),
            LoanPenaltyInterestMode.allCases.map(\.id),
            LoanPaymentAllocationMode.allCases.map(\.id),
            LoanOverdueRecordSource.allCases.map(\.id),
            LoanOverdueRecordStatus.allCases.map(\.id),
            PersonalLendingRepaymentMethod.allCases.map(\.id),
            PersonalLendingPlanStatus.allCases.map(\.id),
            PersonalLendingOverdueRecordSource.allCases.map(\.id),
            PersonalLendingOverdueRecordStatus.allCases.map(\.id),
            AppLanguagePreference.allCases.map(\.id),
        ].flatMap { $0 }

        #expect(identifiers.allSatisfy { $0.isEmpty == false })
        #expect(DebtType.value(from: "missing", default: .loan) == .loan)
        #expect(AppText.string("coverage.missing.key", defaultValue: "Fallback") == "Fallback")
        #expect(AppText.money(Decimal(12), currencyCode: "USD").isEmpty == false)
        #expect(AppText.percent(Decimal(string: "0.25") ?? 0).isEmpty == false)
        #expect(AppText.date(nil).isEmpty == false)
        DebtType.allCases.forEach { #expect(AppText.debtType($0).isEmpty == false) }
        DebtStatus.allCases.forEach { #expect(AppText.debtStatus($0).isEmpty == false) }
        PlanStatus.allCases.forEach { #expect(AppText.planStatus($0).isEmpty == false) }
        PersonalLendingPlanStatus.allCases.forEach { #expect(AppText.personalPlanStatus($0).isEmpty == false) }
        CreditCardStatementStatus.allCases.forEach { #expect(AppText.statementStatus($0).isEmpty == false) }
        StatementSource.allCases.forEach { #expect(AppText.statementSource($0).isEmpty == false) }
        AppLanguagePreference.allCases.forEach { #expect($0.displayName.isEmpty == false) }
    }

    @Test
    func projectViewCoverageHarnessRendersWholeAppScenarios() throws {
        #if DEBUG
        try DebtConsoleCoverageHarness.exercisePureHelpers()
        let views = try DebtConsoleCoverageHarness.makeScenarioViews()

        #expect(views.count > 40)

        for view in views {
            let controller = UIHostingController(rootView: view)
            controller.view.frame = CGRect(x: 0, y: 0, width: 430, height: 932)
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        #endif
    }
}
