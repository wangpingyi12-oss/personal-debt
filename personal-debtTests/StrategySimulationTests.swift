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

    private func expectDebtServiceValidation(_ work: () throws -> Void) {
        do {
            try work()
            #expect(Bool(false))
        } catch let error as DebtServiceError {
            if case .validationFailed = error {
                #expect(Bool(true))
            } else {
                #expect(Bool(false))
            }
        } catch {
            #expect(Bool(false))
        }
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
            request: StrategySimulationRequest(monthlyBudget: 0),
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
            request: StrategySimulationRequest(strategyDate: strategyDate, monthlyBudget: 100),
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
            debts: [small, large]
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
            request: StrategySimulationRequest(strategyDate: strategyDate, monthlyBudget: 100),
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
            request: StrategySimulationRequest(strategyDate: date(2026, 5, 16), monthlyBudget: 0),
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
            request: StrategySimulationRequest(strategyDate: date(2026, 5, 16), monthlyBudget: 0),
            debts: [loan]
        )

        #expect(result.simulations.allSatisfy { $0.monthSnapshots.first?.addedInterestAmount == 0 })
        #expect(result.simulations.allSatisfy { $0.monthSnapshots.first?.addedPenaltyInterest == 0 })
        #expect(result.simulations.allSatisfy { $0.monthSnapshots.first?.remainingAmountAfterPayment == 120 })
    }

    @Test
    func strategyComparisonReportsPayoffMonthWhenBudgetCanClearDebt() throws {
        let debt = StrategyDebtSnapshot(
            debtType: .personalLending,
            name: "Friend",
            remainingAmount: 300,
            minimumPaymentAmount: 0
        )

        let result = try StrategySimulationEngine().generateComparison(
            request: StrategySimulationRequest(strategyDate: date(2026, 5, 16), monthlyBudget: 100),
            debts: [debt]
        )

        #expect(result.simulations.count == 3)
        #expect(result.simulations.allSatisfy { $0.simulation.estimatedPayoffMonth == 3 })
        #expect(result.simulations.allSatisfy { $0.summary.payoffMonth == 3 })
    }

    @Test
    func strategyComparisonLeavesPayoffMonthEmptyWhenDebtCannotClearWithinWindow() throws {
        let debt = StrategyDebtSnapshot(
            debtType: .personalLending,
            name: "Friend",
            remainingAmount: 300,
            minimumPaymentAmount: 0
        )

        let result = try StrategySimulationEngine().generateComparison(
            request: StrategySimulationRequest(strategyDate: date(2026, 5, 16), monthlyBudget: 0),
            debts: [debt]
        )

        #expect(result.simulations.count == 3)
        #expect(result.simulations.allSatisfy { $0.simulation.estimatedPayoffMonth == nil })
        #expect(result.simulations.allSatisfy { $0.simulation.status == .cannotProgress })
    }

    @Test
    func strategyServiceCanPreviewWithoutPersistingThenSaveSelectedStrategy() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let service = StrategySimulationService(modelContext: context)
        let request = StrategySimulationRequest(
            strategyDate: date(2026, 5, 16),
            monthlyBudget: 100
        )
        let debt = PersonalLendingDebt(
            name: "Friend",
            principalAmount: 300,
            borrowedDate: date(2026, 5, 1),
            repaymentMethod: .noFixedPlan
        )
        context.insert(debt)
        try context.save()

        let preview = try service.previewComparison(request: request)

        #expect(try context.fetch(FetchDescriptor<StrategyComparisonBatch>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<StrategySimulation>()).isEmpty)

        let saved = try service.saveComparisonResult(preview, selectedStrategy: .snowball)
        let batches = try context.fetch(FetchDescriptor<StrategyComparisonBatch>())
        let simulations = try context.fetch(FetchDescriptor<StrategySimulation>())
        let monthSnapshots = try context.fetch(FetchDescriptor<StrategyMonthSnapshot>())
        let allocations = try context.fetch(FetchDescriptor<StrategyDebtAllocation>())

        #expect(saved.comparisonBatch.recommendedStrategy == .snowball)
        #expect(saved.simulations.count == 1)
        #expect(saved.simulations.first?.simulation.strategyType == .snowball)
        #expect(batches.count == 1)
        #expect(batches.first?.recommendedStrategy == .snowball)
        #expect(simulations.count == 1)
        #expect(simulations.first?.strategyType == .snowball)
        #expect(monthSnapshots.isEmpty == false)
        #expect(allocations.isEmpty == false)
        #expect(monthSnapshots.allSatisfy { $0.simulationID == simulations.first?.id })
        #expect(allocations.allSatisfy { $0.simulationID == simulations.first?.id })

        var missingSelected = preview
        missingSelected.simulations.removeAll { $0.simulation.strategyType == .balanced }
        expectDebtServiceValidation {
            _ = try service.saveComparisonResult(missingSelected, selectedStrategy: .balanced)
        }
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
            monthlyBudget: 200
        )
        let snapshots = try service.makeDebtSnapshots(request: request)

        #expect(snapshots.count == 1)
        #expect(snapshots[0].remainingAmount == 400)
        #expect(snapshots[0].minimumPaymentAmount == 0)
        #expect(request.maxMonths == StrategySimulationRequest.fixedMaxMonths)

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

    @Test
    func strategyServiceBuildsLoanAndPersonalSnapshotsFromPlansAndFallbackBalances() throws {
        let loanService = LoanDebtService()
        let (_, loan, loanPlans) = try loanService.createDebt(
            LoanDebtInput(
                name: "Loan",
                creditorName: "Bank",
                entryMode: .newLoan,
                repaymentMethod: .equalPrincipal,
                originalPrincipal: 600,
                openingPrincipalForManagement: nil,
                annualInterestRate: decimal("0.12"),
                startDate: date(2026, 1, 1),
                managementStartDate: nil,
                endDate: date(2026, 3, 10),
                repaymentDay: 10,
                termCount: 3,
                currencyCode: "USD"
            )
        )
        loanPlans[0].status = .overdue
        loanPlans[0].overdueDays = 4
        loanPlans[0].remainingOverdueFee = 6
        loanPlans[0].remainingPenaltyInterest = 2
        loanPlans[0].remainingTotalAmount = loanPlans[0].remainingPrincipal + loanPlans[0].remainingInterest + 8
        let loanRule = LoanCalculationRule(
            debtID: loan.id,
            overdueFeeMode: .fixed,
            fixedOverdueFee: 6,
            penaltyInterestMode: .fixedDailyRate,
            fixedPenaltyDailyRate: decimal("0.001")
        )
        let globalRule = LoanCalculationRule.builtInDefault(now: date(2026, 1, 1))

        let planPersonal = PersonalLendingDebt(
            name: "Installment Friend",
            lenderName: "Alex",
            principalAmount: 900,
            fixedInterestAmount: 90,
            borrowedDate: date(2026, 1, 1),
            agreedEndDate: date(2026, 6, 10),
            repaymentMethod: .equalPrincipalEqualInterest,
            isInterestBearing: true,
            monthlyRepaymentDay: 10,
            termCount: 6
        )
        let personalPlan = PersonalLendingPlan(
            debtID: planPersonal.id,
            periodIndex: 1,
            dueDate: date(2026, 4, 10),
            scheduledPrincipal: 150,
            scheduledInterest: 15,
            paidAmount: 0,
            status: .pending
        )
        let openPersonal = PersonalLendingDebt(
            name: "Open Friend",
            lenderName: "Sam",
            principalAmount: 500,
            fixedInterestAmount: 0,
            borrowedDate: date(2026, 1, 1),
            agreedEndDate: nil,
            repaymentMethod: .noFixedPlan,
            isInterestBearing: false,
            monthlyRepaymentDay: nil,
            termCount: 0
        )
        let paidLoan = LoanDebt(
            name: "Paid Loan",
            creditorName: "",
            repaymentMethod: .equalPrincipal,
            originalPrincipal: 100,
            annualInterestRate: 0,
            startDate: date(2026, 1, 1),
            endDate: date(2026, 1, 10),
            repaymentDay: 10,
            termCount: 1,
            status: .paidOff
        )

        let service = StrategySimulationService()
        let snapshots = service.makeDebtSnapshots(
            request: StrategySimulationRequest(
                strategyDate: date(2026, 5, 16),
                monthlyBudget: 300
            ),
            creditCardDebts: [],
            creditCardStatements: [],
            creditCardRules: [],
            loanDebts: [loan, paidLoan],
            loanPlans: loanPlans,
            loanRules: [globalRule, loanRule],
            personalLendingDebts: [planPersonal, openPersonal],
            personalLendingPlans: [personalPlan]
        )

        let loanSnapshot = try #require(snapshots.first { $0.id == loan.id })
        #expect(loanSnapshot.debtType == .loan)
        #expect(loanSnapshot.isOverdue)
        #expect(loanSnapshot.riskWeight == 2)
        #expect(loanSnapshot.plans.isEmpty == false)
        #expect(loanSnapshot.loanFixedOverdueFee == 6)
        #expect(loanSnapshot.fixedPenaltyDailyRate == decimal("0.001"))
        #expect(loanSnapshot.minimumPaymentAmount > 0)

        let plannedPersonalSnapshot = try #require(snapshots.first { $0.id == planPersonal.id })
        #expect(plannedPersonalSnapshot.debtType == .personalLending)
        #expect(plannedPersonalSnapshot.dataSource == "personalLendingPlan")
        #expect(plannedPersonalSnapshot.minimumPaymentAmount == personalPlan.remainingAmount)
        #expect(plannedPersonalSnapshot.isOverdue)

        let openPersonalSnapshot = try #require(snapshots.first { $0.id == openPersonal.id })
        #expect(openPersonalSnapshot.dataSource == "personalLendingBalance")
        #expect(openPersonalSnapshot.minimumPaymentAmount == 0)
        #expect(openPersonalSnapshot.userRiskNotes.isEmpty == false)
        #expect(snapshots.contains { $0.id == paidLoan.id } == false)
    }

    @Test
    func strategyEngineSurfacesCreditCardCostAndFallbackRiskBranches() throws {
        let card = StrategyDebtSnapshot(
            debtType: .creditCard,
            name: "Risky Card",
            remainingAmount: 1000,
            minimumPaymentAmount: 100,
            dueDate: date(2026, 5, 10),
            dataSource: "fallbackStatement",
            isFallbackData: true,
            isOverdue: true,
            overdueDays: 15,
            userRiskNotes: ["Confirm issuer balance before acting."],
            revolvingInterestEnabled: true,
            revolvingDailyRate: decimal("0.002"),
            overdueFeeRate: decimal("0.01"),
            minimumOverdueFee: 25,
            fixedOverdueFee: 40,
            penaltyDailyRate: decimal("0.001"),
            penaltyBaseUsesStatementAmount: true
        )

        let result = try StrategySimulationEngine().generateComparison(
            request: StrategySimulationRequest(strategyDate: date(2026, 5, 19), monthlyBudget: 0),
            debts: [card]
        )
        let avalanche = try #require(result.simulations.first { $0.simulation.strategyType == .avalanche })
        let eventTypes = Set(avalanche.costEvents.map(\.eventType))
        let riskTypes = Set(avalanche.riskEvents.map(\.eventType))

        #expect(eventTypes.contains(.creditCardMinimumPaymentProtection))
        #expect(eventTypes.contains(.creditCardRevolvingInterestProtection))
        #expect(eventTypes.contains(.creditCardExistingOverduePenalty))
        #expect(avalanche.costEvents.contains { $0.realizedCost > 0 })
        #expect(riskTypes.contains(.fallbackDataUsed))
        #expect(riskTypes.contains(.missingRepaymentPlan))
        #expect(result.comparisonBatch.globalRiskNotes.contains { $0.contains("fallback") || $0.contains("estimated") })
        #expect(result.recommendedSimulation != nil)
    }

    @Test
    func strategyEngineTieBreaksByDueDateAndSortsPlanStates() {
        let late = StrategyDebtSnapshot(
            debtType: .personalLending,
            name: "Late",
            remainingAmount: 100,
            minimumPaymentAmount: 0,
            dueDate: date(2026, 7, 1)
        )
        let early = StrategyDebtSnapshot(
            debtType: .personalLending,
            name: "Early",
            remainingAmount: 100,
            minimumPaymentAmount: 0,
            dueDate: date(2026, 6, 1)
        )
        let noDue = StrategyDebtSnapshot(
            debtType: .personalLending,
            name: "No Due",
            remainingAmount: 100,
            minimumPaymentAmount: 0,
            dueDate: nil
        )
        let plannedLoan = StrategyDebtSnapshot(
            debtType: .loan,
            name: "Planned",
            remainingAmount: 120,
            minimumPaymentAmount: 0,
            dueDate: date(2026, 6, 30),
            plans: [
                StrategyPlanSnapshot(
                    periodIndex: 2,
                    dueDate: date(2026, 7, 10),
                    remainingAmount: 60,
                    remainingPrincipal: 50,
                    remainingInterest: 10
                ),
                StrategyPlanSnapshot(
                    periodIndex: 1,
                    dueDate: date(2026, 6, 10),
                    remainingAmount: 60,
                    remainingPrincipal: 50,
                    remainingInterest: 10
                ),
            ]
        )

        let snowball = StrategySimulationEngine().generateSimulation(
            name: "Snowball tie",
            strategyType: .snowball,
            monthlyBudget: 50,
            debts: [noDue, late, early]
        )
        let avalanche = StrategySimulationEngine().generateSimulation(
            name: "Avalanche tie",
            strategyType: .avalanche,
            monthlyBudget: 50,
            debts: [late, noDue, early]
        )
        let planned = StrategySimulationEngine().generateSimulation(
            name: "Plan sorting",
            strategyType: .snowball,
            monthlyBudget: 70,
            debts: [plannedLoan]
        )

        #expect(snowball.allocations.first?.sourceDebtID == early.id)
        #expect(avalanche.allocations.first?.sourceDebtID == early.id)
        #expect(planned.allocations.first?.remainingAmountAfterPayment == 50)
        #expect(planned.simulation.status == .completed)
    }

    @Test
    func strategyComparisonRecommendedSimulationReturnsNilWhenNoMatch() {
        let batch = StrategyComparisonBatch(
            strategyDate: date(2026, 5, 19),
            monthlyBudget: 100,
            maxMonths: 12,
            recommendedStrategy: .balanced
        )
        let output = StrategySimulationEngine().generateSimulation(
            name: "Only snowball",
            strategyType: .snowball,
            monthlyBudget: 100,
            debts: [
                StrategyDebtSnapshot(
                    debtType: .loan,
                    name: "Loan",
                    remainingAmount: 100,
                    minimumPaymentAmount: 0
                )
            ]
        )
        let result = StrategyComparisonResult(
            comparisonBatch: batch,
            simulations: [output],
            riskEvents: []
        )

        #expect(result.recommendedSimulation == nil)
    }

    @Test
    func strategyComparisonCanReturnSimulationForSelectedStrategy() {
        let batch = StrategyComparisonBatch(
            strategyDate: date(2026, 5, 19),
            monthlyBudget: 100,
            maxMonths: 12,
            recommendedStrategy: .avalanche
        )
        let snowball = StrategySimulationEngine().generateSimulation(
            name: "Snowball",
            strategyType: .snowball,
            monthlyBudget: 100,
            debts: [
                StrategyDebtSnapshot(
                    debtType: .loan,
                    name: "Loan A",
                    remainingAmount: 120,
                    minimumPaymentAmount: 20
                )
            ]
        )
        let avalanche = StrategySimulationEngine().generateSimulation(
            name: "Avalanche",
            strategyType: .avalanche,
            monthlyBudget: 100,
            debts: [
                StrategyDebtSnapshot(
                    debtType: .creditCard,
                    name: "Card B",
                    remainingAmount: 200,
                    minimumPaymentAmount: 25
                )
            ]
        )
        let result = StrategyComparisonResult(
            comparisonBatch: batch,
            simulations: [snowball, avalanche],
            riskEvents: []
        )

        #expect(result.simulation(for: .snowball)?.simulation.strategyType == .snowball)
        #expect(result.simulation(for: .avalanche)?.simulation.strategyType == .avalanche)
        #expect(result.simulation(for: .balanced) == nil)
        #expect(result.simulation(for: nil) == nil)
    }
}
