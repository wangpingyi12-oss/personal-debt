import Foundation
import SwiftData

#if DEBUG
@MainActor
enum UITestDataResetter {
    private static var didReset = false

    static func resetDataOnlyIfRequested(modelContext: ModelContext, onboardingCompleted: Bool) -> Bool {
        guard ProcessInfo.processInfo.arguments.contains("-UITestResetData") else { return false }
        guard didReset == false else { return true }
        didReset = true

        return resetData(modelContext: modelContext, onboardingCompleted: onboardingCompleted)
    }

    static func resetDataForTesting(modelContext: ModelContext, onboardingCompleted: Bool) -> Bool {
        resetData(modelContext: modelContext, onboardingCompleted: onboardingCompleted)
    }

    private static func resetData(modelContext: ModelContext, onboardingCompleted: Bool) -> Bool {
        do {
            try deleteAll(StrategyRiskEvent.self, in: modelContext)
            try deleteAll(StrategyCostEvent.self, in: modelContext)
            try deleteAll(StrategyDebtAllocation.self, in: modelContext)
            try deleteAll(StrategyMonthSnapshot.self, in: modelContext)
            try deleteAll(StrategySimulation.self, in: modelContext)
            try deleteAll(StrategyComparisonBatch.self, in: modelContext)
            try deleteAll(DebtAnalyticsSnapshot.self, in: modelContext)
            try deleteAll(PaymentAnalyticsSnapshot.self, in: modelContext)
            try deleteAll(OverdueAnalyticsSnapshot.self, in: modelContext)
            try deleteAll(CostAnalyticsSnapshot.self, in: modelContext)
            try deleteAll(AnalyticsInvalidationState.self, in: modelContext)
            try deleteAll(CreditCardInstallmentPlan.self, in: modelContext)
            try deleteAll(CreditCardOverdueRecord.self, in: modelContext)
            try deleteAll(CreditCardPaymentRecord.self, in: modelContext)
            try deleteAll(CreditCardRepaymentPlan.self, in: modelContext)
            try deleteAll(CreditCardStatementBreakdown.self, in: modelContext)
            try deleteAll(CreditCardStatement.self, in: modelContext)
            try deleteAll(CreditCardCalculationRule.self, in: modelContext)
            try deleteAll(CreditCardDebt.self, in: modelContext)
            try deleteAll(LoanPaymentAllocationDetail.self, in: modelContext)
            try deleteAll(LoanPaymentRecord.self, in: modelContext)
            try deleteAll(LoanOverdueRecord.self, in: modelContext)
            try deleteAll(LoanCalculationRule.self, in: modelContext)
            try deleteAll(LoanRepaymentPlan.self, in: modelContext)
            try deleteAll(LoanDebt.self, in: modelContext)
            try deleteAll(PersonalLendingAllocationDetail.self, in: modelContext)
            try deleteAll(PersonalLendingPaymentRecord.self, in: modelContext)
            try deleteAll(PersonalLendingOverdueRecord.self, in: modelContext)
            try deleteAll(PersonalLendingPlan.self, in: modelContext)
            try deleteAll(PersonalLendingDebt.self, in: modelContext)
            try deleteAll(AppUserSettings.self, in: modelContext)
            modelContext.insert(AppUserSettings(onboardingCompleted: onboardingCompleted))
            try DefaultCalculationRuleSeeder.ensureSeeded(in: modelContext)
        } catch {
            assertionFailure("Could not reset UI test data: \(error)")
        }

        return true
    }

    private static func deleteAll<T: PersistentModel>(_ modelType: T.Type, in modelContext: ModelContext) throws {
        let items = try modelContext.fetch(FetchDescriptor<T>())
        for item in items {
            modelContext.delete(item)
        }
    }
}
#endif
