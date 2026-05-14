import Foundation

enum CreditCardCalculator {
    static func ensureCurrentBill(
        for debt: CreditCardDebt,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> CreditCardBill {
        if let realBill = debt.bills
            .filter({ !$0.isFallbackPlaceholder && $0.isValid })
            .max(by: { $0.statementDate < $1.statementDate }) {
            return realBill
        }

        let statementDate = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let dueDate = calendar.date(byAdding: .day, value: max(1, debt.dueDay - 1), to: statementDate) ?? now
        let minimum = max(0, debt.currentBalance * debt.minimumPaymentRate)

        let placeholder = CreditCardBill(
            periodKey: "fallback-\(calendar.component(.year, from: now))-\(calendar.component(.month, from: now))",
            statementDate: statementDate,
            dueDate: dueDate,
            principalDue: debt.currentBalance,
            minimumPaymentDue: minimum,
            isFallbackPlaceholder: true,
            debt: debt
        )
        debt.bills.append(placeholder)
        return placeholder
    }

    static func evaluateStatus(for debt: CreditCardDebt, now: Date = .now) -> String {
        let activeOverdue = debt.overdues.contains(where: { $0.isActive && $0.isValid })
        if activeOverdue { return DebtLifecycleStatus.overdue.rawValue }
        if debt.currentBalance <= 0.01 { return DebtLifecycleStatus.paidOff.rawValue }

        let bill = debt.bills
            .filter({ $0.isValid })
            .max(by: { $0.dueDate < $1.dueDate })

        if let bill, bill.dueDate < now, bill.paidAmount + 0.001 < bill.minimumPaymentDue {
            return DebtLifecycleStatus.overdue.rawValue
        }
        return DebtLifecycleStatus.active.rawValue
    }
}
