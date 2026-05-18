import Foundation
import SwiftData
import Testing
@testable import personal_debt

@MainActor
struct FortyDebtScenarioTests {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    private func scenarioSchema() -> Schema {
        Schema([
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
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = scenarioSchema()
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test
    func fortyDebtScenarioAnalyticsMatchIndependentExpectedValues() {
        let today = date(2026, 5, 17)
        let scenario = FortyDebtScenarioFixtures.makeScenario(today: today)
        let expected = scenario.expected
        let period = AnalyticsSupport.monthPeriod(containing: today)

        let debtAnalytics = DebtAnalyticsService().generate(
            creditCardDebts: scenario.creditCards,
            creditCardStatements: scenario.cardStatements,
            loanDebts: scenario.loans,
            loanPlans: scenario.loanPlans,
            personalLendingDebts: scenario.personalDebts,
            personalLendingPlans: scenario.personalPlans,
            period: period
        )
        let paymentAnalytics = PaymentAnalyticsService().generate(
            creditCardDebts: scenario.creditCards,
            creditCardPayments: scenario.cardPayments,
            loanDebts: scenario.loans,
            loanPayments: scenario.loanPayments,
            personalLendingDebts: scenario.personalDebts,
            personalLendingPayments: scenario.personalPayments,
            period: period
        )
        let overdueAnalytics = OverdueAnalyticsService().generate(
            creditCardDebts: scenario.creditCards,
            creditCardStatements: scenario.cardStatements,
            creditCardBreakdowns: scenario.cardBreakdowns,
            loanDebts: scenario.loans,
            loanPlans: scenario.loanPlans,
            loanOverdues: scenario.loanOverdues,
            personalLendingDebts: scenario.personalDebts,
            personalLendingPlans: scenario.personalPlans,
            personalLendingOverdues: scenario.personalOverdues,
            today: today
        )
        let costAnalytics = CostAnalyticsService().generate(
            creditCardDebts: scenario.creditCards,
            creditCardStatements: scenario.cardStatements,
            creditCardBreakdowns: scenario.cardBreakdowns,
            loanDebts: scenario.loans,
            loanPlans: scenario.loanPlans,
            loanOverdues: scenario.loanOverdues,
            personalLendingDebts: scenario.personalDebts,
            personalLendingPlans: scenario.personalPlans
        )
        let debtItems = DebtReadService().debtListItems(
            creditCards: scenario.creditCards,
            statements: scenario.cardStatements,
            loans: scenario.loans,
            loanPlans: scenario.loanPlans,
            personalDebts: scenario.personalDebts,
            personalPlans: scenario.personalPlans,
            personalOverdues: scenario.personalOverdues,
            today: today
        )

        #expect(scenario.allDebtCount == 40)
        #expect(expected.creditCardCount == 14)
        #expect(expected.loanCount == 14)
        #expect(expected.personalLendingCount == 12)
        #expect(debtItems.count == 40)
        #expect(debtAnalytics.totalDebtCount == expected.totalDebtCount)
        #expect(debtAnalytics.creditCardRemainingAmount == expected.creditCardRemainingAmount)
        #expect(debtAnalytics.loanRemainingAmount == expected.loanRemainingAmount)
        #expect(debtAnalytics.personalLendingRemainingAmount == expected.personalLendingRemainingAmount)
        #expect(debtAnalytics.totalRemainingAmount == expected.totalRemainingAmount)
        #expect(debtAnalytics.currentMonthPlannedRepaymentAmount == expected.currentMonthPlannedRepaymentAmount)
        #expect(debtAnalytics.creditCardCurrentStatementAmount == expected.creditCardCurrentStatementAmount)
        #expect(debtAnalytics.creditCardCurrentStatementPaidAmount == expected.creditCardCurrentStatementPaidAmount)

        #expect(paymentAnalytics.currentMonthPaidAmount == expected.currentMonthPaidAmount)
        #expect(paymentAnalytics.cumulativePaidAmount == expected.cumulativePaidAmount)
        #expect(paymentAnalytics.creditCardCurrentMonthPaidAmount == expected.creditCardCurrentMonthPaidAmount)
        #expect(paymentAnalytics.loanCurrentMonthPaidAmount == expected.loanCurrentMonthPaidAmount)
        #expect(paymentAnalytics.personalLendingCurrentMonthPaidAmount == expected.personalLendingCurrentMonthPaidAmount)
        #expect(paymentAnalytics.currentMonthPaymentRecordCount == expected.currentMonthCreditCardPaymentRecordCount)
        #expect(paymentAnalytics.currentMonthPaymentInputCount == expected.currentMonthFixedPaymentInputCount)

        #expect(overdueAnalytics.currentOverdueDebtCount == expected.currentOverdueDebtCount)
        #expect(overdueAnalytics.currentOverduePeriodCount == expected.currentOverduePeriodCount)
        #expect(overdueAnalytics.currentOverdueTotalAmount == expected.currentOverdueTotalAmount)
        #expect(overdueAnalytics.creditCardMinimumPaymentGap == expected.creditCardMinimumPaymentGap)
        #expect(overdueAnalytics.creditCardOverdueStatementRemainingAmount == expected.creditCardOverdueStatementRemainingAmount)
        #expect(overdueAnalytics.loanOverdueAmount == expected.loanOverdueAmount)
        #expect(overdueAnalytics.personalLendingPastDueAmount == expected.personalLendingPastDueAmount)
        #expect(overdueAnalytics.overdueFeeTotalAmount == expected.overdueFeeTotalAmount)
        #expect(overdueAnalytics.penaltyInterestTotalAmount == expected.penaltyInterestTotalAmount)
        #expect(overdueAnalytics.riskLevel == .high)

        #expect(costAnalytics.totalCostAmount == expected.totalCostAmount)
        #expect(costAnalytics.creditCardCostAmount == expected.creditCardCostAmount)
        #expect(costAnalytics.loanCostAmount == expected.loanCostAmount)
        #expect(costAnalytics.personalLendingInterestAmount == expected.personalLendingInterestAmount)
        #expect(costAnalytics.creditCardBreakdownConflictCount == expected.creditCardBreakdownConflictCount)
    }

    @Test
    func fortyDebtScenarioFeedsStrategySimulationAndPersistsResults() throws {
        let today = date(2026, 5, 17)
        let container = try makeContainer()
        let context = container.mainContext
        let scenario = FortyDebtScenarioFixtures.makeScenario(today: today)
        try FortyDebtScenarioFixtures.insert(scenario, into: context)

        let service = StrategySimulationService(modelContext: context)
        let request = StrategySimulationRequest(strategyDate: today, monthlyBudget: 50_000, maxMonths: 12)
        let snapshots = try service.makeDebtSnapshots(request: request)
        let result = try service.generateComparison(request: request)
        let savedBatches = try context.fetch(FetchDescriptor<StrategyComparisonBatch>())
        let savedSimulations = try context.fetch(FetchDescriptor<StrategySimulation>())

        #expect(snapshots.count == 37)
        #expect(snapshots.contains { $0.debtType == .creditCard && $0.name == "CC-01 Grocery Visa" })
        #expect(snapshots.contains { $0.debtType == .loan && $0.name == "Loan-01 Equal Principal" })
        #expect(snapshots.contains { $0.debtType == .personalLending && $0.name == "Friend-01 No Fixed Plan" })
        #expect(result.simulations.count == 3)
        #expect(result.comparisonBatch.monthlyBudget == 50_000)
        #expect(result.comparisonBatch.recommendedStrategy != nil)
        #expect(savedBatches.count == 1)
        #expect(savedSimulations.count == 3)
    }
}
