import Foundation

/// 用户手动录入的还款流水。
///
/// 流水只是用户录入的还款事实：
/// - 不保留状态字段。
/// - 不保留软删除。
/// - 不保留修改历史。
/// - 修改时直接覆盖，删除时直接移除。
/// - 不绑定具体还款计划（绑定关系由 `LoanPaymentAllocationDetail` 记录）。
///
/// 用户录入时只需提供 `paymentDate`、`totalAmount` 和备注；
/// 系统先刷新 `paymentDate` 当天的逾期状态，再执行自动分配。
struct LoanPaymentRecord: Identifiable, Codable {

    // MARK: Identity

    let id: UUID
    var loanDebtId: UUID

    // MARK: Payment Info

    /// 还款日期。
    var paymentDate: Date

    /// 本次还款总金额。
    var totalAmount: Decimal

    /// 备注。
    var note: String?

    // MARK: Timestamps

    var createdAt: Date
    var updatedAt: Date
}
