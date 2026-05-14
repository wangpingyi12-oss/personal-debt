import Foundation

/// 单期还款计划。
///
/// ## 锁定语义
/// `isLocked` 只锁定计划事实字段，防止还款流水、逾期记录或每日触发器污染原始计划。
/// 执行状态字段（`paidXXX`、`remainingXXX`、`status` 等）始终可以由当前
/// `LoanPaymentAllocationDetail` 重建，不受锁定影响。
///
/// 只要存在任意 `isLocked == true` 的计划，首版不允许重新生成还款计划。
///
/// ## 期日计算规则
/// - 第一期 `periodStartDate` = `planGenerationStartDate`
/// - 每期 `periodEndDate` = 本期 `dueDate`
/// - 第二期以后 `periodStartDate` = 上一期 `periodEndDate`
/// - 若结束日不等于还款日，追加 `finalPartialPeriod`：`dueDate` 和 `periodEndDate` 均等于 `endDate`
/// - 若无法生成任何标准还款日，生成 `shortTermSinglePeriod`，起止日期分别为
///   `planGenerationStartDate` 和 `endDate`
struct LoanRepaymentPlan: Identifiable, Codable {

    // MARK: Identity

    let id: UUID
    var loanDebtId: UUID

    // MARK: - Plan Fact Fields（锁定后禁止修改）

    /// 期次索引，从 0 开始。
    var periodIndex: Int

    /// 期类型。
    var periodType: LoanRepaymentPlanPeriodType

    /// 本期开始日期。
    var periodStartDate: Date

    /// 本期结束日期（等于本期 `dueDate`，尾期等于 `endDate`）。
    var periodEndDate: Date

    /// 本期应还款日。
    var dueDate: Date

    /// 本期计划本金。
    var scheduledPrincipal: Decimal

    /// 本期计划利息。
    var scheduledInterest: Decimal

    /// 本期计划应还合计 = `scheduledPrincipal` + `scheduledInterest`。
    var scheduledTotalAmount: Decimal

    /// 本期还款前剩余本金快照。
    var remainingPrincipalBeforePayment: Decimal

    /// 按计划还款后剩余本金快照。
    var remainingPrincipalAfterScheduledPayment: Decimal

    /// 计划是否已锁定。锁定后只有执行状态字段可以更新。
    var isLocked: Bool

    /// 锁定原因描述。
    var lockReason: String?

    // MARK: - Execution State Fields（由 LoanPaymentAllocationDetail 重建）

    /// 已还本金。
    var paidPrincipal: Decimal

    /// 已还利息。
    var paidInterest: Decimal

    /// 已还逾期费用。
    var paidOverdueFee: Decimal

    /// 已还逾期罚息。
    var paidPenaltyInterest: Decimal

    /// 已还合计。
    var paidTotalAmount: Decimal

    /// 剩余未还本金。
    var remainingPrincipal: Decimal

    /// 剩余未还利息。
    var remainingInterest: Decimal

    /// 剩余未还逾期费用。
    var remainingOverdueFee: Decimal

    /// 剩余未还逾期罚息。
    var remainingPenaltyInterest: Decimal

    /// 剩余未还合计。
    var remainingTotalAmount: Decimal

    /// 逾期开始日期。
    var overdueStartDate: Date?

    /// 累计逾期天数。
    var overdueDays: Int

    /// 本期状态。
    var status: LoanRepaymentPlanStatus

    /// 最后更新时间。
    var updatedAt: Date
}
