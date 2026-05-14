import Foundation

struct OverviewViewModel {
    static func makeMetrics(
        creditCards: [CreditCardDebt],
        loans: [LoanDebt],
        personalLendings: [PersonalLendingDebt]
    ) -> OverviewMetrics {
        let creditBalance = creditCards.filter { $0.isValid }.reduce(0) { $0 + $1.currentBalance }
        let loanBalance = loans.filter { $0.isValid }.reduce(0) { $0 + $1.remainingPrincipal }
        let lendingBalance = personalLendings.filter { $0.isValid }.reduce(0) { $0 + $1.remainingPrincipal }
        let totalRemaining = creditBalance + loanBalance + lendingBalance

        let minimumDue = creditCards.filter { $0.isValid }.reduce(0) { $0 + $1.currentBalance * $1.minimumPaymentRate }
        let loanMonthDue = loans.filter { $0.isValid }.flatMap(\.installments).filter { $0.state == RecordState.pending.rawValue }.reduce(0) { $0 + $1.totalDue }
        let lendingMonthDue = personalLendings.filter { $0.isValid }.flatMap(\.planItems).filter { $0.state == RecordState.pending.rawValue }.reduce(0) { $0 + $1.totalDue }
        let monthDue = minimumDue + loanMonthDue + lendingMonthDue

        let overdue = creditCards.flatMap(\.overdues).filter { $0.isActive && $0.isValid }.reduce(0) { $0 + $1.overdueAmount + $1.penaltyAmount }
            + loans.flatMap(\.overdues).filter { $0.isActive && $0.isValid }.reduce(0) { $0 + $1.overdueAmount + $1.penaltyAmount }
            + personalLendings.flatMap(\.overdues).filter { $0.isActive && $0.isValid }.reduce(0) { $0 + $1.overdueAmount + $1.penaltyAmount }

        let creditLimitTotal = creditCards.reduce(0) { $0 + $1.creditLimit }
        let loanPrincipalTotal = loans.reduce(0) { $0 + $1.principal }
        let personalLendingPrincipalTotal = personalLendings.reduce(0) { $0 + $1.principal }
        let totalPrincipalRaw = creditLimitTotal + loanPrincipalTotal + personalLendingPrincipalTotal

        let completed = max(0, totalPrincipalRaw - totalRemaining)
        let totalPrincipal = max(1, totalPrincipalRaw)
        let progress = min(1, completed / totalPrincipal)

        let todoCount = Int((monthDue > 0 ? 1 : 0) + (overdue > 0 ? 1 : 0))

        return OverviewMetrics(
            currentMonthDue: monthDue,
            minimumDue: minimumDue,
            overdueAmount: overdue,
            totalRemaining: totalRemaining,
            completionProgress: progress,
            todoCount: todoCount
        )
    }
}
