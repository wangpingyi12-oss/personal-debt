import Foundation
import SwiftData

// MARK: - Repayment Method

enum PersonalLendingRepaymentMethod: String, CaseIterable, Codable, Identifiable {
    /// 无固定还款计划 – only interest-free; no plan items generated.
    case noFixedPlan
    /// 到期还本付息 – one lump-sum plan item on the agreed end date.
    case lumpSumAtMaturity
    /// 等本等息 – equal principal + equal interest each month.
    case equalInstallments

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .noFixedPlan: return "无固定还款计划"
        case .lumpSumAtMaturity: return "到期还本付息"
        case .equalInstallments: return "等本等息"
        }
    }
}

// MARK: - Main Debt Model

@Model
final class PersonalLendingDebt {
    @Attribute(.unique) var id: UUID
    var name: String
    /// 出借人名称
    var lenderName: String
    /// 备注
    var note: String
    /// 借款本金
    var principal: Double
    /// 是否有息
    var hasInterest: Bool
    /// 固定总利息 (0 when interest-free)
    var totalInterest: Double
    /// 总应还金额 = principal + totalInterest
    var totalAmountDue: Double
    /// 已还金额 (computed by full recalculate)
    var paidAmount: Double
    /// 剩余金额 (computed by full recalculate)
    var remainingAmount: Double
    /// 借款日期
    var startDate: Date
    /// 约定结束日期 (nil for noFixedPlan when user leaves it blank)
    var endDate: Date?
    /// 还款方式 (PersonalLendingRepaymentMethod raw value)
    var repaymentMethod: String
    /// 每月还款日 1–31, only for equalInstallments
    var monthlyPaymentDay: Int
    /// 总期数, only for equalInstallments
    var totalPeriods: Int
    /// Debt lifecycle status raw value
    var status: String
    var isValid: Bool
    var dataDomain: String

    // MARK: 履约统计 (past-due, not overdue)
    /// 已过约定日未还金额
    var pastDueScheduledAmount: Double
    /// 已过约定日未还计划数
    var pastDuePlanCount: Int
    /// 已过约定日未还债务数 (0 or 1 for this debt)
    var pastDueDebtCount: Int

    @Relationship(deleteRule: .cascade, inverse: \PersonalLendingPlanItem.debt)
    var planItems: [PersonalLendingPlanItem]

    @Relationship(deleteRule: .cascade, inverse: \PersonalLendingTransaction.debt)
    var transactions: [PersonalLendingTransaction]

    @Relationship(deleteRule: .cascade, inverse: \PersonalLendingAllocation.debt)
    var allocations: [PersonalLendingAllocation]

    init(
        id: UUID = UUID(),
        name: String,
        lenderName: String = "",
        note: String = "",
        principal: Double,
        hasInterest: Bool = false,
        totalInterest: Double = 0,
        startDate: Date = .now,
        endDate: Date? = nil,
        repaymentMethod: String = PersonalLendingRepaymentMethod.noFixedPlan.rawValue,
        monthlyPaymentDay: Int = 1,
        totalPeriods: Int = 1,
        status: String = DebtLifecycleStatus.active.rawValue,
        isValid: Bool = true,
        dataDomain: String = DataIsolationDomain.actual.rawValue
    ) {
        self.id = id
        self.name = name
        self.lenderName = lenderName
        self.note = note
        self.principal = principal
        self.hasInterest = hasInterest
        self.totalInterest = totalInterest
        self.totalAmountDue = principal + totalInterest
        self.paidAmount = 0
        self.remainingAmount = principal + totalInterest
        self.startDate = startDate
        self.endDate = endDate
        self.repaymentMethod = repaymentMethod
        self.monthlyPaymentDay = monthlyPaymentDay
        self.totalPeriods = totalPeriods
        self.status = status
        self.isValid = isValid
        self.dataDomain = dataDomain
        self.pastDueScheduledAmount = 0
        self.pastDuePlanCount = 0
        self.pastDueDebtCount = 0
        self.planItems = []
        self.transactions = []
        self.allocations = []
    }
}

// MARK: - Repayment Plan Item

@Model
final class PersonalLendingPlanItem {
    @Attribute(.unique) var id: UUID
    var sequence: Int
    var dueDate: Date
    var principalDue: Double
    var interestDue: Double
    var totalDue: Double
    var paidAmount: Double
    var remainingAmount: Double
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
        remainingAmount: Double? = nil,
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
        self.remainingAmount = remainingAmount ?? totalDue
        self.state = state
        self.isValid = isValid
        self.debt = debt
    }
}

// MARK: - Payment Transaction

@Model
final class PersonalLendingTransaction {
    @Attribute(.unique) var id: UUID
    /// 还款日期
    var occurredAt: Date
    var amount: Double
    var note: String
    /// 创建时间 – used as secondary sort key during full recalculate
    var createdAt: Date
    var isValid: Bool
    var debt: PersonalLendingDebt?

    init(
        id: UUID = UUID(),
        occurredAt: Date,
        amount: Double,
        note: String = "",
        createdAt: Date = .now,
        isValid: Bool = true,
        debt: PersonalLendingDebt? = nil
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.amount = amount
        self.note = note
        self.createdAt = createdAt
        self.isValid = isValid
        self.debt = debt
    }
}

// MARK: - Lightweight Allocation

/// 轻量分配记录 – records how much of a transaction was applied to a plan item.
/// Only generated when the debt has a repayment plan.
@Model
final class PersonalLendingAllocation {
    @Attribute(.unique) var id: UUID
    var allocatedAmount: Double
    var transaction: PersonalLendingTransaction?
    var planItem: PersonalLendingPlanItem?
    var debt: PersonalLendingDebt?

    init(
        id: UUID = UUID(),
        allocatedAmount: Double,
        transaction: PersonalLendingTransaction? = nil,
        planItem: PersonalLendingPlanItem? = nil,
        debt: PersonalLendingDebt? = nil
    ) {
        self.id = id
        self.allocatedAmount = allocatedAmount
        self.transaction = transaction
        self.planItem = planItem
        self.debt = debt
    }
}
