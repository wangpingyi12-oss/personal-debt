import Foundation
import SwiftData

@Model
final class CreditCardDebt {
    @Attribute(.unique) var id: UUID
    var name: String
    var issuer: String
    var creditLimit: Double
    var annualRate: Double
    var statementDay: Int
    var dueDay: Int
    var currentBalance: Double
    var minimumPaymentRate: Double
    var status: String
    var isValid: Bool
    var dataDomain: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \CreditCardBill.debt) var bills: [CreditCardBill]
    @Relationship(deleteRule: .cascade, inverse: \CreditCardTransaction.debt) var transactions: [CreditCardTransaction]
    @Relationship(deleteRule: .cascade, inverse: \CreditCardOverdueRecord.debt) var overdues: [CreditCardOverdueRecord]

    init(
        id: UUID = UUID(),
        name: String,
        issuer: String,
        creditLimit: Double,
        annualRate: Double,
        statementDay: Int,
        dueDay: Int,
        currentBalance: Double,
        minimumPaymentRate: Double = 0.1,
        status: String = DebtLifecycleStatus.active.rawValue,
        isValid: Bool = true,
        dataDomain: String = DataIsolationDomain.actual.rawValue,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.issuer = issuer
        self.creditLimit = creditLimit
        self.annualRate = annualRate
        self.statementDay = statementDay
        self.dueDay = dueDay
        self.currentBalance = currentBalance
        self.minimumPaymentRate = minimumPaymentRate
        self.status = status
        self.isValid = isValid
        self.dataDomain = dataDomain
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.bills = []
        self.transactions = []
        self.overdues = []
    }
}

@Model
final class CreditCardBill {
    @Attribute(.unique) var id: UUID
    var periodKey: String
    var statementDate: Date
    var dueDate: Date
    var principalDue: Double
    var minimumPaymentDue: Double
    var paidAmount: Double
    var state: String
    var isFallbackPlaceholder: Bool
    var isValid: Bool
    var debt: CreditCardDebt?

    init(
        id: UUID = UUID(),
        periodKey: String,
        statementDate: Date,
        dueDate: Date,
        principalDue: Double,
        minimumPaymentDue: Double,
        paidAmount: Double = 0,
        state: String = RecordState.pending.rawValue,
        isFallbackPlaceholder: Bool = false,
        isValid: Bool = true,
        debt: CreditCardDebt? = nil
    ) {
        self.id = id
        self.periodKey = periodKey
        self.statementDate = statementDate
        self.dueDate = dueDate
        self.principalDue = principalDue
        self.minimumPaymentDue = minimumPaymentDue
        self.paidAmount = paidAmount
        self.state = state
        self.isFallbackPlaceholder = isFallbackPlaceholder
        self.isValid = isValid
        self.debt = debt
    }
}

@Model
final class CreditCardTransaction {
    @Attribute(.unique) var id: UUID
    var occurredAt: Date
    var amount: Double
    var kind: String
    var note: String
    var isValid: Bool
    var debt: CreditCardDebt?

    init(
        id: UUID = UUID(),
        occurredAt: Date,
        amount: Double,
        kind: String,
        note: String = "",
        isValid: Bool = true,
        debt: CreditCardDebt? = nil
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.amount = amount
        self.kind = kind
        self.note = note
        self.isValid = isValid
        self.debt = debt
    }
}

@Model
final class CreditCardOverdueRecord {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    var endDate: Date?
    var overdueAmount: Double
    var penaltyAmount: Double
    var isActive: Bool
    var isValid: Bool
    var debt: CreditCardDebt?

    init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date? = nil,
        overdueAmount: Double,
        penaltyAmount: Double = 0,
        isActive: Bool = true,
        isValid: Bool = true,
        debt: CreditCardDebt? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.overdueAmount = overdueAmount
        self.penaltyAmount = penaltyAmount
        self.isActive = isActive
        self.isValid = isValid
        self.debt = debt
    }
}
