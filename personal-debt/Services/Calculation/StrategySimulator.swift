import Foundation

struct SimulatedDebtInput: Identifiable {
    let id: UUID
    let name: String
    let debtKind: DebtKind
    let balance: Double
    let monthlyRate: Double
    let overdueAmount: Double

    func withBalance(_ newBalance: Double) -> SimulatedDebtInput {
        SimulatedDebtInput(
            id: id,
            name: name,
            debtKind: debtKind,
            balance: newBalance,
            monthlyRate: monthlyRate,
            overdueAmount: overdueAmount
        )
    }
}

struct StrategySimulationResult {
    let mode: StrategyMode
    let monthlyBudget: Double
    let totalCost: Double
    let monthsToDebtFree: Int
    let riskWarning: String
    let months: [StrategySimulationMonthDraft]
}

struct StrategySimulationMonthDraft {
    let sequence: Int
    let principalPaid: Double
    let interestPaid: Double
    let overduePaid: Double
    let remainingBalance: Double
    let pressureIndex: Double
}

enum StrategySimulator {
    private static let overdueBudgetShare = 0.2

    static func simulate(
        inputs: [SimulatedDebtInput],
        mode: StrategyMode,
        monthlyBudget: Double,
        maxMonths: Int = 360
    ) -> StrategySimulationResult {
        var working = inputs
        var monthDrafts: [StrategySimulationMonthDraft] = []
        var totalCost = 0.0
        var warning = ""

        for month in 1...maxMonths {
            let totalBalance = working.reduce(0) { $0 + $1.balance + $1.overdueAmount }
            if totalBalance <= 0.01 {
                return StrategySimulationResult(
                    mode: mode,
                    monthlyBudget: monthlyBudget,
                    totalCost: totalCost,
                    monthsToDebtFree: month - 1,
                    riskWarning: warning,
                    months: monthDrafts
                )
            }

            let interest = working.reduce(0) { $0 + $1.balance * $1.monthlyRate }
            totalCost += interest

            let overdueDue = working.reduce(0) { $0 + $1.overdueAmount }
            if monthlyBudget < interest + overdueDue * 0.05 {
                warning = "预算低于建议安全阈值，存在高风险。"
            }

            var budget = monthlyBudget
            let paidInterest = min(interest, budget)
            budget -= paidInterest

            var paidOverdue = 0.0
            if budget > 0 {
                paidOverdue = min(overdueDue, budget * overdueBudgetShare)
                budget -= paidOverdue
            }

            let sortRule: (SimulatedDebtInput, SimulatedDebtInput) -> Bool = {
                switch mode {
                case .avalanche:
                    if $0.monthlyRate == $1.monthlyRate { return $0.balance > $1.balance }
                    return $0.monthlyRate > $1.monthlyRate
                case .snowball:
                    if $0.balance == $1.balance { return $0.monthlyRate > $1.monthlyRate }
                    return $0.balance < $1.balance
                case .balanced:
                    let s0 = $0.monthlyRate * 0.5 + ($0.balance / max(1, totalBalance)) * 0.5
                    let s1 = $1.monthlyRate * 0.5 + ($1.balance / max(1, totalBalance)) * 0.5
                    return s0 > s1
                }
            }

            working.sort(by: sortRule)
            var principalPaid = 0.0
            for idx in working.indices {
                guard budget > 0 else { break }
                let pay = min(working[idx].balance, budget)
                working[idx] = working[idx].withBalance(max(0, working[idx].balance - pay))
                principalPaid += pay
                budget -= pay
            }

            let remaining = working.reduce(0) { $0 + $1.balance + $1.overdueAmount }
            let pressure = monthlyBudget == 0 ? 1 : min(1, (interest + overdueDue) / monthlyBudget)
            monthDrafts.append(
                StrategySimulationMonthDraft(
                    sequence: month,
                    principalPaid: principalPaid,
                    interestPaid: paidInterest,
                    overduePaid: paidOverdue,
                    remainingBalance: remaining,
                    pressureIndex: pressure
                )
            )
        }

        return StrategySimulationResult(
            mode: mode,
            monthlyBudget: monthlyBudget,
            totalCost: totalCost,
            monthsToDebtFree: maxMonths,
            riskWarning: warning.isEmpty ? "已达到最长 360 个月模拟上限。" : warning,
            months: monthDrafts
        )
    }
}
