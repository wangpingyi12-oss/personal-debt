import Foundation

enum LoanCalculator {
    static func buildInstallments(
        principal: Double,
        annualRate: Double,
        periods: Int,
        startDate: Date,
        method: LoanRepaymentMethod,
        calendar: Calendar = .current
    ) -> [LoanInstallment] {
        guard periods > 0, principal > 0 else { return [] }

        let monthlyRate = annualRate / 12.0
        var result: [LoanInstallment] = []
        var remaining = principal

        for i in 1...periods {
            let dueDate = calendar.date(byAdding: .month, value: i, to: startDate) ?? startDate
            let principalDue: Double
            let interestDue: Double

            switch method {
            case .equalPrincipalAndInterest:
                let factor = pow(1 + monthlyRate, Double(periods))
                let denominator = factor - 1
                let monthlyPayment = monthlyRate == 0 || abs(denominator) < 1e-10
                    ? principal / Double(periods)
                    : principal * monthlyRate * factor / denominator
                interestDue = remaining * monthlyRate
                principalDue = max(0, monthlyPayment - interestDue)
            case .equalPrincipal:
                principalDue = principal / Double(periods)
                interestDue = remaining * monthlyRate
            case .interestOnlyThenPrincipal:
                if i == periods {
                    principalDue = remaining
                } else {
                    principalDue = 0
                }
                interestDue = remaining * monthlyRate
            case .bullet:
                if i == periods {
                    principalDue = principal
                    interestDue = principal * monthlyRate * Double(periods)
                } else {
                    principalDue = 0
                    interestDue = 0
                }
            }

            remaining = max(0, remaining - principalDue)
            let total = principalDue + interestDue
            result.append(
                LoanInstallment(
                    periodNumber: i,
                    dueDate: dueDate,
                    principalDue: principalDue,
                    interestDue: interestDue,
                    totalDue: total
                )
            )
        }
        return result
    }

    static func resolveStatus(for debt: LoanDebt) -> String {
        if debt.overdues.contains(where: { $0.isActive && $0.isValid }) {
            return DebtLifecycleStatus.overdue.rawValue
        }
        if debt.remainingPrincipal <= 0.01 {
            return DebtLifecycleStatus.paidOff.rawValue
        }
        return DebtLifecycleStatus.active.rawValue
    }
}
