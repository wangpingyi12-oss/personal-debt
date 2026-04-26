import Foundation

enum DetailTone {
    case info
    case success
    case warning
    case danger
    case neutral
}

struct DetailMetricItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let subtitle: String?
    let systemImage: String
    let tone: DetailTone
}

struct DetailFieldItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    var tone: DetailTone = .neutral
}

struct DetailStatusSummary {
    let title: String
    let message: String
    let footnote: String?
    let systemImage: String
    let tone: DetailTone
}

struct RepaymentAllocationSnapshot {
    var overdueFee: Double
    var penaltyInterest: Double
    var interest: Double
    var fee: Double
    var principal: Double
    var inputAmount: Double
    var appliedAmount: Double
    var remainingAmount: Double
    var calculatedAt: Date?

    var totalCostCoverage: Double {
        overdueFee + penaltyInterest + interest + fee
    }

    static func from(record: RepaymentRecord) -> RepaymentAllocationSnapshot {
        guard
            let data = record.allocationJSON.data(using: .utf8),
            let payload = try? JSONDecoder().decode(RepaymentAllocationPayload.self, from: data)
        else {
            return RepaymentAllocationSnapshot(
                overdueFee: 0,
                penaltyInterest: 0,
                interest: 0,
                fee: 0,
                principal: record.amount,
                inputAmount: record.amount,
                appliedAmount: record.amount,
                remainingAmount: 0,
                calculatedAt: nil
            )
        }

        let formatter = ISO8601DateFormatter()
        let calculatedAt = payload.calculatedAt.flatMap { formatter.date(from: $0) }
        let appliedAmount = payload.appliedAmount ?? record.amount
        let inputAmount = payload.inputAmount ?? max(appliedAmount + (payload.remainingAmount ?? 0), record.amount)

        return RepaymentAllocationSnapshot(
            overdueFee: payload.allocation.overdueFee,
            penaltyInterest: payload.allocation.penaltyInterest,
            interest: payload.allocation.interest,
            fee: payload.allocation.fee,
            principal: payload.allocation.principal,
            inputAmount: inputAmount,
            appliedAmount: appliedAmount,
            remainingAmount: payload.remainingAmount ?? max(inputAmount - appliedAmount, 0),
            calculatedAt: calculatedAt
        )
    }
}

private struct RepaymentAllocationPayload: Decodable {
    struct Allocation: Decodable {
        var overdueFee: Double
        var penaltyInterest: Double
        var interest: Double
        var fee: Double
        var principal: Double
    }

    var allocation: Allocation
    var inputAmount: Double?
    var appliedAmount: Double?
    var remainingAmount: Double?
    var calculatedAt: String?
}

struct DebtDetailViewModel {
    let debt: Debt

    private var activePlans: [RepaymentPlan] {
        debt.repaymentPlans
            .filter { $0.status != .paid }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var unresolvedOverdues: [OverdueEvent] {
        debt.overdueEvents
            .filter { !$0.isResolved }
            .sorted { $0.startDate < $1.startDate }
    }

    private var pendingReminders: [ReminderTask] {
        debt.reminderTasks
            .filter { !$0.isCompleted }
            .sorted { $0.remindAt < $1.remindAt }
    }

    var recentRecords: [RepaymentRecord] {
        Array(debt.repaymentRecords.sorted { $0.paidAt > $1.paidAt }.prefix(3))
    }

    private var nextPlan: RepaymentPlan? {
        activePlans.first
    }

    private var unresolvedOverdueAmount: Double {
        unresolvedOverdues.reduce(0) { partial, event in
            partial + event.overduePrincipal + event.overdueInterest + event.penaltyInterest + event.overdueFee
        }
    }

    private var completionRatio: Double {
        guard debt.principal > 0 else { return debt.status == .settled ? 1 : 0 }
        return min(max((debt.principal - debt.outstandingPrincipal) / debt.principal, 0), 1)
    }

    var heroSubtitle: String {
        "\(debt.type.rawValue) · \(debt.subtype)"
    }

    var badgeText: String {
        debt.status.rawValue
    }

    var badgeTone: DetailTone {
        switch debt.status {
        case .normal:
            return .success
        case .overdue:
            return .danger
        case .settled:
            return .neutral
        }
    }

    var statusSummary: DetailStatusSummary {
        let refreshReminderCount = pendingReminders.filter { $0.category == .creditCardStatementRefresh }.count

        switch debt.status {
        case .settled:
            return DetailStatusSummary(
                title: "当前已结清",
                message: "这笔债务当前没有待还本金，也没有未结清逾期，已完成本轮还款流程。",
                footnote: "结清时间：\(shortDateText(debt.endDate)) · 共记录 \(debt.repaymentRecords.count) 笔还款",
                systemImage: "checkmark.seal.fill",
                tone: .success
            )

        case .overdue:
            let nextDueText = nextPlan.map { "最近待处理计划到期日为 \(shortDateText($0.dueDate))" } ?? "当前没有可展示的待执行计划"
            return DetailStatusSummary(
                title: "当前存在逾期压力",
                message: "这笔债务目前有 \(unresolvedOverdues.count) 笔未结清逾期，待处理总额约 \(currencyText(unresolvedOverdueAmount))，建议优先覆盖罚息与费用，避免继续滚增。",
                footnote: nextDueText,
                systemImage: "exclamationmark.triangle.fill",
                tone: .danger
            )

        case .normal:
            if let nextPlan {
                let reminderHint = refreshReminderCount > 0
                    ? "另有 \(refreshReminderCount) 条账单更新提醒待处理。"
                    : "当前没有未结清逾期。"
                return DetailStatusSummary(
                    title: "当前履约状态正常",
                    message: "最近一期还款将在 \(shortDateText(nextPlan.dueDate)) 到期，最低应还 \(currencyText(nextPlan.minimumDue))，全额应还 \(currencyText(nextPlan.totalDue))。",
                    footnote: reminderHint,
                    systemImage: "calendar.badge.clock",
                    tone: .info
                )
            }

            return DetailStatusSummary(
                title: "当前状态稳定",
                message: "这笔债务当前没有未结清逾期，且暂无待执行计划，可继续按最新账单或协商结果维护。",
                footnote: pendingReminders.isEmpty ? "当前也没有待办提醒。" : "当前仍有 \(pendingReminders.count) 条提醒待处理。",
                systemImage: "checkmark.circle.fill",
                tone: .success
            )
        }
    }

    var metrics: [DetailMetricItem] {
        [
            DetailMetricItem(
                title: "原始本金",
                value: currencyText(debt.principal),
                subtitle: "开始于 \(shortDateText(debt.startDate))",
                systemImage: "banknote",
                tone: .info
            ),
            DetailMetricItem(
                title: "剩余本金",
                value: currencyText(debt.outstandingPrincipal),
                subtitle: "本金进度 \(Int((completionRatio * 100).rounded()))%",
                systemImage: "creditcard.fill",
                tone: debt.status == .overdue ? .danger : .info
            ),
            DetailMetricItem(
                title: "未结清逾期",
                value: currencyText(unresolvedOverdueAmount),
                subtitle: "\(unresolvedOverdues.count) 笔待处理",
                systemImage: "exclamationmark.shield.fill",
                tone: unresolvedOverdues.isEmpty ? .success : .danger
            ),
            DetailMetricItem(
                title: "待办提醒",
                value: "\(pendingReminders.count) 条",
                subtitle: activePlans.isEmpty ? "暂无待还计划" : "待还计划 \(activePlans.count) 期",
                systemImage: "bell.badge.fill",
                tone: pendingReminders.isEmpty ? .neutral : .warning
            )
        ]
    }

    var basicFields: [DetailFieldItem] {
        [
            DetailFieldItem(title: "债务名称", value: debt.name),
            DetailFieldItem(title: "债务类型", value: debt.type.rawValue),
            DetailFieldItem(title: "债务子类型", value: debt.subtype),
            DetailFieldItem(title: "当前状态", value: debt.status.rawValue, tone: badgeTone),
            DetailFieldItem(title: "名义年化", value: String(format: "%.2f%%", debt.nominalAPR * 100)),
            DetailFieldItem(title: "实际年化", value: String(format: "%.2f%%", debt.effectiveAPR * 100)),
            DetailFieldItem(title: "开始日期", value: shortDateText(debt.startDate)),
            DetailFieldItem(title: "结束日期", value: shortDateText(debt.endDate)),
            DetailFieldItem(title: "还款记录", value: "\(debt.repaymentRecords.count) 笔"),
            DetailFieldItem(title: "待执行计划", value: "\(activePlans.count) 期")
        ]
    }

    var ruleFields: [DetailFieldItem] {
        let rule = debt.customRule
        return [
            DetailFieldItem(title: "当前规则", value: rule?.name ?? debt.calculationRuleName),
            DetailFieldItem(title: "分配顺序", value: rule?.paymentAllocationOrder.displayText ?? PaymentAllocationOrder.overdueFeeFirst.displayText),
            DetailFieldItem(title: "逾期计息方式", value: rule?.overduePenaltyMode.rawValue ?? OverduePenaltyMode.simple.rawValue),
            DetailFieldItem(title: "还款提醒提前", value: "\((rule?.repaymentReminderLeadDays) ?? 3) 天"),
            DetailFieldItem(title: "账单更新提醒", value: ((rule?.requireCreditCardStatementRefresh) ?? false) ? "开启" : "关闭")
        ]
    }

    var creditCardFields: [DetailFieldItem] {
        guard let detail = debt.creditCardDetail else { return [] }

        var fields: [DetailFieldItem] = [
            DetailFieldItem(title: "账单日", value: "每月 \(detail.billingDay) 日"),
            DetailFieldItem(title: "还款日", value: "每月 \(detail.repaymentDay) 日"),
            DetailFieldItem(title: "最低还款比例", value: String(format: "%.2f%%", detail.minimumRepaymentRate * 100)),
            DetailFieldItem(title: "最低还款保底", value: currencyText(detail.minimumRepaymentFloor)),
            DetailFieldItem(title: "逾期计息基数", value: detail.overdueInterestBase.rawValue),
            DetailFieldItem(title: "罚息日利率", value: String(format: "%.4f%%", detail.penaltyDailyRate * 100)),
            DetailFieldItem(title: "逾期固定费用", value: currencyText(detail.overdueFeeFlat)),
            DetailFieldItem(title: "分期期数", value: detail.installmentPeriods > 0 ? "\(detail.installmentPeriods) 期" : "无分期"),
            DetailFieldItem(title: "分期本金", value: detail.installmentPrincipal > 0 ? currencyText(detail.installmentPrincipal) : "—")
        ]

        if let refreshedAt = detail.lastStatementRefreshedAt {
            fields.append(DetailFieldItem(title: "最近账单更新", value: shortDateText(refreshedAt)))
            fields.append(DetailFieldItem(title: "最新账单金额", value: currencyText(detail.lastStatementBalance)))
            fields.append(DetailFieldItem(title: "最新最低还款", value: currencyText(detail.lastStatementMinimumDue)))
        } else {
            fields.append(DetailFieldItem(title: "最近账单更新", value: "尚未更新", tone: .warning))
        }

        return fields
    }

    var loanFields: [DetailFieldItem] {
        guard let detail = debt.loanDetail else { return [] }
        return [
            DetailFieldItem(title: "还款方式", value: detail.repaymentMethod.rawValue),
            DetailFieldItem(title: "总期数", value: "\(detail.termMonths) 个月"),
            DetailFieldItem(title: "到期日期", value: shortDateText(detail.maturityDate)),
            DetailFieldItem(title: "是否抵押类", value: detail.isMortgage ? "是" : "否"),
            DetailFieldItem(title: "逾期计息基数", value: detail.overdueInterestBase.rawValue),
            DetailFieldItem(title: "罚息日利率", value: String(format: "%.4f%%", detail.penaltyDailyRate * 100)),
            DetailFieldItem(title: "逾期固定费用", value: currencyText(detail.overdueFeeFlat))
        ]
    }

    var privateLoanFields: [DetailFieldItem] {
        guard let detail = debt.privateLoanDetail else { return [] }
        return [
            DetailFieldItem(title: "是否免息", value: detail.isInterestFree ? "是" : "否"),
            DetailFieldItem(title: "约定年化", value: String(format: "%.2f%%", detail.agreedAPR * 100)),
            DetailFieldItem(title: "逾期计息基数", value: detail.overdueInterestBase.rawValue),
            DetailFieldItem(title: "罚息日利率", value: String(format: "%.4f%%", detail.penaltyDailyRate * 100)),
            DetailFieldItem(title: "逾期固定费用", value: currencyText(detail.overdueFeeFlat))
        ]
    }

    var pendingRemindersPreview: [ReminderTask] {
        Array(pendingReminders.prefix(5))
    }

    var upcomingPlansPreview: [RepaymentPlan] {
        activePlans
    }
}

struct RepaymentDetailViewModel {
    let record: RepaymentRecord

    var allocation: RepaymentAllocationSnapshot {
        RepaymentAllocationSnapshot.from(record: record)
    }

    private var debt: Debt? {
        record.debt
    }

    private var unresolvedOverdues: [OverdueEvent] {
        debt?.overdueEvents.filter { !$0.isResolved }.sorted { $0.startDate < $1.startDate } ?? []
    }

    private var unresolvedOverdueAmount: Double {
        unresolvedOverdues.reduce(0) { partial, event in
            partial + event.overduePrincipal + event.overdueInterest + event.penaltyInterest + event.overdueFee
        }
    }

    private var nextPlan: RepaymentPlan? {
        debt?.repaymentPlans
            .filter { $0.status != .paid }
            .sorted { $0.dueDate < $1.dueDate }
            .first
    }

    var title: String {
        debt?.name ?? "还款流水详情"
    }

    var heroSubtitle: String {
        if let debt {
            return "\(debt.type.rawValue) · 记账时间 \(shortDateText(record.paidAt))"
        }
        return "历史流水 · 记账时间 \(shortDateText(record.paidAt))"
    }

    var badgeText: String {
        debt?.status.rawValue ?? "已脱关联"
    }

    var badgeTone: DetailTone {
        guard let debt else { return .neutral }
        switch debt.status {
        case .normal:
            return .success
        case .overdue:
            return .danger
        case .settled:
            return .info
        }
    }

    var statusSummary: DetailStatusSummary {
        guard let debt else {
            return DetailStatusSummary(
                title: "当前仅保留历史流水",
                message: "关联债务已不存在，但这笔还款记录仍可用于追溯历史支付情况和分配结果。",
                footnote: allocation.remainingAmount > 0 ? "本次输入中仍有 \(currencyText(allocation.remainingAmount)) 未被系统分配。" : nil,
                systemImage: "tray.full.fill",
                tone: .neutral
            )
        }

        switch debt.status {
        case .settled:
            return DetailStatusSummary(
                title: "当前已进入结清状态",
                message: "基于最新债务数据，这笔流水已纳入结清过程，关联债务当前已无剩余待还本金。",
                footnote: allocation.remainingAmount > 0 ? "本次输入金额仍有 \(currencyText(allocation.remainingAmount)) 未被使用。" : "说明基于当前数据快照，不一定等同于支付当日即时状态。",
                systemImage: "checkmark.circle.fill",
                tone: .success
            )

        case .overdue:
            return DetailStatusSummary(
                title: "当前仍有逾期待处理",
                message: "这笔还款后，关联债务当前仍存在 \(unresolvedOverdues.count) 笔未结清逾期，待处理金额约 \(currencyText(unresolvedOverdueAmount))。",
                footnote: nextPlan.map { "最近计划到期：\(shortDateText($0.dueDate)) · 最低应还 \(currencyText($0.minimumDue))" } ?? "暂无后续计划信息",
                systemImage: "exclamationmark.triangle.fill",
                tone: .danger
            )

        case .normal:
            if let nextPlan {
                return DetailStatusSummary(
                    title: "当前已回到正常履约",
                    message: "关联债务目前状态正常，剩余本金 \(currencyText(debt.outstandingPrincipal))，下一期将在 \(shortDateText(nextPlan.dueDate)) 到期。",
                    footnote: allocation.remainingAmount > 0 ? "本次输入中有 \(currencyText(allocation.remainingAmount)) 未被分配。" : "当前最近一期最低应还为 \(currencyText(nextPlan.minimumDue))。",
                    systemImage: "arrow.clockwise.circle.fill",
                    tone: .info
                )
            }

            return DetailStatusSummary(
                title: "当前无明显阻塞项",
                message: "关联债务当前没有显示中的逾期，且暂无待执行计划，可继续观察后续账单与提醒变化。",
                footnote: nil,
                systemImage: "checkmark.seal.fill",
                tone: .success
            )
        }
    }

    var metrics: [DetailMetricItem] {
        [
            DetailMetricItem(
                title: "输入金额",
                value: currencyText(allocation.inputAmount),
                subtitle: "本次录入支付金额",
                systemImage: "arrow.down.circle.fill",
                tone: .info
            ),
            DetailMetricItem(
                title: "实际生效",
                value: currencyText(allocation.appliedAmount),
                subtitle: "已分配到费用、利息和本金",
                systemImage: "checkmark.circle.fill",
                tone: .success
            ),
            DetailMetricItem(
                title: "本次未分配",
                value: currencyText(allocation.remainingAmount),
                subtitle: allocation.remainingAmount > 0 ? "通常表示超额支付未被当前规则使用" : "本次金额已全部分配",
                systemImage: "arrow.uturn.backward.circle.fill",
                tone: allocation.remainingAmount > 0 ? .warning : .neutral
            ),
            DetailMetricItem(
                title: "当前剩余本金",
                value: debt.map { currencyText($0.outstandingPrincipal) } ?? "—",
                subtitle: debt.map { "债务状态：\($0.status.rawValue)" } ?? "关联债务缺失",
                systemImage: "creditcard.and.123",
                tone: badgeTone
            )
        ]
    }

    var summaryFields: [DetailFieldItem] {
        var fields: [DetailFieldItem] = [
            DetailFieldItem(title: "记账时间", value: record.paidAt.formatted(date: .abbreviated, time: .omitted)),
            DetailFieldItem(title: "关联债务", value: debt?.name ?? "已删除"),
            DetailFieldItem(title: "债务状态", value: debt?.status.rawValue ?? "已脱关联", tone: badgeTone),
            DetailFieldItem(title: "债务类型", value: debt?.type.rawValue ?? "—"),
            DetailFieldItem(title: "系统计算时间", value: shortDateText(allocation.calculatedAt))
        ]

        if let plan = record.plan {
            fields.append(DetailFieldItem(title: "关联计划", value: "第 \(plan.periodIndex) 期"))
            fields.append(DetailFieldItem(title: "计划到期", value: shortDateText(plan.dueDate)))
        } else {
            fields.append(DetailFieldItem(title: "关联计划", value: "未关联"))
        }

        if !record.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.append(DetailFieldItem(title: "备注", value: record.note))
        }

        return fields
    }

    var allocationFields: [DetailFieldItem] {
        [
            DetailFieldItem(title: "逾期费用", value: currencyText(allocation.overdueFee), tone: allocation.overdueFee > 0 ? .danger : .neutral),
            DetailFieldItem(title: "逾期罚息", value: currencyText(allocation.penaltyInterest), tone: allocation.penaltyInterest > 0 ? .warning : .neutral),
            DetailFieldItem(title: "当期利息", value: currencyText(allocation.interest), tone: allocation.interest > 0 ? .warning : .neutral),
            DetailFieldItem(title: "当期费用", value: currencyText(allocation.fee), tone: allocation.fee > 0 ? .warning : .neutral),
            DetailFieldItem(title: "冲减本金", value: currencyText(allocation.principal), tone: allocation.principal > 0 ? .success : .neutral)
        ]
    }
}

struct OverdueDetailViewModel {
    let event: OverdueEvent

    private var debt: Debt? {
        event.debt
    }

    var overdueDays: Int {
        let end = event.endDate ?? Date()
        return max(Calendar.current.dateComponents([.day], from: event.startDate, to: end).day ?? 0, 0)
    }

    var totalExposure: Double {
        event.overduePrincipal + event.overdueInterest + event.penaltyInterest + event.overdueFee
    }

    var title: String {
        debt?.name ?? "逾期详情"
    }

    var heroSubtitle: String {
        if let debt {
            return "\(debt.type.rawValue) · 逾期开始于 \(shortDateText(event.startDate))"
        }
        return "历史逾期记录 · 开始于 \(shortDateText(event.startDate))"
    }

    var badgeText: String {
        event.isResolved ? "已处理" : "处理中"
    }

    var badgeTone: DetailTone {
        event.isResolved ? .success : .danger
    }

    var statusSummary: DetailStatusSummary {
        guard let debt else {
            return DetailStatusSummary(
                title: "保留中的历史逾期",
                message: "该逾期事件仍可查看，但关联债务已经不存在，建议仅作为历史参考。",
                footnote: event.isResolved ? "该记录已处理完成。" : "当前仍标记为未处理状态。",
                systemImage: "clock.arrow.circlepath",
                tone: .neutral
            )
        }

        if event.isResolved {
            return DetailStatusSummary(
                title: "当前已完成处理",
                message: "这笔逾期已在 \(shortDateText(event.endDate)) 前处理完成，共持续 \(overdueDays) 天，当前不会继续新增罚息与逾期费用。",
                footnote: "关联债务当前状态：\(debt.status.rawValue)",
                systemImage: "checkmark.shield.fill",
                tone: .success
            )
        }

        let planHint: String
        if let plan = event.plan {
            planHint = "关联第 \(plan.periodIndex) 期计划，到期日 \(shortDateText(plan.dueDate))。"
        } else {
            planHint = "当前未关联具体计划，请优先核对债务整体待还余额。"
        }

        return DetailStatusSummary(
            title: "当前仍处于逾期中",
            message: "这笔逾期已持续 \(overdueDays) 天，待处理总额约 \(currencyText(totalExposure))，其中罚息与费用仍可能继续累积。",
            footnote: planHint,
            systemImage: "exclamationmark.octagon.fill",
            tone: .danger
        )
    }

    var metrics: [DetailMetricItem] {
        [
            DetailMetricItem(
                title: "待处理总额",
                value: currencyText(totalExposure),
                subtitle: event.isResolved ? "该值仅用于回溯历史影响" : "当前仍需关注",
                systemImage: "sum",
                tone: event.isResolved ? .neutral : .danger
            ),
            DetailMetricItem(
                title: "逾期本金",
                value: currencyText(event.overduePrincipal),
                subtitle: "对应未覆盖本金部分",
                systemImage: "banknote.fill",
                tone: .info
            ),
            DetailMetricItem(
                title: "逾期罚息",
                value: currencyText(event.penaltyInterest),
                subtitle: "按当前规则累计结果",
                systemImage: "flame.fill",
                tone: event.penaltyInterest > 0 ? .warning : .neutral
            ),
            DetailMetricItem(
                title: "逾期费用",
                value: currencyText(event.overdueFee),
                subtitle: "固定或比例费用",
                systemImage: "exclamationmark.circle.fill",
                tone: event.overdueFee > 0 ? .danger : .neutral
            )
        ]
    }

    var summaryFields: [DetailFieldItem] {
        [
            DetailFieldItem(title: "起始时间", value: shortDateText(event.startDate)),
            DetailFieldItem(title: "结束时间", value: shortDateText(event.endDate)),
            DetailFieldItem(title: "持续天数", value: "\(overdueDays) 天", tone: event.isResolved ? .neutral : .warning),
            DetailFieldItem(title: "处理状态", value: event.isResolved ? "已处理" : "未处理", tone: badgeTone),
            DetailFieldItem(title: "关联债务", value: debt?.name ?? "已删除"),
            DetailFieldItem(title: "债务状态", value: debt?.status.rawValue ?? "已脱关联", tone: debt.map {
                switch $0.status {
                case .normal: return .success
                case .overdue: return .danger
                case .settled: return .neutral
                }
            } ?? .neutral)
        ]
    }

    var costFields: [DetailFieldItem] {
        [
            DetailFieldItem(title: "逾期本金", value: currencyText(event.overduePrincipal), tone: .info),
            DetailFieldItem(title: "逾期利息", value: currencyText(event.overdueInterest), tone: .warning),
            DetailFieldItem(title: "逾期罚息", value: currencyText(event.penaltyInterest), tone: .warning),
            DetailFieldItem(title: "逾期费用", value: currencyText(event.overdueFee), tone: .danger)
        ]
    }

    var relatedFields: [DetailFieldItem] {
        var fields: [DetailFieldItem] = []

        if let debt {
            fields.append(DetailFieldItem(title: "债务类型", value: debt.type.rawValue))
            if let plan = event.plan {
                fields.append(DetailFieldItem(title: "关联计划", value: "第 \(plan.periodIndex) 期"))
                fields.append(DetailFieldItem(title: "计划到期", value: shortDateText(plan.dueDate)))
                fields.append(DetailFieldItem(title: "当前计划状态", value: plan.status.rawValue, tone: plan.status == .overdue ? .danger : (plan.status == .paid ? .success : .info)))
            } else {
                fields.append(DetailFieldItem(title: "关联计划", value: "未关联"))
            }

            let rate = overdueDailyRateText(for: debt)
            if !rate.isEmpty {
                fields.append(DetailFieldItem(title: "当前罚息口径", value: rate))
            }
        }

        return fields
    }

    private func overdueDailyRateText(for debt: Debt) -> String {
        switch debt.type {
        case .creditCard:
            guard let detail = debt.creditCardDetail else { return "" }
            return "\(detail.overdueInterestBase.rawValue) · 日利率 \(String(format: "%.4f%%", detail.penaltyDailyRate * 100))"
        case .loan:
            guard let detail = debt.loanDetail else { return "" }
            return "\(detail.overdueInterestBase.rawValue) · 日利率 \(String(format: "%.4f%%", detail.penaltyDailyRate * 100))"
        case .privateLending:
            guard let detail = debt.privateLoanDetail else { return "" }
            return "\(detail.overdueInterestBase.rawValue) · 日利率 \(String(format: "%.4f%%", detail.penaltyDailyRate * 100))"
        }
    }
}
