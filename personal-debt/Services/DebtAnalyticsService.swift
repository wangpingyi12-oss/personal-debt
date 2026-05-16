import Foundation

struct DebtAnalyticsService {
    var roundingPolicy: MoneyRoundingPolicy
    var calendar: Calendar

    init(
        roundingPolicy: MoneyRoundingPolicy = .standard,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.roundingPolicy = roundingPolicy
        self.calendar = calendar
    }

    func generate(
        creditCardDebts: [CreditCardDebt],
        creditCardStatements: [CreditCardStatement],
        loanDebts: [LoanDebt],
        loanPlans: [LoanRepaymentPlan],
        personalLendingDebts: [PersonalLendingDebt],
        personalLendingPlans: [PersonalLendingPlan],
        period: AnalyticsPeriod
    ) -> DebtAnalytics {
        let activeCreditCards = AnalyticsSupport.activeCreditCardDebts(creditCardDebts)
        let activeLoans = AnalyticsSupport.activeLoanDebts(loanDebts)
        let activePersonalLending = AnalyticsSupport.activePersonalLendingDebts(personalLendingDebts)

        let creditCardDebtIDs = Set(activeCreditCards.map(\.id))
        let loanDebtIDs = Set(activeLoans.map(\.id))
        let personalDebtIDs = Set(activePersonalLending.map(\.id))

        let latestStatements = AnalyticsSupport.latestEffectiveStatementByDebt(
            creditCardStatements,
            debtIDs: creditCardDebtIDs,
            calendar: calendar
        )
        let effectiveStatements = AnalyticsSupport.effectiveStatements(
            creditCardStatements,
            debtIDs: creditCardDebtIDs,
            calendar: calendar
        )

        let creditCardRemaining = round(latestStatements.values.reduce(Decimal(0)) {
            $0 + AnalyticsSupport.nonNegative($1.remainingAmount)
        })

        let loanPlansByDebt = Dictionary(grouping: loanPlans.filter { loanDebtIDs.contains($0.debtID) }, by: \.debtID)
        let loanRemaining = round(loanPlansByDebt.values.flatMap { $0 }.reduce(Decimal(0)) {
            $0 + scheduledRemainingAmount(for: $1)
        })

        let personalPlansByDebt = Dictionary(grouping: personalLendingPlans.filter { personalDebtIDs.contains($0.debtID) }, by: \.debtID)
        let personalRemaining = round(activePersonalLending.reduce(Decimal(0)) { partial, debt in
            if let plans = personalPlansByDebt[debt.id], plans.isEmpty == false {
                return partial + plans.reduce(Decimal(0)) { $0 + AnalyticsSupport.nonNegative($1.remainingAmount) }
            }
            return partial + AnalyticsSupport.nonNegative(debt.remainingAmount)
        })

        let currentMonthCreditCardPlanned = effectiveStatements
            .filter { period.contains($0.dueDate) }
            .reduce(Decimal(0)) { $0 + AnalyticsSupport.nonNegative($1.remainingAmount) }

        let currentMonthLoanPlanned = loanPlansByDebt.values.flatMap { $0 }
            .filter { period.contains($0.dueDate) }
            .reduce(Decimal(0)) { $0 + scheduledRemainingAmount(for: $1) }

        let currentMonthPersonalPlanned = personalPlansByDebt.values.flatMap { $0 }
            .filter { period.contains($0.dueDate) }
            .reduce(Decimal(0)) { $0 + AnalyticsSupport.nonNegative($1.remainingAmount) }

        let totalRemaining = round(creditCardRemaining + loanRemaining + personalRemaining)
        let currentMonthPlanned = round(currentMonthCreditCardPlanned + currentMonthLoanPlanned + currentMonthPersonalPlanned)
        let fixedDebtAmount = round(loanRemaining + personalRemaining)
        let revolvingDebtAmount = creditCardRemaining

        let maxDebt = maxSingleDebt(
            activeCreditCards: activeCreditCards,
            latestStatements: latestStatements,
            activeLoans: activeLoans,
            loanPlansByDebt: loanPlansByDebt,
            activePersonalLending: activePersonalLending,
            personalPlansByDebt: personalPlansByDebt
        )

        let unpaidDebtCount = unpaidCreditCardCount(activeCreditCards, latestStatements: latestStatements)
            + unpaidLoanCount(activeLoans, loanPlansByDebt: loanPlansByDebt)
            + unpaidPersonalLendingCount(activePersonalLending, personalPlansByDebt: personalPlansByDebt)

        let paidOffDebtCount = activeCreditCards.filter { $0.status == .paidOff }.count
            + activeLoans.filter { $0.status == .paidOff }.count
            + activePersonalLending.filter { $0.status == .paidOff }.count

        let totalStatementAmount = round(latestStatements.values.reduce(Decimal(0)) {
            $0 + AnalyticsSupport.nonNegative($1.statementAmount)
        })
        let totalStatementPaidAmount = round(latestStatements.values.reduce(Decimal(0)) {
            $0 + AnalyticsSupport.nonNegative($1.paidAmount)
        })

        return DebtAnalytics(
            totalRemainingAmount: totalRemaining,
            currentMonthPlannedRepaymentAmount: currentMonthPlanned,
            creditCardRemainingAmount: creditCardRemaining,
            loanRemainingAmount: loanRemaining,
            personalLendingRemainingAmount: personalRemaining,
            creditCardShare: AnalyticsSupport.ratio(creditCardRemaining, totalRemaining),
            loanShare: AnalyticsSupport.ratio(loanRemaining, totalRemaining),
            personalLendingShare: AnalyticsSupport.ratio(personalRemaining, totalRemaining),
            fixedDebtAmount: fixedDebtAmount,
            revolvingDebtAmount: revolvingDebtAmount,
            totalDebtCount: activeCreditCards.count + activeLoans.count + activePersonalLending.count,
            unpaidDebtCount: unpaidDebtCount,
            paidOffDebtCount: paidOffDebtCount,
            maxSingleDebt: maxDebt,
            creditCardCurrentStatementPaidAmount: totalStatementPaidAmount,
            creditCardCurrentStatementAmount: totalStatementAmount
        )
    }

    private func scheduledRemainingAmount(for plan: LoanRepaymentPlan) -> Decimal {
        AnalyticsSupport.nonNegative(plan.remainingPrincipal + plan.remainingInterest)
    }

    private func maxSingleDebt(
        activeCreditCards: [CreditCardDebt],
        latestStatements: [UUID: CreditCardStatement],
        activeLoans: [LoanDebt],
        loanPlansByDebt: [UUID: [LoanRepaymentPlan]],
        activePersonalLending: [PersonalLendingDebt],
        personalPlansByDebt: [UUID: [PersonalLendingPlan]]
    ) -> AnalyticsDebtItem? {
        var candidates: [AnalyticsDebtItem] = []

        for debt in activeCreditCards {
            let amount = round(AnalyticsSupport.nonNegative(latestStatements[debt.id]?.remainingAmount ?? 0))
            candidates.append(
                AnalyticsDebtItem(
                    id: debt.id,
                    debtType: .creditCard,
                    name: debt.name,
                    amount: amount,
                    source: latestStatements[debt.id]?.source.rawValue
                )
            )
        }

        for debt in activeLoans {
            let amount = round((loanPlansByDebt[debt.id] ?? []).reduce(Decimal(0)) {
                $0 + scheduledRemainingAmount(for: $1)
            })
            candidates.append(
                AnalyticsDebtItem(
                    id: debt.id,
                    debtType: .loan,
                    name: debt.name,
                    amount: amount,
                    source: "scheduledPlan"
                )
            )
        }

        for debt in activePersonalLending {
            let amount: Decimal
            if let plans = personalPlansByDebt[debt.id], plans.isEmpty == false {
                amount = round(plans.reduce(Decimal(0)) { $0 + AnalyticsSupport.nonNegative($1.remainingAmount) })
            } else {
                amount = round(AnalyticsSupport.nonNegative(debt.remainingAmount))
            }
            candidates.append(
                AnalyticsDebtItem(
                    id: debt.id,
                    debtType: .personalLending,
                    name: debt.name,
                    amount: amount,
                    source: personalPlansByDebt[debt.id]?.isEmpty == false ? "scheduledPlan" : "debt"
                )
            )
        }

        return candidates
            .filter { $0.amount > 0 }
            .sorted {
                if $0.amount == $1.amount { return $0.name < $1.name }
                return $0.amount > $1.amount
            }
            .first
    }

    private func unpaidCreditCardCount(
        _ debts: [CreditCardDebt],
        latestStatements: [UUID: CreditCardStatement]
    ) -> Int {
        debts.filter { debt in
            let amount = AnalyticsSupport.nonNegative(latestStatements[debt.id]?.remainingAmount ?? 0)
            return amount > 0 || debt.status != .paidOff
        }.count
    }

    private func unpaidLoanCount(
        _ debts: [LoanDebt],
        loanPlansByDebt: [UUID: [LoanRepaymentPlan]]
    ) -> Int {
        debts.filter { debt in
            let amount = (loanPlansByDebt[debt.id] ?? []).reduce(Decimal(0)) {
                $0 + scheduledRemainingAmount(for: $1)
            }
            return amount > 0 || debt.status != .paidOff
        }.count
    }

    private func unpaidPersonalLendingCount(
        _ debts: [PersonalLendingDebt],
        personalPlansByDebt: [UUID: [PersonalLendingPlan]]
    ) -> Int {
        debts.filter { debt in
            if let plans = personalPlansByDebt[debt.id], plans.isEmpty == false {
                let amount = plans.reduce(Decimal(0)) { $0 + AnalyticsSupport.nonNegative($1.remainingAmount) }
                return amount > 0 || debt.status != .paidOff
            }
            return AnalyticsSupport.nonNegative(debt.remainingAmount) > 0 || debt.status != .paidOff
        }.count
    }

    private func round(_ value: Decimal) -> Decimal {
        roundingPolicy.round(AnalyticsSupport.nonNegative(value))
    }
}
