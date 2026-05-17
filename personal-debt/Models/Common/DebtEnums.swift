import Foundation

enum DebtType: String, Codable, CaseIterable, Identifiable {
    case creditCard
    case loan
    case personalLending

    var id: String { rawValue }
}

enum DebtStatus: String, Codable, CaseIterable, Identifiable {
    case active
    case partiallyPaid
    case overdue
    case paidOff
    case archived

    var id: String { rawValue }
}

enum PlanStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case partiallyPaid
    case paid
    case overdue

    var id: String { rawValue }
}

enum CreditCardStatementStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case partiallyPaid
    case paid
    case carriedForward
    case overdue
    case replaced

    var id: String { rawValue }
}

enum CreditCardOverdueRecordStatus: String, Codable, CaseIterable, Identifiable {
    case active
    case ended
    case ignored
    case replaced
    case voided

    var id: String { rawValue }
}

enum CreditCardOverdueRecordSource: String, Codable, CaseIterable, Identifiable {
    case systemGenerated
    case userCreated
    case userAdjusted

    var id: String { rawValue }
}

enum StatementSource: String, Codable, CaseIterable, Identifiable {
    case userConfirmed
    case fallback

    var id: String { rawValue }
}

enum BreakdownSource: String, Codable, CaseIterable, Identifiable {
    case userProvided
    case fallback
    case mixed

    var id: String { rawValue }
}

enum StrategyType: String, Codable, CaseIterable, Identifiable {
    case avalanche
    case snowball
    case balanced

    var id: String { rawValue }
}

enum LoanEntryMode: String, Codable, CaseIterable, Identifiable {
    case newLoan
    case inProgressLoan

    var id: String { rawValue }
}

enum LoanRepaymentMethod: String, Codable, CaseIterable, Identifiable {
    case equalPrincipal
    case equalPayment
    case interestFirst
    case principalAtEnd

    var id: String { rawValue }
}

enum LoanPlanPeriodType: String, Codable, CaseIterable, Identifiable {
    case regular
    case finalPartialPeriod
    case shortTermSinglePeriod

    var id: String { rawValue }
}

enum LoanPenaltyBaseType: String, Codable, CaseIterable, Identifiable {
    case unpaidPrincipal
    case unpaidAmount

    var id: String { rawValue }
}

enum LoanPenaltyCalculationMode: String, Codable, CaseIterable, Identifiable {
    case simpleDynamic

    var id: String { rawValue }
}

enum LoanOverdueBaseType: String, Codable, CaseIterable, Identifiable {
    case currentUnpaidPrincipal
    case currentRemainingScheduledAmount

    var id: String { rawValue }
}

enum LoanOverdueFeeMode: String, Codable, CaseIterable, Identifiable {
    case zero
    case fixed
    case percentage
    case disabled

    var id: String { rawValue }
}

enum LoanPenaltyInterestMode: String, Codable, CaseIterable, Identifiable {
    case loanDailyRateMultiplier
    case fixedDailyRate
    case zero
    case disabled

    var id: String { rawValue }
}

enum LoanPaymentAllocationMode: String, Codable, CaseIterable, Identifiable {
    case feeFirst
    case currentPeriodFirst

    var id: String { rawValue }
}

enum LoanOverdueRecordSource: String, Codable, CaseIterable, Identifiable {
    case systemGenerated
    case userCreated
    case userAdjusted

    var id: String { rawValue }
}

enum LoanOverdueRecordStatus: String, Codable, CaseIterable, Identifiable {
    case active
    case paid
    case waived
    case closed
    case ignored
    case voided

    var id: String { rawValue }
}

enum PersonalLendingRepaymentMethod: String, Codable, CaseIterable, Identifiable {
    case noFixedPlan
    case principalAndInterestAtMaturity
    case equalPrincipalEqualInterest

    var id: String { rawValue }
}

enum PersonalLendingPlanStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case partiallyPaid
    case paid
    case overdue

    var id: String { rawValue }
}

enum PersonalLendingOverdueRecordSource: String, Codable, CaseIterable, Identifiable {
    case systemGenerated
    case userCreated
    case userAdjusted

    var id: String { rawValue }
}

enum PersonalLendingOverdueRecordStatus: String, Codable, CaseIterable, Identifiable {
    case active
    case resolved
    case ignored
    case voided

    var id: String { rawValue }
}

extension RawRepresentable where RawValue == String {
    static func value(from rawValue: String, default defaultValue: Self) -> Self {
        Self(rawValue: rawValue) ?? defaultValue
    }
}
