import Foundation

// MARK: - Statement

/// 账单来源：用户确认的真实账单 vs 系统临时兜底账单
enum StatementSource: String, Codable {
    case userConfirmed
    case fallback
}

/// 账单状态（参见规范第八节还款状态判断表）
enum StatementStatus: String, Codable {
    /// 待还款：paidAmount == 0 且 today <= dueDate
    case pending
    /// 部分还款：0 < paidAmount < statementAmount 且 today <= dueDate
    case partiallyPaid
    /// 全额还款：paidAmount >= statementAmount
    case paid
    /// 结转下期：today > dueDate 且 minimumPayment <= paidAmount < statementAmount
    case carriedForward
    /// 逾期：today > dueDate 且 paidAmount < minimumPayment
    case overdue
    /// 兜底账单已被真实账单替换，仅适用于 fallback 账单
    case replaced
}

// MARK: - RepaymentPlan

/// 还款计划类型：仅支持全额还款计划
enum RepaymentPlanType: String, Codable {
    case fullStatementPayment
}

/// 还款计划来源
enum RepaymentPlanSource: String, Codable {
    case userStatementGenerated
    case fallbackStatementGenerated
}

/// 还款计划状态
enum RepaymentPlanStatus: String, Codable {
    case pending
    case partiallyPaid
    case paid
    case overdue
    case voided
}

// MARK: - OverdueRecord

/// 逾期记录状态
enum OverdueRecordStatus: String, Codable {
    /// 逾期进行中
    case active
    /// 用户手动结束
    case ended
    /// 已被新记录替换（废弃旧记录时使用）
    case replaced
    /// 作废（用户认为原记录有误时使用）
    case voided
}

/// 逾期记录管理模式
enum ManagementMode: String, Codable {
    case system
    case manual
}

// MARK: - CalculationRule

/// 最低还款额来源
enum MinimumPaymentSource: String, Codable {
    case userProvided
    case systemCalculated
}

/// 逾期费用计算方式
enum OverdueFeeType: String, Codable {
    /// 比例费用加最低金额：max(overdueAmount × rate, minimumFee)
    case percentageWithMinimum
    /// 固定费用
    case fixed
    /// 不收取逾期费用
    case none
}

/// 逾期罚息基数类型
enum PenaltyBaseType: String, Codable {
    case unpaidAmount
    case statementAmount
}

/// 循环利息天数计算方式
enum RevolvingInterestDaysType: String, Codable {
    case billingDateToCurrentDate
}

/// 逾期罚息天数计算方式
enum PenaltyDaysType: String, Codable {
    case billingDateToCurrentDate
}

/// 分期计算模式
enum InstallmentCalculationMode: String, Codable {
    /// 等本等息：每期本金、手续费、利息均按总额÷期数
    case equalPrincipalEqualInterest
}

/// 当期消费兜底模式
enum CurrentPurchaseFallbackMode: String, Codable {
    /// 用户未更新账单时当期消费记为 0
    case zero
}

// MARK: - Debt

/// 信用卡债务整体状态
enum CreditCardDebtStatus: String, Codable {
    case active
    case overdue
    case paid
    case closed
}
