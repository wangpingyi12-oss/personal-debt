import Foundation

struct MoneyRoundingPolicy: Sendable {
    var scale: Int16
    var roundingMode: NSDecimalNumber.RoundingMode

    static let standard = MoneyRoundingPolicy(scale: 2, roundingMode: .plain)

    func round(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, Int(scale), roundingMode)
        return result
    }

    func allocateEvenly(total: Decimal, count: Int) -> [Decimal] {
        guard count > 0 else { return [] }
        guard count > 1 else { return [round(total)] }

        let regular = round(total / Decimal(count))
        var values = Array(repeating: regular, count: count)
        let subtotal = regular * Decimal(count - 1)
        values[count - 1] = round(total - subtotal)
        return values
    }
}

extension Decimal {
    var isZero: Bool { self == 0 }
    var isPositive: Bool { self > 0 }

    func roundedMoney(_ policy: MoneyRoundingPolicy = .standard) -> Decimal {
        policy.round(self)
    }

    static func pow(_ base: Decimal, _ exponent: Int) -> Decimal {
        guard exponent >= 0 else { return 0 }
        let value = Foundation.pow(NSDecimalNumber(decimal: base).doubleValue, Double(exponent))
        return Decimal(value)
    }
}

nonisolated func minDecimal(_ lhs: Decimal, _ rhs: Decimal) -> Decimal {
    lhs < rhs ? lhs : rhs
}

nonisolated func maxDecimal(_ lhs: Decimal, _ rhs: Decimal) -> Decimal {
    lhs > rhs ? lhs : rhs
}
