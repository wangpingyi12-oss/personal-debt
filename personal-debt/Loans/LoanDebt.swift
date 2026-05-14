import Foundation

/// 贷款主体。
///
/// ## 录入模式与本金口径
/// - `entryMode == .newLoan`：从合同 `startDate` 开始管理；
///   `openingPrincipalForManagement == originalPrincipal`。
/// - `entryMode == .inProgressLoan`：从 `managementStartDate` 开始管理，不生成历史计划；
///   `openingPrincipalForManagement` 为用户录入的当前剩余本金。
///
/// ## 期数口径
/// `termCount` 只表示 App 当前实际生成的还款计划数量，不表示合同总期数。
/// 进行中贷款只生成 `managementStartDate` 之后的未来计划，因此 `termCount` 不含历史期数。
///
/// ## 结清与未分配余额
/// `status == .paidOff` 与 `unappliedPaymentBalance > 0` 可以同时成立。
/// 贷款已结清但存在未分配余额时，UI 应单独提示用户处理。
struct LoanDebt: Identifiable, Codable {

    // MARK: Identity

    let id: UUID
    var name: String
    var note: String?

    // MARK: Entry Mode

    /// 录入模式，决定计划生成起点和本金基数，不可通过日期隐式推断。
    var entryMode: LoanEntryMode

    // MARK: Dates

    /// 贷款合同开始日期，永远表示合同签订起始日，不作为 App 管理开始日期。
    var startDate: Date

    /// App 内开始管理该贷款的日期，仅 `inProgressLoan` 必填。
    var managementStartDate: Date?

    /// 贷款合同结束日期。
    var endDate: Date

    // MARK: Principal

    /// 合同原始本金，用于记录和展示，不直接参与 App 内计划计算。
    var originalPrincipal: Decimal

    /// App 开始管理时的本金基数，用于生成当前 App 内还款计划。
    ///
    /// - `newLoan`：录入时必须等于 `originalPrincipal`，由调用方在创建时保证。
    /// - `inProgressLoan`：为用户录入的当前剩余本金，与 `originalPrincipal` 无强制关联。
    var openingPrincipalForManagement: Decimal

    /// 当前实时剩余本金 = `openingPrincipalForManagement` - 管理期内已还本金合计。
    /// 不能使用 `originalPrincipal` - 已还本金。
    var outstandingPrincipal: Decimal

    // MARK: Repayment Terms

    /// App 当前实际生成的还款计划期数（不含历史期数）。
    var termCount: Int

    /// 标准还款期数（不含尾期），用于等额本金每期固定本金计算。
    var regularTermCount: Int

    /// 还款方式。
    var repaymentMethod: LoanRepaymentMethod

    /// 合同年利率。
    var annualInterestRate: Decimal

    // MARK: Penalty

    /// 逾期罚息基数类型。
    var penaltyBaseType: LoanPenaltyBaseType

    /// 逾期罚息计算模式，当前只支持 `simpleDynamic`。
    var penaltyCalculationMode: LoanPenaltyCalculationMode

    /// 日罚息率，用于公式：`penaltyInterest = penaltyBase × penaltyDailyRate × overdueDays`。
    var penaltyDailyRate: Decimal

    // MARK: Overpayment

    /// 未分配余额，不是债务余额，而是资金分配状态。
    /// `unappliedPaymentBalance > 0` 不阻止 `status` 变为 `.paidOff`。
    var unappliedPaymentBalance: Decimal

    /// 超额还款后是否自动重算未来利息；首版固定为 `false`。
    var recalculateFutureInterestAfterOverpayment: Bool

    // MARK: Status

    var status: LoanDebtStatus

    // MARK: Timestamps

    var createdAt: Date
    var updatedAt: Date

    // MARK: Computed

    /// App 计划生成起始日期：`newLoan` 使用 `startDate`；`inProgressLoan` 使用 `managementStartDate`。
    ///
    /// - Precondition: `inProgressLoan` 类型的贷款必须设置 `managementStartDate`。
    var planGenerationStartDate: Date {
        switch entryMode {
        case .newLoan:
            return startDate
        case .inProgressLoan:
            guard let managementStartDate else {
                preconditionFailure("inProgressLoan 必须提供 managementStartDate")
            }
            return managementStartDate
        }
    }
}
