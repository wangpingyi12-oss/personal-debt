import Foundation

struct OverdueAnalyticsService {
    var roundingPolicy: MoneyRoundingPolicy
    var datePolicy: DateCalculationPolicy

    init(
        roundingPolicy: MoneyRoundingPolicy = .standard,
        datePolicy: DateCalculationPolicy = .standard
    ) {
        self.roundingPolicy = roundingPolicy
        self.datePolicy = datePolicy
    }

    func generate(
        creditCardDebts: [CreditCardDebt],
        creditCardStatements: [CreditCardStatement],
        creditCardBreakdowns: [CreditCardStatementBreakdown],
        loanDebts: [LoanDebt],
        loanPlans: [LoanRepaymentPlan],
        loanOverdues: [LoanOverdueRecord],
        personalLendingDebts: [PersonalLendingDebt],
        personalLendingPlans: [PersonalLendingPlan],
        today: Date
    ) -> OverdueAnalytics {
        let activeCreditCards = AnalyticsSupport.activeCreditCardDebts(creditCardDebts)
        let activeLoans = AnalyticsSupport.activeLoanDebts(loanDebts)
        let activePersonalLending = AnalyticsSupport.activePersonalLendingDebts(personalLendingDebts)

        let names = AnalyticsSupport.debtNameMaps(
            creditCardDebts: activeCreditCards,
            loanDebts: activeLoans,
            personalLendingDebts: activePersonalLending
        )

        let creditCardItems = creditCardOverdueItems(
            statements: creditCardStatements,
            breakdowns: creditCardBreakdowns,
            debtIDs: Set(activeCreditCards.map(\.id)),
            names: names.creditCards,
            today: today
        )
        let loanItems = loanOverdueItems(
            plans: loanPlans,
            overdues: loanOverdues,
            debtIDs: Set(activeLoans.map(\.id)),
            names: names.loans,
            today: today
        )
        let personalItems = personalLendingOverdueItems(
            debts: activePersonalLending,
            plans: personalLendingPlans,
            names: names.personalLending,
            today: today
        )

        let items = creditCardItems + loanItems + personalItems
        let overdueDebtCount = Set(items.map(\.debtID)).count
        let totalOverdueAmount = round(items.reduce(Decimal(0)) { $0 + $1.overdueAmount })
        let feeAmount = round(items.reduce(Decimal(0)) { $0 + $1.overdueFeeAmount })
        let penaltyAmount = round(items.reduce(Decimal(0)) { $0 + $1.penaltyInterestAmount })

        let buckets = bucketAmounts(for: items)
        let highestRiskItem = items.sorted {
            if $0.overdueDays == $1.overdueDays {
                if $0.overdueAmount == $1.overdueAmount { return $0.debtName < $1.debtName }
                return $0.overdueAmount > $1.overdueAmount
            }
            return $0.overdueDays > $1.overdueDays
        }.first

        return OverdueAnalytics(
            currentOverdueDebtCount: overdueDebtCount,
            currentOverduePeriodCount: items.count,
            currentOverdueTotalAmount: totalOverdueAmount,
            creditCardMinimumPaymentGap: round(creditCardItems.reduce(Decimal(0)) { $0 + $1.minimumPaymentGap }),
            creditCardOverdueStatementRemainingAmount: round(creditCardItems.reduce(Decimal(0)) { $0 + $1.overdueAmount }),
            loanOverdueAmount: round(loanItems.reduce(Decimal(0)) { $0 + $1.overdueAmount }),
            personalLendingPastDueAmount: round(personalItems.reduce(Decimal(0)) { $0 + $1.overdueAmount }),
            overdueAmount1To30Days: buckets.oneToThirty,
            overdueAmount31To90Days: buckets.thirtyOneToNinety,
            overdueAmountOver90Days: buckets.overNinety,
            overdueFeeTotalAmount: feeAmount,
            penaltyInterestTotalAmount: penaltyAmount,
            highestRiskItem: highestRiskItem,
            riskLevel: riskLevel(for: items),
            items: items
        )
    }

    private func creditCardOverdueItems(
        statements: [CreditCardStatement],
        breakdowns: [CreditCardStatementBreakdown],
        debtIDs: Set<UUID>,
        names: [UUID: String],
        today: Date
    ) -> [AnalyticsOverdueItem] {
        let effectiveStatements = AnalyticsSupport.effectiveStatements(statements, debtIDs: debtIDs, calendar: datePolicy.calendar)
        let breakdownsByStatement = Dictionary(grouping: breakdowns.filter(\.isActive), by: \.statementID)

        return effectiveStatements.compactMap { statement in
            guard isPastDue(statement.dueDate, today: today),
                  statement.paidAmount < statement.minimumPaymentAmount,
                  statement.remainingAmount > 0 else {
                return nil
            }

            let statementBreakdowns = breakdownsByStatement[statement.id] ?? []
            let overdueFee = round(statementBreakdowns.reduce(Decimal(0)) { $0 + AnalyticsSupport.nonNegative($1.overdueFee) })
            let penaltyInterest = round(statementBreakdowns.reduce(Decimal(0)) { $0 + AnalyticsSupport.nonNegative($1.penaltyInterest) })

            return AnalyticsOverdueItem(
                id: statement.id,
                debtID: statement.debtID,
                debtType: .creditCard,
                debtName: names[statement.debtID] ?? "",
                dueDate: statement.dueDate,
                overdueDays: overdueDays(since: statement.dueDate, today: today),
                overdueAmount: round(statement.remainingAmount),
                minimumPaymentGap: round(statement.minimumPaymentAmount - statement.paidAmount),
                overdueFeeAmount: overdueFee,
                penaltyInterestAmount: penaltyInterest
            )
        }
    }

    private func loanOverdueItems(
        plans: [LoanRepaymentPlan],
        overdues: [LoanOverdueRecord],
        debtIDs: Set<UUID>,
        names: [UUID: String],
        today: Date
    ) -> [AnalyticsOverdueItem] {
        let activeOverduesByPlan = Dictionary(
            grouping: overdues.filter { $0.status == .active && debtIDs.contains($0.debtID) },
            by: \.planID
        )

        return plans.compactMap { plan in
            guard debtIDs.contains(plan.debtID),
                  isPastDue(plan.dueDate, today: today) else {
                return nil
            }

            let overdueAmount = scheduledRemainingAmount(for: plan)
            guard overdueAmount > 0 else { return nil }

            let records = activeOverduesByPlan[plan.id] ?? []
            let overdueFee = round(records.reduce(Decimal(0)) {
                $0 + ($1.generatesOverdueFee ? AnalyticsSupport.nonNegative($1.overdueFee) : 0)
            })
            let penaltyInterest = round(records.reduce(Decimal(0)) {
                $0 + ($1.generatesPenaltyInterest ? AnalyticsSupport.nonNegative($1.penaltyInterest) : 0)
            })

            return AnalyticsOverdueItem(
                id: plan.id,
                debtID: plan.debtID,
                debtType: .loan,
                debtName: names[plan.debtID] ?? "",
                dueDate: plan.dueDate,
                overdueDays: overdueDays(since: plan.dueDate, today: today),
                overdueAmount: overdueAmount,
                minimumPaymentGap: 0,
                overdueFeeAmount: overdueFee,
                penaltyInterestAmount: penaltyInterest
            )
        }
    }

    private func personalLendingOverdueItems(
        debts: [PersonalLendingDebt],
        plans: [PersonalLendingPlan],
        names: [UUID: String],
        today: Date
    ) -> [AnalyticsOverdueItem] {
        let plansByDebt = Dictionary(grouping: plans, by: \.debtID)
        var items: [AnalyticsOverdueItem] = []

        for debt in debts {
            if let debtPlans = plansByDebt[debt.id], debtPlans.isEmpty == false {
                for plan in debtPlans where isPastDue(plan.dueDate, today: today) && plan.remainingAmount > 0 {
                    items.append(
                        AnalyticsOverdueItem(
                            id: plan.id,
                            debtID: debt.id,
                            debtType: .personalLending,
                            debtName: names[debt.id] ?? "",
                            dueDate: plan.dueDate,
                            overdueDays: overdueDays(since: plan.dueDate, today: today),
                            overdueAmount: round(plan.remainingAmount),
                            minimumPaymentGap: 0,
                            overdueFeeAmount: 0,
                            penaltyInterestAmount: 0
                        )
                    )
                }
                continue
            }

            guard let agreedEndDate = debt.agreedEndDate,
                  isPastDue(agreedEndDate, today: today),
                  debt.remainingAmount > 0 else {
                continue
            }

            items.append(
                AnalyticsOverdueItem(
                    id: debt.id,
                    debtID: debt.id,
                    debtType: .personalLending,
                    debtName: names[debt.id] ?? "",
                    dueDate: agreedEndDate,
                    overdueDays: overdueDays(since: agreedEndDate, today: today),
                    overdueAmount: round(debt.remainingAmount),
                    minimumPaymentGap: 0,
                    overdueFeeAmount: 0,
                    penaltyInterestAmount: 0
                )
            )
        }

        return items
    }

    private func bucketAmounts(for items: [AnalyticsOverdueItem]) -> (oneToThirty: Decimal, thirtyOneToNinety: Decimal, overNinety: Decimal) {
        var oneToThirty: Decimal = 0
        var thirtyOneToNinety: Decimal = 0
        var overNinety: Decimal = 0

        for item in items {
            switch item.overdueDays {
            case 1...30:
                oneToThirty += item.overdueAmount
            case 31...90:
                thirtyOneToNinety += item.overdueAmount
            case 91...:
                overNinety += item.overdueAmount
            default:
                break
            }
        }

        return (round(oneToThirty), round(thirtyOneToNinety), round(overNinety))
    }

    private func riskLevel(for items: [AnalyticsOverdueItem]) -> AnalyticsOverdueRiskLevel {
        let maxDays = items.map(\.overdueDays).max() ?? 0
        switch maxDays {
        case 91...:
            return .critical
        case 31...90:
            return .high
        case 1...30:
            return .medium
        default:
            return .none
        }
    }

    private func scheduledRemainingAmount(for plan: LoanRepaymentPlan) -> Decimal {
        round(plan.remainingPrincipal + plan.remainingInterest)
    }

    private func isPastDue(_ dueDate: Date, today: Date) -> Bool {
        datePolicy.startOfDay(today) > datePolicy.startOfDay(dueDate)
    }

    private func overdueDays(since dueDate: Date, today: Date) -> Int {
        datePolicy.daysBetween(dueDate, today)
    }

    private func round(_ value: Decimal) -> Decimal {
        roundingPolicy.round(AnalyticsSupport.nonNegative(value))
    }
}
