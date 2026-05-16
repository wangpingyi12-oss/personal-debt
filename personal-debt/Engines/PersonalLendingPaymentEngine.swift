import Foundation

enum PersonalLendingPaymentError: Error, Equatable {
    case overpaymentNotAllowed
}

struct PersonalLendingPaymentEngine {
    var roundingPolicy: MoneyRoundingPolicy

    init(roundingPolicy: MoneyRoundingPolicy = .standard) {
        self.roundingPolicy = roundingPolicy
    }

    func rebuildPayments(
        debt: PersonalLendingDebt,
        plans: [PersonalLendingPlan],
        payments: [PersonalLendingPaymentRecord],
        today: Date = Date()
    ) throws -> [PersonalLendingAllocationDetail] {
        let totalPaid = payments.reduce(Decimal(0)) { $0 + $1.amount }
        if totalPaid > debt.totalPayableAmount {
            throw PersonalLendingPaymentError.overpaymentNotAllowed
        }

        reset(debt: debt, plans: plans)
        var allocations: [PersonalLendingAllocationDetail] = []

        for payment in payments.sorted(by: paymentSort) {
            var remainingPayment = payment.amount

            if plans.isEmpty {
                debt.paidAmount = roundingPolicy.round(debt.paidAmount + remainingPayment)
                debt.remainingAmount = roundingPolicy.round(maxDecimal(debt.totalPayableAmount - debt.paidAmount, 0))
                continue
            }

            for plan in plans.sorted(by: planSort) where remainingPayment > 0 {
                guard plan.remainingAmount > 0 else { continue }
                let allocated = minDecimal(remainingPayment, plan.remainingAmount)
                plan.paidAmount = roundingPolicy.round(plan.paidAmount + allocated)
                plan.remainingAmount = roundingPolicy.round(plan.remainingAmount - allocated)
                plan.status = status(paidAmount: plan.paidAmount, remainingAmount: plan.remainingAmount, totalAmount: plan.scheduledTotalAmount)
                remainingPayment = roundingPolicy.round(remainingPayment - allocated)
                allocations.append(
                    PersonalLendingAllocationDetail(
                        paymentID: payment.id,
                        debtID: debt.id,
                        planID: plan.id,
                        allocatedAmount: allocated
                    )
                )
            }
        }

        debt.paidAmount = roundingPolicy.round(payments.reduce(Decimal(0)) { $0 + $1.amount })
        debt.remainingAmount = roundingPolicy.round(maxDecimal(debt.totalPayableAmount - debt.paidAmount, 0))
        debt.status = debtStatus(paidAmount: debt.paidAmount, remainingAmount: debt.remainingAmount, totalAmount: debt.totalPayableAmount)
        updatePastDueStatistics(debt: debt, plans: plans, today: today)
        return allocations
    }

    func updatePastDueStatistics(debt: PersonalLendingDebt, plans: [PersonalLendingPlan], today: Date) {
        if plans.isEmpty {
            if let agreedEndDate = debt.agreedEndDate, today > agreedEndDate, debt.remainingAmount > 0 {
                debt.pastDueScheduledAmount = debt.remainingAmount
                debt.pastDuePlanCount = 0
                debt.pastDueDebtCount = 1
            } else {
                debt.pastDueScheduledAmount = 0
                debt.pastDuePlanCount = 0
                debt.pastDueDebtCount = 0
            }
            return
        }

        let pastDuePlans = plans.filter { $0.dueDate < today && $0.remainingAmount > 0 }
        debt.pastDueScheduledAmount = roundingPolicy.round(pastDuePlans.reduce(Decimal(0)) { $0 + $1.remainingAmount })
        debt.pastDuePlanCount = pastDuePlans.count
        debt.pastDueDebtCount = pastDuePlans.isEmpty ? 0 : 1
    }

    private func reset(debt: PersonalLendingDebt, plans: [PersonalLendingPlan]) {
        debt.paidAmount = 0
        debt.remainingAmount = debt.totalPayableAmount
        debt.status = .active

        for plan in plans {
            plan.paidAmount = 0
            plan.remainingAmount = plan.scheduledTotalAmount
            plan.status = .pending
        }
    }

    private func status(paidAmount: Decimal, remainingAmount: Decimal, totalAmount: Decimal) -> PersonalLendingPlanStatus {
        if remainingAmount == 0 { return .paid }
        if paidAmount > 0 && remainingAmount < totalAmount { return .partiallyPaid }
        return .pending
    }

    private func debtStatus(paidAmount: Decimal, remainingAmount: Decimal, totalAmount: Decimal) -> DebtStatus {
        if remainingAmount == 0 { return .paidOff }
        if paidAmount > 0 && remainingAmount < totalAmount { return .partiallyPaid }
        return .active
    }

    private func paymentSort(_ lhs: PersonalLendingPaymentRecord, _ rhs: PersonalLendingPaymentRecord) -> Bool {
        if lhs.paymentDate == rhs.paymentDate {
            if lhs.createdAt == rhs.createdAt { return lhs.id.uuidString < rhs.id.uuidString }
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.paymentDate < rhs.paymentDate
    }

    private func planSort(_ lhs: PersonalLendingPlan, _ rhs: PersonalLendingPlan) -> Bool {
        if lhs.dueDate == rhs.dueDate { return lhs.periodIndex < rhs.periodIndex }
        return lhs.dueDate < rhs.dueDate
    }
}
