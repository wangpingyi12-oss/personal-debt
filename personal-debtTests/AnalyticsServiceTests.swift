import Foundation
import SwiftData
import Testing
@testable import personal_debt

@MainActor
struct AnalyticsServiceTests {
    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value) ?? 0
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    private func analyticsSchema() -> Schema {
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
        let schema = analyticsSchema()
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test
    func debtAnalyticsUsesRealCardStatementAndExcludesLoanFeesFromDebtBalance() {
        let period = AnalyticsSupport.monthPeriod(containing: date(2026, 5, 16))
        let card = CreditCardDebt(name: "Card", billingDay: 1, dueDay: 20)
        let fallback = CreditCardStatement(
            debtID: card.id,
            billingDate: date(2026, 5, 1),
            dueDate: date(2026, 5, 20),
            statementAmount: 800,
            minimumPaymentAmount: 80,
            minimumPaymentSource: "fallback",
            source: .fallback
        )
        let real = CreditCardStatement(
            debtID: card.id,
            billingDate: date(2026, 5, 1),
            dueDate: date(2026, 5, 20),
            statementAmount: 500,
            minimumPaymentAmount: 50,
            minimumPaymentSource: "userProvided",
            paidAmount: 100,
            source: .userConfirmed
        )

        let loan = LoanDebt(
            name: "Loan",
            repaymentMethod: .equalPrincipal,
            originalPrincipal: 1000,
            annualInterestRate: 0,
            startDate: date(2026, 1, 1),
            endDate: date(2026, 5, 20),
            repaymentDay: 20,
            termCount: 1
        )
        let loanPlan = LoanRepaymentPlan(
            debtID: loan.id,
            periodIndex: 1,
            periodType: .regular,
            periodStartDate: date(2026, 5, 1),
            periodEndDate: date(2026, 5, 20),
            dueDate: date(2026, 5, 20),
            scheduledPrincipal: 1000,
            scheduledInterest: 100,
            remainingPrincipalBeforePayment: 1000,
            remainingPrincipalAfterScheduledPayment: 0
        )
        loanPlan.remainingPrincipal = 700
        loanPlan.remainingInterest = 50
        loanPlan.remainingOverdueFee = 30
        loanPlan.remainingPenaltyInterest = 20
        loanPlan.remainingTotalAmount = 800

        let personal = PersonalLendingDebt(
            name: "Friend",
            principalAmount: 300,
            borrowedDate: date(2026, 1, 1),
            agreedEndDate: date(2026, 5, 30),
            repaymentMethod: .noFixedPlan
        )

        let analytics = DebtAnalyticsService().generate(
            creditCardDebts: [card],
            creditCardStatements: [fallback, real],
            loanDebts: [loan],
            loanPlans: [loanPlan],
            personalLendingDebts: [personal],
            personalLendingPlans: [],
            period: period
        )

        #expect(analytics.creditCardRemainingAmount == 400)
        #expect(analytics.loanRemainingAmount == 750)
        #expect(analytics.personalLendingRemainingAmount == 300)
        #expect(analytics.totalRemainingAmount == 1450)
        #expect(analytics.currentMonthPlannedRepaymentAmount == 1150)
        #expect(analytics.fixedDebtAmount == 1050)
        #expect(analytics.revolvingDebtAmount == 400)
        #expect(analytics.maxSingleDebt?.debtType == .loan)
    }

    @Test
    func paymentAnalyticsReadsExistingPaymentRecordsForAllDebtTypes() {
        let period = AnalyticsSupport.monthPeriod(containing: date(2026, 5, 16))
        let card = CreditCardDebt(name: "Card", billingDay: 1, dueDay: 20)
        let loan = LoanDebt(
            name: "Loan",
            repaymentMethod: .equalPrincipal,
            originalPrincipal: 1000,
            annualInterestRate: 0,
            startDate: date(2026, 1, 1),
            endDate: date(2026, 5, 20),
            repaymentDay: 20,
            termCount: 1
        )
        let personal = PersonalLendingDebt(
            name: "Friend",
            principalAmount: 300,
            borrowedDate: date(2026, 1, 1),
            repaymentMethod: .noFixedPlan
        )
        let cardPayment = CreditCardPaymentRecord(
            debtID: card.id,
            statementID: UUID(),
            paymentDate: date(2026, 5, 2),
            amount: 120
        )
        let oldCardPayment = CreditCardPaymentRecord(
            debtID: card.id,
            statementID: UUID(),
            paymentDate: date(2026, 4, 2),
            amount: 30
        )
        let loanPayment = LoanPaymentRecord(
            debtID: loan.id,
            paymentDate: date(2026, 5, 3),
            totalAmount: 200
        )
        let personalPayment = PersonalLendingPaymentRecord(
            debtID: personal.id,
            paymentDate: date(2026, 5, 4),
            amount: 50
        )

        let analytics = PaymentAnalyticsService().generate(
            creditCardDebts: [card],
            creditCardPayments: [cardPayment, oldCardPayment],
            loanDebts: [loan],
            loanPayments: [loanPayment],
            personalLendingDebts: [personal],
            personalLendingPayments: [personalPayment],
            period: period
        )

        #expect(analytics.currentMonthPaidAmount == 370)
        #expect(analytics.cumulativePaidAmount == 400)
        #expect(analytics.currentMonthPaymentRecordCount == 1)
        #expect(analytics.currentMonthPaymentInputCount == 2)
        #expect(analytics.latestPayment?.debtType == .personalLending)
    }

    @Test
    func overdueAnalyticsSeparatesJudgementFromCostsAndBucketsRisk() {
        let card = CreditCardDebt(name: "Card", billingDay: 1, dueDay: 20)
        let statement = CreditCardStatement(
            debtID: card.id,
            billingDate: date(2026, 5, 1),
            dueDate: date(2026, 5, 20),
            statementAmount: 500,
            minimumPaymentAmount: 200,
            minimumPaymentSource: "userProvided",
            paidAmount: 100,
            source: .userConfirmed
        )
        let breakdown = CreditCardStatementBreakdown(
            statementID: statement.id,
            source: .userProvided,
            overdueFee: 10,
            penaltyInterest: 5
        )

        let loan = LoanDebt(
            name: "Loan",
            repaymentMethod: .equalPrincipal,
            originalPrincipal: 1000,
            annualInterestRate: 0,
            startDate: date(2026, 1, 1),
            endDate: date(2026, 4, 1),
            repaymentDay: 1,
            termCount: 1
        )
        let loanPlan = LoanRepaymentPlan(
            debtID: loan.id,
            periodIndex: 1,
            periodType: .regular,
            periodStartDate: date(2026, 3, 1),
            periodEndDate: date(2026, 4, 1),
            dueDate: date(2026, 4, 1),
            scheduledPrincipal: 1000,
            scheduledInterest: 100,
            remainingPrincipalBeforePayment: 1000,
            remainingPrincipalAfterScheduledPayment: 0
        )
        loanPlan.remainingPrincipal = 700
        loanPlan.remainingInterest = 50
        let loanOverdue = LoanOverdueRecord(
            debtID: loan.id,
            planID: loanPlan.id,
            overdueStartDate: date(2026, 4, 2),
            overdueDays: 85,
            overdueFee: 20,
            penaltyInterest: 30
        )

        let personal = PersonalLendingDebt(
            name: "Friend",
            principalAmount: 300,
            borrowedDate: date(2026, 1, 1),
            agreedEndDate: date(2026, 1, 1),
            repaymentMethod: .noFixedPlan
        )

        let analytics = OverdueAnalyticsService().generate(
            creditCardDebts: [card],
            creditCardStatements: [statement],
            creditCardBreakdowns: [breakdown],
            loanDebts: [loan],
            loanPlans: [loanPlan],
            loanOverdues: [loanOverdue],
            personalLendingDebts: [personal],
            personalLendingPlans: [],
            today: date(2026, 6, 25)
        )

        #expect(analytics.currentOverdueDebtCount == 3)
        #expect(analytics.currentOverduePeriodCount == 3)
        #expect(analytics.creditCardMinimumPaymentGap == 100)
        #expect(analytics.creditCardOverdueStatementRemainingAmount == 400)
        #expect(analytics.loanOverdueAmount == 750)
        #expect(analytics.personalLendingPastDueAmount == 300)
        #expect(analytics.overdueFeeTotalAmount == 30)
        #expect(analytics.penaltyInterestTotalAmount == 35)
        #expect(analytics.overdueAmountOver90Days == 300)
        #expect(analytics.riskLevel == .critical)
    }

    @Test
    func costAnalyticsDoesNotAddCreditCardBreakdownCostsToDebtBalance() {
        let card = CreditCardDebt(name: "Card", billingDay: 1, dueDay: 20)
        let statement = CreditCardStatement(
            debtID: card.id,
            billingDate: date(2026, 5, 1),
            dueDate: date(2026, 5, 20),
            statementAmount: 500,
            minimumPaymentAmount: 50,
            minimumPaymentSource: "userProvided",
            source: .userConfirmed
        )
        let breakdown = CreditCardStatementBreakdown(
            statementID: statement.id,
            source: .userProvided,
            installmentFee: 20,
            installmentInterest: 30,
            revolvingInterest: 40,
            overdueFee: 10,
            penaltyInterest: 5,
            unclassifiedAmount: 2,
            hasBreakdownConflict: true
        )

        let loan = LoanDebt(
            name: "Loan",
            repaymentMethod: .equalPrincipal,
            originalPrincipal: 1000,
            annualInterestRate: 0,
            startDate: date(2026, 1, 1),
            endDate: date(2026, 4, 1),
            repaymentDay: 1,
            termCount: 1
        )
        let loanPlan = LoanRepaymentPlan(
            debtID: loan.id,
            periodIndex: 1,
            periodType: .regular,
            periodStartDate: date(2026, 3, 1),
            periodEndDate: date(2026, 4, 1),
            dueDate: date(2026, 4, 1),
            scheduledPrincipal: 1000,
            scheduledInterest: 100,
            remainingPrincipalBeforePayment: 1000,
            remainingPrincipalAfterScheduledPayment: 0
        )
        loanPlan.paidInterest = 25
        let loanOverdue = LoanOverdueRecord(
            debtID: loan.id,
            planID: loanPlan.id,
            overdueStartDate: date(2026, 4, 2),
            overdueDays: 20,
            overdueFee: 20,
            penaltyInterest: 30
        )

        let personal = PersonalLendingDebt(
            name: "Friend",
            principalAmount: 1200,
            fixedInterestAmount: 120,
            borrowedDate: date(2026, 1, 1),
            repaymentMethod: .equalPrincipalEqualInterest,
            isInterestBearing: true,
            monthlyRepaymentDay: 1,
            termCount: 1
        )
        let personalPlan = PersonalLendingPlan(
            debtID: personal.id,
            periodIndex: 1,
            dueDate: date(2026, 5, 1),
            scheduledPrincipal: 1200,
            scheduledInterest: 120
        )

        let debtAnalytics = DebtAnalyticsService().generate(
            creditCardDebts: [card],
            creditCardStatements: [statement],
            loanDebts: [loan],
            loanPlans: [loanPlan],
            personalLendingDebts: [personal],
            personalLendingPlans: [personalPlan],
            period: AnalyticsSupport.monthPeriod(containing: date(2026, 5, 16))
        )
        let costAnalytics = CostAnalyticsService().generate(
            creditCardDebts: [card],
            creditCardStatements: [statement],
            creditCardBreakdowns: [breakdown],
            loanDebts: [loan],
            loanPlans: [loanPlan],
            loanOverdues: [loanOverdue],
            personalLendingDebts: [personal],
            personalLendingPlans: [personalPlan]
        )

        #expect(debtAnalytics.creditCardRemainingAmount == 500)
        #expect(costAnalytics.creditCardCostAmount == 107)
        #expect(costAnalytics.loanCostAmount == 150)
        #expect(costAnalytics.personalLendingInterestAmount == 120)
        #expect(costAnalytics.loanAppAllocatedPaidInterestAmount == 25)
        #expect(costAnalytics.totalCostAmount == 377)
        #expect(costAnalytics.creditCardBreakdownConflictCount == 1)
    }

    @Test
    func coordinatorUpsertsDailySnapshotsAndClearsDirtyState() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let card = CreditCardDebt(name: "Card", billingDay: 1, dueDay: 20)
        let statement = CreditCardStatement(
            debtID: card.id,
            billingDate: date(2026, 5, 1),
            dueDate: date(2026, 5, 20),
            statementAmount: 500,
            minimumPaymentAmount: 50,
            minimumPaymentSource: "userProvided",
            source: .userConfirmed
        )
        context.insert(card)
        context.insert(statement)
        try context.save()

        let invalidationStore = AnalyticsInvalidationStore(modelContext: context)
        try invalidationStore.markAnalyticsDirty(.all)
        let dirtyState = try invalidationStore.currentState()
        #expect(dirtyState.isDebtAnalyticsDirty)

        let coordinator = AnalyticsCoordinator(modelContext: context)
        let first = try coordinator.generateSummary(today: date(2026, 5, 16), saveSnapshots: true)
        statement.paidAmount = 100
        statement.remainingAmount = 400
        let second = try coordinator.generateSummary(today: date(2026, 5, 16), saveSnapshots: true)

        let debtSnapshots = try context.fetch(FetchDescriptor<DebtAnalyticsSnapshot>())
        let paymentSnapshots = try context.fetch(FetchDescriptor<PaymentAnalyticsSnapshot>())
        let overdueSnapshots = try context.fetch(FetchDescriptor<OverdueAnalyticsSnapshot>())
        let costSnapshots = try context.fetch(FetchDescriptor<CostAnalyticsSnapshot>())
        let state = try invalidationStore.currentState()

        #expect(first.debtAnalytics.totalRemainingAmount == 500)
        #expect(second.debtAnalytics.totalRemainingAmount == 400)
        #expect(debtSnapshots.count == 1)
        #expect(paymentSnapshots.count == 1)
        #expect(overdueSnapshots.count == 1)
        #expect(costSnapshots.count == 1)
        #expect(debtSnapshots[0].totalRemainingAmount == 400)
        #expect(state.isDebtAnalyticsDirty == false)
        #expect(state.isPaymentAnalyticsDirty == false)
        #expect(state.isOverdueAnalyticsDirty == false)
        #expect(state.isCostAnalyticsDirty == false)
        #expect(try invalidationStore.needsDailyGeneration(today: date(2026, 5, 16)) == false)
    }
}
