import Foundation
import SwiftData

@MainActor
enum TransactionOrchestrator {
    static func appendCreditCardPayment(
        amount: Double,
        debt: CreditCardDebt,
        context: ModelContext
    ) throws {
        let transaction = CreditCardTransaction(
            occurredAt: .now,
            amount: amount,
            kind: "payment",
            debt: debt
        )
        debt.transactions.append(transaction)
        debt.currentBalance = max(0, debt.currentBalance - amount)
        _ = CreditCardCalculator.ensureCurrentBill(for: debt)
        debt.status = CreditCardCalculator.evaluateStatus(for: debt)
        debt.updatedAt = .now
        try context.save()
    }

    static func appendLoanPayment(
        amount: Double,
        debt: LoanDebt,
        context: ModelContext
    ) throws {
        debt.transactions.append(LoanTransaction(occurredAt: .now, amount: amount, debt: debt))
        debt.remainingPrincipal = max(0, debt.remainingPrincipal - amount)
        debt.status = LoanCalculator.resolveStatus(for: debt)
        try context.save()
    }

    static func appendPersonalLendingPayment(
        amount: Double,
        debt: PersonalLendingDebt,
        context: ModelContext
    ) throws {
        debt.transactions.append(PersonalLendingTransaction(occurredAt: .now, amount: amount, debt: debt))
        debt.remainingPrincipal = max(0, debt.remainingPrincipal - amount)
        debt.status = PersonalLendingCalculator.resolveStatus(for: debt)
        try context.save()
    }
}
