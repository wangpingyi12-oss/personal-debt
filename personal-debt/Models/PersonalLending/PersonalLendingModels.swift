import Foundation
import SwiftData

@Model
final class PersonalLendingDebt {
    var id: UUID
    var name: String
    var lenderName: String
    var note: String
    var principalAmount: Decimal
    var fixedInterestAmount: Decimal
    var totalPayableAmount: Decimal
    var paidAmount: Decimal
    var remainingAmount: Decimal
    var borrowedDate: Date
    var agreedEndDate: Date?
    var repaymentMethodRawValue: String
    var isInterestBearing: Bool
    var monthlyRepaymentDay: Int?
    var termCount: Int
    var statusRawValue: String
    var pastDueScheduledAmount: Decimal
    var pastDuePlanCount: Int
    var pastDueDebtCount: Int
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    var repaymentMethod: PersonalLendingRepaymentMethod {
        get { .value(from: repaymentMethodRawValue, default: .noFixedPlan) }
        set { repaymentMethodRawValue = newValue.rawValue }
    }

    var status: DebtStatus {
        get { .value(from: statusRawValue, default: .active) }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        lenderName: String = "",
        note: String = "",
        principalAmount: Decimal,
        fixedInterestAmount: Decimal = 0,
        totalPayableAmount: Decimal? = nil,
        paidAmount: Decimal = 0,
        borrowedDate: Date,
        agreedEndDate: Date? = nil,
        repaymentMethod: PersonalLendingRepaymentMethod,
        isInterestBearing: Bool = false,
        monthlyRepaymentDay: Int? = nil,
        termCount: Int = 0,
        status: DebtStatus = .active,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        let total = totalPayableAmount ?? principalAmount + fixedInterestAmount
        self.id = id
        self.name = name
        self.lenderName = lenderName
        self.note = note
        self.principalAmount = principalAmount
        self.fixedInterestAmount = fixedInterestAmount
        self.totalPayableAmount = total
        self.paidAmount = paidAmount
        self.remainingAmount = maxDecimal(total - paidAmount, 0)
        self.borrowedDate = borrowedDate
        self.agreedEndDate = agreedEndDate
        self.repaymentMethodRawValue = repaymentMethod.rawValue
        self.isInterestBearing = isInterestBearing
        self.monthlyRepaymentDay = monthlyRepaymentDay
        self.termCount = termCount
        self.statusRawValue = status.rawValue
        self.pastDueScheduledAmount = 0
        self.pastDuePlanCount = 0
        self.pastDueDebtCount = 0
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class PersonalLendingPlan {
    var id: UUID
    var debtID: UUID
    var periodIndex: Int
    var dueDate: Date
    var scheduledPrincipal: Decimal
    var scheduledInterest: Decimal
    var scheduledTotalAmount: Decimal
    var paidAmount: Decimal
    var remainingAmount: Decimal
    var statusRawValue: String

    var status: PersonalLendingPlanStatus {
        get { .value(from: statusRawValue, default: .pending) }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        debtID: UUID,
        periodIndex: Int,
        dueDate: Date,
        scheduledPrincipal: Decimal,
        scheduledInterest: Decimal,
        paidAmount: Decimal = 0,
        status: PersonalLendingPlanStatus = .pending
    ) {
        self.id = id
        self.debtID = debtID
        self.periodIndex = periodIndex
        self.dueDate = dueDate
        self.scheduledPrincipal = scheduledPrincipal
        self.scheduledInterest = scheduledInterest
        self.scheduledTotalAmount = scheduledPrincipal + scheduledInterest
        self.paidAmount = paidAmount
        self.remainingAmount = maxDecimal(scheduledPrincipal + scheduledInterest - paidAmount, 0)
        self.statusRawValue = status.rawValue
    }
}

@Model
final class PersonalLendingPaymentRecord {
    var id: UUID
    var debtID: UUID
    var paymentDate: Date
    var amount: Decimal
    var note: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        debtID: UUID,
        paymentDate: Date,
        amount: Decimal,
        note: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.debtID = debtID
        self.paymentDate = paymentDate
        self.amount = amount
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class PersonalLendingAllocationDetail {
    var id: UUID
    var paymentID: UUID
    var debtID: UUID
    var planID: UUID
    var allocatedAmount: Decimal
    var createdAt: Date

    init(
        id: UUID = UUID(),
        paymentID: UUID,
        debtID: UUID,
        planID: UUID,
        allocatedAmount: Decimal,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.paymentID = paymentID
        self.debtID = debtID
        self.planID = planID
        self.allocatedAmount = allocatedAmount
        self.createdAt = createdAt
    }
}

@Model
final class PersonalLendingOverdueRecord {
    var id: UUID
    var debtID: UUID
    var planID: UUID?
    var sourceRawValue: String
    var statusRawValue: String
    var isUserManaged: Bool
    var overdueStartDate: Date
    var overdueEndDate: Date?
    var overdueDays: Int
    var overdueAmount: Decimal
    var overdueFee: Decimal
    var penaltyInterest: Decimal
    var note: String
    var createdAt: Date
    var updatedAt: Date

    var source: PersonalLendingOverdueRecordSource {
        get { .value(from: sourceRawValue, default: .systemGenerated) }
        set { sourceRawValue = newValue.rawValue }
    }

    var status: PersonalLendingOverdueRecordStatus {
        get { .value(from: statusRawValue, default: .active) }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        debtID: UUID,
        planID: UUID? = nil,
        source: PersonalLendingOverdueRecordSource = .systemGenerated,
        status: PersonalLendingOverdueRecordStatus = .active,
        isUserManaged: Bool = false,
        overdueStartDate: Date,
        overdueEndDate: Date? = nil,
        overdueDays: Int,
        overdueAmount: Decimal,
        overdueFee: Decimal = 0,
        penaltyInterest: Decimal = 0,
        note: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.debtID = debtID
        self.planID = planID
        self.sourceRawValue = source.rawValue
        self.statusRawValue = status.rawValue
        self.isUserManaged = isUserManaged
        self.overdueStartDate = overdueStartDate
        self.overdueEndDate = overdueEndDate
        self.overdueDays = overdueDays
        self.overdueAmount = overdueAmount
        self.overdueFee = overdueFee
        self.penaltyInterest = penaltyInterest
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
