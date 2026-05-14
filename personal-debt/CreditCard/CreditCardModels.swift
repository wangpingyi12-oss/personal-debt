import Foundation
import SwiftData

// MARK: - CreditCardCalculationRule (Codable value type)

/// 信用卡计算规则配置（按规范第十四节）。
/// 作为值类型嵌入 CreditCardDebt，避免额外的关系表。
struct CreditCardCalculationRule: Codable {
    // 最低还款
    var minimumPaymentRatio: Double

    // 循环利息
    var revolvingInterestEnabled: Bool
    var revolvingDailyRate: Double
    var revolvingInterestDaysType: RevolvingInterestDaysType

    // 逾期费用
    var overdueFeeType: OverdueFeeType
    var overdueFeeRate: Double
    var minimumOverdueFee: Double
    var fixedOverdueFee: Double?

    // 逾期罚息
    var penaltyBaseType: PenaltyBaseType
    var penaltyDailyRate: Double
    var penaltyDaysType: PenaltyDaysType

    // 分期
    var installmentCalculationMode: InstallmentCalculationMode

    // 兜底
    var currentPurchaseFallbackMode: CurrentPurchaseFallbackMode

    init(
        minimumPaymentRatio: Double = 0.10,
        revolvingInterestEnabled: Bool = true,
        revolvingDailyRate: Double = 0.0005,
        revolvingInterestDaysType: RevolvingInterestDaysType = .billingDateToCurrentDate,
        overdueFeeType: OverdueFeeType = .percentageWithMinimum,
        overdueFeeRate: Double = 0.005,
        minimumOverdueFee: Double = 25,
        fixedOverdueFee: Double? = nil,
        penaltyBaseType: PenaltyBaseType = .unpaidAmount,
        penaltyDailyRate: Double = 0.0005,
        penaltyDaysType: PenaltyDaysType = .billingDateToCurrentDate,
        installmentCalculationMode: InstallmentCalculationMode = .equalPrincipalEqualInterest,
        currentPurchaseFallbackMode: CurrentPurchaseFallbackMode = .zero
    ) {
        self.minimumPaymentRatio = minimumPaymentRatio
        self.revolvingInterestEnabled = revolvingInterestEnabled
        self.revolvingDailyRate = revolvingDailyRate
        self.revolvingInterestDaysType = revolvingInterestDaysType
        self.overdueFeeType = overdueFeeType
        self.overdueFeeRate = overdueFeeRate
        self.minimumOverdueFee = minimumOverdueFee
        self.fixedOverdueFee = fixedOverdueFee
        self.penaltyBaseType = penaltyBaseType
        self.penaltyDailyRate = penaltyDailyRate
        self.penaltyDaysType = penaltyDaysType
        self.installmentCalculationMode = installmentCalculationMode
        self.currentPurchaseFallbackMode = currentPurchaseFallbackMode
    }
}

// MARK: - CreditCardStatementBreakdown (Codable value type)

/// 账单明细统计（按规范第三节 CreditCardStatementBreakdown 职责）。
/// 用于消费分析，不反推账单主金额。
struct CreditCardStatementBreakdown: Codable {
    /// 当期消费金额
    var currentPurchaseAmount: Double
    /// 上期未还金额（滚入本期普通账单）
    var previousUnpaidAmount: Double
    /// 循环利息
    var revolvingInterest: Double
    /// 逾期费用（由上期逾期产生）
    var overdueFee: Double
    /// 罚息
    var penaltyInterest: Double
    /// 本期分期本金
    var currentInstallmentPrincipal: Double
    /// 本期分期手续费
    var currentInstallmentFee: Double
    /// 本期分期利息
    var currentInstallmentInterest: Double

    init(
        currentPurchaseAmount: Double = 0,
        previousUnpaidAmount: Double = 0,
        revolvingInterest: Double = 0,
        overdueFee: Double = 0,
        penaltyInterest: Double = 0,
        currentInstallmentPrincipal: Double = 0,
        currentInstallmentFee: Double = 0,
        currentInstallmentInterest: Double = 0
    ) {
        self.currentPurchaseAmount = currentPurchaseAmount
        self.previousUnpaidAmount = previousUnpaidAmount
        self.revolvingInterest = revolvingInterest
        self.overdueFee = overdueFee
        self.penaltyInterest = penaltyInterest
        self.currentInstallmentPrincipal = currentInstallmentPrincipal
        self.currentInstallmentFee = currentInstallmentFee
        self.currentInstallmentInterest = currentInstallmentInterest
    }
}

// MARK: - CreditCardDebt

/// 信用卡债务长期信息（按规范第三节 CreditCardDebt 职责边界）。
/// 不保存每期账单金额、最低还款额、逾期金额、罚息或普通消费。
@Model
final class CreditCardDebt {
    var id: UUID
    var cardName: String
    var bankName: String
    /// 账单日（1–31）
    var billingDay: Int
    /// 还款日（1–31）
    var dueDay: Int
    var currency: String
    var creditLimit: Double
    var status: CreditCardDebtStatus
    /// 计算规则配置，允许用户自定义
    var calculationRule: CreditCardCalculationRule
    var isActive: Bool
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \CreditCardStatement.debt)
    var statements: [CreditCardStatement]

    @Relationship(deleteRule: .cascade, inverse: \CreditCardInstallmentPlan.debt)
    var installmentPlans: [CreditCardInstallmentPlan]

    init(
        id: UUID = UUID(),
        cardName: String,
        bankName: String,
        billingDay: Int,
        dueDay: Int,
        currency: String = "CNY",
        creditLimit: Double,
        status: CreditCardDebtStatus = .active,
        calculationRule: CreditCardCalculationRule = CreditCardCalculationRule(),
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.cardName = cardName
        self.bankName = bankName
        self.billingDay = billingDay
        self.dueDay = dueDay
        self.currency = currency
        self.creditLimit = creditLimit
        self.status = status
        self.calculationRule = calculationRule
        self.isActive = isActive
        self.createdAt = createdAt
        self.statements = []
        self.installmentPlans = []
    }
}

// MARK: - CreditCardStatement

/// 每期信用卡账单主账（按规范第三节 CreditCardStatement 职责边界）。
/// 是还款计划、流水、逾期判断的事实来源。
@Model
final class CreditCardStatement {
    var id: UUID
    var debt: CreditCardDebt?

    // 账期
    var billingDate: Date
    var dueDate: Date

    // 账单金额（规范第四节）
    /// 账单总金额 = normalAmount + installmentAmount
    var statementAmount: Double
    /// 普通账单金额（消费+上期未还+费用+利息）
    var normalAmount: Double
    /// 分期账单金额（本期分期本金+手续费+利息）
    var installmentAmount: Double

    // 最低还款额（规范第五节）
    var minimumPaymentAmount: Double
    var minimumPaymentSource: MinimumPaymentSource

    // 还款汇总（由重算服务维护）
    var paidAmount: Double
    var remainingAmount: Double

    // 状态与来源
    var status: StatementStatus
    var source: StatementSource
    var isActive: Bool

    // 账单明细统计（分析用，不反推主金额）
    var breakdown: CreditCardStatementBreakdown?

    // 用户手动数据标记
    var isUserEdited: Bool
    var userEditedAt: Date?
    var userNote: String?
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \CreditCardRepaymentPlan.statement)
    var repaymentPlan: CreditCardRepaymentPlan?

    @Relationship(deleteRule: .cascade, inverse: \CreditCardPaymentRecord.statement)
    var paymentRecords: [CreditCardPaymentRecord]

    @Relationship(deleteRule: .cascade, inverse: \CreditCardOverdueRecord.statement)
    var overdueRecords: [CreditCardOverdueRecord]

    init(
        id: UUID = UUID(),
        billingDate: Date,
        dueDate: Date,
        statementAmount: Double,
        normalAmount: Double,
        installmentAmount: Double,
        minimumPaymentAmount: Double,
        minimumPaymentSource: MinimumPaymentSource = .systemCalculated,
        paidAmount: Double = 0,
        remainingAmount: Double? = nil,
        status: StatementStatus = .pending,
        source: StatementSource,
        isActive: Bool = true,
        breakdown: CreditCardStatementBreakdown? = nil,
        isUserEdited: Bool = false,
        userEditedAt: Date? = nil,
        userNote: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.billingDate = billingDate
        self.dueDate = dueDate
        self.statementAmount = statementAmount
        self.normalAmount = normalAmount
        self.installmentAmount = installmentAmount
        self.minimumPaymentAmount = minimumPaymentAmount
        self.minimumPaymentSource = minimumPaymentSource
        self.paidAmount = paidAmount
        self.remainingAmount = remainingAmount ?? max(statementAmount - paidAmount, 0)
        self.status = status
        self.source = source
        self.isActive = isActive
        self.breakdown = breakdown
        self.isUserEdited = isUserEdited
        self.userEditedAt = userEditedAt
        self.userNote = userNote
        self.createdAt = createdAt
        self.paymentRecords = []
        self.overdueRecords = []
    }
}

// MARK: - CreditCardRepaymentPlan

/// 每期账单的全额还款计划（按规范第三节 CreditCardRepaymentPlan 职责边界）。
/// 每期账单只生成一条，计划金额等于账单总额。
@Model
final class CreditCardRepaymentPlan {
    var id: UUID
    var statement: CreditCardStatement?

    var planAmount: Double
    var dueDate: Date
    var planType: RepaymentPlanType
    var source: RepaymentPlanSource
    var status: RepaymentPlanStatus

    // 与账单还款状态保持同步（由重算服务维护）
    var paidAmount: Double
    var remainingAmount: Double

    var isActive: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        planAmount: Double,
        dueDate: Date,
        planType: RepaymentPlanType = .fullStatementPayment,
        source: RepaymentPlanSource,
        status: RepaymentPlanStatus = .pending,
        paidAmount: Double = 0,
        remainingAmount: Double? = nil,
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.planAmount = planAmount
        self.dueDate = dueDate
        self.planType = planType
        self.source = source
        self.status = status
        self.paidAmount = paidAmount
        self.remainingAmount = remainingAmount ?? max(planAmount - paidAmount, 0)
        self.isActive = isActive
        self.createdAt = createdAt
    }
}

// MARK: - CreditCardPaymentRecord

/// 用户真实还款流水（按规范第三节 CreditCardPaymentRecord 职责边界）。
/// 只冲减账单总额，不拆分到消费、利息、分期或逾期费用。
@Model
final class CreditCardPaymentRecord {
    var id: UUID
    var statement: CreditCardStatement?
    var repaymentPlan: CreditCardRepaymentPlan?

    var amount: Double
    var paymentDate: Date

    /// 软删除标记；isActive = false 表示该流水已被删除
    var isActive: Bool

    // 用户手动数据标记
    var isUserEdited: Bool
    var userEditedAt: Date?
    var userNote: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        amount: Double,
        paymentDate: Date,
        isActive: Bool = true,
        isUserEdited: Bool = true,
        userEditedAt: Date? = nil,
        userNote: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.amount = amount
        self.paymentDate = paymentDate
        self.isActive = isActive
        self.isUserEdited = isUserEdited
        self.userEditedAt = userEditedAt
        self.userNote = userNote
        self.createdAt = createdAt
    }
}

// MARK: - CreditCardOverdueRecord

/// 某一期账单的逾期事实记录（按规范第三节 CreditCardOverdueRecord 职责边界）。
/// 不反向改写当前账单金额。
@Model
final class CreditCardOverdueRecord {
    var id: UUID
    var statement: CreditCardStatement?

    /// 逾期金额 = 账单金额 - 已还金额（规范第十节）
    var overdueAmount: Double
    var overdueFee: Double
    var penaltyInterest: Double

    var startDate: Date
    var endDate: Date?

    var status: OverdueRecordStatus
    var isActive: Bool
    var managementMode: ManagementMode

    // 用户手动数据标记（规范第十一节）
    var isUserEdited: Bool
    var userEditedAt: Date?
    var userNote: String?

    // 系统参考值（只用于提示，不覆盖用户手动值）
    var systemCalculatedOverdueAmount: Double?
    var systemCalculatedOverdueFee: Double?
    var systemCalculatedPenaltyInterest: Double?

    var createdAt: Date

    init(
        id: UUID = UUID(),
        overdueAmount: Double,
        overdueFee: Double,
        penaltyInterest: Double,
        startDate: Date,
        endDate: Date? = nil,
        status: OverdueRecordStatus = .active,
        isActive: Bool = true,
        managementMode: ManagementMode,
        isUserEdited: Bool = false,
        userEditedAt: Date? = nil,
        userNote: String? = nil,
        systemCalculatedOverdueAmount: Double? = nil,
        systemCalculatedOverdueFee: Double? = nil,
        systemCalculatedPenaltyInterest: Double? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.overdueAmount = overdueAmount
        self.overdueFee = overdueFee
        self.penaltyInterest = penaltyInterest
        self.startDate = startDate
        self.endDate = endDate
        self.status = status
        self.isActive = isActive
        self.managementMode = managementMode
        self.isUserEdited = isUserEdited
        self.userEditedAt = userEditedAt
        self.userNote = userNote
        self.systemCalculatedOverdueAmount = systemCalculatedOverdueAmount
        self.systemCalculatedOverdueFee = systemCalculatedOverdueFee
        self.systemCalculatedPenaltyInterest = systemCalculatedPenaltyInterest
        self.createdAt = createdAt
    }
}

// MARK: - CreditCardInstallmentPlan

/// 信用卡分期计划（按规范第三节 CreditCardInstallmentPlan 职责边界）。
/// 等本等息分期，每期本金/手续费/利息按总额÷期数计算。
@Model
final class CreditCardInstallmentPlan {
    var id: UUID
    var debt: CreditCardDebt?

    var totalPrincipal: Double
    var totalFee: Double
    var totalInterest: Double
    var totalPeriods: Int
    var startBillingDate: Date

    /// 等本等息：每期本金
    var perPeriodPrincipal: Double
    /// 等本等息：每期手续费
    var perPeriodFee: Double
    /// 等本等息：每期利息
    var perPeriodInterest: Double

    var isActive: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        totalPrincipal: Double,
        totalFee: Double,
        totalInterest: Double,
        totalPeriods: Int,
        startBillingDate: Date,
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.totalPrincipal = totalPrincipal
        self.totalFee = totalFee
        self.totalInterest = totalInterest
        self.totalPeriods = totalPeriods
        self.startBillingDate = startBillingDate
        let periods = max(totalPeriods, 1)
        self.perPeriodPrincipal = totalPrincipal / Double(periods)
        self.perPeriodFee = totalFee / Double(periods)
        self.perPeriodInterest = totalInterest / Double(periods)
        self.isActive = isActive
        self.createdAt = createdAt
    }
}
