import Foundation

enum PersonalLendingValidationError: Error, Equatable {
    case principalMustBePositive
    case fixedInterestMustNotBeNegative
    case fixedInterestMustBePositive
    case interestBearingRequiresPlan
    case noFixedPlanMustBeInterestFree
    case agreedEndDateRequired
    case agreedEndDateBeforeBorrowedDate
    case invalidMonthlyRepaymentDay
    case invalidTermCount
}

struct PersonalLendingScheduleEngine {
    var roundingPolicy: MoneyRoundingPolicy
    var datePolicy: DateCalculationPolicy

    init(roundingPolicy: MoneyRoundingPolicy = .standard, datePolicy: DateCalculationPolicy = .standard) {
        self.roundingPolicy = roundingPolicy
        self.datePolicy = datePolicy
    }

    func generatePlans(for debt: PersonalLendingDebt) throws -> [PersonalLendingPlan] {
        try validate(debt)
        debt.totalPayableAmount = roundingPolicy.round(debt.principalAmount + debt.fixedInterestAmount)
        debt.paidAmount = 0
        debt.remainingAmount = debt.totalPayableAmount
        debt.status = .active

        switch debt.repaymentMethod {
        case .noFixedPlan:
            return []
        case .principalAndInterestAtMaturity:
            guard let agreedEndDate = debt.agreedEndDate else {
                throw PersonalLendingValidationError.agreedEndDateRequired
            }
            return [
                PersonalLendingPlan(
                    debtID: debt.id,
                    periodIndex: 1,
                    dueDate: agreedEndDate,
                    scheduledPrincipal: debt.principalAmount,
                    scheduledInterest: debt.fixedInterestAmount
                )
            ]
        case .equalPrincipalEqualInterest:
            guard let monthlyDay = debt.monthlyRepaymentDay, (1...31).contains(monthlyDay) else {
                throw PersonalLendingValidationError.invalidMonthlyRepaymentDay
            }
            guard debt.termCount > 0 else {
                throw PersonalLendingValidationError.invalidTermCount
            }

            let principalParts = roundingPolicy.allocateEvenly(total: debt.principalAmount, count: debt.termCount)
            let interestParts = roundingPolicy.allocateEvenly(total: debt.fixedInterestAmount, count: debt.termCount)
            let firstDueDate = datePolicy.firstRepaymentDate(after: debt.borrowedDate, dayOfMonth: monthlyDay)
            var plans: [PersonalLendingPlan] = []

            for index in 0..<debt.termCount {
                let dueDate = datePolicy.addingMonths(index, to: firstDueDate, matchingDay: monthlyDay)
                plans.append(
                    PersonalLendingPlan(
                        debtID: debt.id,
                        periodIndex: index + 1,
                        dueDate: dueDate,
                        scheduledPrincipal: principalParts[index],
                        scheduledInterest: interestParts[index]
                    )
                )
            }

            debt.agreedEndDate = plans.last?.dueDate
            return plans
        }
    }

    func validate(_ debt: PersonalLendingDebt) throws {
        guard debt.principalAmount > 0 else { throw PersonalLendingValidationError.principalMustBePositive }
        guard debt.fixedInterestAmount >= 0 else { throw PersonalLendingValidationError.fixedInterestMustNotBeNegative }

        if debt.isInterestBearing && debt.fixedInterestAmount <= 0 {
            throw PersonalLendingValidationError.fixedInterestMustBePositive
        }

        switch debt.repaymentMethod {
        case .noFixedPlan:
            if debt.isInterestBearing || debt.fixedInterestAmount != 0 {
                throw PersonalLendingValidationError.noFixedPlanMustBeInterestFree
            }
        case .principalAndInterestAtMaturity:
            guard let agreedEndDate = debt.agreedEndDate else {
                throw PersonalLendingValidationError.agreedEndDateRequired
            }
            if agreedEndDate < debt.borrowedDate {
                throw PersonalLendingValidationError.agreedEndDateBeforeBorrowedDate
            }
        case .equalPrincipalEqualInterest:
            if debt.isInterestBearing == false && debt.fixedInterestAmount != 0 {
                throw PersonalLendingValidationError.fixedInterestMustNotBeNegative
            }
            guard let monthlyDay = debt.monthlyRepaymentDay, (1...31).contains(monthlyDay) else {
                throw PersonalLendingValidationError.invalidMonthlyRepaymentDay
            }
            guard debt.termCount > 0 else {
                throw PersonalLendingValidationError.invalidTermCount
            }
        }

        if debt.isInterestBearing && debt.repaymentMethod == .noFixedPlan {
            throw PersonalLendingValidationError.interestBearingRequiresPlan
        }
    }
}
