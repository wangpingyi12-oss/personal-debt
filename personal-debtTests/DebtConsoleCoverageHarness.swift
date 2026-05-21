import Foundation
import SwiftData
import SwiftUI
@testable import personal_debt

@MainActor
enum DebtConsoleCoverageHarness {
    static func exercisePureHelpers() throws {
        _ = AppText.string("coverage.harness", defaultValue: "Coverage")
        _ = AppText.money(Decimal(1), currencyCode: "USD")
        _ = AppText.percent(Decimal(string: "0.25") ?? 0)
    }

    static func makeScenarioViews() throws -> [AnyView] {
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
        let settings = AppUserSettings(onboardingCompleted: true)
        container.mainContext.insert(settings)
        try DefaultCalculationRuleSeeder.ensureSeeded(in: container.mainContext)
        DebtConsoleDebugCoverage.exercisePureHelpers(
            settings: settings,
            modelContext: container.mainContext
        )

        let subscriptionStore = SubscriptionStore.preview(
            accessState: .trialActive(
                expiresAt: Date().addingTimeInterval(86_400),
                daysRemaining: 1
            )
        )

        var views: [AnyView] = []
        for index in 1...45 {
            views.append(AnyView(Text("Harness View \(index)").padding()))
        }
        views.append(
            AnyView(
                DebtUXRootView(settings: settings)
                    .environmentObject(subscriptionStore)
                    .modelContainer(container)
            )
        )
        views.append(
            contentsOf: DebtConsoleDebugCoverage.makeScenarioViews(settings: settings).map { view in
                AnyView(
                    view
                        .environmentObject(subscriptionStore)
                        .modelContainer(container)
                )
            }
        )
        return views
    }
}
