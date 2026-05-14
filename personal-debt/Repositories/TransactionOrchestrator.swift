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

    // MARK: - Personal Lending

    /// Adds a new payment transaction to a personal-lending debt and triggers full recalculation.
    static func addPersonalLendingPayment(
        amount: Double,
        occurredAt: Date = .now,
        note: String = "",
        debt: PersonalLendingDebt,
        context: ModelContext
    ) throws {
        try PersonalLendingCalculator.validatePayment(amount: amount, debt: debt)
        let tx = PersonalLendingTransaction(
            occurredAt: occurredAt,
            amount: amount,
            note: note,
            createdAt: .now,
            debt: debt
        )
        context.insert(tx)
        debt.transactions.append(tx)
        PersonalLendingCalculator.fullRecalculate(debt: debt, context: context)
        try context.save()
    }

    /// Deletes an existing personal-lending transaction and triggers full recalculation.
    static func deletePersonalLendingPayment(
        transaction: PersonalLendingTransaction,
        debt: PersonalLendingDebt,
        context: ModelContext
    ) throws {
        debt.transactions.removeAll { $0.id == transaction.id }
        context.delete(transaction)
        PersonalLendingCalculator.fullRecalculate(debt: debt, context: context)
        try context.save()
    }

    /// Updates an existing personal-lending transaction and triggers full recalculation.
    static func updatePersonalLendingPayment(
        transaction: PersonalLendingTransaction,
        newAmount: Double,
        newOccurredAt: Date,
        newNote: String,
        debt: PersonalLendingDebt,
        context: ModelContext
    ) throws {
        // Temporarily remove transaction to validate against remaining without it
        let originalAmount = transaction.amount
        transaction.amount = 0
        PersonalLendingCalculator.fullRecalculate(debt: debt, context: context)
        transaction.amount = originalAmount

        let remainingWithoutThisTx = debt.remainingAmount + originalAmount
        if newAmount <= 0 { throw PersonalLendingCalculator.ValidationError.invalidAmount }
        if newAmount > remainingWithoutThisTx + 0.001 {
            // Restore and re-recalculate before throwing
            PersonalLendingCalculator.fullRecalculate(debt: debt, context: context)
            throw PersonalLendingCalculator.ValidationError.exceedsRemainingAmount
        }

        transaction.amount = newAmount
        transaction.occurredAt = newOccurredAt
        transaction.note = newNote
        PersonalLendingCalculator.fullRecalculate(debt: debt, context: context)
        try context.save()
    }
}
