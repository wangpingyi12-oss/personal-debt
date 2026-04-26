import SwiftData
import SwiftUI

private enum OverdueDaysFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case oneToThirty = "1-30天"
    case thirtyToNinety = "30-90天"
    case overNinety = "90天以上"

    var id: String { rawValue }

    func matches(days: Int) -> Bool {
        switch self {
        case .all:
            return true
        case .oneToThirty:
            return (1...30).contains(days)
        case .thirtyToNinety:
            return (31...90).contains(days)
        case .overNinety:
            return days > 90
        }
    }
}

struct RepaymentManagementView: View {
    @Query(sort: \RepaymentRecord.paidAt, order: .reverse) private var records: [RepaymentRecord]
    @Query(sort: \Debt.createdAt, order: .reverse) private var debts: [Debt]
    @State private var showAdd = false
    @State private var selectedType: DebtType?
    @State private var selectedStatus: DebtStatus?
    @State private var selectedDebtName: String?

    private var debtNameOptions: [String] {
        Array(Set(records.compactMap { $0.debt?.name })).sorted()
    }

    private var filteredRecords: [RepaymentRecord] {
        records.filter { record in
            let typeMatch = selectedType == nil || record.debt?.type == selectedType
            let statusMatch = selectedStatus == nil || record.debt?.status == selectedStatus
            let nameMatch = selectedDebtName == nil || record.debt?.name == selectedDebtName
            return typeMatch && statusMatch && nameMatch
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("债务类型")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal)
                    FilterGrid(columns: 4) {
                        FilterButton(title: "全部", isSelected: selectedType == nil) {
                            selectedType = nil
                        }
                        ForEach(DebtType.allCases) { type in
                            FilterButton(title: type.rawValue, isSelected: selectedType == type) {
                                selectedType = type
                            }
                        }
                    }

                    Text("债务状态")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal)
                    FilterGrid(columns: 4) {
                        FilterButton(title: "全部", isSelected: selectedStatus == nil) {
                            selectedStatus = nil
                        }
                        ForEach(DebtStatus.allCases) { status in
                            FilterButton(title: status.rawValue, isSelected: selectedStatus == status) {
                                selectedStatus = status
                            }
                        }
                    }

                    Text("债务名称")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal)
                    FilterMenu(
                        placeholder: "全部",
                        selection: selectedDebtName,
                        options: debtNameOptions,
                        displayText: { $0 }
                    ) { selection in
                        selectedDebtName = selection
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 4)

                VStack(spacing: 12) {
                    if filteredRecords.isEmpty {
                        Text("暂无流水记录")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 40)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(filteredRecords) { record in
                            NavigationLink {
                                RepaymentDetailView(record: record)
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "arrow.up.right.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(AppColors.accentGreen)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.debt?.name ?? "已删债务")
                                            .font(.subheadline.weight(.bold))
                                            .foregroundColor(.primary)
                                        Text(record.paidAt, style: .date)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Text(String(format: "-¥%.2f", record.amount))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.primary)
                                }
                                .padding()
                                .background(AppColors.cardBackground)
                                .cornerRadius(12)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 20)
        }
        .background(AppColors.backgroundGray)
        .overlay(alignment: .bottomTrailing) {
            FloatingAddButton {
                showAdd = true
            }
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                RepaymentFormView(debts: debts)
            }
        }
    }
}

private struct RepaymentDetailView: View {
    let record: RepaymentRecord

    private var viewModel: RepaymentDetailViewModel {
        RepaymentDetailViewModel(record: record)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DetailHeroCard(
                    title: viewModel.title,
                    subtitle: viewModel.heroSubtitle,
                    badgeText: viewModel.badgeText,
                    badgeTone: viewModel.badgeTone
                )

                DetailStatusCard(summary: viewModel.statusSummary)

                DetailMetricGrid(items: viewModel.metrics)

                DetailSectionCard(title: "流水概览", subtitle: "展示这笔还款与当前债务、计划的对应关系。") {
                    DetailFieldList(items: viewModel.summaryFields)
                }

                DetailSectionCard(title: "分配明细", subtitle: "金额按当前记录中的分配结果拆分为费用、利息和本金。") {
                    DetailFieldList(items: viewModel.allocationFields)
                }

                DetailSectionCard(title: "当前状态说明", subtitle: "以下描述基于最新债务数据，帮助理解这笔还款此刻所处的位置。") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(viewModel.statusSummary.message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let footnote = viewModel.statusSummary.footnote, !footnote.isEmpty {
                            Text(footnote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .background(AppColors.backgroundGray)
        .navigationTitle("还款详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RepaymentFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CalculationRuleProfile.name, order: .forward) private var ruleProfiles: [CalculationRuleProfile]

    let debts: [Debt]

    @State private var selectedDebtID: UUID?
    @State private var amount = 0.0
    @State private var note = ""

    private var uniqueDebts: [Debt] {
        var seenNames = Set<String>()
        return debts.filter { seenNames.insert($0.name).inserted }
    }

    var body: some View {
        Form {
            Picker("选择债务", selection: $selectedDebtID) {
                Text("请选择").tag(UUID?.none)
                ForEach(uniqueDebts) { debt in
                    Text(debt.name).tag(UUID?.some(debt.id))
                }
            }
            Text("提示：可在债务详情中为该笔债务自定义专属计算规则，再执行还款。")
                .font(.caption)
                .foregroundStyle(.secondary)
            TitledInputRow(title: "还款金额") {
                TextField("请输入还款金额", value: $amount, format: .number)
                    .keyboardType(.decimalPad)
            }
            TitledInputRow(title: "备注") {
                TextField("请输入备注（可选）", text: $note)
            }

            Button("保存还款") {
                saveRecord()
            }
            .disabled(selectedDebtID == nil || amount <= 0)
        }
    }

    private func saveRecord() {
        guard let id = selectedDebtID, let debt = debts.first(where: { $0.id == id }) else { return }
        let profile = RuleProfileResolver.resolve(for: debt, profiles: ruleProfiles)
        let allocationOrder = profile?.paymentAllocationOrder ?? .overdueFeeFirst

        let result = RepaymentDomainService.applyRepayment(
            debt: debt,
            amount: amount,
            note: note,
            paidAt: Date(),
            allocationOrder: allocationOrder
        )
        modelContext.insert(result.record)
        dismiss()
    }
}

struct OverdueManagementView: View {
    @Query(sort: \OverdueEvent.startDate, order: .reverse) private var overdueEvents: [OverdueEvent]
    @Query(sort: \Debt.createdAt, order: .reverse) private var debts: [Debt]
    @State private var showAdd = false
    @State private var selectedType: DebtType?
    @State private var selectedDebtName: String?
    @State private var overdueDaysFilter: OverdueDaysFilter = .all

    private func overdueDays(for event: OverdueEvent) -> Int {
        let end = event.endDate ?? Date()
        return max(Calendar.current.dateComponents([.day], from: event.startDate, to: end).day ?? 0, 0)
    }

    private var debtNameOptions: [String] {
        Array(Set(debts.map(\.name))).sorted()
    }

    private var filteredOverdueEvents: [OverdueEvent] {
        overdueEvents.filter { event in
            let typeMatch = selectedType == nil || event.debt?.type == selectedType
            let nameMatch = selectedDebtName == nil || event.debt?.name == selectedDebtName
            let daysMatch = overdueDaysFilter.matches(days: overdueDays(for: event))
            return typeMatch && nameMatch && daysMatch
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("债务类型")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal)
                    FilterGrid(columns: 4) {
                        FilterButton(title: "全部", isSelected: selectedType == nil) {
                            selectedType = nil
                        }
                        ForEach(DebtType.allCases) { type in
                            FilterButton(title: type.rawValue, isSelected: selectedType == type) {
                                selectedType = type
                            }
                        }
                    }

                    Text("逾期天数")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal)
                    FilterGrid(columns: 4) {
                        ForEach(OverdueDaysFilter.allCases) { filter in
                            FilterButton(title: filter.rawValue, isSelected: overdueDaysFilter == filter) {
                                overdueDaysFilter = filter
                            }
                        }
                    }

                    Text("债务名称")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal)
                    FilterMenu(
                        placeholder: "全部",
                        selection: selectedDebtName,
                        options: debtNameOptions,
                        displayText: { $0 }
                    ) { selection in
                        selectedDebtName = selection
                    }
                    .padding(.horizontal)
                }

                if filteredOverdueEvents.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 40))
                            .foregroundColor(AppColors.accentGreen)
                        Text("当前没有逾期记录，保持良好！")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    SectionHeader(title: "逾期列表")
                    VStack(spacing: 12) {
                        ForEach(filteredOverdueEvents) { event in
                            NavigationLink {
                                OverdueDetailView(event: event)
                            } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text(event.debt?.name ?? "未关联债务")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Text("\(overdueDays(for: event)) 天")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    HStack(spacing: 16) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("逾期费用")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            Text(String(format: "¥%.2f", event.overdueFee))
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundColor(.red)
                                        }
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("产生罚息")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            Text(String(format: "¥%.2f", event.penaltyInterest))
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundColor(.orange)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding()
                                .background(AppColors.cardBackground)
                                .cornerRadius(16)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 20)
        }
        .background(AppColors.backgroundGray)
        .overlay(alignment: .bottomTrailing) {
            FloatingAddButton {
                showAdd = true
            }
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                OverdueFormView(debts: debts)
            }
        }
    }
}

private struct OverdueDetailView: View {
    let event: OverdueEvent

    private var viewModel: OverdueDetailViewModel {
        OverdueDetailViewModel(event: event)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DetailHeroCard(
                    title: viewModel.title,
                    subtitle: viewModel.heroSubtitle,
                    badgeText: viewModel.badgeText,
                    badgeTone: viewModel.badgeTone
                )

                DetailStatusCard(summary: viewModel.statusSummary)

                DetailMetricGrid(items: viewModel.metrics)

                DetailSectionCard(title: "逾期概览", subtitle: "记录起止时间、持续时长与当前处理状态。") {
                    DetailFieldList(items: viewModel.summaryFields)
                }

                DetailSectionCard(title: "费用拆解", subtitle: "帮助你快速识别这笔逾期的成本结构。") {
                    DetailFieldList(items: viewModel.costFields)
                }

                DetailSectionCard(title: "关联信息", subtitle: "说明它与债务、计划及当前罚息口径的关系。") {
                    if viewModel.relatedFields.isEmpty {
                        Text("暂无关联信息")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        DetailFieldList(items: viewModel.relatedFields)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .background(AppColors.backgroundGray)
        .navigationTitle("逾期详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct OverdueFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CalculationRuleProfile.name, order: .forward) private var ruleProfiles: [CalculationRuleProfile]

    let debts: [Debt]

    @State private var selectedDebtID: UUID?
    @State private var startDate = Date()

    private var uniqueDebts: [Debt] {
        var seenNames = Set<String>()
        return debts.filter { seenNames.insert($0.name).inserted }
    }

    var body: some View {
        Form {
            Picker("债务", selection: $selectedDebtID) {
                Text("请选择").tag(UUID?.none)
                ForEach(uniqueDebts) { debt in
                    Text(debt.name).tag(UUID?.some(debt.id))
                }
            }

            Text("提示：可在债务详情中按单笔债务自定义计算规则，逾期计费会按该规则执行。")
                .font(.caption)
                .foregroundStyle(.secondary)

            DatePicker("逾期开始", selection: $startDate, displayedComponents: .date)

            Button("保存逾期") {
                saveEvent()
            }
            .disabled(selectedDebtID == nil)
        }
    }

    private func saveEvent() {
        guard let selectedDebtID, let debt = debts.first(where: { $0.id == selectedDebtID }) else { return }
        let profile = RuleProfileResolver.resolve(for: debt, profiles: ruleProfiles)
        let dailyRate = debt.creditCardDetail?.penaltyDailyRate
            ?? debt.loanDetail?.penaltyDailyRate
            ?? debt.privateLoanDetail?.penaltyDailyRate
            ?? 0.0005
        let fixedFee = debt.creditCardDetail?.overdueFeeFlat
            ?? debt.loanDetail?.overdueFeeFlat
            ?? debt.privateLoanDetail?.overdueFeeFlat
            ?? 0
        let penaltyMode = profile?.overduePenaltyMode ?? .simple

        let registration = OverdueDomainService.registerOverdue(
            debt: debt,
            startDate: startDate,
            penaltyMode: penaltyMode,
            dailyRate: dailyRate,
            fixedFee: fixedFee
        )
        if registration.isNew {
            modelContext.insert(registration.event)
        }
        dismiss()
    }
}

struct StrategyView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Debt.createdAt, order: .reverse) private var debts: [Debt]
    @Query(sort: \StrategyScenario.generatedAt, order: .reverse) private var savedScenarios: [StrategyScenario]
    @Query(sort: \SubscriptionEntitlement.lastSyncedAt, order: .reverse) private var entitlements: [SubscriptionEntitlement]

    @AppStorage("guidanceMonthlyBudget") private var budget = 3000.0
    @State private var selectedMethod: StrategyMethod = .avalanche
    @State private var generatedResult: FinanceEngine.StrategyResult?
    @State private var generatedMethod: StrategyMethod?
    @State private var generatedScenarioName = ""
    @State private var compareLeftScenarioID: UUID?
    @State private var compareRightScenarioID: UUID?
    @State private var selectedCompareSnapshotID: UUID?
    @State private var compareSnapshots: [StrategyComparisonSnapshot] = []
    @State private var compareMessage = ""
    @State private var showClearSavedScenariosAlert = false

    private var subscriptionAudit: SubscriptionStatusAudit {
        SubscriptionLifecycleAuditService.audit(entitlements: entitlements)
    }

    private var currentEntitlement: SubscriptionEntitlement? {
        subscriptionAudit.currentEntitlement
    }


    private var strategyConstraints: FinanceEngine.StrategyConstraints {
        FinanceEngine.StrategyConstraints(
            includeMinimumDue: true,
            includeOverduePenalty: true,
            prioritizeOverdueBalances: true,
            requireFullOverdueCoverage: true,
            minimumMonthlyReserve: 0,
            requireFullMinimumCoverage: true,
            maxMonths: 600
        )
    }

    private var guidance: DebtGuidanceService.Recommendation? {
        guard !debts.isEmpty, budget > 0 else { return nil }
        return DebtGuidanceService.build(
            debts: debts,
            monthlyBudget: budget,
            constraints: strategyConstraints
        )
    }

    private var generatedSnapshot: StrategyComparisonSnapshot? {
        guard let generatedMethod, let generatedResult else { return nil }
        return StrategyComparisonSnapshot(method: generatedMethod, result: generatedResult)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 16) {
                    if let currentEntitlement {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("订阅状态：\(currentEntitlement.status.rawValue)", systemImage: subscriptionStatusIconName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(subscriptionStatusTint)
                                Spacer()
                                if currentEntitlement.willAutoRenew {
                                    Text("自动续费中")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(AppColors.accentGreen)
                                }
                            }
                            if currentEntitlement.status == .expiringSoon {
                                Text("当前订阅即将到期，建议在真机测试时覆盖续费与恢复场景。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .background(AppColors.cardBackground)
                        .cornerRadius(16)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("还款预算配置")
                            .font(.headline)

                        TitledInputRow(title: "月度还款预算") {
                            HStack {
                                Image(systemName: "yensign.circle.fill")
                                    .foregroundColor(AppColors.primaryBlue)
                                TextField("请输入月度还款预算", value: $budget, format: .currency(code: "CNY"))
                                    .font(.title3.bold())
                                    .keyboardType(.decimalPad)
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)

                        HStack(spacing: 12) {
                            ForEach(StrategyMethod.allCases) { method in
                                Button {
                                    selectedMethod = method
                                } label: {
                                    Text(method.rawValue)
                                        .font(.caption.weight(.medium))
                                        .padding(.vertical, 8)
                                        .frame(maxWidth: .infinity)
                                        .background(selectedMethod == method ? AppColors.primaryBlue : Color.gray.opacity(0.1))
                                        .foregroundColor(selectedMethod == method ? .white : .primary)
                                        .cornerRadius(8)
                                }
                            }
                        }

                        Button {
                            generateSelectedStrategy()
                        } label: {
                            Text("生成策略")
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppColors.primaryBlue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                    .padding()
                    .background(AppColors.cardBackground)
                    .cornerRadius(16)
                }
                .padding(.horizontal)
                .padding(.top, 4)

                SectionHeader(title: "策略对比")
                StrategyPairComparePanel(
                    leftScenarioID: $compareLeftScenarioID,
                    rightScenarioID: $compareRightScenarioID,
                    scenarios: savedScenarios,
                    message: compareMessage,
                    onCompare: runPairComparison
                )
                .padding(.horizontal)

                if !compareSnapshots.isEmpty {
                    StrategyComparisonChartsSection(
                        snapshots: compareSnapshots,
                        selectedSnapshotID: selectedCompareSnapshotID
                    )
                }

                if let guidance {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "测算建议")

                        VStack(alignment: .leading, spacing: 12) {
                            if let method = guidance.recommendedMethod {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("推荐使用")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(method.rawValue)
                                            .font(.headline)
                                            .foregroundColor(AppColors.primaryBlue)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("预计节省利息")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(String(format: "¥%.2f", guidance.interestSavingsVsWorst))
                                            .font(.headline)
                                            .foregroundColor(AppColors.accentGreen)
                                    }
                                }

                                Divider()

                                Label("预计结清需 \(guidance.monthsToPayoff) 个月", systemImage: "clock.fill")
                                    .font(.subheadline)

                                HStack(spacing: 12) {
                                    MetricMiniCard(title: "当前预算", value: currencyText(guidance.monthlyBudget), tint: AppColors.primaryBlue)
                                    MetricMiniCard(title: "预计总利息", value: currencyText(guidance.totalInterest), tint: AppColors.warningOrange)
                                }

                                if !guidance.actions.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("建议动作")
                                            .font(.subheadline.weight(.semibold))
                                        ForEach(Array(guidance.actions.sorted { $0.priority < $1.priority }.prefix(3))) { action in
                                            BulletNoteRow(text: "\(action.title)：\(action.detail)", tint: AppColors.accentGreen)
                                        }
                                    }
                                }

                                if !guidance.risks.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("风险提醒")
                                            .font(.subheadline.weight(.semibold))
                                        ForEach(Array(guidance.risks.prefix(2)), id: \.self) { risk in
                                            BulletNoteRow(text: risk, tint: AppColors.warningOrange)
                                        }
                                    }
                                }

                                Text("请先点击上方“生成策略”，查看策略明细后再确认保存。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 8)
                            } else {
                                Text("当前预算下暂无完全可执行策略")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Text("当前月预算为 \(currencyText(guidance.monthlyBudget))，建议先提高到至少 \(currencyText(guidance.minimumFeasibleBudget))。")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                if !guidance.actions.isEmpty {
                                    Divider()
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("先做这几件事")
                                            .font(.subheadline.weight(.semibold))
                                        ForEach(Array(guidance.actions.sorted { $0.priority < $1.priority }.prefix(3))) { action in
                                            BulletNoteRow(text: "\(action.title)：\(action.detail)", tint: AppColors.warningOrange)
                                        }
                                    }
                                }

                                if let firstReason = guidance.alternatives.first(where: { !$0.isFeasible })?.reason {
                                    Divider()
                                    Text(firstReason)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(AppColors.cardBackground)
                        .cornerRadius(16)
                    }
                    .padding(.horizontal)
                }

                if let generatedMethod, let generatedResult {
                    SectionHeader(title: "策略预览")
                    VStack(alignment: .leading, spacing: 12) {
                        DetailRow(title: "策略", value: generatedMethod.rawValue)
                        DetailDivider()
                        DetailRow(title: "预计结清", value: shortDateText(generatedResult.payoffDate))
                        DetailDivider()
                        DetailRow(title: "预计总利息", value: currencyText(generatedResult.totalInterest), valueColor: AppColors.warningOrange)
                        DetailDivider()
                        TitledInputRow(title: "策略名称") {
                            TextField("请输入策略名称", text: $generatedScenarioName)
                        }

                        if let generatedSnapshot {
                            StrategyTimelineChartsSection(
                                monthRecords: generatedSnapshot.monthRecords,
                                statusText: generatedSnapshot.shortSummary
                            )
                        }

                        Button {
                            confirmSaveGeneratedScenario()
                        } label: {
                            Text("确认保存该策略")
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(AppColors.primaryBlue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                    .padding()
                    .background(AppColors.cardBackground)
                    .cornerRadius(16)
                    .padding(.horizontal)
                }

                SectionHeader(title: "已存方案", actionTitle: "清空") {
                    if !savedScenarios.isEmpty {
                        showClearSavedScenariosAlert = true
                    }
                }

                VStack(spacing: 12) {
                    if savedScenarios.isEmpty {
                        Text("暂无保存方案")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 40)
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(savedScenarios) { scenario in
                            NavigationLink {
                                StrategyScenarioDetailView(scenario: scenario)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(scenario.name)
                                            .font(.subheadline.weight(.bold))
                                        Text("\(scenario.method.rawValue) · 预算: ¥\(String(format: "%.0f", scenario.monthlyBudget)) · 结清: \(scenario.payoffDate, style: .date)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(AppColors.cardBackground)
                                .cornerRadius(12)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 20)
        }
        .background(AppColors.backgroundGray)
        .onAppear(perform: syncCompareSelectionDefaults)
        .onChange(of: savedScenarios.map(\.id)) { _, _ in
            syncCompareSelectionDefaults()
        }
        .alert("清空已存方案", isPresented: $showClearSavedScenariosAlert) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                clearSavedScenarios()
            }
        } message: {
            Text("该操作会删除所有已保存策略，且无法撤销。")
        }
    }

    private func generateSelectedStrategy() {
        guard let result = FinanceEngine.generateStrategyDetailed(
            debts: debts,
            monthlyBudget: budget,
            method: selectedMethod,
            constraints: strategyConstraints
        ) else { return }

        generatedMethod = selectedMethod
        generatedResult = result
        generatedScenarioName = "\(selectedMethod.rawValue)-\(Date().formatted(date: .abbreviated, time: .shortened))"
    }

    private func confirmSaveGeneratedScenario() {
        guard let generatedMethod, let generatedResult else { return }

        let scenario = StrategyScenario(
            name: generatedScenarioName.trimmingCharacters(in: .whitespacesAndNewlines),
            method: generatedMethod,
            monthlyBudget: budget,
            totalInterest: generatedResult.totalInterest,
            payoffDate: generatedResult.payoffDate,
            timelineJSON: generatedResult.timelineJSON
        )
        modelContext.insert(scenario)
    }

    private func runPairComparison() {
        compareMessage = ""
        compareSnapshots = []
        selectedCompareSnapshotID = nil

        guard let compareLeftScenarioID,
              let compareRightScenarioID else {
            compareMessage = "请先选择两个已保存方案。"
            return
        }

        guard compareLeftScenarioID != compareRightScenarioID else {
            compareMessage = "请先选择两个不同方案再进行对比。"
            return
        }

        guard let leftScenario = savedScenarios.first(where: { $0.id == compareLeftScenarioID }),
              let rightScenario = savedScenarios.first(where: { $0.id == compareRightScenarioID }) else {
            compareMessage = "所选方案已不存在，请重新选择。"
            return
        }

        compareSnapshots = [
            StrategyComparisonSnapshot(scenario: leftScenario),
            StrategyComparisonSnapshot(scenario: rightScenario)
        ]
        selectedCompareSnapshotID = leftScenario.id
    }

    private func clearSavedScenarios() {
        for scenario in savedScenarios {
            modelContext.delete(scenario)
        }
        compareLeftScenarioID = nil
        compareRightScenarioID = nil
        selectedCompareSnapshotID = nil
        compareSnapshots = []
        compareMessage = "已清空历史策略方案。"
    }

    private func syncCompareSelectionDefaults() {
        let ids = savedScenarios.map(\.id)
        if let compareLeftScenarioID, !ids.contains(compareLeftScenarioID) {
            self.compareLeftScenarioID = nil
        }
        if let compareRightScenarioID, !ids.contains(compareRightScenarioID) {
            self.compareRightScenarioID = nil
        }

        if compareLeftScenarioID == nil {
            compareLeftScenarioID = savedScenarios.first?.id
        }
        if compareRightScenarioID == nil {
            compareRightScenarioID = savedScenarios.dropFirst().first?.id ?? savedScenarios.first?.id
        }
        if selectedCompareSnapshotID == nil {
            selectedCompareSnapshotID = compareLeftScenarioID
        }
    }

    private var subscriptionStatusIconName: String {
        switch currentEntitlement?.status ?? .inactive {
        case .inactive:
            return "star.slash"
        case .trial:
            return "sparkles"
        case .active:
            return "checkmark.seal.fill"
        case .expiringSoon:
            return "clock.badge.exclamationmark"
        case .gracePeriod:
            return "checkmark.circle.trianglebadge.exclamationmark"
        case .billingRetry:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .expired:
            return "xmark.seal.fill"
        case .revoked:
            return "hand.raised.slash.fill"
        case .verificationFailed:
            return "exclamationmark.shield.fill"
        }
    }

    private var subscriptionStatusTint: Color {
        switch currentEntitlement?.status ?? .inactive {
        case .trial:
            return AppColors.accentGreen
        case .active:
            return AppColors.primaryBlue
        case .expiringSoon, .gracePeriod, .billingRetry:
            return AppColors.warningOrange
        case .revoked, .verificationFailed:
            return .red
        case .inactive, .expired:
            return .gray
        }
    }
}

private struct StrategyPairComparePanel: View {
    @Binding var leftScenarioID: UUID?
    @Binding var rightScenarioID: UUID?
    let scenarios: [StrategyScenario]
    let message: String
    let onCompare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if scenarios.count < 2 {
                Text("请先至少保存两种策略方案，再进行策略对比。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Picker("方案A", selection: $leftScenarioID) {
                    Text("请选择").tag(UUID?.none)
                    ForEach(scenarios) { scenario in
                        Text(scenarioLabel(for: scenario)).tag(UUID?.some(scenario.id))
                    }
                }
                .pickerStyle(.menu)

                Picker("方案B", selection: $rightScenarioID) {
                    Text("请选择").tag(UUID?.none)
                    ForEach(scenarios) { scenario in
                        Text(scenarioLabel(for: scenario)).tag(UUID?.some(scenario.id))
                    }
                }
                .pickerStyle(.menu)
            }

            Button(action: onCompare) {
                Text("生成对比")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(10)
            }
            .disabled(scenarios.count < 2)

            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(AppColors.cardBackground)
        .cornerRadius(16)
    }

    private func scenarioLabel(for scenario: StrategyScenario) -> String {
        "\(scenario.name) · \(scenario.generatedAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct StrategyScenarioDetailView: View {
    let scenario: StrategyScenario

    private var timeline: FinanceEngine.StrategyTimelinePayload? {
        FinanceEngine.decodeStrategyTimeline(from: scenario.timelineJSON)
    }

    private var monthRecords: [FinanceEngine.StrategyTimelinePayload.MonthRecord] {
        timeline?.records ?? []
    }

    private var averageMonthlyPayment: Double {
        guard !monthRecords.isEmpty else { return 0 }
        return monthRecords.reduce(0) { $0 + $1.paymentApplied } / Double(monthRecords.count)
    }

    private var chartStatusText: String {
        if let timeline {
            if timeline.completed {
                return "该策略当前可执行，图表展示完整月度变化。"
            }
            return timeline.infeasibleReason ?? "该策略未满足当前预算或约束要求。"
        }
        return "暂无可绘制的时间线数据。"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionHeader(title: "策略摘要")
                VStack(spacing: 0) {
                    DetailRow(title: "名称", value: scenario.name)
                    DetailDivider()
                    DetailRow(title: "策略", value: scenario.method.rawValue)
                    DetailDivider()
                    DetailRow(title: "生成时间", value: scenario.generatedAt.formatted(date: .abbreviated, time: .omitted))
                    DetailDivider()
                    DetailRow(title: "月预算", value: String(format: "¥%.2f", scenario.monthlyBudget))
                    DetailDivider()
                    DetailRow(title: "预计结清", value: scenario.payoffDate.formatted(date: .abbreviated, time: .omitted))
                    DetailDivider()
                    DetailRow(title: "总利息", value: String(format: "¥%.2f", scenario.totalInterest), valueColor: AppColors.warningOrange)
                    DetailDivider()
                    DetailRow(title: "预计用时", value: "\(monthRecords.count)个月")
                    DetailDivider()
                    DetailRow(title: "平均月还款", value: String(format: "¥%.2f", averageMonthlyPayment))
                }
                .background(AppColors.cardBackground)
                .cornerRadius(16)
                .padding(.horizontal)

                if !monthRecords.isEmpty {
                    StrategyTimelineChartsSection(monthRecords: monthRecords, statusText: chartStatusText)
                }

                SectionHeader(title: "每月明细")
                if monthRecords.isEmpty {
                    Text("暂无策略时间线数据")
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(AppColors.cardBackground)
                        .cornerRadius(16)
                        .padding(.horizontal)
                } else {
                    VStack(spacing: 12) {
                        ForEach(monthRecords, id: \.monthIndex) { record in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("第\(record.monthIndex)个月")
                                        .font(.subheadline.weight(.bold))
                                    Spacer()
                                    Text("剩余本金：\(currencyText(record.totalPrincipal))")
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(AppColors.primaryBlue)
                                }
                                Divider()
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("当月还款")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text(String(format: "¥%.2f", record.paymentApplied))
                                            .font(.caption.weight(.semibold))
                                    }
                                    Spacer()
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("新增利息")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text(String(format: "¥%.2f", record.interestAccrued))
                                            .font(.caption.weight(.semibold))
                                            .foregroundColor(AppColors.warningOrange)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("最低应还")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text(String(format: "¥%.2f", record.minimumRequired))
                                            .font(.caption.weight(.semibold))
                                    }
                                }

                                if let targetedDebtName = record.targetedDebtName {
                                    Text("额外优先还款债务：\(targetedDebtName)")
                                        .font(.caption)
                                        .padding(.top, 4)
                                }
                                if !record.notes.isEmpty {
                                    ForEach(record.notes, id: \.self) { note in
                                        Text(note)
                                            .font(.caption2)
                                            .foregroundStyle(record.isBudgetShortfall ? .orange : .secondary)
                                    }
                                }
                            }
                            .padding()
                            .background(AppColors.cardBackground)
                            .cornerRadius(16)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 20)
            .padding(.top, 4)
        }
        .background(AppColors.backgroundGray)
    }
}
