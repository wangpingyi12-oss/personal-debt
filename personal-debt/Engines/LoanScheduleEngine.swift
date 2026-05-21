import Foundation

enum LoanScheduleError: Error, Equatable {
    case startDateAfterEndDate
    case invalidRepaymentDay
}

struct LoanScheduleEngine {
    static let autoSettledHistoryLockReason = "autoSettledHistory"

    var roundingPolicy: MoneyRoundingPolicy
    var datePolicy: DateCalculationPolicy

    init(roundingPolicy: MoneyRoundingPolicy = .standard, datePolicy: DateCalculationPolicy = .standard) {
        self.roundingPolicy = roundingPolicy
        self.datePolicy = datePolicy
    }

    func generatePlans(
        for debt: LoanDebt,
        preservingOriginalContractForInProgress: Bool = false
    ) throws -> [LoanRepaymentPlan] {
        let usesOriginalContractForInProgress = preservingOriginalContractForInProgress && debt.entryMode == .inProgressLoan
        let planStartDate = usesOriginalContractForInProgress ? debt.startDate : planGenerationStartDate(for: debt)
        guard planStartDate <= debt.endDate else { throw LoanScheduleError.startDateAfterEndDate }
        guard (1...31).contains(debt.repaymentDay) else { throw LoanScheduleError.invalidRepaymentDay }

        let managedPeriods = generatedPeriods(
            startDate: planStartDate,
            endDate: debt.endDate,
            repaymentDay: debt.repaymentDay
        )

        let historicalPlans: [LoanRepaymentPlan]
        if debt.entryMode == .inProgressLoan && usesOriginalContractForInProgress == false {
            let firstManagedDueDate = managedPeriods.first?.dueDate ?? debt.endDate
            historicalPlans = historicalPaidPlans(
                debtID: debt.id,
                startDate: debt.startDate,
                cutoffDate: firstManagedDueDate,
                repaymentDay: debt.repaymentDay
            )
        } else {
            historicalPlans = []
        }

        let regularTermCount = max(managedPeriods.filter { $0.type == .regular }.count, 1)
        let principal = usesOriginalContractForInProgress ? debt.originalPrincipal : debt.openingPrincipalForManagement
        let monthlyRate = debt.annualInterestRate / Decimal(12)
        let equalPrincipalValues = roundingPolicy.allocateEvenly(total: principal, count: regularTermCount)
        let equalPaymentAmount = equalPayment(principal: principal, monthlyRate: monthlyRate, termCount: regularTermCount)

        var remainingPrincipal = principal
        var plans: [LoanRepaymentPlan] = historicalPlans

        for (offset, period) in managedPeriods.enumerated() {
            let index = historicalPlans.count + offset + 1
            let isLast = offset == managedPeriods.count - 1
            let scheduledPrincipal: Decimal
            let scheduledInterest: Decimal

            switch debt.repaymentMethod {
            case .equalPrincipal:
                scheduledPrincipal = isLast ? remainingPrincipal : equalPrincipalValues[min(offset, equalPrincipalValues.count - 1)]
                scheduledInterest = roundingPolicy.round(remainingPrincipal * monthlyRate)
            case .equalPayment:
                scheduledInterest = roundingPolicy.round(remainingPrincipal * monthlyRate)
                if isLast {
                    scheduledPrincipal = remainingPrincipal
                } else {
                    scheduledPrincipal = roundingPolicy.round(maxDecimal(equalPaymentAmount - scheduledInterest, 0))
                }
            case .interestFirst:
                scheduledInterest = roundingPolicy.round(principal * monthlyRate)
                scheduledPrincipal = isLast ? remainingPrincipal : 0
            case .principalAtEnd:
                if isLast {
                    scheduledPrincipal = remainingPrincipal
                    scheduledInterest = roundingPolicy.round(principal * monthlyRate * Decimal(regularTermCount))
                } else {
                    scheduledPrincipal = 0
                    scheduledInterest = 0
                }
            }

            let afterScheduled = roundingPolicy.round(maxDecimal(remainingPrincipal - scheduledPrincipal, 0))
            let plan = LoanRepaymentPlan(
                debtID: debt.id,
                periodIndex: index,
                periodType: period.type,
                periodStartDate: period.startDate,
                periodEndDate: period.endDate,
                dueDate: period.dueDate,
                scheduledPrincipal: scheduledPrincipal,
                scheduledInterest: scheduledInterest,
                remainingPrincipalBeforePayment: remainingPrincipal,
                remainingPrincipalAfterScheduledPayment: afterScheduled
            )
            plans.append(plan)
            remainingPrincipal = afterScheduled
        }

        if usesOriginalContractForInProgress {
            applyDefaultHistoricalSettlement(to: plans, debt: debt)
        }

        return plans
    }

    func planGenerationStartDate(for debt: LoanDebt) -> Date {
        switch debt.entryMode {
        case .newLoan:
            return debt.startDate
        case .inProgressLoan:
            return debt.managementStartDate ?? debt.startDate
        }
    }

    private func equalPayment(principal: Decimal, monthlyRate: Decimal, termCount: Int) -> Decimal {
        guard monthlyRate > 0 else {
            return roundingPolicy.round(principal / Decimal(termCount))
        }

        let growth = Decimal.pow(1 + monthlyRate, termCount)
        let numerator = principal * monthlyRate * growth
        let denominator = growth - 1
        return roundingPolicy.round(numerator / denominator)
    }

    private func generatedPeriods(
        startDate: Date,
        endDate: Date,
        repaymentDay: Int
    ) -> [(startDate: Date, endDate: Date, dueDate: Date, type: LoanPlanPeriodType)] {
        var periods: [(startDate: Date, endDate: Date, dueDate: Date, type: LoanPlanPeriodType)] = []
        var dueDate = datePolicy.firstRepaymentDate(after: startDate, dayOfMonth: repaymentDay)
        var periodStart = startDate

        while dueDate <= endDate {
            periods.append((periodStart, dueDate, dueDate, .regular))
            periodStart = dueDate
            dueDate = datePolicy.addingMonths(1, to: dueDate, matchingDay: repaymentDay)
        }

        if periods.isEmpty {
            return [(startDate, endDate, endDate, .shortTermSinglePeriod)]
        }

        if let last = periods.last, !datePolicy.isSameDay(last.dueDate, endDate), last.dueDate < endDate {
            periods.append((last.dueDate, endDate, endDate, .finalPartialPeriod))
        }

        return periods
    }

    private func historicalPaidPlans(
        debtID: UUID,
        startDate: Date,
        cutoffDate: Date,
        repaymentDay: Int
    ) -> [LoanRepaymentPlan] {
        var periods: [(startDate: Date, endDate: Date, dueDate: Date)] = []
        var dueDate = datePolicy.firstRepaymentDate(after: startDate, dayOfMonth: repaymentDay)
        var periodStart = startDate

        while dueDate < cutoffDate {
            periods.append((periodStart, dueDate, dueDate))
            periodStart = dueDate
            dueDate = datePolicy.addingMonths(1, to: dueDate, matchingDay: repaymentDay)
        }

        return periods.enumerated().map { offset, period in
            let plan = LoanRepaymentPlan(
                debtID: debtID,
                periodIndex: offset + 1,
                periodType: .regular,
                periodStartDate: period.startDate,
                periodEndDate: period.endDate,
                dueDate: period.dueDate,
                scheduledPrincipal: 0,
                scheduledInterest: 0,
                remainingPrincipalBeforePayment: 0,
                remainingPrincipalAfterScheduledPayment: 0,
                lockReason: Self.autoSettledHistoryLockReason
            )
            plan.status = .paid
            plan.remainingPrincipal = 0
            plan.remainingInterest = 0
            plan.remainingOverdueFee = 0
            plan.remainingPenaltyInterest = 0
            plan.remainingTotalAmount = 0
            plan.paidPrincipal = 0
            plan.paidInterest = 0
            plan.paidOverdueFee = 0
            plan.paidPenaltyInterest = 0
            plan.paidTotalAmount = 0
            return plan
        }
    }

    private func applyDefaultHistoricalSettlement(to plans: [LoanRepaymentPlan], debt: LoanDebt) {
        guard debt.entryMode == .inProgressLoan else { return }
        guard let managementStartDate = debt.managementStartDate else { return }

        let managementDay = datePolicy.startOfDay(managementStartDate)
        let firstDueAfterManagementStart = datePolicy.firstRepaymentDate(after: managementDay, dayOfMonth: debt.repaymentDay)
        let cutoffDate = datePolicy.startOfDay(firstDueAfterManagementStart) > datePolicy.startOfDay(debt.endDate)
            ? datePolicy.startOfDay(debt.endDate)
            : datePolicy.startOfDay(firstDueAfterManagementStart)

        for plan in plans where datePolicy.startOfDay(plan.dueDate) < cutoffDate {
            applyDefaultPaidState(to: plan)
        }
    }

    private func applyDefaultPaidState(to plan: LoanRepaymentPlan) {
        plan.lockReason = Self.autoSettledHistoryLockReason
        plan.status = .paid
        plan.remainingPrincipal = 0
        plan.remainingInterest = 0
        plan.remainingOverdueFee = 0
        plan.remainingPenaltyInterest = 0
        plan.remainingTotalAmount = 0
        plan.paidPrincipal = plan.scheduledPrincipal
        plan.paidInterest = plan.scheduledInterest
        plan.paidOverdueFee = 0
        plan.paidPenaltyInterest = 0
        plan.paidTotalAmount = plan.scheduledTotalAmount
    }
}
