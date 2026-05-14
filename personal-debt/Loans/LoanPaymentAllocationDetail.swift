import Foundation

/// 系统自动分配的还款明细记录。
///
/// 每条 `LoanPaymentRecord` 对应一组 `LoanPaymentAllocationDetail`，
/// 记录该笔流水分配到哪些计划期的哪些科目。
///
/// ## 分配顺序
/// 1. 优先处理所有未结清逾期计划，按逾期时间从早到晚排序；
///    若逾期时间相同，则按 `dueDate` 和 `periodIndex` 兜底排序。
/// 2. 单期内部分配顺序：逾期费用 → 逾期罚息 → 逾期本金 → 原计划未还利息 → 原计划未还本金。
/// 3. 非逾期计划只执行原计划未还利息和原计划未还本金。
///
/// ## 超额还款
/// 当 `totalAvailableAmount > currentDuePayableAmount` 时，系统暂停自动分配并询问用户。
/// 用户可选择保留为未分配余额，或冲抵未来本金（按 `dueDate` 从早到晚分配 `futurePrincipal`）。
/// 首版 `recalculateFutureInterestAfterOverpayment` 固定为 `false`，不自动重算未来利息。
///
/// ## 快照重建
/// `LoanRepaymentPlan.paidXXX` 是状态快照，必须由当前存在的
/// `LoanPaymentAllocationDetail` 重建，而非独立存储。
struct LoanPaymentAllocationDetail: Identifiable, Codable {

    // MARK: Identity

    let id: UUID

    /// 关联的还款流水 ID。
    var paymentRecordId: UUID

    /// 关联的贷款 ID。
    var loanDebtId: UUID

    /// 关联的还款计划期 ID；`nil` 表示该笔分配为未分配余额。
    var repaymentPlanId: UUID?

    // MARK: Allocation Amounts

    /// 本次分配的逾期费用金额。
    var allocatedOverdueFee: Decimal

    /// 本次分配的逾期罚息金额。
    var allocatedPenaltyInterest: Decimal

    /// 本次分配的本金金额。
    var allocatedPrincipal: Decimal

    /// 本次分配的利息金额。
    var allocatedInterest: Decimal

    /// 本次分配的合计金额。
    var allocatedTotal: Decimal

    /// 是否为未分配余额记录。
    var isUnappliedBalance: Bool

    // MARK: Timestamps

    var createdAt: Date
}
