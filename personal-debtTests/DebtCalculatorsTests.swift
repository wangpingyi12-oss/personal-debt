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

    @Test func personalLendingSnapshotCanRebuildPlan() {
        let snapshot = PersonalLendingCalculator.snapshotFacts(
            principal: 6000,
            annualRate: 0.06,
            periods: 6,
            startDate: .now
        )

        let plan = PersonalLendingCalculator.rebuildPlan(from: snapshot)

        #expect(plan.count == 6)
        #expect(plan.first?.sequence == 1)
        #expect(plan.last?.sequence == 6)
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
