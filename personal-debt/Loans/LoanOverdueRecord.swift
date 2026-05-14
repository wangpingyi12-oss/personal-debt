import Foundation

/// 单期逾期记录。
///
/// ## 生成来源
/// - 系统每日触发器自动生成：`source = .systemGenerated`。
/// - 用户手动指定最早逾期期数，系统从该期扫描后续已到期未结清计划：
///   `source = .userCreated`，`isUserManaged = false`，金额仍由系统规则计算。
/// - 用户手动修改逾期天数、逾期费用或逾期罚息：`source = .userAdjusted`，
///   `isUserManaged = true`，用户输入覆盖系统数据。
///
/// ## 自动更新规则
/// `isUserManaged == true` 后，每日触发器不再覆盖该条记录的金额和天数。
///
/// ## 状态（整体闭环）
/// `status` 表示该期逾期事件是否整体闭环，不只是逾期费用或罚息是否结清：
/// - `.paid`：该期原计划本金、原计划利息、逾期费用、逾期罚息均已处理完成。
/// - `.waived`：逾期费用或罚息有减免，且该期原计划本金和利息也已处理完成。
/// - `.closed`：用户主动关闭逾期记录。若该期本金或利息仍未还清，还款计划不能变为 `paid`。
///
/// ## 罚息公式
/// `penaltyInterest = penaltyBase × penaltyDailyRate × overdueDays`
/// 不使用复利，罚息基数不包含逾期费用、既有罚息或手续费。
struct LoanOverdueRecord: Identifiable, Codable {

    // MARK: Identity

    let id: UUID

    /// 关联的贷款 ID。
    var loanDebtId: UUID

    /// 关联的还款计划期 ID。
    var repaymentPlanId: UUID

    // MARK: Source & Management

    /// 逾期记录来源。
    var source: LoanOverdueRecordSource

    /// 用户是否手动管理该条记录。
    /// `true` 后，每日触发器不再自动覆盖金额和天数。
    var isUserManaged: Bool

    // MARK: Overdue Details

    /// 逾期开始日期。
    var overdueStartDate: Date

    /// 逾期天数。
    var overdueDays: Int

    /// 逾期费用（固定费用，不参与罚息基数）。
    var overdueFee: Decimal

    /// 逾期罚息金额（由公式计算或用户覆盖）。
    var penaltyInterest: Decimal

    /// 罚息基数快照（计算时所用的基数值）。
    var penaltyBase: Decimal

    /// 日罚息率快照（计算时所用的日罚息率）。
    var penaltyDailyRate: Decimal

    // MARK: Status

    /// 逾期事件整体闭环状态。
    var status: LoanOverdueRecordStatus

    // MARK: Timestamps

    var createdAt: Date
    var updatedAt: Date
}
