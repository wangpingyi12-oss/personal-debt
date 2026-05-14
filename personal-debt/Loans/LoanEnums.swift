import Foundation

// MARK: - Entry Mode

/// 贷款录入模式：区分"从合同开始管理的新贷款"与"已发生一段时间后才录入 App 的进行中贷款"。
enum LoanEntryMode: String, Codable, CaseIterable, Identifiable {
    /// 从贷款合同开始日期 startDate 开始管理。
    case newLoan
    /// 从 managementStartDate 开始管理，不生成历史计划和历史流水。
    case inProgressLoan

    var id: String { rawValue }
}

// MARK: - Repayment Method

/// 还款方式。
enum LoanRepaymentMethod: String, Codable, CaseIterable, Identifiable {
    /// 等额本息：每期月供固定，按 App 当前剩余计划期数计算。
    case equalInstallment
    /// 等额本金：每期固定本金，按 App 当前 regularTermCount 计算；尾期结清剩余本金。
    case equalPrincipal
    /// 先息后本：前 N-1 期只还利息，最后一期归还剩余本金。
    case interestFirst
    /// 到期还本付息：一次性归还全部本金和累计利息。
    case bulletRepayment

    var id: String { rawValue }
}

// MARK: - Penalty Base Type

/// 逾期罚息基数类型。
///
/// - `unpaidPrincipal`：罚息基数为未还本金（`outstandingPrincipal`）。
/// - `unpaidAmount`：罚息基数为未还本金加未还原计划利息。
///
/// 罚息基数不包含逾期费用、既有罚息或手续费。
enum LoanPenaltyBaseType: String, Codable, CaseIterable, Identifiable {
    case unpaidPrincipal
    case unpaidAmount

    var id: String { rawValue }
}

// MARK: - Penalty Calculation Mode

/// 逾期罚息计算模式。当前只支持 `simpleDynamic`。
///
/// 罚息公式：`penaltyInterest = penaltyBase × penaltyDailyRate × overdueDays`。
/// 不使用复利，不做费用滚费用。
enum LoanPenaltyCalculationMode: String, Codable, CaseIterable, Identifiable {
    /// 简单动态：罚息 = 基数 × 日罚息率 × 逾期天数。
    case simpleDynamic

    var id: String { rawValue }
}

// MARK: - Repayment Plan Period Type

/// 还款计划期类型。
enum LoanRepaymentPlanPeriodType: String, Codable, CaseIterable, Identifiable {
    /// 标准还款期。
    case standard
    /// 结束日不等于还款日时追加的尾期，`dueDate` 和 `periodEndDate` 均等于 `endDate`。
    case finalPartialPeriod
    /// 从 `planGenerationStartDate` 到 `endDate` 无法生成任何标准还款日时生成的单期。
    case shortTermSinglePeriod

    var id: String { rawValue }
}

// MARK: - Repayment Plan Status

/// 还款计划单期状态。
enum LoanRepaymentPlanStatus: String, Codable, CaseIterable, Identifiable {
    /// 未到期。
    case scheduled
    /// 已到期，待还款。
    case due
    /// 逾期中。
    case overdue
    /// 部分已还。
    case partiallyPaid
    /// 已还清。
    case paid

    var id: String { rawValue }
}

// MARK: - Loan Debt Status

/// 贷款整体状态。
///
/// `paidOff` 条件：`outstandingPrincipal == 0`，所有 `LoanRepaymentPlan.status == .paid`，
/// 且所有 `LoanOverdueRecord.status` 属于 `.paid`、`.waived` 或 `.closed`。
/// `unappliedPaymentBalance > 0` 不阻止变为 `paidOff`。
enum LoanDebtStatus: String, Codable, CaseIterable, Identifiable {
    /// 进行中。
    case active
    /// 已结清。
    case paidOff

    var id: String { rawValue }
}

// MARK: - Overdue Record Source

/// 逾期记录来源。`imported` 已移除。
enum LoanOverdueRecordSource: String, Codable, CaseIterable, Identifiable {
    /// 系统每日触发器自动生成。
    case systemGenerated
    /// 用户手动指定最早逾期期数，金额仍由系统规则计算。
    case userCreated
    /// 用户手动修改了逾期天数、逾期费用或逾期罚息，用户输入覆盖系统数据。
    case userAdjusted

    var id: String { rawValue }
}

// MARK: - Overdue Record Status

/// 逾期记录整体闭环状态。
///
/// - `paid`：该期原计划本金、原计划利息、逾期费用、逾期罚息均已处理完成。
/// - `waived`：逾期费用或罚息有减免，且该期原计划本金和利息也已处理完成。
/// - `closed`：用户主动关闭逾期记录。若该期本金或利息仍未还清，还款计划不能变为 `paid`。
enum LoanOverdueRecordStatus: String, Codable, CaseIterable, Identifiable {
    case paid
    case waived
    case closed

    var id: String { rawValue }
}
