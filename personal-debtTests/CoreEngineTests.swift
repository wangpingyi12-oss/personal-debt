import Foundation
import Testing
@testable import personal_debt

@MainActor
struct CoreEngineTests {
    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value) ?? 0
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    @Test
    func creditCardRealStatementDoesNotDoubleCountInstallments() {
        let debtID = UUID()
        let rule = CreditCardCalculationRule(debtID: debtID, minimumPaymentRatio: decimal("0.10"), minimumPaymentFloor: 50)
        let engine = CreditCardBillingEngine()

        let statement = engine.makeUserConfirmedStatement(
            debtID: debtID,
            billingDate: date(2026, 1, 1),
            dueDate: date(2026, 1, 20),
            statementAmount: 1000,
            userMinimumPaymentAmount: nil,
            rule: rule
        )

        #expect(statement.source == .userConfirmed)
        #expect(statement.statementAmount == 1000)
        #expect(statement.minimumPaymentAmount == 100)
        #expect(statement.remainingAmount == 1000)
    }

    @Test
    func creditCardFallbackOnlyUsesPreviousRemainingAndNextInstallment() {
        let debtID = UUID()
        let rule = CreditCardCalculationRule(debtID: debtID, minimumPaymentRatio: decimal("0.10"), minimumPaymentFloor: 0)
        let previous = CreditCardStatement(
            debtID: debtID,
            billingDate: date(2026, 1, 1),
            dueDate: date(2026, 1, 20),
            statementAmount: 1000,
            minimumPaymentAmount: 100,
            minimumPaymentSource: "userProvided",
            paidAmount: 400,
            source: .userConfirmed
        )
        let installment = CreditCardInstallmentPlan(
            debtID: debtID,
            nextBillingDate: date(2026, 2, 1),
            principalPerTerm: 100,
            feePerTerm: 10,
            interestPerTerm: 5,
            totalTerms: 6
        )

        let fallback = CreditCardBillingEngine().makeFallbackStatement(
            debtID: debtID,
            billingDate: date(2026, 2, 1),
            dueDate: date(2026, 2, 20),
            previousStatement: previous,
            installments: [installment],
            rule: rule
        )

        #expect(fallback.source == .fallback)
        #expect(fallback.statementAmount == 715)
        #expect(fallback.minimumPaymentAmount == decimal("71.50"))
    }

    @Test
    func creditCardPaymentRecalculationUpdatesStatementPlanAndDebtStatus() {
        let debt = CreditCardDebt(name: "Card", billingDay: 1, dueDay: 20)
        let statement = CreditCardStatement(
            debtID: debt.id,
            billingDate: date(2026, 1, 1),
            dueDate: date(2026, 1, 20),
            statementAmount: 1000,
            minimumPaymentAmount: 200,
            minimumPaymentSource: "userProvided",
            source: .userConfirmed
        )
        let plan = CreditCardBillingEngine().makeRepaymentPlan(for: statement)
        let payment = CreditCardPaymentRecord(
            debtID: debt.id,
            statementID: statement.id,
            paymentDate: date(2026, 1, 21),
            amount: 150
        )

        let engine = CreditCardBillingEngine()
        engine.recalculate(statement: statement, plan: plan, payments: [payment], debt: debt, today: date(2026, 1, 21))
        #expect(statement.status == .overdue)
        #expect(plan.status == .overdue)
        #expect(debt.status == .overdue)

        payment.amount = 250
        engine.recalculate(statement: statement, plan: plan, payments: [payment], debt: debt, today: date(2026, 1, 21))
        #expect(statement.status == .carriedForward)
        #expect(plan.status == .partiallyPaid)

        payment.amount = 1000
        engine.recalculate(statement: statement, plan: plan, payments: [payment], debt: debt, today: date(2026, 1, 21))
        #expect(statement.status == .paid)
        #expect(statement.remainingAmount == 0)
        #expect(debt.status == .paidOff)
    }

    @Test
    func loanInProgressUsesOpeningPrincipalAndManagementTermCount() throws {
        let debt = LoanDebt(
            name: "Loan",
            entryMode: .inProgressLoan,
            repaymentMethod: .equalPrincipal,
            originalPrincipal: 10000,
            openingPrincipalForManagement: 6000,
            annualInterestRate: decimal("0.12"),
            startDate: date(2026, 1, 1),
            managementStartDate: date(2026, 5, 15),
            endDate: date(2026, 7, 31),
            repaymentDay: 31,
            termCount: 3
        )

        let plans = try LoanScheduleEngine().generatePlans(for: debt)

        #expect(plans.count == 3)
        #expect(plans[0].dueDate == date(2026, 5, 31))
        #expect(plans[1].dueDate == date(2026, 6, 30))
        #expect(plans[2].dueDate == date(2026, 7, 31))
        #expect(plans[0].scheduledPrincipal == 2000)
        #expect(plans[0].scheduledInterest == 60)
        #expect(plans[0].remainingPrincipalBeforePayment == 6000)
    }

    @Test
    func loanScheduleSupportsFourRepaymentMethods() throws {
        let methods: [LoanRepaymentMethod] = [.equalPrincipal, .equalPayment, .interestFirst, .principalAtEnd]
        for method in methods {
            let debt = LoanDebt(
                name: method.rawValue,
                repaymentMethod: method,
                originalPrincipal: 1200,
                annualInterestRate: decimal("0.12"),
                startDate: date(2026, 1, 1),
                endDate: date(2026, 2, 10),
                repaymentDay: 10,
                termCount: 2
            )

            let plans = try LoanScheduleEngine().generatePlans(for: debt)
            #expect(plans.isEmpty == false)
            #expect(plans.last?.remainingPrincipalAfterScheduledPayment == 0)
        }
    }

    @Test
    func loanOverduePenaltyUsesSimpleInterestOnly() {
        let debtID = UUID()
        let debt = LoanDebt(
            id: debtID,
            name: "Loan",
            repaymentMethod: .equalPrincipal,
            originalPrincipal: 100,
            annualInterestRate: decimal("0.12"),
            startDate: date(2026, 1, 1),
            endDate: date(2026, 1, 10),
            repaymentDay: 10,
            termCount: 1
        )
        let plan = LoanRepaymentPlan(
            debtID: debtID,
            periodIndex: 1,
            periodType: .regular,
            periodStartDate: date(2026, 1, 1),
            periodEndDate: date(2026, 1, 10),
            dueDate: date(2026, 1, 10),
            scheduledPrincipal: 100,
            scheduledInterest: 10,
            remainingPrincipalBeforePayment: 100,
            remainingPrincipalAfterScheduledPayment: 0
        )
        let rule = LoanCalculationRule(
            debtID: debtID,
            overdueBaseType: .currentRemainingScheduledAmount,
            overdueFeeMode: .fixed,
            fixedOverdueFee: 5,
            penaltyInterestMode: .fixedDailyRate,
            fixedPenaltyDailyRate: decimal("0.01")
        )

        let record = LoanOverdueEngine().makeOrUpdateOverdueRecord(
            for: plan,
            debt: debt,
            rule: rule,
            today: date(2026, 1, 20)
        )

        #expect(record?.penaltyInterest == 11)
        #expect(record?.overdueFee == 5)
        #expect(plan.status == .overdue)
        #expect(plan.remainingTotalAmount == 126)
    }

    @Test
    func loanOverdueUsesBuiltInDefaultRules() {
        let debtID = UUID()
        let debt = LoanDebt(
            id: debtID,
            name: "Loan",
            repaymentMethod: .equalPrincipal,
            originalPrincipal: 100,
            annualInterestRate: decimal("0.12"),
            startDate: date(2026, 1, 1),
            endDate: date(2026, 1, 10),
            repaymentDay: 10,
            termCount: 1
        )
        let plan = LoanRepaymentPlan(
            debtID: debtID,
            periodIndex: 1,
            periodType: .regular,
            periodStartDate: date(2026, 1, 1),
            periodEndDate: date(2026, 1, 10),
            dueDate: date(2026, 1, 10),
            scheduledPrincipal: 100,
            scheduledInterest: 10,
            remainingPrincipalBeforePayment: 100,
            remainingPrincipalAfterScheduledPayment: 0
        )

        let record = LoanOverdueEngine().makeOrUpdateOverdueRecord(
            for: plan,
            debt: debt,
            rule: LoanCalculationRule.builtInDefault(debtID: debtID),
            today: date(2026, 1, 20)
        )

        #expect(record?.overdueFee == 0)
        #expect(record?.penaltyInterest == decimal("0.49"))
        #expect(record?.generatesOverdueFee == true)
        #expect(record?.generatesPenaltyInterest == true)
        #expect(plan.remainingTotalAmount == decimal("110.49"))
    }

    @Test
    func loanOverdueCanDisableGeneratedComponents() {
        let debtID = UUID()
        let debt = LoanDebt(
            id: debtID,
            name: "Loan",
            repaymentMethod: .equalPrincipal,
            originalPrincipal: 100,
            annualInterestRate: decimal("0.12"),
            startDate: date(2026, 1, 1),
            endDate: date(2026, 1, 10),
            repaymentDay: 10,
            termCount: 1
        )
        let plan = LoanRepaymentPlan(
            debtID: debtID,
            periodIndex: 1,
            periodType: .regular,
            periodStartDate: date(2026, 1, 1),
            periodEndDate: date(2026, 1, 10),
            dueDate: date(2026, 1, 10),
            scheduledPrincipal: 100,
            scheduledInterest: 10,
            remainingPrincipalBeforePayment: 100,
            remainingPrincipalAfterScheduledPayment: 0
        )
        let rule = LoanCalculationRule(
            debtID: debtID,
            overdueFeeMode: .disabled,
            penaltyInterestMode: .disabled
        )

        let record = LoanOverdueEngine().makeOrUpdateOverdueRecord(
            for: plan,
            debt: debt,
            rule: rule,
            today: date(2026, 1, 20)
        )

        #expect(record?.overdueFee == 0)
        #expect(record?.penaltyInterest == 0)
        #expect(record?.generatesOverdueFee == false)
        #expect(record?.generatesPenaltyInterest == false)
        #expect(plan.remainingTotalAmount == 110)
    }

    @Test
    func loanMultipleOverduePlansCalculateIndependentDays() {
        let debtID = UUID()
        let debt = LoanDebt(
            id: debtID,
            name: "Loan",
            repaymentMethod: .equalPrincipal,
            originalPrincipal: 200,
            annualInterestRate: 0,
            startDate: date(2026, 1, 1),
            endDate: date(2026, 2, 10),
            repaymentDay: 10,
            termCount: 2
        )
        let first = LoanRepaymentPlan(
            debtID: debtID,
            periodIndex: 1,
            periodType: .regular,
            periodStartDate: date(2026, 1, 1),
            periodEndDate: date(2026, 1, 10),
            dueDate: date(2026, 1, 10),
            scheduledPrincipal: 100,
            scheduledInterest: 10,
            remainingPrincipalBeforePayment: 200,
            remainingPrincipalAfterScheduledPayment: 100
        )
        let second = LoanRepaymentPlan(
            debtID: debtID,
            periodIndex: 2,
            periodType: .regular,
            periodStartDate: date(2026, 1, 10),
            periodEndDate: date(2026, 2, 10),
            dueDate: date(2026, 2, 10),
            scheduledPrincipal: 100,
            scheduledInterest: 10,
            remainingPrincipalBeforePayment: 100,
            remainingPrincipalAfterScheduledPayment: 0
        )
        let rule = LoanCalculationRule(
            debtID: debtID,
            overdueFeeMode: .percentage,
            overdueFeeRate: decimal("0.10"),
            penaltyInterestMode: .fixedDailyRate,
            fixedPenaltyDailyRate: decimal("0.01")
        )

        let firstRecord = LoanOverdueEngine().makeOrUpdateOverdueRecord(
            for: first,
            debt: debt,
            rule: rule,
            today: date(2026, 2, 20)
        )
        let secondRecord = LoanOverdueEngine().makeOrUpdateOverdueRecord(
            for: second,
            debt: debt,
            rule: rule,
            today: date(2026, 2, 20)
        )

        #expect(firstRecord?.overdueDays == 41)
        #expect(firstRecord?.overdueFee == 10)
        #expect(firstRecord?.penaltyInterest == 41)
        #expect(secondRecord?.overdueDays == 10)
        #expect(secondRecord?.overdueFee == 10)
        #expect(secondRecord?.penaltyInterest == 10)
    }

    @Test
    func loanAllocationHandlesOldestOverdueFirstAndStopsOverpayment() {
        let debtID = UUID()
        let first = LoanRepaymentPlan(
            debtID: debtID,
            periodIndex: 1,
            periodType: .regular,
            periodStartDate: date(2026, 1, 1),
            periodEndDate: date(2026, 1, 10),
            dueDate: date(2026, 1, 10),
            scheduledPrincipal: 100,
            scheduledInterest: 10,
            remainingPrincipalBeforePayment: 200,
            remainingPrincipalAfterScheduledPayment: 100
        )
        let second = LoanRepaymentPlan(
            debtID: debtID,
            periodIndex: 2,
            periodType: .regular,
            periodStartDate: date(2026, 1, 10),
            periodEndDate: date(2026, 2, 10),
            dueDate: date(2026, 2, 10),
            scheduledPrincipal: 100,
            scheduledInterest: 10,
            remainingPrincipalBeforePayment: 100,
            remainingPrincipalAfterScheduledPayment: 0
        )
        let overdue = LoanOverdueRecord(
            debtID: debtID,
            planID: first.id,
            overdueStartDate: date(2026, 1, 11),
            overdueDays: 10,
            overdueFee: 5,
            penaltyInterest: 10
        )
        let payment = LoanPaymentRecord(debtID: debtID, paymentDate: date(2026, 2, 11), totalAmount: 50)

        let output = LoanPaymentAllocationEngine().rebuildAllocations(
            payments: [payment],
            plans: [first, second],
            overdues: [overdue]
        )

        #expect(first.paidOverdueFee == 5)
        #expect(first.paidPenaltyInterest == 10)
        #expect(first.paidPrincipal == 25)
        #expect(first.paidInterest == 10)
        #expect(output.details.first?.allocatedTotal == 50)

        let overpay = LoanPaymentRecord(debtID: debtID, paymentDate: date(2026, 2, 11), totalAmount: 500)
        let overpayOutput = LoanPaymentAllocationEngine().rebuildAllocations(
            payments: [overpay],
            plans: [first, second],
            overdues: [overdue]
        )

        if case let .requiresUserDecision(unappliedAmount) = overpayOutput.result {
            #expect(unappliedAmount > 0)
        } else {
            #expect(Bool(false))
        }
    }

    @Test
    func loanAllocationCanPrioritizeCurrentPeriod() {
        let debtID = UUID()
        let overduePlan = LoanRepaymentPlan(
            debtID: debtID,
            periodIndex: 1,
            periodType: .regular,
            periodStartDate: date(2026, 1, 1),
            periodEndDate: date(2026, 1, 10),
            dueDate: date(2026, 1, 10),
            scheduledPrincipal: 100,
            scheduledInterest: 10,
            remainingPrincipalBeforePayment: 200,
            remainingPrincipalAfterScheduledPayment: 100
        )
        let currentPlan = LoanRepaymentPlan(
            debtID: debtID,
            periodIndex: 2,
            periodType: .regular,
            periodStartDate: date(2026, 1, 10),
            periodEndDate: date(2026, 2, 10),
            dueDate: date(2026, 2, 10),
            scheduledPrincipal: 100,
            scheduledInterest: 10,
            remainingPrincipalBeforePayment: 100,
            remainingPrincipalAfterScheduledPayment: 0
        )
        let overdue = LoanOverdueRecord(
            debtID: debtID,
            planID: overduePlan.id,
            overdueStartDate: date(2026, 1, 11),
            overdueDays: 10,
            overdueFee: 5,
            penaltyInterest: 10
        )
        let payment = LoanPaymentRecord(debtID: debtID, paymentDate: date(2026, 2, 10), totalAmount: 50)

        let output = LoanPaymentAllocationEngine().rebuildAllocations(
            payments: [payment],
            plans: [overduePlan, currentPlan],
            overdues: [overdue],
            allocationMode: .currentPeriodFirst
        )

        #expect(output.details.count == 1)
        #expect(currentPlan.paidInterest == 10)
        #expect(currentPlan.paidPrincipal == 40)
        #expect(overduePlan.paidOverdueFee == 0)
        #expect(overduePlan.paidPenaltyInterest == 0)
    }

    @Test
    func personalLendingGeneratesP0SchedulesAndRejectsInvalidInterestMode() throws {
        let invalid = PersonalLendingDebt(
            name: "Invalid",
            principalAmount: 1000,
            fixedInterestAmount: 100,
            borrowedDate: date(2026, 5, 14),
            repaymentMethod: .noFixedPlan,
            isInterestBearing: true
        )

        do {
            _ = try PersonalLendingScheduleEngine().generatePlans(for: invalid)
            #expect(Bool(false))
        } catch {
            let typedError = error as? PersonalLendingValidationError
            #expect(typedError == .fixedInterestMustBePositive
                || typedError == .fixedInterestMustNotBeNegative
                || typedError == .noFixedPlanMustBeInterestFree
                || typedError == .interestBearingRequiresPlan)
        }

        let maturity = PersonalLendingDebt(
            name: "Maturity",
            principalAmount: 1200,
            fixedInterestAmount: 120,
            borrowedDate: date(2026, 5, 14),
            agreedEndDate: date(2026, 8, 14),
            repaymentMethod: .principalAndInterestAtMaturity,
            isInterestBearing: true
        )
        let maturityPlans = try PersonalLendingScheduleEngine().generatePlans(for: maturity)
        #expect(maturityPlans.count == 1)
        #expect(maturityPlans[0].scheduledTotalAmount == 1320)

        let equal = PersonalLendingDebt(
            name: "Equal",
            principalAmount: 12000,
            fixedInterestAmount: 1200,
            borrowedDate: date(2026, 5, 14),
            repaymentMethod: .equalPrincipalEqualInterest,
            isInterestBearing: true,
            monthlyRepaymentDay: 10,
            termCount: 12
        )
        let equalPlans = try PersonalLendingScheduleEngine().generatePlans(for: equal)
        #expect(equalPlans.count == 12)
        #expect(equalPlans[0].dueDate == date(2026, 6, 10))
        #expect(equalPlans[0].scheduledPrincipal == 1000)
        #expect(equalPlans[0].scheduledInterest == 100)
    }

    @Test
    func personalLendingPaymentRebuildsAllocationsAndPastDueWithoutOverdueStatus() throws {
        let debt = PersonalLendingDebt(
            name: "Friend",
            principalAmount: 1000,
            fixedInterestAmount: 100,
            borrowedDate: date(2026, 1, 1),
            repaymentMethod: .equalPrincipalEqualInterest,
            isInterestBearing: true,
            monthlyRepaymentDay: 10,
            termCount: 2
        )
        let plans = try PersonalLendingScheduleEngine().generatePlans(for: debt)
        let payment = PersonalLendingPaymentRecord(debtID: debt.id, paymentDate: date(2026, 1, 11), amount: 600)

        let allocations = try PersonalLendingPaymentEngine().rebuildPayments(
            debt: debt,
            plans: plans,
            payments: [payment],
            today: date(2026, 3, 1)
        )

        #expect(allocations.count == 2)
        #expect(plans[0].status == .paid)
        #expect(plans[1].status == .partiallyPaid)
        #expect(debt.status == .partiallyPaid)
        #expect(debt.pastDueScheduledAmount > 0)
        #expect(debt.status != .overdue)

        let overpay = PersonalLendingPaymentRecord(debtID: debt.id, paymentDate: date(2026, 1, 11), amount: 1200)
        do {
            _ = try PersonalLendingPaymentEngine().rebuildPayments(debt: debt, plans: plans, payments: [overpay])
            #expect(Bool(false))
        } catch {
            #expect(error as? PersonalLendingPaymentError == .overpaymentNotAllowed)
        }
    }

    @Test
    func strategySimulationUsesSnapshotsWithoutMutatingInputs() {
        let highRateDebt = StrategyDebtSnapshot(
            debtType: .creditCard,
            name: "High rate",
            remainingAmount: 1000,
            minimumPaymentAmount: 0,
            costRate: decimal("0.20")
        )
        let smallDebt = StrategyDebtSnapshot(
            debtType: .personalLending,
            name: "Small",
            remainingAmount: 100,
            minimumPaymentAmount: 0,
            costRate: decimal("0.01")
        )

        let snowball = StrategySimulationEngine().generateSimulation(
            name: "Snowball",
            strategyType: .snowball,
            monthlyBudget: 100,
            debts: [highRateDebt, smallDebt]
        )
        #expect(snowball.allocations.first?.sourceDebtID == smallDebt.id)
        #expect(snowball.allocations.first?.remainingAmountAfterPayment == 0)

        let avalanche = StrategySimulationEngine().generateSimulation(
            name: "Avalanche",
            strategyType: .avalanche,
            monthlyBudget: 100,
            debts: [highRateDebt, smallDebt]
        )
        #expect(avalanche.allocations.first?.sourceDebtID == highRateDebt.id)
        #expect(highRateDebt.remainingAmount == 1000)
        #expect(smallDebt.remainingAmount == 100)
    }
}
