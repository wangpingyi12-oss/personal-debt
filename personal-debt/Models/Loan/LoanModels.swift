import Foundation
import SwiftData

enum LoanRepaymentMethod: String, CaseIterable, Codable, Identifiable {
    case equalPrincipalAndInterest
    case equalPrincipal
    case interestOnlyThenPrincipal
    case bullet

    var id: String { rawValue }
}

@Model
final class LoanDebt {
    @Attribute(.unique) var id: UUID
    var name: String
    var principal: Double
    var annualRate: Double
    var totalPeriods: Int
    var startDate: Date
    var repaymentMethod: String
    var remainingPrincipal: Double
    var status: String
    var isValid: Bool
    var dataDomain: String

    @Relationship(deleteRule: .cascade, inverse: \LoanInstallment.debt) var installments: [LoanInstallment]
    @Relationship(deleteRule: .cascade, inverse: \LoanTransaction.debt) var transactions: [LoanTransaction]
    @Relationship(deleteRule: .cascade, inverse: \LoanOverdueRecord.debt) var overdues: [LoanOverdueRecord]

    init(
        id: UUID = UUID(),
        name: String,
        principal: Double,
        annualRate: Double,
        totalPeriods: Int,
        startDate: Date,
        repaymentMethod: String,
        remainingPrincipal: Double,
        status: String = DebtLifecycleStatus.active.rawValue,
        isValid: Bool = true,
        dataDomain: String = DataIsolationDomain.actual.rawValue
    ) {
        self.id = id
        self.name = name
        self.principal = principal
        self.annualRate = annualRate
        self.totalPeriods = totalPeriods
        self.startDate = startDate
        self.repaymentMethod = repaymentMethod
        self.remainingPrincipal = remainingPrincipal
        self.status = status
        self.isValid = isValid
        self.dataDomain = dataDomain
        self.installments = []
        self.transactions = []
        self.overdues = []
    }
}

@Model
final class LoanInstallment {
    @Attribute(.unique) var id: UUID
    var periodNumber: Int
    var dueDate: Date
    var principalDue: Double
    var interestDue: Double
    var totalDue: Double
    var paidAmount: Double
    var state: String
    var isValid: Bool
    var debt: LoanDebt?

    init(
        id: UUID = UUID(),
        periodNumber: Int,
        dueDate: Date,
        principalDue: Double,
        interestDue: Double,
        totalDue: Double,
        paidAmount: Double = 0,
        state: String = RecordState.pending.rawValue,
        isValid: Bool = true,
        debt: LoanDebt? = nil
    ) {
        self.id = id
        self.periodNumber = periodNumber
        self.dueDate = dueDate
        self.principalDue = principalDue
        self.interestDue = interestDue
        self.totalDue = totalDue
        self.paidAmount = paidAmount
        self.state = state
        self.isValid = isValid
        self.debt = debt
    }
}

@Model
final class LoanTransaction {
    @Attribute(.unique) var id: UUID
    var occurredAt: Date
    var amount: Double
    var note: String
    var isValid: Bool
    var debt: LoanDebt?

    init(
        id: UUID = UUID(),
        occurredAt: Date,
        amount: Double,
        note: String = "",
        isValid: Bool = true,
        debt: LoanDebt? = nil
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.amount = amount
        self.note = note
        self.isValid = isValid
        self.debt = debt
    }
}

@Model
final class LoanOverdueRecord {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    var endDate: Date?
    var overdueAmount: Double
    var penaltyAmount: Double
    var isActive: Bool
    var isValid: Bool
    var debt: LoanDebt?

    init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date? = nil,
        overdueAmount: Double,
        penaltyAmount: Double = 0,
        isActive: Bool = true,
        isValid: Bool = true,
        debt: LoanDebt? = nil
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
