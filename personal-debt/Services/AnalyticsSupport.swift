import Foundation

enum AnalyticsSupport {
    static func monthPeriod(containing date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> AnalyticsPeriod {
        let components = calendar.dateComponents([.year, .month], from: date)
        let start = calendar.date(from: DateComponents(year: components.year, month: components.month, day: 1)) ?? calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return AnalyticsPeriod(periodStart: start, periodEndExclusive: end)
    }

    static func nonNegative(_ value: Decimal) -> Decimal {
        maxDecimal(value, 0)
    }

    static func nonNegativeMoney(_ value: Decimal, roundingPolicy: MoneyRoundingPolicy = .standard) -> Decimal {
        roundingPolicy.round(nonNegative(value))
    }

    static func ratio(_ numerator: Decimal, _ denominator: Decimal) -> Decimal {
        guard denominator > 0 else { return 0 }
        return numerator / denominator
    }

    static func activeCreditCardDebts(_ debts: [CreditCardDebt]) -> [CreditCardDebt] {
        debts.filter { $0.isActive && $0.status != .archived }
    }

    static func activeLoanDebts(_ debts: [LoanDebt]) -> [LoanDebt] {
        debts.filter { $0.status != .archived }
    }

    static func activePersonalLendingDebts(_ debts: [PersonalLendingDebt]) -> [PersonalLendingDebt] {
        debts.filter { !$0.isArchived && $0.status != .archived }
    }

    static func effectiveStatements(
        _ statements: [CreditCardStatement],
        debtIDs: Set<UUID>? = nil,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [CreditCardStatement] {
        struct StatementKey: Hashable {
            var debtID: UUID
            var billingDate: Date
        }

        var selectedByCycle: [StatementKey: CreditCardStatement] = [:]

        for statement in statements where statement.isActive && statement.status != .replaced {
            if let debtIDs, debtIDs.contains(statement.debtID) == false {
                continue
            }

            let key = StatementKey(
                debtID: statement.debtID,
                billingDate: calendar.startOfDay(for: statement.billingDate)
            )

            guard let existing = selectedByCycle[key] else {
                selectedByCycle[key] = statement
                continue
            }

            if statementPrecedes(statement, existing) {
                selectedByCycle[key] = statement
            }
        }

        return Array(selectedByCycle.values)
    }

    static func latestEffectiveStatementByDebt(
        _ statements: [CreditCardStatement],
        debtIDs: Set<UUID>? = nil,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [UUID: CreditCardStatement] {
        var selected: [UUID: CreditCardStatement] = [:]

        for statement in effectiveStatements(statements, debtIDs: debtIDs, calendar: calendar) {
            guard let existing = selected[statement.debtID] else {
                selected[statement.debtID] = statement
                continue
            }

            if statement.billingDate > existing.billingDate {
                selected[statement.debtID] = statement
            } else if calendar.isDate(statement.billingDate, inSameDayAs: existing.billingDate),
                      statementPrecedes(statement, existing) {
                selected[statement.debtID] = statement
            }
        }

        return selected
    }

    static func debtNameMaps(
        creditCardDebts: [CreditCardDebt],
        loanDebts: [LoanDebt],
        personalLendingDebts: [PersonalLendingDebt]
    ) -> (creditCards: [UUID: String], loans: [UUID: String], personalLending: [UUID: String]) {
        (
            Dictionary(uniqueKeysWithValues: creditCardDebts.map { ($0.id, $0.name) }),
            Dictionary(uniqueKeysWithValues: loanDebts.map { ($0.id, $0.name) }),
            Dictionary(uniqueKeysWithValues: personalLendingDebts.map { ($0.id, $0.name) })
        )
    }

    static func breakdownCostSource(_ source: BreakdownSource) -> AnalyticsCostSource {
        switch source {
        case .userProvided:
            return .userProvided
        case .fallback:
            return .systemFallback
        case .mixed:
            return .mixed
        }
    }

    static func loanOverdueCostSource(_ source: LoanOverdueRecordSource) -> AnalyticsCostSource {
        switch source {
        case .systemGenerated:
            return .systemFallback
        case .userCreated, .userAdjusted:
            return .userProvided
        }
    }

    private static func statementPrecedes(_ lhs: CreditCardStatement, _ rhs: CreditCardStatement) -> Bool {
        let lhsPriority = lhs.source == .userConfirmed ? 0 : 1
        let rhsPriority = rhs.source == .userConfirmed ? 0 : 1
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        if lhs.dueDate != rhs.dueDate {
            return lhs.dueDate > rhs.dueDate
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
