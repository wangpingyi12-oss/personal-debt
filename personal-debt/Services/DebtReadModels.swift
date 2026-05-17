import Foundation

struct DebtListItem: Identifiable, Equatable {
    var id: UUID
    var debtType: DebtType
    var name: String
    var status: DebtStatus
    var remainingAmount: Decimal
    var nextDueDate: Date?
    var nextDueAmount: Decimal
    var overdueAmount: Decimal
    var overdueDays: Int
    var progress: Decimal
    var source: String
}

struct DebtDashboardReadModel: Equatable {
    var summary: AnalyticsSummary
    var debts: [DebtListItem]
    var overdueItems: [AnalyticsOverdueItem]
}

struct CreditCardDetailReadModel {
    var debt: CreditCardDebt
    var currentStatement: CreditCardStatement?
    var statements: [CreditCardStatement]
    var payments: [CreditCardPaymentRecord]
    var overdues: [CreditCardOverdueRecord]
    var rule: CreditCardCalculationRule?
}

struct LoanDetailReadModel {
    var debt: LoanDebt
    var plans: [LoanRepaymentPlan]
    var payments: [LoanPaymentRecord]
    var allocationDetails: [LoanPaymentAllocationDetail]
    var overdues: [LoanOverdueRecord]
    var rule: LoanCalculationRule
}

struct PersonalLendingDetailReadModel {
    var debt: PersonalLendingDebt
    var plans: [PersonalLendingPlan]
    var payments: [PersonalLendingPaymentRecord]
    var allocationDetails: [PersonalLendingAllocationDetail]
    var overdues: [PersonalLendingOverdueRecord]
}

struct DebtReadService {
    var roundingPolicy: MoneyRoundingPolicy
    var datePolicy: DateCalculationPolicy

    init(
        roundingPolicy: MoneyRoundingPolicy = .standard,
        datePolicy: DateCalculationPolicy = .standard
    ) {
        self.roundingPolicy = roundingPolicy
        self.datePolicy = datePolicy
    }

    func debtListItems(
        creditCards: [CreditCardDebt],
        statements: [CreditCardStatement],
        loans: [LoanDebt],
        loanPlans: [LoanRepaymentPlan],
        personalDebts: [PersonalLendingDebt],
        personalPlans: [PersonalLendingPlan],
        personalOverdues: [PersonalLendingOverdueRecord],
        today: Date = Date()
    ) -> [DebtListItem] {
        let activeCards = AnalyticsSupport.activeCreditCardDebts(creditCards)
        let activeLoans = AnalyticsSupport.activeLoanDebts(loans)
        let activePersonal = AnalyticsSupport.activePersonalLendingDebts(personalDebts)

        let latestStatements = AnalyticsSupport.latestEffectiveStatementByDebt(
            statements,
            debtIDs: Set(activeCards.map(\.id)),
            calendar: datePolicy.calendar
        )
        var items: [DebtListItem] = []

        items.append(contentsOf: activeCards.map { debt in
            let statement = latestStatements[debt.id]
            let remaining = round(statement?.remainingAmount ?? 0)
            let total = round(statement?.statementAmount ?? remaining)
            let overdueDays = statement.map { overdueDaysIfNeeded(dueDate: $0.dueDate, remainingAmount: $0.remainingAmount, today: today) } ?? 0
            return DebtListItem(
                id: debt.id,
                debtType: .creditCard,
                name: debt.name,
                status: debt.status,
                remainingAmount: remaining,
                nextDueDate: statement?.dueDate,
                nextDueAmount: remaining,
                overdueAmount: overdueDays > 0 ? remaining : 0,
                overdueDays: overdueDays,
                progress: progress(paid: statement?.paidAmount ?? 0, total: total),
                source: statement?.source.rawValue ?? "none"
            )
        })

        let loanPlansByDebt = Dictionary(grouping: loanPlans, by: \.debtID)
        items.append(contentsOf: activeLoans.map { debt in
            let plans = (loanPlansByDebt[debt.id] ?? []).sorted(by: loanPlanSort)
            let remaining = round(plans.reduce(Decimal(0)) { $0 + $1.remainingPrincipal + $1.remainingInterest })
            let scheduled = round(plans.reduce(Decimal(0)) { $0 + $1.scheduledPrincipal + $1.scheduledInterest })
            let next = plans.first { $0.remainingPrincipal + $0.remainingInterest > 0 }
            let overduePlans = plans.filter { $0.dueDate < today && $0.remainingPrincipal + $0.remainingInterest > 0 }
            return DebtListItem(
                id: debt.id,
                debtType: .loan,
                name: debt.name,
                status: debt.status,
                remainingAmount: remaining,
                nextDueDate: next?.dueDate,
                nextDueAmount: round((next?.remainingPrincipal ?? 0) + (next?.remainingInterest ?? 0)),
                overdueAmount: round(overduePlans.reduce(Decimal(0)) { $0 + $1.remainingPrincipal + $1.remainingInterest }),
                overdueDays: overduePlans.map { overdueDaysIfNeeded(dueDate: $0.dueDate, remainingAmount: $0.remainingPrincipal + $0.remainingInterest, today: today) }.max() ?? 0,
                progress: progress(paid: scheduled - remaining, total: scheduled),
                source: "repaymentPlan"
            )
        })

        let personalPlansByDebt = Dictionary(grouping: personalPlans, by: \.debtID)
        let activePersonalOverdues = personalOverdues.filter { $0.status == .active }
        items.append(contentsOf: activePersonal.map { debt in
            let plans = (personalPlansByDebt[debt.id] ?? []).sorted(by: personalPlanSort)
            let remaining = plans.isEmpty ? round(debt.remainingAmount) : round(plans.reduce(Decimal(0)) { $0 + $1.remainingAmount })
            let total = plans.isEmpty ? debt.totalPayableAmount : plans.reduce(Decimal(0)) { $0 + $1.scheduledTotalAmount }
            let next = plans.first { $0.remainingAmount > 0 }
            let overdueAmount = round(activePersonalOverdues.filter { $0.debtID == debt.id }.reduce(Decimal(0)) { $0 + $1.overdueAmount })
            let debtLevelOverdueDays = debt.agreedEndDate.map {
                overdueDaysIfNeeded(dueDate: $0, remainingAmount: debt.remainingAmount, today: today)
            } ?? 0
            let planOverdueDays = plans.map {
                overdueDaysIfNeeded(dueDate: $0.dueDate, remainingAmount: $0.remainingAmount, today: today)
            }.max() ?? 0
            return DebtListItem(
                id: debt.id,
                debtType: .personalLending,
                name: debt.name,
                status: debt.status,
                remainingAmount: remaining,
                nextDueDate: next?.dueDate ?? debt.agreedEndDate,
                nextDueAmount: round(next?.remainingAmount ?? debt.remainingAmount),
                overdueAmount: overdueAmount > 0 ? overdueAmount : (max(debtLevelOverdueDays, planOverdueDays) > 0 ? remaining : 0),
                overdueDays: max(debtLevelOverdueDays, planOverdueDays),
                progress: progress(paid: total - remaining, total: total),
                source: plans.isEmpty ? "debtBalance" : "personalLendingPlan"
            )
        })

        return items.sorted {
            if $0.status == $1.status {
                if $0.nextDueDate == $1.nextDueDate { return $0.name < $1.name }
                return ($0.nextDueDate ?? .distantFuture) < ($1.nextDueDate ?? .distantFuture)
            }
            return statusRank($0.status) > statusRank($1.status)
        }
    }

    func creditCardDetail(
        debt: CreditCardDebt,
        statements: [CreditCardStatement],
        payments: [CreditCardPaymentRecord],
        overdues: [CreditCardOverdueRecord],
        rules: [CreditCardCalculationRule]
    ) -> CreditCardDetailReadModel {
        let debtStatements = statements
            .filter { $0.debtID == debt.id && $0.isActive && $0.status != .replaced }
            .sorted { $0.billingDate > $1.billingDate }
        return CreditCardDetailReadModel(
            debt: debt,
            currentStatement: debtStatements.first,
            statements: debtStatements,
            payments: payments.filter { $0.debtID == debt.id && $0.isActive }.sorted { $0.paymentDate > $1.paymentDate },
            overdues: overdues.filter { $0.debtID == debt.id && $0.status != .voided }.sorted { $0.startDate > $1.startDate },
            rule: rules.sorted { $0.debtID.uuidString < $1.debtID.uuidString }.first { $0.debtID == debt.id }
        )
    }

    func loanDetail(
        debt: LoanDebt,
        plans: [LoanRepaymentPlan],
        payments: [LoanPaymentRecord],
        allocationDetails: [LoanPaymentAllocationDetail],
        overdues: [LoanOverdueRecord],
        rules: [LoanCalculationRule]
    ) -> LoanDetailReadModel {
        return LoanDetailReadModel(
            debt: debt,
            plans: plans.filter { $0.debtID == debt.id }.sorted(by: loanPlanSort),
            payments: payments.filter { $0.debtID == debt.id }.sorted { $0.paymentDate > $1.paymentDate },
            allocationDetails: allocationDetails.filter { $0.debtID == debt.id },
            overdues: overdues.filter { $0.debtID == debt.id && $0.status != .voided }.sorted { $0.overdueStartDate > $1.overdueStartDate },
            rule: effectiveLoanRule(for: debt, rules: rules)
        )
    }

    func personalLendingDetail(
        debt: PersonalLendingDebt,
        plans: [PersonalLendingPlan],
        payments: [PersonalLendingPaymentRecord],
        allocationDetails: [PersonalLendingAllocationDetail],
        overdues: [PersonalLendingOverdueRecord]
    ) -> PersonalLendingDetailReadModel {
        PersonalLendingDetailReadModel(
            debt: debt,
            plans: plans.filter { $0.debtID == debt.id }.sorted(by: personalPlanSort),
            payments: payments.filter { $0.debtID == debt.id }.sorted { $0.paymentDate > $1.paymentDate },
            allocationDetails: allocationDetails.filter { $0.debtID == debt.id },
            overdues: overdues.filter { $0.debtID == debt.id && $0.status != .voided }.sorted { $0.overdueStartDate > $1.overdueStartDate }
        )
    }

    private func progress(paid: Decimal, total: Decimal) -> Decimal {
        guard total > 0 else { return 0 }
        return minDecimal(round(maxDecimal(paid, 0) / total), Decimal(1))
    }

    private func overdueDaysIfNeeded(dueDate: Date, remainingAmount: Decimal, today: Date) -> Int {
        guard remainingAmount > 0, datePolicy.startOfDay(today) > datePolicy.startOfDay(dueDate) else { return 0 }
        return datePolicy.daysBetween(dueDate, today)
    }

    private func round(_ value: Decimal) -> Decimal {
        roundingPolicy.round(maxDecimal(value, 0))
    }

    private func loanPlanSort(_ lhs: LoanRepaymentPlan, _ rhs: LoanRepaymentPlan) -> Bool {
        if lhs.dueDate == rhs.dueDate { return lhs.periodIndex < rhs.periodIndex }
        return lhs.dueDate < rhs.dueDate
    }

    private func personalPlanSort(_ lhs: PersonalLendingPlan, _ rhs: PersonalLendingPlan) -> Bool {
        if lhs.dueDate == rhs.dueDate { return lhs.periodIndex < rhs.periodIndex }
        return lhs.dueDate < rhs.dueDate
    }

    private func statusRank(_ status: DebtStatus) -> Int {
        switch status {
        case .overdue:
            return 4
        case .partiallyPaid:
            return 3
        case .active:
            return 2
        case .paidOff:
            return 1
        case .archived:
            return 0
        }
    }

    private func effectiveLoanRule(for debt: LoanDebt, rules: [LoanCalculationRule]) -> LoanCalculationRule {
        let orderedRules = rules.sorted {
            if $0.updatedAt == $1.updatedAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.updatedAt > $1.updatedAt
        }
        if let debtRule = orderedRules.first(where: { $0.debtID == debt.id }) {
            return debtRule
        }
        if let globalDefault = orderedRules.first(where: { $0.debtID == nil }) {
            return globalDefault
        }
        return LoanCalculationRule.builtInDefault()
    }
}
