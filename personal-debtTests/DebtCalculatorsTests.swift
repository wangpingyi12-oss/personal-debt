import Foundation
import Testing
@testable import personal_debt

struct DebtCalculatorsTests {
    @Test func creditCardCalculatorCreatesFallbackBillWhenNoRealBill() {
        let debt = CreditCardDebt(
            name: "信用卡A",
            issuer: "Bank",
            creditLimit: 10000,
            annualRate: 0.18,
            statementDay: 1,
            dueDay: 20,
            currentBalance: 1200,
            minimumPaymentRate: 0.1
        )

        let bill = CreditCardCalculator.ensureCurrentBill(for: debt)

        #expect(bill.isFallbackPlaceholder)
        #expect(abs(bill.minimumPaymentDue - 120) < 0.01)
        #expect(debt.bills.count == 1)
    }

    @Test func loanCalculatorBuildsInstallmentsForFourMethods() {
        let methods = LoanRepaymentMethod.allCases
        for method in methods {
            let installments = LoanCalculator.buildInstallments(
                principal: 12000,
                annualRate: 0.12,
                periods: 12,
                startDate: .now,
                method: method
            )
            #expect(installments.count == 12)
            #expect(installments.allSatisfy { $0.totalDue >= 0 })
        }
    }

    @Test func personalLendingNoFixedPlanBuildsPlanEmpty() {
        let debt = PersonalLendingDebt(
            name: "借款",
            principal: 5000,
            hasInterest: false,
            totalInterest: 0,
            startDate: .now,
            repaymentMethod: PersonalLendingRepaymentMethod.noFixedPlan.rawValue
        )
        let plan = PersonalLendingCalculator.buildPlan(for: debt)
        #expect(plan.isEmpty)
    }

    @Test func personalLendingLumpSumAtMaturityBuildsOnePlanItem() {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let end   = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 1))!
        let debt = PersonalLendingDebt(
            name: "借款",
            principal: 10000,
            hasInterest: true,
            totalInterest: 600,
            startDate: start,
            endDate: end,
            repaymentMethod: PersonalLendingRepaymentMethod.lumpSumAtMaturity.rawValue
        )
        let plan = PersonalLendingCalculator.buildPlan(for: debt)
        #expect(plan.count == 1)
        #expect(abs(plan[0].principalDue - 10000) < 0.01)
        #expect(abs(plan[0].interestDue  - 600)   < 0.01)
        #expect(abs(plan[0].totalDue     - 10600) < 0.01)
        #expect(plan[0].dueDate == end)
    }

    @Test func personalLendingEqualInstallmentsAmountsSumCorrectly() {
        let debt = PersonalLendingDebt(
            name: "借款",
            principal: 12000,
            hasInterest: true,
            totalInterest: 1200,
            startDate: Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 15))!,
            repaymentMethod: PersonalLendingRepaymentMethod.equalInstallments.rawValue,
            monthlyPaymentDay: 10,
            totalPeriods: 12
        )
        let plan = PersonalLendingCalculator.buildPlan(for: debt)
        #expect(plan.count == 12)

        let totalPrincipal = plan.reduce(0) { $0 + $1.principalDue }
        let totalInterest  = plan.reduce(0) { $0 + $1.interestDue }
        #expect(abs(totalPrincipal - 12000) < 0.01)
        #expect(abs(totalInterest  - 1200)  < 0.01)
    }

    @Test func personalLendingFirstPaymentDateLogic() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!

        // Borrow on May 14, payment day 10 → first payment June 10
        let startA = cal.date(from: DateComponents(year: 2026, month: 5, day: 14))!
        let firstA = PersonalLendingCalculator.firstPaymentDate(startDate: startA, monthlyPaymentDay: 10, calendar: cal)
        let compsA = cal.dateComponents([.year, .month, .day], from: firstA)
        #expect(compsA.year == 2026 && compsA.month == 6 && compsA.day == 10)

        // Borrow on May 1, payment day 10 → first payment May 10
        let startB = cal.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let firstB = PersonalLendingCalculator.firstPaymentDate(startDate: startB, monthlyPaymentDay: 10, calendar: cal)
        let compsB = cal.dateComponents([.year, .month, .day], from: firstB)
        #expect(compsB.year == 2026 && compsB.month == 5 && compsB.day == 10)
    }

    @Test func personalLendingPaymentDayClampedToLastDayOfMonth() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!

        // Payment day 31; April has only 30 days → April 30
        let april = PersonalLendingCalculator.dateInMonth(year: 2026, month: 4, day: 31, calendar: cal)
        let comps = cal.dateComponents([.year, .month, .day], from: april)
        #expect(comps.month == 4 && comps.day == 30)
    }

    @Test func personalLendingStatusResolutionRules() {
        let debt = PersonalLendingDebt(name: "借款", principal: 1000)

        // Active when nothing paid
        #expect(PersonalLendingCalculator.resolveDebtStatus(for: debt) == DebtLifecycleStatus.active.rawValue)

        // PartiallyPaid when some paid
        debt.paidAmount = 400
        debt.remainingAmount = 600
        #expect(PersonalLendingCalculator.resolveDebtStatus(for: debt) == DebtLifecycleStatus.partiallyPaid.rawValue)

        // PaidOff when remaining is 0
        debt.paidAmount = 1000
        debt.remainingAmount = 0
        #expect(PersonalLendingCalculator.resolveDebtStatus(for: debt) == DebtLifecycleStatus.paidOff.rawValue)
    }

    @Test func personalLendingPastDueNoFixedPlan() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let debt = PersonalLendingDebt(
            name: "借款",
            principal: 5000,
            endDate: yesterday,
            repaymentMethod: PersonalLendingRepaymentMethod.noFixedPlan.rawValue
        )
        debt.remainingAmount = 5000

        let (amount, planCount, debtCount) = PersonalLendingCalculator.computePastDueStats(debt: debt, asOf: Date())
        #expect(amount > 0)
        #expect(planCount == 0)
        #expect(debtCount == 1)
    }

    @Test func personalLendingValidationRejectsInterestWithNoFixedPlan() {
        #expect(throws: PersonalLendingCalculator.ValidationError.self) {
            try PersonalLendingCalculator.validateDebt(
                principal: 1000,
                hasInterest: true,
                totalInterest: 100,
                repaymentMethod: .noFixedPlan,
                startDate: .now,
                endDate: nil,
                monthlyPaymentDay: 1,
                totalPeriods: 1
            )
        }
    }

    @Test func strategySimulatorKeepsSimulatedOutputSeparate() {
        let inputs = [
            SimulatedDebtInput(id: UUID(), name: "A", debtKind: .creditCard, balance: 1000, monthlyRate: 0.01, overdueAmount: 0),
            SimulatedDebtInput(id: UUID(), name: "B", debtKind: .loan, balance: 2000, monthlyRate: 0.005, overdueAmount: 100)
        ]

        let result = StrategySimulator.simulate(inputs: inputs, mode: .avalanche, monthlyBudget: 500)

        #expect(result.monthlyBudget == 500)
        #expect(result.monthsToDebtFree > 0)
        #expect(result.months.count > 0)
    }
}
