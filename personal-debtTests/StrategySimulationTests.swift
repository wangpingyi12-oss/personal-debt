import Foundation
import SwiftData
import Testing
@testable import personal_debt

@MainActor
struct StrategySimulationTests {
    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value) ?? 0
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    private func strategySchema() -> Schema {
        Schema([
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
        let schema = strategySchema()
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test
    func strategyComparisonValidatesInputsAndZeroBudgetCannotProgress() throws {
        let engine = StrategySimulationEngine()
        let debt = StrategyDebtSnapshot(
            debtType: .personalLending,
            name: "Friend",
            remainingAmount: 100,
            minimumPaymentAmount: 0
        )

        do {
            _ = try engine.generateComparison(
                request: StrategySimulationRequest(monthlyBudget: -1),
                debts: [debt]
            )
            #expect(Bool(false))
        } catch {
            #expect(error as? StrategySimulationError == .invalidMonthlyBudget)
        }

        do {
            _ = try engine.generateComparison(
                request: StrategySimulationRequest(monthlyBudget: 100),
                debts: []
            )
            #expect(Bool(false))
        } catch {
            #expect(error as? StrategySimulationError == .noDebtToSimulate)
        }

        let zeroBudget = try engine.generateComparison(
            request: StrategySimulationRequest(monthlyBudget: 0, maxMonths: 2),
            debts: [debt]
        )

        #expect(zeroBudget.simulations.count == 3)
        #expect(zeroBudget.simulations.allSatisfy { $0.simulation.status == .cannotProgress })
        #expect(zeroBudget.simulations.allSatisfy { $0.simulation.endingRemainingAmount == 100 })
    }

    @Test
    func avalancheUsesMarginalCostInsteadOfMechanicalOverduePriority() throws {
        let strategyDate = date(2026, 5, 16)
        let expensiveCard = StrategyDebtSnapshot(
            debtType: .creditCard,
            name: "Expensive Card",
            remainingAmount: 1000,
            minimumPaymentAmount: 0,
            dueDate: date(2026, 5, 30),
            revolvingDailyRate: decimal("0.01"),
            overdueFeeRate: 0,
            minimumOverdueFee: 0,
            penaltyDailyRate: 0
        )
        let overduePersonal = StrategyDebtSnapshot(
            debtType: .personalLending,
            name: "Overdue Personal",
            remainingAmount: 100,
            minimumPaymentAmount: 0,
            dueDate: date(2026, 4, 1),
            isOverdue: true,
            overdueDays: 45
        )

        let result = try StrategySimulationEngine().generateComparison(
            request: StrategySimulationRequest(strategyDate: strategyDate, monthlyBudget: 100, maxMonths: 1),
            debts: [expensiveCard, overduePersonal]
        )
        let avalanche = try #require(result.simulations.first { $0.simulation.strategyType == .avalanche })
        let snowball = try #require(result.simulations.first { $0.simulation.strategyType == .snowball })

        #expect(avalanche.allocations.first?.sourceDebtID == expensiveCard.id)
        #expect(snowball.allocations.first?.sourceDebtID == overduePersonal.id)
    }

    @Test
    func balancedAllocationRedistributesWithoutNegativeBalancesOrOverpayment() {
        let small = StrategyDebtSnapshot(
            debtType: .loan,
            name: "Small",
            remainingAmount: 50,
            minimumPaymentAmount: 0
        )
        let large = StrategyDebtSnapshot(
            debtType: .loan,
            name: "Large",
            remainingAmount: 150,
            minimumPaymentAmount: 0
        )

        let result = StrategySimulationEngine().generateSimulation(
            name: "Balanced",
            strategyType: .balanced,
            monthlyBudget: 500,
            debts: [small, large],
            maxMonths: 1
        )

        #expect(result.monthSnapshots.first?.allocatedAmount == 200)
        #expect(result.monthSnapshots.first?.unusedBudget == 300)
        #expect(result.allocations.allSatisfy { $0.remainingAmountAfterPayment >= 0 })
        #expect(result.simulation.estimatedPayoffMonth == 1)
    }

    @Test
    func recommendationDefaultsToLowestEstimatedExtraCost() throws {
        let strategyDate = date(2026, 5, 16)
        let highCostCard = StrategyDebtSnapshot(
            debtType: .creditCard,
            name: "High Cost Card",
            remainingAmount: 1000,
            minimumPaymentAmount: 0,
            revolvingDailyRate: decimal("0.01"),
            overdueFeeRate: 0,
            minimumOverdueFee: 0,
            penaltyDailyRate: 0
        )
        let smallPersonal = StrategyDebtSnapshot(
            debtType: .personalLending,
            name: "Small Personal",
            remainingAmount: 100,
            minimumPaymentAmount: 0
        )

        let result = try StrategySimulationEngine().generateComparison(
            request: StrategySimulationRequest(strategyDate: strategyDate, monthlyBudget: 100, maxMonths: 2),
            debts: [highCostCard, smallPersonal]
        )
        let avalanche = try #require(result.simulations.first { $0.simulation.strategyType == .avalanche })
        let snowball = try #require(result.simulations.first { $0.simulation.strategyType == .snowball })

        #expect(result.comparisonBatch.recommendedStrategy == .avalanche)
        #expect(avalanche.simulation.totalEstimatedCost < snowball.simulation.totalEstimatedCost)
    }

    @Test
    func personalLendingCreatesRiskWithoutDefaultFinancialCost() throws {
        let personal = StrategyDebtSnapshot(
            debtType: .personalLending,
            name: "Friend",
            remainingAmount: 300,
            minimumPaymentAmount: 0,
            dueDate: date(2026, 4, 1),
            isOverdue: true,
            overdueDays: 45
        )

        let result = try StrategySimulationEngine().generateComparison(
            request: StrategySimulationRequest(strategyDate: date(2026, 5, 16), monthlyBudget: 0, maxMonths: 1),
            debts: [personal]
        )

        #expect(result.simulations.allSatisfy { $0.simulation.totalEstimatedCost == 0 })
        #expect(result.simulations.flatMap(\.riskEvents).contains { $0.eventType == .informalPersonalLending })
    }

    @Test
    func loanSimulationDoesNotRecalculateNormalInterestAlreadyInPlan() throws {
        let loan = StrategyDebtSnapshot(
            debtType: .loan,
            name: "Loan",
            remainingAmount: 120,
            minimumPaymentAmount: 0,
            dueDate: date(2026, 6, 30),
            plans: [
                StrategyPlanSnapshot(
                    periodIndex: 1,
                    dueDate: date(2026, 6, 30),
                    remainingAmount: 120,
                    remainingPrincipal: 100,
                    remainingInterest: 20
                )
            ],
            annualInterestRate: decimal("1.00")
        )

        let result = try StrategySimulationEngine().generateComparison(
            request: StrategySimulationRequest(strategyDate: date(2026, 5, 16), monthlyBudget: 0, maxMonths: 1),
            debts: [loan]
        )

        #expect(result.simulations.allSatisfy { $0.simulation.totalEstimatedCost == 0 })
        #expect(result.simulations.allSatisfy { $0.simulation.endingRemainingAmount == 120 })
    }

    @Test
    func strategyServiceUsesMainStatementsAndPersistsSimulationWithoutMutatingFacts() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let card = CreditCardDebt(name: "Card", billingDay: 1, dueDay: 20)
        let rule = CreditCardCalculationRule(
            debtID: card.id,
            revolvingDailyRate: decimal("0.001"),
            overdueFeeRate: 0,
            minimumOverdueFee: 0,
            penaltyDailyRate: 0
        )
        let statement = CreditCardStatement(
            debtID: card.id,
            billingDate: date(2026, 5, 1),
            dueDate: date(2026, 5, 20),
            statementAmount: 500,
            minimumPaymentAmount: 50,
            minimumPaymentSource: "userProvided",
            paidAmount: 100,
            source: .userConfirmed
        )
        let breakdown = CreditCardStatementBreakdown(
            statementID: statement.id,
            source: .userProvided,
            revolvingInterest: 999,
            overdueFee: 999,
            penaltyInterest: 999
        )
        context.insert(card)
        context.insert(rule)
        context.insert(statement)
        context.insert(breakdown)
        try context.save()

        let service = StrategySimulationService(modelContext: context)
        let request = StrategySimulationRequest(
            strategyDate: date(2026, 5, 16),
            monthlyBudget: 200,
            maxMonths: 3
        )
        let snapshots = try service.makeDebtSnapshots(request: request)

        #expect(snapshots.count == 1)
        #expect(snapshots[0].remainingAmount == 400)
        #expect(snapshots[0].minimumPaymentAmount == 0)

        _ = try service.generateComparison(request: request)

        let batches = try context.fetch(FetchDescriptor<StrategyComparisonBatch>())
        let simulations = try context.fetch(FetchDescriptor<StrategySimulation>())
        let monthSnapshots = try context.fetch(FetchDescriptor<StrategyMonthSnapshot>())
        let allocations = try context.fetch(FetchDescriptor<StrategyDebtAllocation>())
        let costEvents = try context.fetch(FetchDescriptor<StrategyCostEvent>())

        #expect(batches.count == 1)
        #expect(simulations.count == 3)
        #expect(monthSnapshots.isEmpty == false)
        #expect(allocations.isEmpty == false)
        #expect(costEvents.isEmpty == false)
        #expect(statement.remainingAmount == 400)
        #expect(statement.status == .pending)
    }
}
