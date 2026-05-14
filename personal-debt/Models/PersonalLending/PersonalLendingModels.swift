import Foundation
import SwiftData

@Model
final class PersonalLendingDebt {
    @Attribute(.unique) var id: UUID
    var name: String
    var counterparty: String
    var principal: Double
    var annualRate: Double
    var startDate: Date
    var remainingPrincipal: Double
    var status: String
    var isValid: Bool
    var dataDomain: String
    var userFactSnapshot: String

    @Relationship(deleteRule: .cascade, inverse: \PersonalLendingPlanItem.debt) var planItems: [PersonalLendingPlanItem]
    @Relationship(deleteRule: .cascade, inverse: \PersonalLendingTransaction.debt) var transactions: [PersonalLendingTransaction]
    @Relationship(deleteRule: .cascade, inverse: \PersonalLendingOverdueRecord.debt) var overdues: [PersonalLendingOverdueRecord]

    init(
        id: UUID = UUID(),
        name: String,
        counterparty: String,
        principal: Double,
        annualRate: Double,
        startDate: Date,
        remainingPrincipal: Double,
        status: String = DebtLifecycleStatus.active.rawValue,
        isValid: Bool = true,
        dataDomain: String = DataIsolationDomain.actual.rawValue,
        userFactSnapshot: String = "{}"
    ) {
        self.id = id
        self.name = name
        self.counterparty = counterparty
        self.principal = principal
        self.annualRate = annualRate
        self.startDate = startDate
        self.remainingPrincipal = remainingPrincipal
        self.status = status
        self.isValid = isValid
        self.dataDomain = dataDomain
        self.userFactSnapshot = userFactSnapshot
        self.planItems = []
        self.transactions = []
        self.overdues = []
    }
}

@Model
final class PersonalLendingPlanItem {
    @Attribute(.unique) var id: UUID
    var sequence: Int
    var dueDate: Date
    var principalDue: Double
    var interestDue: Double
    var totalDue: Double
    var paidAmount: Double
    var state: String
    var isValid: Bool
    var debt: PersonalLendingDebt?

    init(
        id: UUID = UUID(),
        sequence: Int,
        dueDate: Date,
        principalDue: Double,
        interestDue: Double,
        totalDue: Double,
        paidAmount: Double = 0,
        state: String = RecordState.pending.rawValue,
        isValid: Bool = true,
        debt: PersonalLendingDebt? = nil
    ) {
        self.id = id
        self.sequence = sequence
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
final class PersonalLendingTransaction {
    @Attribute(.unique) var id: UUID
    var occurredAt: Date
    var amount: Double
    var note: String
    var isValid: Bool
    var debt: PersonalLendingDebt?

    init(
        id: UUID = UUID(),
        occurredAt: Date,
        amount: Double,
        note: String = "",
        isValid: Bool = true,
        debt: PersonalLendingDebt? = nil
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
final class PersonalLendingOverdueRecord {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    var endDate: Date?
    var overdueAmount: Double
    var penaltyAmount: Double
    var isActive: Bool
    var isValid: Bool
    var debt: PersonalLendingDebt?

    init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date? = nil,
        overdueAmount: Double,
        penaltyAmount: Double = 0,
        isActive: Bool = true,
        isValid: Bool = true,
        debt: PersonalLendingDebt? = nil
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
