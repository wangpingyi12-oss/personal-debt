import Foundation
import SwiftData

@Model
final class CreditCardDebt {
    var id: UUID
    var name: String
    var bankName: String
    var note: String
    var billingDay: Int
    var dueDay: Int
    var currencyCode: String
    var statusRawValue: String
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    var status: DebtStatus {
        get { .value(from: statusRawValue, default: .active) }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        bankName: String = "",
        note: String = "",
        billingDay: Int,
        dueDay: Int,
        currencyCode: String = Locale.current.currency?.identifier ?? "USD",
        status: DebtStatus = .active,
        isActive: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.bankName = bankName
        self.note = note
        self.billingDay = billingDay
        self.dueDay = dueDay
        self.currencyCode = currencyCode
        self.statusRawValue = status.rawValue
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class CreditCardCalculationRule {
    var id: UUID
    var debtID: UUID?
    var minimumPaymentRatio: Decimal
    var minimumPaymentFloor: Decimal
    var revolvingInterestEnabled: Bool
    var revolvingDailyRate: Decimal
    var overdueFeeRate: Decimal
    var minimumOverdueFee: Decimal
    var fixedOverdueFee: Decimal?
    var penaltyBaseTypeRawValue: String
    var penaltyDailyRate: Decimal
    var currentPurchaseFallbackMode: String

    var penaltyBaseType: LoanPenaltyBaseType {
        get { .value(from: penaltyBaseTypeRawValue, default: .unpaidAmount) }
        set { penaltyBaseTypeRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        debtID: UUID? = nil,
        minimumPaymentRatio: Decimal = Decimal(string: "0.10") ?? 0.10,
        minimumPaymentFloor: Decimal = 0,
        revolvingInterestEnabled: Bool = true,
        revolvingDailyRate: Decimal = Decimal(string: "0.0005") ?? 0.0005,
        overdueFeeRate: Decimal = Decimal(string: "0.005") ?? 0.005,
        minimumOverdueFee: Decimal = 25,
        fixedOverdueFee: Decimal? = nil,
        penaltyBaseType: LoanPenaltyBaseType = .unpaidAmount,
        penaltyDailyRate: Decimal = Decimal(string: "0.0005") ?? 0.0005,
        currentPurchaseFallbackMode: String = "zero"
    ) {
        self.id = id
        self.debtID = debtID
        self.minimumPaymentRatio = minimumPaymentRatio
        self.minimumPaymentFloor = minimumPaymentFloor
        self.revolvingInterestEnabled = revolvingInterestEnabled
        self.revolvingDailyRate = revolvingDailyRate
        self.overdueFeeRate = overdueFeeRate
        self.minimumOverdueFee = minimumOverdueFee
        self.fixedOverdueFee = fixedOverdueFee
        self.penaltyBaseTypeRawValue = penaltyBaseType.rawValue
        self.penaltyDailyRate = penaltyDailyRate
        self.currentPurchaseFallbackMode = currentPurchaseFallbackMode
    }

    var isGlobalDefault: Bool {
        debtID == nil
    }

    static func builtInDefault(debtID: UUID? = nil, now: Date = Date()) -> CreditCardCalculationRule {
        _ = now
        return CreditCardCalculationRule(debtID: debtID)
    }
}

@Model
final class CreditCardStatement {
    var id: UUID
    var debtID: UUID
    var billingDate: Date
    var dueDate: Date
    var statementAmount: Decimal
    var minimumPaymentAmount: Decimal
    var minimumPaymentSource: String
    var paidAmount: Decimal
    var remainingAmount: Decimal
    var statusRawValue: String
    var sourceRawValue: String
    var isActive: Bool
    var replacedByStatementID: UUID?
    var createdAt: Date
    var updatedAt: Date

    var status: CreditCardStatementStatus {
        get { .value(from: statusRawValue, default: .pending) }
        set { statusRawValue = newValue.rawValue }
    }

    var source: StatementSource {
        get { .value(from: sourceRawValue, default: .userConfirmed) }
        set { sourceRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        debtID: UUID,
        billingDate: Date,
        dueDate: Date,
        statementAmount: Decimal,
        minimumPaymentAmount: Decimal,
        minimumPaymentSource: String,
        paidAmount: Decimal = 0,
        remainingAmount: Decimal? = nil,
        status: CreditCardStatementStatus = .pending,
        source: StatementSource,
        isActive: Bool = true,
        replacedByStatementID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.debtID = debtID
        self.billingDate = billingDate
        self.dueDate = dueDate
        self.statementAmount = statementAmount
        self.minimumPaymentAmount = minimumPaymentAmount
        self.minimumPaymentSource = minimumPaymentSource
        self.paidAmount = paidAmount
        self.remainingAmount = remainingAmount ?? maxDecimal(statementAmount - paidAmount, 0)
        self.statusRawValue = status.rawValue
        self.sourceRawValue = source.rawValue
        self.isActive = isActive
        self.replacedByStatementID = replacedByStatementID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class CreditCardStatementBreakdown {
    var id: UUID
    var statementID: UUID
    var sourceRawValue: String
    var normalSpending: Decimal
    var previousCycleRemainingAmount: Decimal
    var installmentPrincipal: Decimal
    var installmentFee: Decimal
    var installmentInterest: Decimal
    var revolvingInterest: Decimal
    var overdueFee: Decimal
    var penaltyInterest: Decimal
    var unclassifiedAmount: Decimal
    var hasBreakdownConflict: Bool
    var isActive: Bool

    var source: BreakdownSource {
        get { .value(from: sourceRawValue, default: .fallback) }
        set { sourceRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        statementID: UUID,
        source: BreakdownSource,
        normalSpending: Decimal = 0,
        previousCycleRemainingAmount: Decimal = 0,
        installmentPrincipal: Decimal = 0,
        installmentFee: Decimal = 0,
        installmentInterest: Decimal = 0,
        revolvingInterest: Decimal = 0,
        overdueFee: Decimal = 0,
        penaltyInterest: Decimal = 0,
        unclassifiedAmount: Decimal = 0,
        hasBreakdownConflict: Bool = false,
        isActive: Bool = true
    ) {
        self.id = id
        self.statementID = statementID
        self.sourceRawValue = source.rawValue
        self.normalSpending = normalSpending
        self.previousCycleRemainingAmount = previousCycleRemainingAmount
        self.installmentPrincipal = installmentPrincipal
        self.installmentFee = installmentFee
        self.installmentInterest = installmentInterest
        self.revolvingInterest = revolvingInterest
        self.overdueFee = overdueFee
        self.penaltyInterest = penaltyInterest
        self.unclassifiedAmount = unclassifiedAmount
        self.hasBreakdownConflict = hasBreakdownConflict
        self.isActive = isActive
    }
}

@Model
final class CreditCardRepaymentPlan {
    var id: UUID
    var debtID: UUID
    var statementID: UUID
    var dueDate: Date
    var scheduledAmount: Decimal
    var paidAmount: Decimal
    var remainingAmount: Decimal
    var statusRawValue: String
    var sourceRawValue: String
    var isActive: Bool

    var status: PlanStatus {
        get { .value(from: statusRawValue, default: .pending) }
        set { statusRawValue = newValue.rawValue }
    }

    var source: StatementSource {
        get { .value(from: sourceRawValue, default: .userConfirmed) }
        set { sourceRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        debtID: UUID,
        statementID: UUID,
        dueDate: Date,
        scheduledAmount: Decimal,
        paidAmount: Decimal = 0,
        remainingAmount: Decimal? = nil,
        status: PlanStatus = .pending,
        source: StatementSource,
        isActive: Bool = true
    ) {
        self.id = id
        self.debtID = debtID
        self.statementID = statementID
        self.dueDate = dueDate
        self.scheduledAmount = scheduledAmount
        self.paidAmount = paidAmount
        self.remainingAmount = remainingAmount ?? maxDecimal(scheduledAmount - paidAmount, 0)
        self.statusRawValue = status.rawValue
        self.sourceRawValue = source.rawValue
        self.isActive = isActive
    }
}

@Model
final class CreditCardPaymentRecord {
    var id: UUID
    var debtID: UUID
    var statementID: UUID
    var paymentDate: Date
    var amount: Decimal
    var note: String
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        debtID: UUID,
        statementID: UUID,
        paymentDate: Date,
        amount: Decimal,
        note: String = "",
        isActive: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.debtID = debtID
        self.statementID = statementID
        self.paymentDate = paymentDate
        self.amount = amount
        self.note = note
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class CreditCardOverdueRecord {
    var id: UUID
    var debtID: UUID
    var statementID: UUID
    var overdueAmount: Decimal
    var overdueFee: Decimal
    var penaltyInterest: Decimal
    var startDate: Date
    var endDate: Date?
    var statusRawValue: String
    var source: String
    var isUserManaged: Bool
    var isActive: Bool
    var note: String
    var systemCalculatedOverdueAmount: Decimal
    var systemCalculatedOverdueFee: Decimal
    var systemCalculatedPenaltyInterest: Decimal
    var updatedAt: Date

    var status: CreditCardOverdueRecordStatus {
        get { .value(from: statusRawValue, default: .active) }
        set { statusRawValue = newValue.rawValue }
    }

    var recordSource: CreditCardOverdueRecordSource {
        get { .value(from: source, default: .systemGenerated) }
        set { source = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        debtID: UUID,
        statementID: UUID,
        overdueAmount: Decimal,
        overdueFee: Decimal = 0,
        penaltyInterest: Decimal = 0,
        startDate: Date,
        endDate: Date? = nil,
        status: CreditCardOverdueRecordStatus = .active,
        source: CreditCardOverdueRecordSource = .systemGenerated,
        isUserManaged: Bool = false,
        isActive: Bool = true,
        note: String = "",
        systemCalculatedOverdueAmount: Decimal = 0,
        systemCalculatedOverdueFee: Decimal = 0,
        systemCalculatedPenaltyInterest: Decimal = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.debtID = debtID
        self.statementID = statementID
        self.overdueAmount = overdueAmount
        self.overdueFee = overdueFee
        self.penaltyInterest = penaltyInterest
        self.startDate = startDate
        self.endDate = endDate
        self.statusRawValue = status.rawValue
        self.source = source.rawValue
        self.isUserManaged = isUserManaged
        self.isActive = isActive
        self.note = note
        self.systemCalculatedOverdueAmount = systemCalculatedOverdueAmount
        self.systemCalculatedOverdueFee = systemCalculatedOverdueFee
        self.systemCalculatedPenaltyInterest = systemCalculatedPenaltyInterest
        self.updatedAt = updatedAt
    }
}

@Model
final class CreditCardInstallmentPlan {
    var id: UUID
    var debtID: UUID
    var nextBillingDate: Date
    var principalPerTerm: Decimal
    var feePerTerm: Decimal
    var interestPerTerm: Decimal
    var totalTerms: Int
    var paidTerms: Int
    var isActive: Bool

    init(
        id: UUID = UUID(),
        debtID: UUID,
        nextBillingDate: Date,
        principalPerTerm: Decimal,
        feePerTerm: Decimal = 0,
        interestPerTerm: Decimal = 0,
        totalTerms: Int,
        paidTerms: Int = 0,
        isActive: Bool = true
    ) {
        self.id = id
        self.debtID = debtID
        self.nextBillingDate = nextBillingDate
        self.principalPerTerm = principalPerTerm
        self.feePerTerm = feePerTerm
        self.interestPerTerm = interestPerTerm
        self.totalTerms = totalTerms
        self.paidTerms = paidTerms
        self.isActive = isActive
    }
}
