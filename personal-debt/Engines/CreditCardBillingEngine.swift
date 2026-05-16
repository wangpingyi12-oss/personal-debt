import Foundation

struct CreditCardBillingEngine {
    var roundingPolicy: MoneyRoundingPolicy
    var datePolicy: DateCalculationPolicy

    init(roundingPolicy: MoneyRoundingPolicy = .standard, datePolicy: DateCalculationPolicy = .standard) {
        self.roundingPolicy = roundingPolicy
        self.datePolicy = datePolicy
    }

    func makeUserConfirmedStatement(
        debtID: UUID,
        billingDate: Date,
        dueDate: Date,
        statementAmount: Decimal,
        userMinimumPaymentAmount: Decimal?,
        rule: CreditCardCalculationRule
    ) -> CreditCardStatement {
        let minimum = minimumPaymentAmount(
            statementAmount: statementAmount,
            userInput: userMinimumPaymentAmount,
            rule: rule
        )

        return CreditCardStatement(
            debtID: debtID,
            billingDate: billingDate,
            dueDate: dueDate,
            statementAmount: roundingPolicy.round(statementAmount),
            minimumPaymentAmount: minimum,
            minimumPaymentSource: userMinimumPaymentAmount == nil ? "fallbackRule" : "userProvided",
            source: .userConfirmed
        )
    }

    func makeFallbackStatement(
        debtID: UUID,
        billingDate: Date,
        dueDate: Date,
        previousStatement: CreditCardStatement?,
        installments: [CreditCardInstallmentPlan],
        rule: CreditCardCalculationRule
    ) -> CreditCardStatement {
        let previousRemaining = previousCycleRemainingAmount(from: previousStatement)
        let installmentAmount = nextInstallmentAmount(for: billingDate, installments: installments)
        let amount = roundingPolicy.round(previousRemaining + installmentAmount)
        let minimum = minimumPaymentAmount(statementAmount: amount, userInput: nil, rule: rule)

        return CreditCardStatement(
            debtID: debtID,
            billingDate: billingDate,
            dueDate: dueDate,
            statementAmount: amount,
            minimumPaymentAmount: minimum,
            minimumPaymentSource: "fallbackRule",
            source: .fallback
        )
    }

    func makeRepaymentPlan(for statement: CreditCardStatement) -> CreditCardRepaymentPlan {
        CreditCardRepaymentPlan(
            debtID: statement.debtID,
            statementID: statement.id,
            dueDate: statement.dueDate,
            scheduledAmount: statement.statementAmount,
            source: statement.source
        )
    }

    func minimumPaymentAmount(
        statementAmount: Decimal,
        userInput: Decimal?,
        rule: CreditCardCalculationRule
    ) -> Decimal {
        if let userInput {
            return roundingPolicy.round(userInput)
        }
        return roundingPolicy.round(maxDecimal(statementAmount * rule.minimumPaymentRatio, rule.minimumPaymentFloor))
    }

    func previousCycleRemainingAmount(from statement: CreditCardStatement?) -> Decimal {
        guard let statement, statement.isActive else { return 0 }
        return maxDecimal(statement.statementAmount - statement.paidAmount, 0)
    }

    func nextInstallmentAmount(for billingDate: Date, installments: [CreditCardInstallmentPlan]) -> Decimal {
        installments
            .filter { installment in
                installment.isActive
                    && installment.paidTerms < installment.totalTerms
                    && datePolicy.startOfDay(installment.nextBillingDate) <= datePolicy.startOfDay(billingDate)
            }
            .reduce(Decimal(0)) { partial, installment in
                partial + installment.principalPerTerm + installment.feePerTerm + installment.interestPerTerm
            }
            .roundedMoney(roundingPolicy)
    }

    func updateBreakdown(_ breakdown: CreditCardStatementBreakdown, for statement: CreditCardStatement) {
        let knownAmount = breakdown.normalSpending
            + breakdown.previousCycleRemainingAmount
            + breakdown.installmentPrincipal
            + breakdown.installmentFee
            + breakdown.installmentInterest
            + breakdown.revolvingInterest
            + breakdown.overdueFee
            + breakdown.penaltyInterest

        breakdown.hasBreakdownConflict = knownAmount > statement.statementAmount
        breakdown.unclassifiedAmount = maxDecimal(statement.statementAmount - knownAmount, 0)
    }

    func recalculate(
        statement: CreditCardStatement,
        plan: CreditCardRepaymentPlan?,
        payments: [CreditCardPaymentRecord],
        debt: CreditCardDebt?,
        today: Date = Date()
    ) {
        let paidAmount = payments
            .filter { $0.isActive && $0.statementID == statement.id }
            .reduce(Decimal(0)) { $0 + $1.amount }
            .roundedMoney(roundingPolicy)

        statement.paidAmount = paidAmount
        statement.remainingAmount = roundingPolicy.round(maxDecimal(statement.statementAmount - paidAmount, 0))
        statement.status = status(
            statementAmount: statement.statementAmount,
            paidAmount: paidAmount,
            minimumPaymentAmount: statement.minimumPaymentAmount,
            dueDate: statement.dueDate,
            today: today
        )
        statement.updatedAt = today

        if let plan {
            plan.paidAmount = paidAmount
            plan.remainingAmount = statement.remainingAmount
            plan.status = planStatus(from: statement.status)
        }

        if let debt {
            switch statement.status {
            case .overdue:
                debt.status = .overdue
            case .paid where statement.remainingAmount == 0:
                debt.status = .paidOff
            default:
                debt.status = statement.paidAmount > 0 ? .partiallyPaid : .active
            }
            debt.updatedAt = today
        }
    }

    func status(
        statementAmount: Decimal,
        paidAmount: Decimal,
        minimumPaymentAmount: Decimal,
        dueDate: Date,
        today: Date
    ) -> CreditCardStatementStatus {
        if paidAmount >= statementAmount {
            return .paid
        }
        if paidAmount == 0 && today <= dueDate {
            return .pending
        }
        if paidAmount > 0 && today <= dueDate {
            return .partiallyPaid
        }
        if today > dueDate && paidAmount >= minimumPaymentAmount {
            return .carriedForward
        }
        if today > dueDate && paidAmount < minimumPaymentAmount {
            return .overdue
        }
        return .pending
    }

    private func planStatus(from statementStatus: CreditCardStatementStatus) -> PlanStatus {
        switch statementStatus {
        case .paid:
            return .paid
        case .partiallyPaid, .carriedForward:
            return .partiallyPaid
        case .overdue:
            return .overdue
        case .pending, .replaced:
            return .pending
        }
    }
}
