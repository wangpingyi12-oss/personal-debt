import Foundation

// MARK: - CreditCardCalculationService

/// 信用卡计算服务（规范第十七节"建议封装为统一重算服务"）。
///
/// 所有纯计算函数为 `static`，不依赖持久化模型，便于单元测试。
/// 模型级操作（重算账单状态、生成兜底账单等）需传入 SwiftData 模型实例。
enum CreditCardCalculationService {

    // MARK: - Pure Calculation Functions

    /// 计算两个日期之间的天数差（向下取整，start → end）
    static func daysBetween(_ start: Date, _ end: Date) -> Int {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let components = calendar.dateComponents([.day], from: startDay, to: endDay)
        return max(components.day ?? 0, 0)
    }

    /// 计算最低还款额（规范第五节）
    ///
    /// - 如果用户已提供真实最低还款额，调用方直接使用用户值，不调用本函数。
    /// - 本函数只在 `minimumPaymentSource == .systemCalculated` 时使用。
    static func calculateSystemMinimumPayment(
        normalAmount: Double,
        installmentAmount: Double,
        rule: CreditCardCalculationRule
    ) -> Double {
        installmentAmount + normalAmount * rule.minimumPaymentRatio
    }

    /// 判断账单还款状态（规范第八节还款状态判断表）
    static func determineStatementStatus(
        statementAmount: Double,
        minimumPaymentAmount: Double,
        paidAmount: Double,
        dueDate: Date,
        today: Date
    ) -> StatementStatus {
        if paidAmount >= statementAmount {
            return .paid
        }
        let pastDue = today > dueDate
        if !pastDue {
            return paidAmount > 0 ? .partiallyPaid : .pending
        }
        // today > dueDate
        if paidAmount >= minimumPaymentAmount {
            return .carriedForward
        }
        return .overdue
    }

    /// 将还款状态映射为还款计划状态
    static func repaymentPlanStatus(from statementStatus: StatementStatus) -> RepaymentPlanStatus {
        switch statementStatus {
        case .pending:        return .pending
        case .partiallyPaid:  return .partiallyPaid
        case .paid:           return .paid
        case .carriedForward: return .partiallyPaid
        case .overdue:        return .overdue
        case .replaced:       return .voided
        }
    }

    /// 计算循环利息（规范第九节）
    ///
    /// 循环利息 = 未还金额 × 循环日利率 × 天数
    /// 天数 = billingDate → today（兜底账单使用上期账单日到本期账单日）
    static func calculateRevolvingInterest(
        unpaidAmount: Double,
        rule: CreditCardCalculationRule,
        billingDate: Date,
        today: Date
    ) -> Double {
        guard rule.revolvingInterestEnabled, unpaidAmount > 0 else { return 0 }
        let days = daysBetween(billingDate, today)
        return unpaidAmount * rule.revolvingDailyRate * Double(days)
    }

    /// 计算逾期费用（规范第十节）
    ///
    /// - `.percentageWithMinimum`：max(overdueAmount × rate, minimumFee)
    /// - `.fixed`：使用 `fixedOverdueFee`（未设置时退化为 0）
    /// - `.none`：0
    static func calculateOverdueFee(
        overdueAmount: Double,
        rule: CreditCardCalculationRule
    ) -> Double {
        switch rule.overdueFeeType {
        case .percentageWithMinimum:
            return max(overdueAmount * rule.overdueFeeRate, rule.minimumOverdueFee)
        case .fixed:
            return rule.fixedOverdueFee ?? 0
        case .none:
            return 0
        }
    }

    /// 计算逾期罚息（规范第十节）
    ///
    /// 罚息 = base × 罚息日利率 × 逾期天数
    /// 逾期天数 = billingDate → today（兜底账单使用账单日到本期账单日）
    static func calculatePenaltyInterest(
        base: Double,
        rule: CreditCardCalculationRule,
        billingDate: Date,
        today: Date
    ) -> Double {
        guard base > 0 else { return 0 }
        let days = daysBetween(billingDate, today)
        return base * rule.penaltyDailyRate * Double(days)
    }

    /// 根据罚息基数类型选择实际基数（规范第十节）
    static func penaltyBase(
        unpaidAmount: Double,
        statementAmount: Double,
        rule: CreditCardCalculationRule
    ) -> Double {
        switch rule.penaltyBaseType {
        case .unpaidAmount:    return unpaidAmount
        case .statementAmount: return statementAmount
        }
    }

    // MARK: - Fallback Statement Generation

    /// 计算兜底账单金额（规范第十三节）
    ///
    /// 普通兜底金额 = 当期消费（0） + 上期未还金额 + 逾期费用 + 罚息或利息
    /// 兜底账单金额 = 普通兜底金额 + 本期分期账单金额
    static func calculateFallbackStatementAmount(
        previousUnpaidAmount: Double,
        overdueFee: Double,
        interestOrPenalty: Double,
        currentInstallmentAmount: Double
    ) -> Double {
        let normalFallback = previousUnpaidAmount + overdueFee + interestOrPenalty
        return normalFallback + currentInstallmentAmount
    }

    /// 计算兜底最低还款额（规范第十三节）
    ///
    /// 兜底最低 = 分期账单金额 + 普通兜底金额 × 最低还款比例
    static func calculateFallbackMinimumPayment(
        fallbackNormalAmount: Double,
        installmentAmount: Double,
        rule: CreditCardCalculationRule
    ) -> Double {
        installmentAmount + fallbackNormalAmount * rule.minimumPaymentRatio
    }

    // MARK: - Model-Level Operations

    /// 汇总账单下所有有效还款流水，更新 paidAmount 和 remainingAmount（规范第七节）
    static func aggregatePayments(for statement: CreditCardStatement) {
        let paid = statement.paymentRecords
            .filter(\.isActive)
            .reduce(0) { $0 + $1.amount }
        statement.paidAmount = paid
        statement.remainingAmount = max(statement.statementAmount - paid, 0)
    }

    /// 统一重算单期账单所有状态（规范第十七节"封装为统一的重算服务"）
    ///
    /// 调用时机：新增/修改/删除还款流水、真实账单替换兜底账单、手动结束逾期后。
    static func recalculate(statement: CreditCardStatement, today: Date = Date()) {
        aggregatePayments(for: statement)

        let newStatus = determineStatementStatus(
            statementAmount: statement.statementAmount,
            minimumPaymentAmount: statement.minimumPaymentAmount,
            paidAmount: statement.paidAmount,
            dueDate: statement.dueDate,
            today: today
        )
        statement.status = newStatus

        // 同步更新还款计划状态与金额
        if let plan = statement.repaymentPlan {
            plan.paidAmount = statement.paidAmount
            plan.remainingAmount = statement.remainingAmount
            plan.status = repaymentPlanStatus(from: newStatus)
        }

        // 同步更新逾期记录中的系统参考值（不覆盖用户手动值）
        if let overdueRecord = statement.overdueRecords.first(where: { $0.status != .voided }) {
            let rule = statement.debt?.calculationRule ?? CreditCardCalculationRule()
            let sysOverdueAmount = max(statement.statementAmount - statement.paidAmount, 0)
            let sysOverdueFee = calculateOverdueFee(overdueAmount: sysOverdueAmount, rule: rule)
            let base = penaltyBase(
                unpaidAmount: sysOverdueAmount,
                statementAmount: statement.statementAmount,
                rule: rule
            )
            let sysPenalty = calculatePenaltyInterest(
                base: base,
                rule: rule,
                billingDate: statement.billingDate,
                today: today
            )
            overdueRecord.systemCalculatedOverdueAmount = sysOverdueAmount
            overdueRecord.systemCalculatedOverdueFee = sysOverdueFee
            overdueRecord.systemCalculatedPenaltyInterest = sysPenalty
        }
    }

    /// 重算债务整体状态（规范第十五节）
    ///
    /// 只要有一期账单处于逾期状态，债务整体状态即为 overdue。
    static func recalculateDebtStatus(_ debt: CreditCardDebt) {
        let activeStatements = debt.statements.filter(\.isActive)
        if activeStatements.contains(where: { $0.status == .overdue }) {
            debt.status = .overdue
        } else if activeStatements.allSatisfy({ $0.status == .paid }) {
            debt.status = .paid
        } else {
            debt.status = .active
        }
    }

    // MARK: - Overdue Record Management

    /// 为账单生成系统逾期记录（规范第十节）
    ///
    /// 如果已存在非 voided 的记录，更新系统参考值而不是新建。
    @discardableResult
    static func createOrUpdateSystemOverdueRecord(
        for statement: CreditCardStatement,
        today: Date = Date()
    ) -> CreditCardOverdueRecord {
        let rule = statement.debt?.calculationRule ?? CreditCardCalculationRule()
        let overdueAmount = max(statement.statementAmount - statement.paidAmount, 0)
        let overdueFee = calculateOverdueFee(overdueAmount: overdueAmount, rule: rule)
        let base = penaltyBase(
            unpaidAmount: overdueAmount,
            statementAmount: statement.statementAmount,
            rule: rule
        )
        let penalty = calculatePenaltyInterest(
            base: base,
            rule: rule,
            billingDate: statement.billingDate,
            today: today
        )

        if let existing = statement.overdueRecords.first(where: { $0.status != .voided && $0.managementMode == .system }) {
            // 更新系统参考值
            existing.systemCalculatedOverdueAmount = overdueAmount
            existing.systemCalculatedOverdueFee = overdueFee
            existing.systemCalculatedPenaltyInterest = penalty
            if !existing.isUserEdited {
                existing.overdueAmount = overdueAmount
                existing.overdueFee = overdueFee
                existing.penaltyInterest = penalty
            }
            return existing
        }

        let record = CreditCardOverdueRecord(
            overdueAmount: overdueAmount,
            overdueFee: overdueFee,
            penaltyInterest: penalty,
            startDate: today,
            managementMode: .system,
            systemCalculatedOverdueAmount: overdueAmount,
            systemCalculatedOverdueFee: overdueFee,
            systemCalculatedPenaltyInterest: penalty
        )
        statement.overdueRecords.append(record)
        return record
    }

    // MARK: - Fallback Statement Replacement

    /// 用真实账单替换兜底账单（规范第十三节）
    ///
    /// 失效兜底账单和兜底还款计划，真实账单继承剩余未还金额计算。
    static func replaceFallback(
        _ fallback: CreditCardStatement,
        withReal real: CreditCardStatement,
        today: Date = Date()
    ) {
        // 将兜底账单标记为已替换
        fallback.status = .replaced
        fallback.isActive = false
        fallback.repaymentPlan?.status = .voided
        fallback.repaymentPlan?.isActive = false

        // 为真实账单生成还款计划（如果还未生成）
        if real.repaymentPlan == nil {
            let plan = CreditCardRepaymentPlan(
                planAmount: real.statementAmount,
                dueDate: real.dueDate,
                source: .userStatementGenerated,
                paidAmount: real.paidAmount,
                remainingAmount: real.remainingAmount
            )
            plan.statement = real
            real.repaymentPlan = plan
        }

        recalculate(statement: real, today: today)
    }

    // MARK: - Manual Overdue Eligibility

    /// 查找最近一期真实账单（规范第十一节）
    ///
    /// 条件：同一信用卡下 billingDate 最大、isActive 为 true、status 不是 replaced、source 为 userConfirmed
    static func latestRealStatement(for debt: CreditCardDebt) -> CreditCardStatement? {
        debt.statements
            .filter { $0.isActive && $0.status != .replaced && $0.source == .userConfirmed }
            .max(by: { $0.billingDate < $1.billingDate })
    }

    /// 判断是否允许手动添加逾期（规范第十一节）
    ///
    /// - 最近一期必须是真实账单（非兜底）
    /// - 同一账单不能已有非 voided 的逾期记录
    static func canAddManualOverdue(for debt: CreditCardDebt) -> ManualOverdueEligibility {
        guard let latest = latestRealStatement(for: debt) else {
            return .noRealStatement
        }
        let hasExisting = latest.overdueRecords.contains { $0.status != .voided }
        if hasExisting {
            return .existingOverdueRecord
        }
        return .eligible(statement: latest)
    }

    // MARK: - Manual End Overdue

    /// 手动结束逾期处理流程（规范第十二节）
    ///
    /// 调用方必须先更新最近一期账单金额和最低还款额，然后再调用本方法。
    /// 返回 false 表示当前 paidAmount 仍低于 minimumPaymentAmount，首版建议阻止保存。
    @discardableResult
    static func endManualOverdue(
        record: CreditCardOverdueRecord,
        endDate: Date,
        today: Date = Date()
    ) -> Bool {
        guard let statement = record.statement else { return false }

        record.endDate = endDate
        record.status = .ended
        record.isActive = false

        recalculate(statement: statement, today: today)

        // 首版：若结算后 paidAmount 仍低于 minimumPayment，建议阻止保存
        return statement.paidAmount >= statement.minimumPaymentAmount
    }
}

// MARK: - ManualOverdueEligibility

/// 手动添加逾期的资格结果
enum ManualOverdueEligibility {
    /// 允许添加手动逾期，关联的最近一期真实账单
    case eligible(statement: CreditCardStatement)
    /// 最近一期不是真实账单（是兜底账单），提示用户先更新真实账单
    case noRealStatement
    /// 该账单已有非 voided 的逾期记录，提示用户先将原记录作废
    case existingOverdueRecord
}
