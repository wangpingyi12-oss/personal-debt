import Foundation
import SwiftData

@MainActor
final class StrategySimulationService {
    private let modelContext: ModelContext?
    private let engine: StrategySimulationEngine
    private let roundingPolicy: MoneyRoundingPolicy
    private let datePolicy: DateCalculationPolicy

    init(
        modelContext: ModelContext? = nil,
        engine: StrategySimulationEngine? = nil,
        roundingPolicy: MoneyRoundingPolicy? = nil,
        datePolicy: DateCalculationPolicy? = nil
    ) {
        self.modelContext = modelContext
        self.roundingPolicy = roundingPolicy ?? .standard
        self.datePolicy = datePolicy ?? .standard
        self.engine = engine ?? StrategySimulationEngine(
            roundingPolicy: self.roundingPolicy,
            datePolicy: self.datePolicy
        )
    }

    func generateComparison(request: StrategySimulationRequest) throws -> StrategyComparisonResult {
        guard let modelContext else {
            throw DebtServiceError.validationFailed("A model context is required to generate a strategy comparison from stored debts.")
        }

        let snapshots = try makeDebtSnapshots(request: request)
        let result = try engine.generateComparison(request: request, debts: snapshots)
        try save(result, in: modelContext)
        return result
    }

    func generateComparison(
        request: StrategySimulationRequest,
        debtSnapshots: [StrategyDebtSnapshot],
        saveResult: Bool = false
    ) throws -> StrategyComparisonResult {
        let result = try engine.generateComparison(request: request, debts: debtSnapshots)
        if saveResult, let modelContext {
            try save(result, in: modelContext)
        }
        return result
    }

    func makeDebtSnapshots(request: StrategySimulationRequest) throws -> [StrategyDebtSnapshot] {
        guard let modelContext else {
            throw DebtServiceError.validationFailed("A model context is required to read strategy debt snapshots.")
        }

        let creditCardDebts = try modelContext.fetch(FetchDescriptor<CreditCardDebt>())
        let creditCardStatements = try modelContext.fetch(FetchDescriptor<CreditCardStatement>())
        let creditCardRules = try modelContext.fetch(FetchDescriptor<CreditCardCalculationRule>())
        let loanDebts = try modelContext.fetch(FetchDescriptor<LoanDebt>())
        let loanPlans = try modelContext.fetch(FetchDescriptor<LoanRepaymentPlan>())
        let loanRules = try modelContext.fetch(FetchDescriptor<LoanCalculationRule>())
        let personalLendingDebts = try modelContext.fetch(FetchDescriptor<PersonalLendingDebt>())
        let personalLendingPlans = try modelContext.fetch(FetchDescriptor<PersonalLendingPlan>())

        return makeDebtSnapshots(
            request: request,
            creditCardDebts: creditCardDebts,
            creditCardStatements: creditCardStatements,
            creditCardRules: creditCardRules,
            loanDebts: loanDebts,
            loanPlans: loanPlans,
            loanRules: loanRules,
            personalLendingDebts: personalLendingDebts,
            personalLendingPlans: personalLendingPlans
        )
    }

    func makeDebtSnapshots(
        request: StrategySimulationRequest,
        creditCardDebts: [CreditCardDebt],
        creditCardStatements: [CreditCardStatement],
        creditCardRules: [CreditCardCalculationRule],
        loanDebts: [LoanDebt],
        loanPlans: [LoanRepaymentPlan],
        loanRules: [LoanCalculationRule],
        personalLendingDebts: [PersonalLendingDebt],
        personalLendingPlans: [PersonalLendingPlan]
    ) -> [StrategyDebtSnapshot] {
        let strategyDate = datePolicy.startOfDay(request.strategyDate)
        let activeCardDebts = AnalyticsSupport.activeCreditCardDebts(creditCardDebts)
        let activeLoanDebts = AnalyticsSupport.activeLoanDebts(loanDebts)
        let activePersonalDebts = AnalyticsSupport.activePersonalLendingDebts(personalLendingDebts)

        let cardSnapshots = makeCreditCardSnapshots(
            debts: activeCardDebts,
            statements: creditCardStatements,
            rules: creditCardRules,
            strategyDate: strategyDate
        )
        let loanSnapshots = makeLoanSnapshots(
            debts: activeLoanDebts,
            plans: loanPlans,
            rules: loanRules,
            strategyDate: strategyDate
        )
        let personalSnapshots = makePersonalLendingSnapshots(
            debts: activePersonalDebts,
            plans: personalLendingPlans,
            strategyDate: strategyDate
        )

        return cardSnapshots + loanSnapshots + personalSnapshots
    }

    private func save(_ result: StrategyComparisonResult, in modelContext: ModelContext) throws {
        modelContext.insert(result.comparisonBatch)
        result.riskEvents.forEach(modelContext.insert)

        for output in result.simulations {
            modelContext.insert(output.simulation)
            output.monthSnapshots.forEach(modelContext.insert)
            output.allocations.forEach(modelContext.insert)
            output.costEvents.forEach(modelContext.insert)
            output.riskEvents.forEach(modelContext.insert)
        }

        try modelContext.save()
    }

    private func makeCreditCardSnapshots(
        debts: [CreditCardDebt],
        statements: [CreditCardStatement],
        rules: [CreditCardCalculationRule],
        strategyDate: Date
    ) -> [StrategyDebtSnapshot] {
        let debtIDs = Set(debts.map(\.id))
        let latestStatements = AnalyticsSupport.latestEffectiveStatementByDebt(
            statements,
            debtIDs: debtIDs,
            calendar: datePolicy.calendar
        )
        let rulesByDebtID = Dictionary(uniqueKeysWithValues: rules.map { ($0.debtID, $0) })

        return debts.compactMap { debt in
            guard let statement = latestStatements[debt.id] else { return nil }
            let remaining = roundingPolicy.round(maxDecimal(statement.remainingAmount, 0))
            guard remaining > 0 else { return nil }

            let rule = rulesByDebtID[debt.id] ?? CreditCardCalculationRule(debtID: debt.id)
            let minimumGap = roundingPolicy.round(maxDecimal(statement.minimumPaymentAmount - statement.paidAmount, 0))
            let isOverdue = statement.status == .overdue || statement.dueDate < strategyDate
            let overdueDays = isOverdue ? datePolicy.daysBetween(statement.dueDate, strategyDate) : 0
            let dataSource = statement.source.rawValue
            let isFallback = statement.source == .fallback

            return StrategyDebtSnapshot(
                id: debt.id,
                debtType: .creditCard,
                name: debt.name,
                remainingAmount: remaining,
                minimumPaymentAmount: minDecimal(minimumGap, remaining),
                costRate: roundingPolicy.round(rule.revolvingDailyRate * Decimal(30)),
                riskWeight: isOverdue ? 2 : 1,
                dueDate: statement.dueDate,
                dataSource: dataSource,
                isFallbackData: isFallback,
                isOverdue: isOverdue,
                overdueDays: overdueDays,
                userRiskNotes: isFallback ? ["\(debt.name) uses a fallback credit card statement in the strategy simulation."] : [],
                revolvingInterestEnabled: rule.revolvingInterestEnabled,
                revolvingDailyRate: rule.revolvingDailyRate,
                overdueFeeRate: rule.overdueFeeRate,
                minimumOverdueFee: rule.minimumOverdueFee,
                fixedOverdueFee: rule.fixedOverdueFee,
                penaltyDailyRate: rule.penaltyDailyRate,
                penaltyBaseUsesStatementAmount: rule.penaltyBaseType == .unpaidPrincipal
            )
        }
    }

    private func makeLoanSnapshots(
        debts: [LoanDebt],
        plans: [LoanRepaymentPlan],
        rules: [LoanCalculationRule],
        strategyDate: Date
    ) -> [StrategyDebtSnapshot] {
        debts.compactMap { debt in
            guard debt.status != .paidOff else { return nil }
            let effectiveRule = effectiveLoanRule(for: debt, rules: rules)
            let debtPlans = plans
                .filter { $0.debtID == debt.id && $0.status != .paid && $0.remainingTotalAmount > 0 }
                .sorted {
                    if $0.dueDate == $1.dueDate { return $0.periodIndex < $1.periodIndex }
                    return $0.dueDate < $1.dueDate
                }

            var planSnapshots = debtPlans.map {
                let isOverdue = $0.status == .overdue || $0.dueDate < strategyDate
                return StrategyPlanSnapshot(
                    id: $0.id,
                    periodIndex: $0.periodIndex,
                    dueDate: $0.dueDate,
                    remainingAmount: $0.remainingTotalAmount,
                    remainingPrincipal: $0.remainingPrincipal,
                    remainingInterest: $0.remainingInterest,
                    dataSource: "repaymentPlan",
                    isOverdue: isOverdue,
                    overdueDays: isOverdue ? max($0.overdueDays, datePolicy.daysBetween($0.dueDate, strategyDate)) : 0
                )
            }
            var userRiskNotes: [String] = []
            var isFallback = false

            if planSnapshots.isEmpty && debt.outstandingPrincipal > 0 {
                isFallback = true
                userRiskNotes.append("\(debt.name) has no usable repayment plan, so outstanding principal is used as fallback simulation data.")
                planSnapshots = [
                    StrategyPlanSnapshot(
                        periodIndex: 1,
                        dueDate: debt.endDate,
                        remainingAmount: debt.outstandingPrincipal,
                        remainingPrincipal: debt.outstandingPrincipal,
                        remainingInterest: 0,
                        dataSource: "fallbackOutstandingPrincipal",
                        isOverdue: debt.endDate < strategyDate,
                        overdueDays: debt.endDate < strategyDate ? datePolicy.daysBetween(debt.endDate, strategyDate) : 0
                    )
                ]
            }

            let remaining = roundingPolicy.round(planSnapshots.reduce(Decimal(0)) { $0 + maxDecimal($1.remainingAmount, 0) })
            guard remaining > 0 else { return nil }
            let isOverdue = planSnapshots.contains { $0.isOverdue }
            let firstDueDate = planSnapshots.map(\.dueDate).min()
            let dueThisMonth = planSnapshots
                .filter { $0.dueDate <= endOfMonth(containing: strategyDate) }
                .reduce(Decimal(0)) { $0 + $1.remainingAmount }

            return StrategyDebtSnapshot(
                id: debt.id,
                debtType: .loan,
                name: debt.name,
                remainingAmount: remaining,
                minimumPaymentAmount: dueThisMonth,
                costRate: loanMonthlyCostRate(debt: debt, rule: effectiveRule),
                riskWeight: isOverdue ? 2 : 1,
                dueDate: firstDueDate,
                dataSource: isFallback ? "fallbackOutstandingPrincipal" : "repaymentPlan",
                isFallbackData: isFallback,
                isOverdue: isOverdue,
                overdueDays: planSnapshots.map(\.overdueDays).max() ?? 0,
                plans: planSnapshots,
                userRiskNotes: userRiskNotes,
                annualInterestRate: debt.annualInterestRate,
                loanPenaltyRateMultiplier: effectiveRule.penaltyRateMultiplier,
                fixedPenaltyDailyRate: effectiveRule.fixedPenaltyDailyRate,
                loanOverdueFeeMode: effectiveRule.overdueFeeMode,
                loanFixedOverdueFee: effectiveRule.fixedOverdueFee,
                loanOverdueFeeRate: effectiveRule.overdueFeeRate,
                loanOverdueBaseType: effectiveRule.overdueBaseType
            )
        }
    }

    private func makePersonalLendingSnapshots(
        debts: [PersonalLendingDebt],
        plans: [PersonalLendingPlan],
        strategyDate: Date
    ) -> [StrategyDebtSnapshot] {
        debts.compactMap { debt in
            guard debt.status != .paidOff else { return nil }
            var userRiskNotes: [String] = []
            let debtPlans = plans
                .filter { $0.debtID == debt.id && $0.status != .paid && $0.remainingAmount > 0 }
                .sorted {
                    if $0.dueDate == $1.dueDate { return $0.periodIndex < $1.periodIndex }
                    return $0.dueDate < $1.dueDate
                }

            let planSnapshots = debtPlans.map {
                let isOverdue = $0.dueDate < strategyDate
                return StrategyPlanSnapshot(
                    id: $0.id,
                    periodIndex: $0.periodIndex,
                    dueDate: $0.dueDate,
                    remainingAmount: $0.remainingAmount,
                    remainingPrincipal: $0.scheduledPrincipal,
                    remainingInterest: $0.scheduledInterest,
                    dataSource: "personalLendingPlan",
                    isOverdue: isOverdue,
                    overdueDays: isOverdue ? datePolicy.daysBetween($0.dueDate, strategyDate) : 0
                )
            }

            if debt.isInterestBearing && planSnapshots.isEmpty {
                userRiskNotes.append("\(debt.name) is interest-bearing but has no usable fixed repayment plan for precise strategy simulation.")
            }
            if debt.repaymentMethod == .noFixedPlan {
                userRiskNotes.append("\(debt.name) has no fixed repayment plan; the simulation directly reduces the remaining personal lending amount.")
            }

            let remainingFromPlans = roundingPolicy.round(planSnapshots.reduce(Decimal(0)) { $0 + $1.remainingAmount })
            let remaining = planSnapshots.isEmpty ? roundingPolicy.round(maxDecimal(debt.remainingAmount, 0)) : remainingFromPlans
            guard remaining > 0 else { return nil }

            let dueDate = planSnapshots.map(\.dueDate).min() ?? debt.agreedEndDate
            let isOverdue = planSnapshots.contains { $0.isOverdue } || (dueDate.map { $0 < strategyDate } ?? false)
            let dueThisMonth = planSnapshots
                .filter { $0.dueDate <= endOfMonth(containing: strategyDate) }
                .reduce(Decimal(0)) { $0 + $1.remainingAmount }

            return StrategyDebtSnapshot(
                id: debt.id,
                debtType: .personalLending,
                name: debt.name,
                remainingAmount: remaining,
                minimumPaymentAmount: planSnapshots.isEmpty ? 0 : dueThisMonth,
                costRate: 0,
                riskWeight: isOverdue ? 2 : 1,
                dueDate: dueDate,
                dataSource: planSnapshots.isEmpty ? "personalLendingBalance" : "personalLendingPlan",
                isFallbackData: debt.isInterestBearing && planSnapshots.isEmpty,
                isOverdue: isOverdue,
                overdueDays: isOverdue ? datePolicy.daysBetween(dueDate ?? strategyDate, strategyDate) : 0,
                plans: planSnapshots,
                userRiskNotes: userRiskNotes
            )
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

    private func loanMonthlyCostRate(debt: LoanDebt, rule: LoanCalculationRule) -> Decimal {
        let dailyRate = rule.fixedPenaltyDailyRate ?? (debt.annualInterestRate / Decimal(365) * rule.penaltyRateMultiplier)
        return roundingPolicy.round(maxDecimal(dailyRate, 0) * Decimal(30))
    }

    private func endOfMonth(containing date: Date) -> Date {
        let components = datePolicy.calendar.dateComponents([.year, .month], from: date)
        let firstDay = datePolicy.calendar.date(from: DateComponents(year: components.year, month: components.month, day: 1)) ?? date
        let nextMonth = datePolicy.calendar.date(byAdding: .month, value: 1, to: firstDay) ?? firstDay
        return datePolicy.calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? date
    }
}
