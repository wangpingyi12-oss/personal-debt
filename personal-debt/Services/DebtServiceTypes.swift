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
    var lastFourDigits: String
    var creditLimit: Decimal?
    var note: String
    var billingDay: Int
    var dueDay: Int
    var currencyCode: String

    init(
        name: String,
        bankName: String = "",
        lastFourDigits: String = "",
        creditLimit: Decimal? = nil,
        note: String = "",
        billingDay: Int,
        dueDay: Int,
        currencyCode: String = Locale.current.currency?.identifier ?? "USD"
    ) {
        self.name = name
        self.bankName = bankName
        self.lastFourDigits = lastFourDigits
        self.creditLimit = creditLimit
        self.note = note
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
    var note: String

    init(
        overdueAmount: Decimal,
        overdueFee: Decimal,
        penaltyInterest: Decimal,
        startDate: Date,
        endDate: Date? = nil,
        note: String = ""
    ) {
        self.overdueAmount = overdueAmount
        self.overdueFee = overdueFee
        self.penaltyInterest = penaltyInterest
        self.startDate = startDate
        self.endDate = endDate
        self.note = note
    }
}

struct LoanDebtInput: Equatable {
    var name: String
    var creditorName: String
    var note: String
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

    init(
        name: String,
        creditorName: String = "",
        note: String = "",
        entryMode: LoanEntryMode,
        repaymentMethod: LoanRepaymentMethod,
        originalPrincipal: Decimal,
        openingPrincipalForManagement: Decimal? = nil,
        annualInterestRate: Decimal,
        startDate: Date,
        managementStartDate: Date? = nil,
        endDate: Date,
        repaymentDay: Int,
        termCount: Int,
        currencyCode: String = Locale.current.currency?.identifier ?? "USD"
    ) {
        self.name = name
        self.creditorName = creditorName
        self.note = note
        self.entryMode = entryMode
        self.repaymentMethod = repaymentMethod
        self.originalPrincipal = originalPrincipal
        self.openingPrincipalForManagement = openingPrincipalForManagement
        self.annualInterestRate = annualInterestRate
        self.startDate = startDate
        self.managementStartDate = managementStartDate
        self.endDate = endDate
        self.repaymentDay = repaymentDay
        self.termCount = termCount
        self.currencyCode = currencyCode
    }
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

struct LoanManualOverdueInput: Equatable {
    var overdueFee: Decimal
    var penaltyInterest: Decimal
    var startDate: Date
    var endDate: Date?
    var note: String

    init(
        overdueFee: Decimal,
        penaltyInterest: Decimal,
        startDate: Date,
        endDate: Date? = nil,
        note: String = ""
    ) {
        self.overdueFee = overdueFee
        self.penaltyInterest = penaltyInterest
        self.startDate = startDate
        self.endDate = endDate
        self.note = note
    }
}

struct PersonalLendingManualOverdueInput: Equatable {
    var overdueAmount: Decimal
    var overdueFee: Decimal
    var penaltyInterest: Decimal
    var startDate: Date
    var endDate: Date?
    var note: String

    init(
        overdueAmount: Decimal,
        overdueFee: Decimal = 0,
        penaltyInterest: Decimal = 0,
        startDate: Date,
        endDate: Date? = nil,
        note: String = ""
    ) {
        self.overdueAmount = overdueAmount
        self.overdueFee = overdueFee
        self.penaltyInterest = penaltyInterest
        self.startDate = startDate
        self.endDate = endDate
        self.note = note
    }
}
