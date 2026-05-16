import Foundation

enum LoanPaymentAllocationResult: Equatable {
    case allocated([UUID])
    case requiresUserDecision(unappliedAmount: Decimal)
}

private enum LoanAllocationComponent {
    case overdueFee
    case penaltyInterest
    case scheduledInterest
    case scheduledPrincipal
}

struct LoanPaymentAllocationEngine {
    var roundingPolicy: MoneyRoundingPolicy

    init(roundingPolicy: MoneyRoundingPolicy = .standard) {
        self.roundingPolicy = roundingPolicy
    }

    func currentDuePayableAmount(
        plans: [LoanRepaymentPlan],
        overdues: [LoanOverdueRecord],
        paymentDate: Date
    ) -> Decimal {
        let overduePlanIDs = Set(overdues.filter { $0.status == .active }.map(\.planID))
        let overdueAmount = plans
            .filter { overduePlanIDs.contains($0.id) }
            .reduce(Decimal(0)) { partial, plan in
                partial
                    + plan.remainingPrincipal
                    + plan.remainingInterest
                    + plan.remainingOverdueFee
                    + plan.remainingPenaltyInterest
            }

        let currentAmount = plans
            .filter { $0.dueDate <= paymentDate && !overduePlanIDs.contains($0.id) }
            .reduce(Decimal(0)) { partial, plan in
                partial + plan.remainingInterest + plan.remainingPrincipal
            }

        return roundingPolicy.round(overdueAmount + currentAmount)
    }

    func rebuildAllocations(
        payments: [LoanPaymentRecord],
        plans: [LoanRepaymentPlan],
        overdues: [LoanOverdueRecord],
        allocationMode: LoanPaymentAllocationMode = .feeFirst
    ) -> (result: LoanPaymentAllocationResult, details: [LoanPaymentAllocationDetail]) {
        reset(plans: plans, overdues: overdues)
        var details: [LoanPaymentAllocationDetail] = []

        for payment in payments.sorted(by: paymentSort) {
            let dueAmount = currentDuePayableAmount(plans: plans, overdues: overdues, paymentDate: payment.paymentDate)
            if payment.totalAmount > dueAmount {
                return (.requiresUserDecision(unappliedAmount: roundingPolicy.round(payment.totalAmount - dueAmount)), details)
            }

            var remainingPayment = payment.totalAmount

            allocate(
                payment: payment,
                plans: plans,
                overdues: overdues,
                allocationMode: allocationMode,
                remainingPayment: &remainingPayment,
                details: &details
            )

            synchronizeOverdueRecords(overdues, plans: plans)
        }

        return (.allocated(details.map(\.id)), details)
    }

    private func reset(plans: [LoanRepaymentPlan], overdues: [LoanOverdueRecord]) {
        for plan in plans {
            plan.paidPrincipal = 0
            plan.paidInterest = 0
            plan.paidOverdueFee = 0
            plan.paidPenaltyInterest = 0
            plan.paidTotalAmount = 0
            plan.remainingPrincipal = plan.scheduledPrincipal
            plan.remainingInterest = plan.scheduledInterest
            plan.remainingOverdueFee = 0
            plan.remainingPenaltyInterest = 0
            plan.remainingTotalAmount = plan.scheduledTotalAmount
            plan.status = .pending
        }

        for overdue in overdues {
            overdue.paidOverdueFee = 0
            overdue.paidPenaltyInterest = 0
            if let plan = plans.first(where: { $0.id == overdue.planID }) {
                plan.remainingOverdueFee = overdue.overdueFee
                plan.remainingPenaltyInterest = overdue.penaltyInterest
                plan.remainingTotalAmount = plan.remainingPrincipal + plan.remainingInterest + overdue.overdueFee + overdue.penaltyInterest
                plan.status = .overdue
            }
        }
    }

    private func plansForOverdueAllocation(plans: [LoanRepaymentPlan], overdues: [LoanOverdueRecord]) -> [LoanRepaymentPlan] {
        let activeOverdues = overdues.filter { $0.status == .active }
        return plans
            .filter { plan in activeOverdues.contains(where: { $0.planID == plan.id }) }
            .sorted { lhs, rhs in
                let lhsOverdue = activeOverdues.first { $0.planID == lhs.id }
                let rhsOverdue = activeOverdues.first { $0.planID == rhs.id }
                if lhsOverdue?.overdueStartDate == rhsOverdue?.overdueStartDate {
                    if lhs.dueDate == rhs.dueDate { return lhs.periodIndex < rhs.periodIndex }
                    return lhs.dueDate < rhs.dueDate
                }
                return (lhsOverdue?.overdueStartDate ?? lhs.dueDate) < (rhsOverdue?.overdueStartDate ?? rhs.dueDate)
            }
    }

    private func currentDuePlans(
        plans: [LoanRepaymentPlan],
        overdues: [LoanOverdueRecord],
        paymentDate: Date
    ) -> [LoanRepaymentPlan] {
        let overduePlanIDs = Set(overdues.filter { $0.status == .active }.map(\.planID))
        return plans
            .filter {
                $0.dueDate <= paymentDate
                    && !overduePlanIDs.contains($0.id)
                    && $0.status != .paid
                    && remainingScheduledAmount($0) > 0
            }
            .sorted { lhs, rhs in
                if lhs.dueDate == rhs.dueDate { return lhs.periodIndex < rhs.periodIndex }
                return lhs.dueDate < rhs.dueDate
            }
    }

    private func allocate(
        payment: LoanPaymentRecord,
        plans: [LoanRepaymentPlan],
        overdues: [LoanOverdueRecord],
        allocationMode: LoanPaymentAllocationMode,
        remainingPayment: inout Decimal,
        details: inout [LoanPaymentAllocationDetail]
    ) {
        let overduePlans = plansForOverdueAllocation(plans: plans, overdues: overdues)
        let currentPlans = currentDuePlans(plans: plans, overdues: overdues, paymentDate: payment.paymentDate)

        switch allocationMode {
        case .feeFirst:
            allocate(
                payment: payment,
                to: overduePlans,
                amount: &remainingPayment,
                components: [.overdueFee, .penaltyInterest, .scheduledInterest, .scheduledPrincipal],
                details: &details
            )
            allocate(
                payment: payment,
                to: currentPlans,
                amount: &remainingPayment,
                components: [.scheduledInterest, .scheduledPrincipal],
                details: &details
            )
        case .currentPeriodFirst:
            allocate(
                payment: payment,
                to: currentPlans,
                amount: &remainingPayment,
                components: [.scheduledInterest, .scheduledPrincipal],
                details: &details
            )
            allocate(
                payment: payment,
                to: overduePlans,
                amount: &remainingPayment,
                components: [.scheduledInterest, .scheduledPrincipal],
                details: &details
            )
            allocate(
                payment: payment,
                to: overduePlans,
                amount: &remainingPayment,
                components: [.overdueFee],
                details: &details
            )
            allocate(
                payment: payment,
                to: overduePlans,
                amount: &remainingPayment,
                components: [.penaltyInterest],
                details: &details
            )
        }
    }

    private func allocate(
        payment: LoanPaymentRecord,
        to plans: [LoanRepaymentPlan],
        amount remainingPayment: inout Decimal,
        components: [LoanAllocationComponent],
        details: inout [LoanPaymentAllocationDetail]
    ) {
        for plan in plans where remainingPayment > 0 {
            let detail = allocate(payment: payment, to: plan, amount: &remainingPayment, components: components)
            appendOrMerge(detail, into: &details)
        }
    }

    private func allocate(
        payment: LoanPaymentRecord,
        to plan: LoanRepaymentPlan,
        amount remainingPayment: inout Decimal,
        components: [LoanAllocationComponent]
    ) -> LoanPaymentAllocationDetail {
        var overdueFee: Decimal = 0
        var penaltyInterest: Decimal = 0
        var principal: Decimal = 0
        var interest: Decimal = 0

        for component in components where remainingPayment > 0 {
            switch component {
            case .overdueFee:
                let amount = take(from: &remainingPayment, remainingBucket: &plan.remainingOverdueFee)
                overdueFee += amount
                plan.paidOverdueFee += amount
            case .penaltyInterest:
                let amount = take(from: &remainingPayment, remainingBucket: &plan.remainingPenaltyInterest)
                penaltyInterest += amount
                plan.paidPenaltyInterest += amount
            case .scheduledInterest:
                let amount = take(from: &remainingPayment, remainingBucket: &plan.remainingInterest)
                interest += amount
                plan.paidInterest += amount
            case .scheduledPrincipal:
                let amount = take(from: &remainingPayment, remainingBucket: &plan.remainingPrincipal)
                principal += amount
                plan.paidPrincipal += amount
            }
        }

        plan.paidTotalAmount = plan.paidPrincipal + plan.paidInterest + plan.paidOverdueFee + plan.paidPenaltyInterest
        plan.remainingTotalAmount = plan.remainingPrincipal + plan.remainingInterest + plan.remainingOverdueFee + plan.remainingPenaltyInterest
        if plan.remainingTotalAmount == 0 {
            plan.status = .paid
        } else if plan.paidTotalAmount > 0 {
            plan.status = .partiallyPaid
        }

        return LoanPaymentAllocationDetail(
            paymentID: payment.id,
            debtID: payment.debtID,
            planID: plan.id,
            allocatedPrincipal: principal,
            allocatedInterest: interest,
            allocatedOverdueFee: overdueFee,
            allocatedPenaltyInterest: penaltyInterest
        )
    }

    private func appendOrMerge(
        _ detail: LoanPaymentAllocationDetail,
        into details: inout [LoanPaymentAllocationDetail]
    ) {
        guard detail.allocatedTotal > 0 else { return }

        if let index = details.firstIndex(where: { $0.paymentID == detail.paymentID && $0.planID == detail.planID }) {
            details[index].allocatedPrincipal = roundingPolicy.round(details[index].allocatedPrincipal + detail.allocatedPrincipal)
            details[index].allocatedInterest = roundingPolicy.round(details[index].allocatedInterest + detail.allocatedInterest)
            details[index].allocatedOverdueFee = roundingPolicy.round(details[index].allocatedOverdueFee + detail.allocatedOverdueFee)
            details[index].allocatedPenaltyInterest = roundingPolicy.round(details[index].allocatedPenaltyInterest + detail.allocatedPenaltyInterest)
            details[index].allocatedTotal = roundingPolicy.round(details[index].allocatedTotal + detail.allocatedTotal)
        } else {
            details.append(detail)
        }
    }

    private func synchronizeOverdueRecords(_ overdues: [LoanOverdueRecord], plans: [LoanRepaymentPlan]) {
        for overdue in overdues {
            guard let plan = plans.first(where: { $0.id == overdue.planID }) else { continue }
            overdue.paidOverdueFee = plan.paidOverdueFee
            overdue.paidPenaltyInterest = plan.paidPenaltyInterest

            let originalPlanSettled = plan.remainingPrincipal == 0 && plan.remainingInterest == 0
            let feeSettled = overdue.paidOverdueFee >= overdue.overdueFee
            let penaltySettled = overdue.paidPenaltyInterest >= overdue.penaltyInterest

            if originalPlanSettled && feeSettled && penaltySettled {
                overdue.status = .paid
                plan.status = .paid
            } else if overdue.status == .closed {
                plan.status = plan.paidTotalAmount > 0 ? .partiallyPaid : .pending
            } else if overdue.status == .active {
                plan.status = plan.paidTotalAmount > 0 ? .partiallyPaid : .overdue
            }
        }
    }

    private func take(from paymentAmount: inout Decimal, remainingBucket: inout Decimal) -> Decimal {
        let amount = minDecimal(paymentAmount, remainingBucket)
        paymentAmount = roundingPolicy.round(paymentAmount - amount)
        remainingBucket = roundingPolicy.round(remainingBucket - amount)
        return roundingPolicy.round(amount)
    }

    private func remainingPlanAmount(_ plan: LoanRepaymentPlan) -> Decimal {
        plan.remainingPrincipal + plan.remainingInterest + plan.remainingOverdueFee + plan.remainingPenaltyInterest
    }

    private func remainingScheduledAmount(_ plan: LoanRepaymentPlan) -> Decimal {
        plan.remainingPrincipal + plan.remainingInterest
    }

    private func paymentSort(_ lhs: LoanPaymentRecord, _ rhs: LoanPaymentRecord) -> Bool {
        if lhs.paymentDate == rhs.paymentDate { return lhs.createdAt < rhs.createdAt }
        return lhs.paymentDate < rhs.paymentDate
    }
}
