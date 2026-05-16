import Foundation

enum DebtServiceResult: Equatable {
    case created
    case recalculated
    case requiresUserDecision(unappliedAmount: Decimal)
}

enum DebtServiceError: Error, Equatable {
    case validationFailed(String)
    case notFound(String)
    case unsupported(String)
}

struct CreditCardDebtInput: Equatable {
    var name: String
    var bankName: String
    var billingDay: Int
    var dueDay: Int
    var currencyCode: String

    init(
        name: String,
        bankName: String = "",
        billingDay: Int,
        dueDay: Int,
        currencyCode: String = Locale.current.currency?.identifier ?? "USD"
    ) {
        self.name = name
        self.bankName = bankName
        self.billingDay = billingDay
        self.dueDay = dueDay
        self.currencyCode = currencyCode
    }
}

struct CreditCardStatementInput: Equatable {
    var billingDate: Date
    var dueDate: Date
    var statementAmount: Decimal
    var minimumPaymentAmount: Decimal?
}

struct CreditCardPaymentInput: Equatable {
    var paymentDate: Date
    var amount: Decimal
    var note: String

    init(paymentDate: Date, amount: Decimal, note: String = "") {
        self.paymentDate = paymentDate
        self.amount = amount
        self.note = note
    }
}

struct CreditCardManualOverdueInput: Equatable {
    var overdueAmount: Decimal
    var overdueFee: Decimal
    var penaltyInterest: Decimal
    var startDate: Date
    var endDate: Date?
}

struct LoanDebtInput: Equatable {
    var name: String
    var creditorName: String
    var entryMode: LoanEntryMode
    var repaymentMethod: LoanRepaymentMethod
    var originalPrincipal: Decimal
    var openingPrincipalForManagement: Decimal?
    var annualInterestRate: Decimal
    var startDate: Date
    var managementStartDate: Date?
    var endDate: Date
    var repaymentDay: Int
    var termCount: Int
    var currencyCode: String
}

struct LoanPaymentInput: Equatable {
    var paymentDate: Date
    var totalAmount: Decimal
    var note: String

    init(paymentDate: Date, totalAmount: Decimal, note: String = "") {
        self.paymentDate = paymentDate
        self.totalAmount = totalAmount
        self.note = note
    }
}

struct LoanCalculationRuleInput: Equatable {
    var debtID: UUID?
    var overdueBaseType: LoanOverdueBaseType
    var overdueFeeMode: LoanOverdueFeeMode
    var fixedOverdueFee: Decimal?
    var overdueFeeRate: Decimal?
    var penaltyInterestMode: LoanPenaltyInterestMode
    var penaltyRateMultiplier: Decimal
    var fixedPenaltyDailyRate: Decimal?
    var paymentAllocationMode: LoanPaymentAllocationMode

    init(
        debtID: UUID? = nil,
        overdueBaseType: LoanOverdueBaseType = .currentUnpaidPrincipal,
        overdueFeeMode: LoanOverdueFeeMode = .zero,
        fixedOverdueFee: Decimal? = nil,
        overdueFeeRate: Decimal? = nil,
        penaltyInterestMode: LoanPenaltyInterestMode = .loanDailyRateMultiplier,
        penaltyRateMultiplier: Decimal = Decimal(string: "1.5") ?? 1.5,
        fixedPenaltyDailyRate: Decimal? = nil,
        paymentAllocationMode: LoanPaymentAllocationMode = .feeFirst
    ) {
        self.debtID = debtID
        self.overdueBaseType = overdueBaseType
        self.overdueFeeMode = overdueFeeMode
        self.fixedOverdueFee = fixedOverdueFee
        self.overdueFeeRate = overdueFeeRate
        self.penaltyInterestMode = penaltyInterestMode
        self.penaltyRateMultiplier = penaltyRateMultiplier
        self.fixedPenaltyDailyRate = fixedPenaltyDailyRate
        self.paymentAllocationMode = paymentAllocationMode
    }
}

struct PersonalLendingDebtInput: Equatable {
    var name: String
    var lenderName: String
    var note: String
    var principalAmount: Decimal
    var fixedInterestAmount: Decimal
    var borrowedDate: Date
    var agreedEndDate: Date?
    var repaymentMethod: PersonalLendingRepaymentMethod
    var isInterestBearing: Bool
    var monthlyRepaymentDay: Int?
    var termCount: Int
}

struct PersonalLendingPaymentInput: Equatable {
    var paymentDate: Date
    var amount: Decimal
    var note: String

    init(paymentDate: Date, amount: Decimal, note: String = "") {
        self.paymentDate = paymentDate
        self.amount = amount
        self.note = note
    }
}
