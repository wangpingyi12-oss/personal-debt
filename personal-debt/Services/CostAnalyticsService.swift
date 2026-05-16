import Foundation

struct CostAnalyticsService {
    var roundingPolicy: MoneyRoundingPolicy

    init(roundingPolicy: MoneyRoundingPolicy = .standard) {
        self.roundingPolicy = roundingPolicy
    }

    func generate(
        creditCardDebts: [CreditCardDebt],
        creditCardStatements: [CreditCardStatement],
        creditCardBreakdowns: [CreditCardStatementBreakdown],
        loanDebts: [LoanDebt],
        loanPlans: [LoanRepaymentPlan],
        loanOverdues: [LoanOverdueRecord],
        personalLendingDebts: [PersonalLendingDebt],
        personalLendingPlans: [PersonalLendingPlan]
    ) -> CostAnalytics {
        let activeCreditCards = AnalyticsSupport.activeCreditCardDebts(creditCardDebts)
        let activeLoans = AnalyticsSupport.activeLoanDebts(loanDebts)
        let activePersonalLending = AnalyticsSupport.activePersonalLendingDebts(personalLendingDebts)

        let creditCardDebtIDs = Set(activeCreditCards.map(\.id))
        let loanDebtIDs = Set(activeLoans.map(\.id))
        let personalDebtIDs = Set(activePersonalLending.map(\.id))

        let names = AnalyticsSupport.debtNameMaps(
            creditCardDebts: activeCreditCards,
            loanDebts: activeLoans,
            personalLendingDebts: activePersonalLending
        )

        var totalInterest: Decimal = 0
        var totalInstallmentFee: Decimal = 0
        var totalOverdueFee: Decimal = 0
        var totalPenaltyInterest: Decimal = 0
        var totalOtherFee: Decimal = 0
        var creditCardCost: Decimal = 0
        var loanCost: Decimal = 0
        var personalInterest: Decimal = 0
        var loanPaidInterest: Decimal = 0
        var sourceAmounts = CostSourceAmounts.empty
        var costByDebt: [UUID: (debtType: DebtType, name: String, amount: Decimal, sources: Set<AnalyticsCostSource>)] = [:]

        let effectiveStatementIDs = Set(
            AnalyticsSupport.effectiveStatements(
                creditCardStatements,
                debtIDs: creditCardDebtIDs
            ).map(\.id)
        )

        let activeBreakdowns = creditCardBreakdowns.filter {
            $0.isActive && effectiveStatementIDs.contains($0.statementID)
        }
        let statementsByID = Dictionary(uniqueKeysWithValues: creditCardStatements.map { ($0.id, $0) })
        let creditCardConflictCount = activeBreakdowns.filter(\.hasBreakdownConflict).count

        for breakdown in activeBreakdowns {
            guard let statement = statementsByID[breakdown.statementID],
                  creditCardDebtIDs.contains(statement.debtID) else {
                continue
            }

            let source = AnalyticsSupport.breakdownCostSource(breakdown.source)
            let interest = round(breakdown.revolvingInterest + breakdown.installmentInterest)
            let installmentFee = round(breakdown.installmentFee)
            let overdueFee = round(breakdown.overdueFee)
            let penaltyInterest = round(breakdown.penaltyInterest)
            let otherFee = round(breakdown.unclassifiedAmount)
            let cost = round(interest + installmentFee + overdueFee + penaltyInterest + otherFee)

            totalInterest += interest
            totalInstallmentFee += installmentFee
            totalOverdueFee += overdueFee
            totalPenaltyInterest += penaltyInterest
            totalOtherFee += otherFee
            creditCardCost += cost
            sourceAmounts.add(cost, source: source)
            addCost(
                debtID: statement.debtID,
                debtType: .creditCard,
                name: names.creditCards[statement.debtID] ?? "",
                amount: cost,
                source: source,
                costByDebt: &costByDebt
            )
        }

        let loanPlansForActiveDebts = loanPlans.filter { loanDebtIDs.contains($0.debtID) }
        for plan in loanPlansForActiveDebts {
            let interest = round(plan.scheduledInterest)
            totalInterest += interest
            loanCost += interest
            loanPaidInterest += round(plan.paidInterest)
            sourceAmounts.add(interest, source: .scheduledPlan)
            addCost(
                debtID: plan.debtID,
                debtType: .loan,
                name: names.loans[plan.debtID] ?? "",
                amount: interest,
                source: .scheduledPlan,
                costByDebt: &costByDebt
            )
        }

        for overdue in loanOverdues where loanDebtIDs.contains(overdue.debtID) && overdue.status != .waived {
            let source = AnalyticsSupport.loanOverdueCostSource(overdue.source)
            let overdueFee = overdue.generatesOverdueFee ? round(overdue.overdueFee) : 0
            let penaltyInterest = overdue.generatesPenaltyInterest ? round(overdue.penaltyInterest) : 0
            let cost = round(overdueFee + penaltyInterest)

            totalOverdueFee += overdueFee
            totalPenaltyInterest += penaltyInterest
            loanCost += cost
            sourceAmounts.add(cost, source: source)
            addCost(
                debtID: overdue.debtID,
                debtType: .loan,
                name: names.loans[overdue.debtID] ?? "",
                amount: cost,
                source: source,
                costByDebt: &costByDebt
            )
        }

        let personalPlansForActiveDebts = personalLendingPlans.filter { personalDebtIDs.contains($0.debtID) }
        for plan in personalPlansForActiveDebts {
            let interest = round(plan.scheduledInterest)
            totalInterest += interest
            personalInterest += interest
            sourceAmounts.add(interest, source: .scheduledPlan)
            addCost(
                debtID: plan.debtID,
                debtType: .personalLending,
                name: names.personalLending[plan.debtID] ?? "",
                amount: interest,
                source: .scheduledPlan,
                costByDebt: &costByDebt
            )
        }

        let highCostDebts = costByDebt
            .filter { $0.value.amount > 0 }
            .map { debtID, value in
                AnalyticsCostDebtItem(
                    id: debtID,
                    debtType: value.debtType,
                    debtName: value.name,
                    costAmount: round(value.amount),
                    primarySource: primarySource(from: value.sources)
                )
            }
            .sorted {
                if $0.costAmount == $1.costAmount { return $0.debtName < $1.debtName }
                return $0.costAmount > $1.costAmount
            }

        let totalCost = round(totalInterest + totalInstallmentFee + totalOverdueFee + totalPenaltyInterest + totalOtherFee)

        return CostAnalytics(
            totalCostAmount: totalCost,
            totalInterestAmount: round(totalInterest),
            totalInstallmentFeeAmount: round(totalInstallmentFee),
            totalOverdueFeeAmount: round(totalOverdueFee),
            totalPenaltyInterestAmount: round(totalPenaltyInterest),
            otherFeeAmount: round(totalOtherFee),
            creditCardCostAmount: round(creditCardCost),
            loanCostAmount: round(loanCost),
            personalLendingInterestAmount: round(personalInterest),
            loanAppAllocatedPaidInterestAmount: round(loanPaidInterest),
            highCostDebts: highCostDebts,
            sourceAmounts: sourceAmounts,
            creditCardBreakdownConflictCount: creditCardConflictCount
        )
    }

    private func addCost(
        debtID: UUID,
        debtType: DebtType,
        name: String,
        amount: Decimal,
        source: AnalyticsCostSource,
        costByDebt: inout [UUID: (debtType: DebtType, name: String, amount: Decimal, sources: Set<AnalyticsCostSource>)]
    ) {
        let safeAmount = round(amount)
        guard safeAmount > 0 else { return }

        var current = costByDebt[debtID] ?? (debtType: debtType, name: name, amount: 0, sources: [])
        current.amount += safeAmount
        current.sources.insert(source)
        costByDebt[debtID] = current
    }

    private func primarySource(from sources: Set<AnalyticsCostSource>) -> AnalyticsCostSource {
        if sources.isEmpty { return .none }
        if sources.count > 1 { return .mixed }
        return sources.first ?? .none
    }

    private func round(_ value: Decimal) -> Decimal {
        roundingPolicy.round(AnalyticsSupport.nonNegative(value))
    }
}
