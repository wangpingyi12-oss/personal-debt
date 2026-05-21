import Foundation
import SwiftData
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
    func uiTestDataResetterClearsProjectModelsAndSeedsSettings() throws {
        #if DEBUG
        let schema = Schema([
            AppUserSettings.self,
            CreditCardDebt.self,
            CreditCardCalculationRule.self,
            CreditCardStatement.self,
            CreditCardStatementBreakdown.self,
            CreditCardRepaymentPlan.self,
            CreditCardPaymentRecord.self,
            CreditCardOverdueRecord.self,
            CreditCardInstallmentPlan.self,
            LoanDebt.self,
            LoanRepaymentPlan.self,
            LoanPaymentRecord.self,
            LoanPaymentAllocationDetail.self,
            LoanOverdueRecord.self,
            LoanCalculationRule.self,
            PersonalLendingDebt.self,
            PersonalLendingPlan.self,
            PersonalLendingPaymentRecord.self,
            PersonalLendingAllocationDetail.self,
            PersonalLendingOverdueRecord.self,
            StrategyComparisonBatch.self,
            StrategySimulation.self,
            StrategyMonthSnapshot.self,
            StrategyDebtAllocation.self,
            StrategyCostEvent.self,
            StrategyRiskEvent.self,
            DebtAnalyticsSnapshot.self,
            PaymentAnalyticsSnapshot.self,
            OverdueAnalyticsSnapshot.self,
            CostAnalyticsSnapshot.self,
            AnalyticsInvalidationState.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let card = CreditCardDebt(name: "Reset Card", billingDay: 1, dueDay: 20)
        let loan = LoanDebt(
            name: "Reset Loan",
            creditorName: "Bank",
            repaymentMethod: .equalPrincipal,
            originalPrincipal: 100,
            annualInterestRate: 0,
            startDate: Date(),
            endDate: Date().addingTimeInterval(86_400),
            repaymentDay: 1,
            termCount: 1
        )
        let personal = PersonalLendingDebt(
            name: "Reset Friend",
            lenderName: "Alex",
            principalAmount: 100,
            fixedInterestAmount: 0,
            borrowedDate: Date(),
            agreedEndDate: Date().addingTimeInterval(86_400),
            repaymentMethod: .noFixedPlan,
            isInterestBearing: false,
            termCount: 0
        )

        context.insert(AppUserSettings(onboardingCompleted: false))
        context.insert(card)
        context.insert(CreditCardCalculationRule(debtID: card.id))
        context.insert(loan)
        context.insert(LoanCalculationRule(debtID: loan.id))
        context.insert(personal)
        try context.save()

        #expect(UITestDataResetter.resetDataForTesting(modelContext: context, onboardingCompleted: true))

        let settings = try context.fetch(FetchDescriptor<AppUserSettings>())
        #expect(settings.count == 1)
        #expect(settings.first?.onboardingCompleted == true)
        #expect(try context.fetch(FetchDescriptor<CreditCardDebt>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<LoanDebt>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PersonalLendingDebt>()).isEmpty)
        #endif
    }

    @Test
    func projectViewCoverageHarnessRendersWholeAppScenarios() throws {
        #if DEBUG
        try DebtConsoleCoverageHarness.exercisePureHelpers()
        let views = try DebtConsoleCoverageHarness.makeScenarioViews()

        #expect(views.count > 40)

        for view in views {
            let frame = CGRect(x: 0, y: 0, width: 430, height: 6_000)
            let window = UIWindow(frame: frame)
            let controller = UIHostingController(rootView: view)
            controller.view.frame = frame
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            window.rootViewController = nil
            window.isHidden = true
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        #endif
    }
}
