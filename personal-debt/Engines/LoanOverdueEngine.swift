import Foundation

struct LoanOverdueEngine {
    var roundingPolicy: MoneyRoundingPolicy
    var datePolicy: DateCalculationPolicy

    init(roundingPolicy: MoneyRoundingPolicy = .standard, datePolicy: DateCalculationPolicy = .standard) {
        self.roundingPolicy = roundingPolicy
        self.datePolicy = datePolicy
    }

    func penaltyInterest(base: Decimal, penaltyDailyRate: Decimal, overdueDays: Int) -> Decimal {
        roundingPolicy.round(base * penaltyDailyRate * Decimal(overdueDays))
    }

    func makeOrUpdateOverdueRecord(
        for plan: LoanRepaymentPlan,
        debt: LoanDebt,
        existingRecord: LoanOverdueRecord? = nil,
        rule: LoanCalculationRule,
        today: Date
    ) -> LoanOverdueRecord? {
        guard today > plan.dueDate, plan.remainingTotalAmount > 0 else { return nil }

        let days = datePolicy.daysBetween(plan.dueDate, today)
        let base = overdueBase(for: plan, rule: rule)
        let feeResult = overdueFee(base: base, rule: rule)
        let penaltyResult = penaltyInterest(base: base, debt: debt, rule: rule, overdueDays: days)

        if let existingRecord {
            guard !existingRecord.isUserManaged else { return existingRecord }
            existingRecord.overdueDays = days
            existingRecord.overdueBaseAmount = base
            existingRecord.overdueFee = feeResult.amount
            existingRecord.penaltyInterest = penaltyResult.amount
            existingRecord.generatesOverdueFee = feeResult.isGenerated
            existingRecord.generatesPenaltyInterest = penaltyResult.isGenerated
            existingRecord.updatedAt = today
            synchronize(plan: plan, with: existingRecord)
            existingRecord.status = status(for: plan, overdueRecord: existingRecord)
            return existingRecord
        }

        plan.overdueStartDate = plan.dueDate
        plan.overdueDays = days
        plan.remainingOverdueFee = feeResult.amount
        plan.remainingPenaltyInterest = penaltyResult.amount
        plan.remainingTotalAmount = plan.remainingPrincipal + plan.remainingInterest + feeResult.amount + penaltyResult.amount
        plan.status = .overdue

        return LoanOverdueRecord(
            debtID: debt.id,
            planID: plan.id,
            overdueStartDate: plan.dueDate,
            overdueDays: days,
            overdueBaseAmount: base,
            overdueFee: feeResult.amount,
            penaltyInterest: penaltyResult.amount,
            generatesOverdueFee: feeResult.isGenerated,
            generatesPenaltyInterest: penaltyResult.isGenerated,
            updatedAt: today
        )
    }

    func status(for plan: LoanRepaymentPlan, overdueRecord: LoanOverdueRecord) -> LoanOverdueRecordStatus {
        let feeSettled = overdueRecord.paidOverdueFee >= overdueRecord.overdueFee
        let penaltySettled = overdueRecord.paidPenaltyInterest >= overdueRecord.penaltyInterest
        let originalPlanSettled = plan.remainingPrincipal == 0 && plan.remainingInterest == 0

        if originalPlanSettled && feeSettled && penaltySettled {
            return .paid
        }
        return overdueRecord.status == .closed ? .closed : .active
    }

    private func overdueBase(for plan: LoanRepaymentPlan, rule: LoanCalculationRule) -> Decimal {
        switch rule.overdueBaseType {
        case .currentUnpaidPrincipal:
            return plan.remainingPrincipal
        case .currentRemainingScheduledAmount:
            return plan.remainingPrincipal + plan.remainingInterest
        }
    }

    private func overdueFee(base: Decimal, rule: LoanCalculationRule) -> (amount: Decimal, isGenerated: Bool) {
        switch rule.overdueFeeMode {
        case .zero:
            return (0, true)
        case .fixed:
            return (roundingPolicy.round(rule.fixedOverdueFee ?? 0), true)
        case .percentage:
            return (roundingPolicy.round(base * (rule.overdueFeeRate ?? 0)), true)
        case .disabled:
            return (0, false)
        }
    }

    private func penaltyInterest(
        base: Decimal,
        debt: LoanDebt,
        rule: LoanCalculationRule,
        overdueDays: Int
    ) -> (amount: Decimal, isGenerated: Bool) {
        switch rule.penaltyInterestMode {
        case .loanDailyRateMultiplier:
            let loanDailyRate = debt.annualInterestRate / Decimal(365)
            let penaltyDailyRate = loanDailyRate * rule.penaltyRateMultiplier
            return (penaltyInterest(base: base, penaltyDailyRate: penaltyDailyRate, overdueDays: overdueDays), true)
        case .fixedDailyRate:
            let penaltyDailyRate = rule.fixedPenaltyDailyRate ?? 0
            return (penaltyInterest(base: base, penaltyDailyRate: penaltyDailyRate, overdueDays: overdueDays), true)
        case .zero:
            return (0, true)
        case .disabled:
            return (0, false)
        }
    }

    private func synchronize(plan: LoanRepaymentPlan, with overdueRecord: LoanOverdueRecord) {
        plan.overdueStartDate = overdueRecord.overdueStartDate
        plan.overdueDays = overdueRecord.overdueDays
        plan.remainingOverdueFee = roundingPolicy.round(maxDecimal(overdueRecord.overdueFee - overdueRecord.paidOverdueFee, 0))
        plan.remainingPenaltyInterest = roundingPolicy.round(maxDecimal(overdueRecord.penaltyInterest - overdueRecord.paidPenaltyInterest, 0))
        plan.remainingTotalAmount = plan.remainingPrincipal
            + plan.remainingInterest
            + plan.remainingOverdueFee
            + plan.remainingPenaltyInterest
        if plan.remainingTotalAmount == 0 {
            plan.status = .paid
        } else if plan.paidTotalAmount > 0 {
            plan.status = .partiallyPaid
        } else {
            plan.status = .overdue
        }
    }
}
