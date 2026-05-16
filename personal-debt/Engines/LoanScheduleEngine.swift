import Foundation

enum LoanScheduleError: Error, Equatable {
    case startDateAfterEndDate
    case invalidTermCount
    case invalidRepaymentDay
}

struct LoanScheduleEngine {
    var roundingPolicy: MoneyRoundingPolicy
    var datePolicy: DateCalculationPolicy

    init(roundingPolicy: MoneyRoundingPolicy = .standard, datePolicy: DateCalculationPolicy = .standard) {
        self.roundingPolicy = roundingPolicy
        self.datePolicy = datePolicy
    }

    func generatePlans(for debt: LoanDebt) throws -> [LoanRepaymentPlan] {
        let planStartDate = planGenerationStartDate(for: debt)
        guard planStartDate <= debt.endDate else { throw LoanScheduleError.startDateAfterEndDate }
        guard debt.termCount > 0 else { throw LoanScheduleError.invalidTermCount }
        guard (1...31).contains(debt.repaymentDay) else { throw LoanScheduleError.invalidRepaymentDay }

        let periods = generatedPeriods(
            startDate: planStartDate,
            endDate: debt.endDate,
            repaymentDay: debt.repaymentDay,
            maxRegularTerms: debt.termCount
        )

        let regularTermCount = max(periods.filter { $0.type == .regular }.count, 1)
        let principal = debt.openingPrincipalForManagement
        let monthlyRate = debt.annualInterestRate / Decimal(12)
        let equalPrincipalValues = roundingPolicy.allocateEvenly(total: principal, count: regularTermCount)
        let equalPaymentAmount = equalPayment(principal: principal, monthlyRate: monthlyRate, termCount: regularTermCount)

        var remainingPrincipal = principal
        var plans: [LoanRepaymentPlan] = []

        for (offset, period) in periods.enumerated() {
            let index = offset + 1
            let isLast = index == periods.count
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
        repaymentDay: Int,
        maxRegularTerms: Int
    ) -> [(startDate: Date, endDate: Date, dueDate: Date, type: LoanPlanPeriodType)] {
        var periods: [(startDate: Date, endDate: Date, dueDate: Date, type: LoanPlanPeriodType)] = []
        var dueDate = datePolicy.firstRepaymentDate(after: startDate, dayOfMonth: repaymentDay)
        var periodStart = startDate

        while dueDate <= endDate && periods.count < maxRegularTerms {
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
}
