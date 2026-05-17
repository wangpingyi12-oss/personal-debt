import Foundation
import SwiftUI

enum AppText {
    static func string(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    static func string(_ key: String, defaultValue: String) -> String {
        Bundle.main.localizedString(forKey: key, value: defaultValue, table: nil)
    }

    static func money(_ value: Decimal, currencyCode: String = Locale.current.currency?.identifier ?? "USD") -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    static func percent(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    static func date(_ value: Date?) -> String {
        guard let value else { return string("common.none") }
        return value.formatted(date: .abbreviated, time: .omitted)
    }

    static func debtType(_ type: DebtType) -> String {
        string("debtType.\(type.rawValue)")
    }

    static func debtStatus(_ status: DebtStatus) -> String {
        string("debtStatus.\(status.rawValue)")
    }

    static func planStatus(_ status: PlanStatus) -> String {
        string("planStatus.\(status.rawValue)")
    }

    static func personalPlanStatus(_ status: PersonalLendingPlanStatus) -> String {
        string("personalPlanStatus.\(status.rawValue)")
    }

    static func statementStatus(_ status: CreditCardStatementStatus) -> String {
        string("statementStatus.\(status.rawValue)")
    }

    static func statementSource(_ source: StatementSource) -> String {
        string("statementSource.\(source.rawValue)")
    }
}

extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
