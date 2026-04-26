//
//  ContentView.swift
//  personal-debt
//
//  Created by Mac on 2026/4/25.
//

import Charts
import SwiftData
import SwiftUI

func currencyText(_ amount: Double) -> String {
    String(format: "¥%.2f", amount)
}

func shortDateText(_ date: Date?) -> String {
    guard let date else { return "待确认" }
    return date.formatted(date: .abbreviated, time: .omitted)
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \SubscriptionEntitlement.lastSyncedAt, order: .reverse) private var entitlements: [SubscriptionEntitlement]

    @State private var accessSnapshot = SubscriptionAccessPolicy.resolve(entitlements: [], now: Date())
    @State private var showTrialReminderAlert = false
    @State private var showSubscriptionSheet = false

    var body: some View {
        TabView {
            NavigationStack {
                HomeDashboardView()
                    .background(AppColors.backgroundGray)
            }
            .tabItem {
                Label("首页", systemImage: "house.fill")
            }

            NavigationStack {
                DebtManagementView()
                    .background(AppColors.backgroundGray)
            }
            .tabItem {
                Label("债务", systemImage: "creditcard.fill")
            }

            NavigationStack {
                RepaymentManagementView()
                    .background(AppColors.backgroundGray)
            }
            .tabItem {
                Label("流水", systemImage: "arrow.left.arrow.right")
            }

            NavigationStack {
                StrategyView()
                    .background(AppColors.backgroundGray)
            }
            .tabItem {
                Label("策略", systemImage: "chart.bar.fill")
            }

            NavigationStack {
                SettingsView()
                    .background(AppColors.backgroundGray)
            }
            .tabItem {
                Label("设置", systemImage: "person.fill")
            }
        }
        .accentColor(AppColors.primaryBlue)
        .task {
            SubscriptionStoreService.startListeningIfNeeded(modelContext: modelContext)
            await SubscriptionStoreService.bootstrapIfNeeded(modelContext: modelContext)
            refreshAccessState(checkReminder: true)
        }
        .onAppear {
            refreshAccessState(checkReminder: true)
        }
        .onChange(of: entitlements.map { "\($0.id.uuidString)-\($0.status.rawValue)-\($0.lastSyncedAt.timeIntervalSince1970)" }.joined(separator: "|")) { _, _ in
            refreshAccessState(checkReminder: true)
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .active {
                refreshAccessState(checkReminder: true)
            }
        }
        .alert("订阅提醒", isPresented: $showTrialReminderAlert) {
            Button("稍后", role: .cancel) { }
            Button("去订阅") {
                showSubscriptionSheet = true
            }
        } message: {
            Text(accessSnapshot.trialReminderMessage)
        }
        .sheet(isPresented: $showSubscriptionSheet) {
            NavigationStack {
                SubscriptionManagementView()
            }
        }
        .fullScreenCover(isPresented: Binding(get: { !accessSnapshot.hasAccess }, set: { _ in })) {
            SubscriptionRequiredGateView(
                statusText: accessSnapshot.trialStatusText,
                message: accessSnapshot.blockingMessage
            ) {
                _ = await SubscriptionStoreService.syncStoreState(modelContext: modelContext)
                refreshAccessState(checkReminder: false)
            }
            .interactiveDismissDisabled(true)
        }
    }

    private func refreshAccessState(checkReminder: Bool) {
        let snapshot = SubscriptionAccessPolicy.resolve(entitlements: entitlements, now: Date())
        accessSnapshot = snapshot

        guard checkReminder else { return }
        guard snapshot.hasAccess else {
            showTrialReminderAlert = false
            return
        }
        guard snapshot.shouldShowTrialReminder else { return }

        AppPreferenceService.markTrialReminderShown()
        showTrialReminderAlert = true
    }
}

private struct SubscriptionRequiredGateView: View {
    let statusText: String
    let message: String
    let onRefreshAccess: () async -> Void

    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("需要订阅")
                    .font(.title2.bold())
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    Task {
                        isRefreshing = true
                        await onRefreshAccess()
                        isRefreshing = false
                    }
                } label: {
                    Text(isRefreshing ? "校验中..." : "我已完成订阅，重新校验")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColors.primaryBlue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(isRefreshing)

                Divider()

                SubscriptionManagementView()
            }
            .padding(.top, 8)
            .padding(.horizontal)
            .navigationTitle("订阅与访问")
            .navigationBarTitleDisplayMode(.inline)
            .background(AppColors.backgroundGray)
        }
    }
}

private struct HomeDashboardView: View {
    @Query(sort: \Debt.createdAt, order: .reverse) private var debts: [Debt]
    @Query(sort: \RepaymentPlan.dueDate, order: .forward) private var plans: [RepaymentPlan]
    @Query(sort: \OverdueEvent.startDate, order: .reverse) private var overdueEvents: [OverdueEvent]
    @Query(sort: \ReminderTask.remindAt, order: .forward) private var reminders: [ReminderTask]
    @AppStorage("guidanceMonthlyBudget") private var guidanceMonthlyBudget = 3000.0

    private var totalOutstanding: Double {
        debts.reduce(0) { $0 + $1.outstandingPrincipal }
    }

    private var totalDebtAmount: Double {
        debts.reduce(0) { $0 + max($1.principal, 0) }
    }

    private var currentMonthDue: Double {
        currentMonthPlans.reduce(0) { $0 + $1.principalDue + $1.interestDue + $1.feeDue }
    }

    private var currentMonthPlans: [RepaymentPlan] {
        let now = Date()
        let cal = Calendar.current
        return plans.filter {
            $0.status != .paid && cal.isDate($0.dueDate, equalTo: now, toGranularity: .month)
        }
    }

    private var activePlans: [RepaymentPlan] {
        plans.filter { $0.status != .paid }
    }

    private var pendingReminders: [ReminderTask] {
        reminders
            .filter { !$0.isCompleted }
            .sorted {
                if $0.remindAt != $1.remindAt {
                    return $0.remindAt < $1.remindAt
                }
                return reminderSortRank(for: $0.category) < reminderSortRank(for: $1.category)
            }
    }

    private var statementRefreshReminders: [ReminderTask] {
        pendingReminders.filter { $0.category == .creditCardStatementRefresh }
    }

    private var overdueDebtCount: Int {
        debts.filter { $0.overdueEvents.contains(where: { !$0.isResolved }) }.count
    }

    private var unresolvedOverdueEvents: [OverdueEvent] {
        overdueEvents.filter { !$0.isResolved }
    }

    private var overdueAmount: Double {
        unresolvedOverdueEvents.reduce(0) {
            $0 + $1.overduePrincipal + $1.overdueInterest + $1.penaltyInterest + $1.overdueFee
        }
    }

    private var guidanceConstraints: FinanceEngine.StrategyConstraints {
        .init(
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
        guard !debts.isEmpty, guidanceMonthlyBudget > 0 else { return nil }
        return DebtGuidanceService.build(
            debts: debts,
            monthlyBudget: guidanceMonthlyBudget,
            constraints: guidanceConstraints
        )
    }

    private var priorityItems: [DashboardPriorityItem] {
        if debts.isEmpty {
            return [
                DashboardPriorityItem(
                    title: "先添加第一笔债务",
                    message: "录入债务后，系统会自动生成还款计划、提醒和清偿建议，帮助你更快建立执行节奏。",
                    systemImage: "plus.circle.fill",
                    tint: AppColors.primaryBlue,
                    rank: 0
                )
            ]
        }

        var items: [DashboardPriorityItem] = []

        if !statementRefreshReminders.isEmpty {
            items.append(
                DashboardPriorityItem(
                    title: "先更新信用卡账单",
                    message: "当前有 \(statementRefreshReminders.count) 条账单更新提醒待处理。先更新最新账单金额后再执行策略，结果会更准确。",
                    systemImage: "creditcard.and.123",
                    tint: AppColors.warningOrange,
                    footnote: statementRefreshReminders.prefix(2).map(\.title).joined(separator: " · "),
                    rank: 20,
                    dueDate: statementRefreshReminders.map(\.remindAt).min()
                )
            )
        }

        if overdueDebtCount > 0 {
            items.append(
                DashboardPriorityItem(
                    title: "优先止损逾期成本",
                    message: "当前有 \(overdueDebtCount) 笔债务存在未结清逾期，建议先覆盖逾期本金、罚息与费用，避免继续滚增。",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .red,
                    footnote: "待处理逾期金额 \(currencyText(overdueAmount))",
                    rank: 10
                )
            )
        }

        if let guidance {
            if let method = guidance.recommendedMethod {
                items.append(
                    DashboardPriorityItem(
                        title: "本月推荐执行：\(method.rawValue)",
                        message: guidance.actions.sorted { $0.priority < $1.priority }.first?.detail ?? "先满足最低还款和逾期硬约束，再把剩余预算投入推荐目标债务。",
                        systemImage: "sparkles",
                        tint: AppColors.primaryBlue,
                        footnote: "预计 \(guidance.monthsToPayoff) 个月结清 · 较最差可行方案少付利息 \(currencyText(guidance.interestSavingsVsWorst))",
                        rank: 30
                    )
                )
            } else {
                items.append(
                    DashboardPriorityItem(
                        title: "先补足执行预算",
                        message: "当前月预算为 \(currencyText(guidance.monthlyBudget))，至少需要 \(currencyText(guidance.minimumFeasibleBudget)) 才能满足最低还款与逾期等硬约束。",
                        systemImage: "arrow.up.circle.fill",
                        tint: AppColors.warningOrange,
                        rank: 30
                    )
                )
            }
        } else {
            items.append(
                DashboardPriorityItem(
                    title: "录入月预算，获取执行建议",
                    message: "设置可实际执行的月还款预算后，系统会结合最低还款、逾期和利率给出清偿顺序建议。",
                    systemImage: "slider.horizontal.3",
                    tint: AppColors.accentGreen,
                    rank: 30
                )
            )
        }

        return items.sorted {
            if $0.rank != $1.rank {
                return $0.rank < $1.rank
            }
            switch ($0.dueDate, $1.dueDate) {
            case let (lhs?, rhs?):
                return lhs < rhs
            case (nil, .some):
                return false
            case (.some, nil):
                return true
            case (nil, nil):
                return $0.title < $1.title
            }
        }
    }

    private func reminderSortRank(for category: ReminderCategory) -> Int {
        switch category {
        case .creditCardStatementRefresh:
            return 0
        case .repaymentDue:
            return 1
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "债务总览")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    StatCard(
                        title: "债务总额",
                        value: currencyText(totalDebtAmount),
                        subtitle: "共 \(debts.count) 笔债务",
                        iconName: "tray.full.fill",
                        color: AppColors.primaryBlue
                    )

                    StatCard(
                        title: "剩余债务金额",
                        value: currencyText(totalOutstanding),
                        subtitle: totalDebtAmount > 0 ? "已压降 \(currencyText(max(totalDebtAmount - totalOutstanding, 0)))" : "待录入债务",
                        iconName: "creditcard.fill",
                        color: .indigo
                    )

                    StatCard(
                        title: "本月应还",
                        value: currencyText(currentMonthDue),
                        subtitle: "\(currentMonthPlans.count) 期待执行",
                        iconName: "calendar",
                        color: AppColors.warningOrange
                    )

                    StatCard(
                        title: "逾期金额",
                        value: currencyText(overdueAmount),
                        subtitle: "\(unresolvedOverdueEvents.count) 笔待处理",
                        iconName: "exclamationmark.triangle.fill",
                        color: .red
                    )
                }
                .padding(.horizontal)

                SectionHeader(title: "还款计划")
                RepaymentPlanCalendarCard(plans: activePlans)
                    .padding(.horizontal)

                SectionHeader(title: "执行重点与近期提醒")
                FocusReminderHubCard(priorityItems: priorityItems, reminders: pendingReminders)
                    .padding(.horizontal)

                SectionHeader(title: "业务入口")
                VStack(spacing: 10) {
                    NavigationLink {
                        DataStatisticsView()
                    } label: {
                        EntryCard(
                            title: "数据统计",
                            subtitle: "查看债务结构、还款效率与资金成本",
                            iconName: "chart.bar.xaxis",
                            tint: AppColors.primaryBlue
                        )
                    }

                    NavigationLink {
                        OverdueManagementView()
                    } label: {
                        EntryCard(
                            title: "逾期管理",
                            subtitle: "当前未结清逾期 \(unresolvedOverdueEvents.count) 笔",
                            iconName: "exclamationmark.triangle",
                            tint: .red
                        )
                    }
                }
                .padding(.horizontal)

                // 推荐策略预览
                if let guidance {
                    SectionHeader(title: "系统推荐策略")
                    VStack(alignment: .leading, spacing: 12) {
                        if let method = guidance.recommendedMethod {
                            HStack {
                                Text(method.rawValue)
                                    .font(.headline)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(AppColors.primaryBlue.opacity(0.1))
                                    .foregroundColor(AppColors.primaryBlue)
                                    .cornerRadius(6)

                                Spacer()

                                if let payoffDate = guidance.payoffDate {
                                    Text("预计结清: \(payoffDate, style: .date)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Divider()

                            HStack(spacing: 12) {
                                MetricMiniCard(title: "预计利息", value: currencyText(guidance.totalInterest), tint: AppColors.warningOrange)
                                MetricMiniCard(title: "预计时长", value: "\(guidance.monthsToPayoff)个月", tint: AppColors.primaryBlue)
                            }

                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(Array(guidance.actions.sorted { $0.priority < $1.priority }.prefix(3))) { action in
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(AppColors.accentGreen)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(action.title)
                                                .font(.subheadline.weight(.medium))
                                            Text(action.detail)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        } else {
                            Text("当前预算下暂无完全可执行策略")
                                .font(.headline)
                                .foregroundColor(AppColors.warningOrange)
                            Text("至少需要 \(currencyText(guidance.minimumFeasibleBudget)) 才能覆盖当前的最低还款与逾期硬约束。")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        if !guidance.risks.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 8) {
                                Text("风险提示")
                                    .font(.subheadline.weight(.semibold))
                                ForEach(Array(guidance.risks.prefix(2)), id: \.self) { risk in
                                    BulletNoteRow(text: risk, tint: .orange)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(AppColors.cardBackground)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 10)
        }
        .task(id: reminders.map(\.id.uuidString).joined(separator: ",")) {
            await ReminderNotificationService.sync(reminders: reminders)
        }
    }
}

private struct DebtManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Debt.createdAt, order: .reverse) private var debts: [Debt]

    @State private var showAddDebt = false
    @State private var selectedType: DebtType?
    @State private var selectedStatus: DebtStatus?
    @State private var selectedDebtName: String?

    private var debtNameOptions: [String] {
        Array(Set(debts.map(\.name))).sorted()
    }

    private var filteredDebts: [Debt] {
        debts.filter { debt in
            let typeMatch = selectedType == nil || debt.type == selectedType
            let statusMatch = selectedStatus == nil || debt.status == selectedStatus
            let nameMatch = selectedDebtName == nil || debt.name == selectedDebtName
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

                // 债务列表
                VStack(spacing: 16) {
                    if filteredDebts.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "creditcard")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("暂无相关债务")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 60)
                    } else {
                        ForEach(filteredDebts) { debt in
                            NavigationLink {
                                DebtDetailView(debt: debt)
                            } label: {
                                DebtCard(debt: debt)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 20)
        }
        .overlay(alignment: .bottomTrailing) {
            FloatingAddButton {
                showAddDebt = true
            }
        }
        .sheet(isPresented: $showAddDebt) {
            NavigationStack {
                DebtFormView(existingDebt: nil)
            }
        }
    }
}

private struct DebtDetailView: View {
    let debt: Debt

    @State private var showEditSheet = false
    @State private var showRuleEditSheet = false

    private var viewModel: DebtDetailViewModel {
        DebtDetailViewModel(debt: debt)
    }

    private var upcomingPlans: [RepaymentPlan] {
        debt.repaymentPlans
            .filter { $0.status != .paid }
            .sorted(by: { $0.dueDate < $1.dueDate })
    }

    private var pendingReminders: [ReminderTask] {
        debt.reminderTasks
            .filter { !$0.isCompleted }
            .sorted(by: { $0.remindAt < $1.remindAt })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DetailHeroCard(
                    title: debt.name,
                    subtitle: viewModel.heroSubtitle,
                    badgeText: viewModel.badgeText,
                    badgeTone: viewModel.badgeTone
                )

                DetailStatusCard(summary: viewModel.statusSummary)

                DetailMetricGrid(items: viewModel.metrics)

                DetailSectionCard(title: "债务概览", subtitle: "聚合展示基础信息、进度与当前执行面。") {
                    DetailFieldList(items: viewModel.basicFields)
                }

                DetailSectionCard(title: "规则与提醒口径", subtitle: "以下信息决定这笔债务的提醒、逾期和还款分配展示。") {
                    VStack(spacing: 0) {
                        DetailFieldList(items: viewModel.ruleFields)
                        DetailDivider()
                        Button {
                            showRuleEditSheet = true
                        } label: {
                            HStack {
                                Text("编辑本债务专属规则")
                                    .foregroundColor(AppColors.primaryBlue)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        }
                    }
                }

                if debt.creditCardDetail != nil {
                    DetailSectionCard(title: "信用卡参数", subtitle: "用于解释最低还款、账单更新与逾期口径。") {
                        VStack(spacing: 0) {
                            DetailFieldList(items: viewModel.creditCardFields)
                            DetailDivider()
                            NavigationLink {
                                CreditCardStatementRefreshFormView(debt: debt)
                            } label: {
                                HStack {
                                    Text("更新信用卡账单")
                                        .foregroundColor(AppColors.primaryBlue)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                            }
                        }
                    }
                }

                if debt.loanDetail != nil {
                    DetailSectionCard(title: "贷款参数", subtitle: "展示到期、罚息与逾期测算所依赖的核心参数。") {
                        DetailFieldList(items: viewModel.loanFields)
                    }
                }

                if debt.privateLoanDetail != nil {
                    DetailSectionCard(title: "借贷参数", subtitle: "说明借贷是否免息及逾期费用口径。") {
                        DetailFieldList(items: viewModel.privateLoanFields)
                    }
                }

                DetailSectionCard(title: "待执行计划", subtitle: upcomingPlans.isEmpty ? "当前暂无待执行计划。" : "按日历查看后续每一期应还安排。") {
                    RepaymentPlanCalendarCard(plans: upcomingPlans)
                }

                DetailSectionCard(title: "最近还款", subtitle: viewModel.recentRecords.isEmpty ? "当前还没有还款记录。" : "帮助你快速回看最近的执行动作。") {
                    if viewModel.recentRecords.isEmpty {
                        Text("暂无还款记录")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(viewModel.recentRecords) { record in
                                DetailTimelineCard(
                                    title: currencyText(record.amount),
                                    subtitle: record.note.isEmpty ? "记账于 \(shortDateText(record.paidAt))" : record.note,
                                    accessory: shortDateText(record.paidAt),
                                    tone: .success
                                )
                            }
                        }
                    }
                }

                DetailSectionCard(title: "提醒", subtitle: pendingReminders.isEmpty ? "当前没有待办提醒。" : "展示最需要关注的近期待办提醒。") {
                    if pendingReminders.isEmpty {
                        Text("暂无待办提醒")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(pendingReminders.prefix(5)) { reminder in
                                DetailTimelineCard(
                                    title: reminder.title,
                                    subtitle: reminder.isNotificationScheduled
                                        ? "已同步本地通知"
                                        : (reminder.notificationErrorMessage.isEmpty ? "待同步本地通知" : reminder.notificationErrorMessage),
                                    accessory: shortDateText(reminder.remindAt),
                                    tone: reminder.category == .creditCardStatementRefresh ? .warning : .info
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .background(AppColors.backgroundGray)
        .navigationTitle("债务详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("编辑") {
                    showEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            NavigationStack {
                DebtFormView(existingDebt: debt)
            }
        }
        .sheet(isPresented: $showRuleEditSheet) {
            NavigationStack {
                DebtCustomRuleFormView(rule: debt.customRule, debt: debt) { updatedRule in
                    debt.customRule = updatedRule
                    debt.calculationRuleName = updatedRule.name
                }
            }
        }
    }
}

private struct DebtFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CalculationRuleProfile.name, order: .forward) private var ruleProfiles: [CalculationRuleProfile]

    let existingDebt: Debt?

    @State private var name = ""
    @State private var type: DebtType = .creditCard
    @State private var subtype = "一般账单"
    @State private var principal = 0.0
    @State private var nominalAPRPercentInput = "18"
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .month, value: 12, to: Date()) ?? Date()
    @State private var loanMethod: LoanRepaymentMethod = .equalInstallment
    @State private var billingDay = 8
    @State private var repaymentDay = 20
    @State private var minimumRepaymentRate = 0.1
    @State private var minimumRepaymentFloor = 100.0
    @State private var minimumIncludesFees = true
    @State private var minimumIncludesPenalty = true
    @State private var minimumIncludesInterest = true
    @State private var minimumIncludesInstallmentPrincipal = true
    @State private var minimumIncludesInstallmentFee = true
    @State private var installmentPeriods = 12
    @State private var installmentPrincipal = 0.0
    @State private var installmentFeeRatePerPeriod = 0.005
    @State private var installmentFeeMode: CreditCardInstallmentFeeMode = .perPeriod
    @State private var termMonths = 12
    @State private var statementCycles = 1
    @State private var penaltyDailyRate = 0.0005
    @State private var overdueFeeFlat = 0.0
    @State private var creditCardOverdueInterestBase: OverdueInterestBase = .principalOnly
    @State private var creditCardOverduePenaltyMode: OverduePenaltyMode = .simple
    @State private var loanOverdueInterestBase: OverdueInterestBase = .principalOnly
    @State private var privateOverdueInterestBase: OverdueInterestBase = .principalOnly
    @State private var errorMessage = ""

    private var subtypeOptions: [String] {
        switch type {
        case .creditCard:
            return ["一般账单", "信用卡分期"]
        case .loan:
            return ["信用贷款", "抵押贷款"]
        case .privateLending:
            return ["有息借贷", "无息借贷"]
        }
    }

    private var defaultRuleProfile: CalculationRuleProfile? {
        RuleTemplateCatalogService.defaultProfile(for: type, in: ruleProfiles) ?? ruleProfiles.first
    }

    private var computedLoanTermMonths: Int {
        let components = Calendar.current.dateComponents([.month], from: startDate, to: endDate)
        return max(components.month ?? 0, 1)
    }

    private var nominalAPRPercentValue: Double {
        max(Double(nominalAPRPercentInput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0, 0)
    }

    var body: some View {
        Form {
            Section("规则提示") {
                Text("保存后可在债务详情中，为该笔债务单独自定义计算规则。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("基本信息") {
                TitledInputRow(title: "债务名称") {
                    TextField("请输入债务名称", text: $name)
                }
                Picker("债务类型", selection: $type) {
                    ForEach(DebtType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                Picker("子类型", selection: $subtype) {
                    ForEach(subtypeOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                TitledInputRow(title: "本金") {
                    TextField("请输入本金", value: $principal, format: .number)
                        .keyboardType(.decimalPad)
                }
                TitledInputRow(title: "名义年化（%）") {
                    TextField(type == .creditCard ? "请输入名义年化（如 18）" : "请输入名义年化（可留空）", text: $nominalAPRPercentInput)
                        .keyboardType(.decimalPad)
                }
                if type != .creditCard {
                    DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                }
                if type == .loan {
                    DatePicker("结束日期", selection: $endDate, displayedComponents: .date)
                }
            }

            if type == .creditCard {
                Section("信用卡参数") {
                    Stepper("账单日：\(billingDay)", value: $billingDay, in: 1...31)
                    Stepper("还款日：\(repaymentDay)", value: $repaymentDay, in: 1...31)
                    TitledInputRow(title: "最低还款比例（%）") {
                        TextField("请输入最低还款比例（如 10）", value: percentBinding($minimumRepaymentRate), format: .number)
                            .keyboardType(.decimalPad)
                    }
                    TitledInputRow(title: "最低还款保底") {
                        TextField("请输入最低还款保底", value: $minimumRepaymentFloor, format: .number)
                            .keyboardType(.decimalPad)
                    }
                    if subtype == "信用卡分期" {
                        Stepper("分期期数：\(installmentPeriods)", value: $installmentPeriods, in: 1...60)
                        TitledInputRow(title: "分期本金") {
                            TextField("请输入分期本金", value: $installmentPrincipal, format: .number)
                                .keyboardType(.decimalPad)
                        }
                        TitledInputRow(title: "每期手续费率") {
                            TextField("请输入每期手续费率（%）", value: percentBinding($installmentFeeRatePerPeriod), format: .number)
                                .keyboardType(.decimalPad)
                        }
                        Picker("手续费模式", selection: $installmentFeeMode) {
                            ForEach(CreditCardInstallmentFeeMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                    }
                }
            }

            if type == .loan {
                Section("贷款参数") {
                    Picker("还款方式", selection: $loanMethod) {
                        ForEach(LoanRepaymentMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    Text("期数：\(computedLoanTermMonths) 个月（按开始/结束日期自动计算）")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Picker("逾期计息基数", selection: $loanOverdueInterestBase) {
                        ForEach(OverdueInterestBase.allCases) { base in
                            Text(base.rawValue).tag(base)
                        }
                    }
                }
            }

            if type == .privateLending {
                Section("个人借贷参数") {
                    Picker("逾期计息基数", selection: $privateOverdueInterestBase) {
                        ForEach(OverdueInterestBase.allCases) { base in
                            Text(base.rawValue).tag(base)
                        }
                    }
                }
            }

            if !errorMessage.isEmpty {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Button(existingDebt == nil ? "保存债务" : "更新债务") {
                saveDebt()
            }
        }
        .onAppear(perform: loadExistingDebt)
        .onChange(of: type) { _, newType in
            subtype = defaultSubtype(for: newType)
            if newType == .loan {
                termMonths = computedLoanTermMonths
            }
        }
        .onChange(of: startDate) { _, _ in
            if type == .loan {
                termMonths = computedLoanTermMonths
            }
        }
        .onChange(of: endDate) { _, _ in
            if type == .loan {
                termMonths = computedLoanTermMonths
            }
        }
    }

    private func loadExistingDebt() {
        guard let debt = existingDebt else { return }
        name = debt.name
        type = debt.type
        subtype = debt.subtype
        principal = debt.principal
        nominalAPRPercentInput = debt.nominalAPR > 0 ? String(format: "%.2f", debt.nominalAPR * 100) : ""
        startDate = debt.startDate
        if let detail = debt.creditCardDetail {
            billingDay = detail.billingDay
            repaymentDay = detail.repaymentDay
            statementCycles = 1
            minimumRepaymentRate = detail.minimumRepaymentRate
            minimumRepaymentFloor = detail.minimumRepaymentFloor
            minimumIncludesFees = detail.minimumIncludesFees
            minimumIncludesPenalty = detail.minimumIncludesPenalty
            minimumIncludesInterest = detail.minimumIncludesInterest
            minimumIncludesInstallmentPrincipal = detail.minimumIncludesInstallmentPrincipal
            minimumIncludesInstallmentFee = detail.minimumIncludesInstallmentFee
            installmentPeriods = detail.installmentPeriods
            installmentPrincipal = detail.installmentPrincipal
            installmentFeeRatePerPeriod = detail.installmentFeeRatePerPeriod
            installmentFeeMode = detail.installmentFeeMode
            penaltyDailyRate = detail.penaltyDailyRate
            overdueFeeFlat = detail.overdueFeeFlat
            creditCardOverdueInterestBase = detail.overdueInterestBase
            creditCardOverduePenaltyMode = debt.customRule?.overduePenaltyMode ?? .simple
        }
        if let detail = debt.loanDetail {
            loanMethod = detail.repaymentMethod
            termMonths = detail.termMonths
            loanOverdueInterestBase = detail.overdueInterestBase
            if let maturityDate = detail.maturityDate {
                endDate = maturityDate
            }
        }
        if let detail = debt.privateLoanDetail {
            privateOverdueInterestBase = detail.overdueInterestBase
        }
    }

    private func saveDebt() {
        let nominalAPR = nominalAPRPercentValue / 100
        do {
            let target = existingDebt ?? Debt(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                type: type,
                subtype: subtype,
                principal: max(principal, 0),
                nominalAPR: nominalAPR,
                effectiveAPR: FinanceEngine.effectiveAPR(nominalAPR: nominalAPR),
                startDate: type == .creditCard ? Date() : startDate
            )
            if existingDebt == nil {
                modelContext.insert(target)
            }

            try DebtMutationService.rebuildDebt(
                modelContext: modelContext,
                debt: target,
                draft: .init(
                    name: name,
                    type: type,
                    subtype: subtype,
                    principal: principal,
                    nominalAPR: nominalAPR,
                    startDate: type == .creditCard ? Date() : startDate,
                    endDate: type == .loan ? endDate : nil,
                    loanMethod: loanMethod,
                    termMonths: computedLoanTermMonths,
                    billingDay: billingDay,
                    repaymentDay: repaymentDay,
                    statementCycles: 1,
                    minimumRepaymentRate: minimumRepaymentRate,
                    minimumRepaymentFloor: minimumRepaymentFloor,
                    minimumIncludesFees: minimumIncludesFees,
                    minimumIncludesPenalty: minimumIncludesPenalty,
                    minimumIncludesInterest: minimumIncludesInterest,
                    minimumIncludesInstallmentPrincipal: minimumIncludesInstallmentPrincipal,
                    minimumIncludesInstallmentFee: minimumIncludesInstallmentFee,
                    installmentPeriods: installmentPeriods,
                    installmentPrincipal: installmentPrincipal,
                    installmentFeeRatePerPeriod: installmentFeeRatePerPeriod,
                    installmentFeeMode: installmentFeeMode,
                    penaltyDailyRate: 0,
                    overdueFeeFlat: 0,
                    creditCardOverdueInterestBase: .principalOnly,
                    creditCardOverduePenaltyMode: .simple,
                    loanOverdueInterestBase: loanOverdueInterestBase,
                    privateOverdueInterestBase: privateOverdueInterestBase
                ),
                ruleProfile: defaultRuleProfile
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func defaultSubtype(for type: DebtType) -> String {
        switch type {
        case .creditCard:
            return "一般账单"
        case .loan:
            return "信用贷款"
        case .privateLending:
            return "有息借贷"
        }
    }

    private func percentBinding(_ value: Binding<Double>) -> Binding<Double> {
        Binding(
            get: { value.wrappedValue * 100 },
            set: { value.wrappedValue = max($0, 0) / 100 }
        )
    }
}

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(isSelected ? AppColors.primaryBlue : AppColors.cardBackground)
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isSelected ? Color.clear : Color.gray.opacity(0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct DebtCard: View {
    let debt: Debt
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(debt.name)
                        .font(.headline)
                    Text(debt.subtype)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                StatusBadge(status: debt.status)
            }
            
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("剩余本金")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "¥%.2f", debt.outstandingPrincipal))
                        .font(.title3.bold())
                        .foregroundColor(AppColors.primaryBlue)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("年化利率")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.2f%%", debt.nominalAPR * 100))
                        .font(.subheadline.weight(.semibold))
                }
            }
            
            // 简单进度条实现 (示意)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 6)
                    
                    let progress = min(max(1 - (debt.outstandingPrincipal / debt.principal), 0), 1)
                    Capsule()
                        .fill(LinearGradient(colors: [AppColors.primaryBlue, AppColors.primaryBlue.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(progress), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding()
        .background(AppColors.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 4)
    }
}

struct StatusBadge: View {
    let status: DebtStatus

    var color: Color {
        switch status {
        case .normal: return AppColors.accentGreen
        case .overdue: return .red
        case .settled: return .gray
        }
    }

    var body: some View {
        Text(status.rawValue)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.1))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

struct AdvisoryCard: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color
    var footnote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundColor(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)
            }

            if let footnote, !footnote.isEmpty {
                Text(footnote)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(AppColors.cardBackground)
        .cornerRadius(16)
    }
}

struct MetricMiniCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundColor(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.08))
        .cornerRadius(12)
    }
}

struct BulletNoteRow: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .padding(.top, 5)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

private struct DashboardPriorityItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let systemImage: String
    let tint: Color
    var footnote: String? = nil
    var rank: Int = 99
    var dueDate: Date? = nil
}

private struct FocusReminderHubCard: View {
    let priorityItems: [DashboardPriorityItem]
    let reminders: [ReminderTask]

    private var reminderPreview: [ReminderTask] {
        Array(reminders
            .sorted {
                if $0.remindAt != $1.remindAt {
                    return $0.remindAt < $1.remindAt
                }
                return reminderSortRank(for: $0.category) < reminderSortRank(for: $1.category)
            }
            .prefix(3))
    }

    private func reminderSortRank(for category: ReminderCategory) -> Int {
        switch category {
        case .creditCardStatementRefresh:
            return 0
        case .repaymentDue:
            return 1
        }
    }

    private var summaryText: String {
        switch (priorityItems.isEmpty, reminderPreview.isEmpty) {
        case (true, true):
            return "当前没有待处理事项，继续保持现有执行节奏即可。"
        case (false, true):
            return "先把上方执行重点完成，再回来复盘策略与预算。"
        case (true, false):
            return "当前没有阻塞项，按提醒日期推进本月计划即可。"
        case (false, false):
            return "先处理执行重点，再跟进近期提醒，避免预算与到期安排脱节。"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summaryText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if priorityItems.isEmpty && reminderPreview.isEmpty {
                HStack {
                    Spacer()
                    Text("暂无待处理提醒")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                    Spacer()
                }
            } else {
                if !priorityItems.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(priorityItems) { item in
                            PriorityItemRow(item: item)
                        }
                    }
                }

                if !reminderPreview.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("近期提醒")
                            .font(.subheadline.weight(.semibold))

                        ForEach(reminderPreview) { reminder in
                            ReminderTimelineRow(reminder: reminder)
                        }
                    }
                }
            }
        }
        .padding()
        .background(AppColors.cardBackground)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 5)
    }
}

private struct PriorityItemRow: View {
    let item: DashboardPriorityItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.systemImage)
                    .font(.title3)
                    .foregroundColor(item.tint)
                    .frame(width: 34, height: 34)
                    .background(item.tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                    Text(item.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            if let footnote = item.footnote, !footnote.isEmpty {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(item.tint.opacity(0.08))
        .cornerRadius(14)
    }
}

private struct ReminderTimelineRow: View {
    let reminder: ReminderTask

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(AppColors.warningOrange)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .font(.subheadline.weight(.semibold))
                Text(reminder.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text(reminder.remindAt, format: .dateTime.month().day())
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
        }
        .padding()
        .background(Color.gray.opacity(0.08))
        .cornerRadius(14)
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}

private struct RepaymentCalendarDay: Identifiable {
    let date: Date
    let isInDisplayedMonth: Bool
    let plans: [RepaymentPlan]

    var id: Date { date }

    var totalDue: Double {
        plans.reduce(0) { $0 + $1.totalDue }
    }

    var markerCount: Int {
        min(plans.count, 3)
    }
}

private struct RepaymentPlanCalendarCard: View {
    let plans: [RepaymentPlan]

    private let calendar = Calendar.current
    @State private var displayedMonth = Calendar.current.startOfMonth(for: Date())
    @State private var selectedDate = Date()

    private var monthPlans: [RepaymentPlan] {
        plans
            .filter { calendar.isDate($0.dueDate, equalTo: displayedMonth, toGranularity: .month) }
            .sorted(by: { $0.dueDate < $1.dueDate })
    }

    private var selectedDayPlans: [RepaymentPlan] {
        monthPlans.filter { calendar.isDate($0.dueDate, inSameDayAs: selectedDate) }
    }

    private var monthTotalDue: Double {
        monthPlans.reduce(0) { $0 + $1.totalDue }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let startIndex = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[startIndex...]) + Array(symbols[..<startIndex])
    }

    private var monthDays: [RepaymentCalendarDay] {
        let startOfMonth = calendar.startOfMonth(for: displayedMonth)
        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        let leadingSlotCount = (firstWeekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leadingSlotCount, to: startOfMonth) ?? startOfMonth

        return (0..<42).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else { return nil }
            return RepaymentCalendarDay(
                date: date,
                isInDisplayedMonth: calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month),
                plans: monthPlans.filter { calendar.isDate($0.dueDate, inSameDayAs: date) }
            )
        }
    }

    private var planListTitle: String {
        selectedDayPlans.isEmpty ? "本月计划" : "\(selectedDate.formatted(date: .abbreviated, time: .omitted)) 还款安排"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button {
                    shiftMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                }

                Spacer()

                VStack(spacing: 4) {
                    Text(displayedMonth, format: .dateTime.year().month(.wide))
                        .font(.caption.weight(.semibold))
                    Text(monthPlans.isEmpty ? "左右滑动切换月份查看计划" : "\(monthPlans.count) 笔计划 · 合计 \(currencyText(monthTotalDue))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)

                Spacer()

                Button {
                    shiftMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Circle())
                }
            }

            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(monthDays) { day in
                    Button {
                        selectedDate = day.date
                    } label: {
                        VStack(spacing: 5) {
                            Text("\(calendar.component(.day, from: day.date))")
                                .font(.subheadline.weight(.semibold))

                            if day.plans.isEmpty {
                                Spacer(minLength: 0)
                            } else {
                                Text(dayAmountText(day.totalDue))
                                    .font(.system(size: 10, weight: .semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)

                                HStack(spacing: 3) {
                                    ForEach(0..<day.markerCount, id: \.self) { _ in
                                        Circle()
                                            .fill(dayMarkerColor(for: day))
                                            .frame(width: 4, height: 4)
                                    }
                                    if day.plans.count > day.markerCount {
                                        Text("+\(day.plans.count - day.markerCount)")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(dayForegroundColor(for: day).opacity(0.85))
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .padding(.vertical, 2)
                        .foregroundStyle(dayForegroundColor(for: day))
                        .background(dayBackground(for: day))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(dayBorderColor(for: day), lineWidth: calendar.isDate(day.date, inSameDayAs: Date()) ? 1.2 : 0.8)
                        )
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }

            if monthPlans.isEmpty {
                Text("所选月份暂无待执行计划，可左右滑动切换月份查看后续安排。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(planListTitle)
                        .font(.subheadline.weight(.semibold))

                    if selectedDayPlans.isEmpty {
                        Text("当前选中日期无计划，以下展示本月最近 \(min(monthPlans.count, 4)) 笔安排。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(selectedDayPlans.isEmpty ? Array(monthPlans.prefix(4)) : selectedDayPlans) { plan in
                    planRow(plan)
                }
            }
        }
        .padding(12)
        .background(AppColors.cardBackground)
        .cornerRadius(16)
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded(handleMonthSwipe)
        )
        .onAppear {
            syncSelection(for: displayedMonth)
        }
        .onChange(of: displayedMonth) { _, newValue in
            syncSelection(for: newValue)
        }
    }

    @ViewBuilder
    private func planRow(_ plan: RepaymentPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.debt?.name ?? "未关联债务")
                        .font(.subheadline.weight(.semibold))
                    Text("第 \(plan.periodIndex) 期 · \(plan.status.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(plan.dueDate, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("全额应还 \(currencyText(plan.totalDue))")
                        .font(.caption.weight(.medium))
                    Text("最低应还 \(currencyText(plan.minimumDue))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(plan.debt?.type.rawValue ?? "")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .padding(10)
        .background(Color.gray.opacity(0.08))
        .cornerRadius(10)
    }

    private func dayAmountText(_ amount: Double) -> String {
        if amount >= 10_000 {
            return String(format: "%.1f万", amount / 10_000)
        }
        return String(format: "¥%.0f", amount)
    }

    private func shiftMonth(by offset: Int) {
        guard let nextMonth = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            displayedMonth = calendar.startOfMonth(for: nextMonth)
        }
    }

    private func syncSelection(for month: Date) {
        if let matchingDay = monthPlans.first(where: { calendar.isDate($0.dueDate, inSameDayAs: selectedDate) }) {
            selectedDate = matchingDay.dueDate
        } else if calendar.isDate(Date(), equalTo: month, toGranularity: .month) {
            selectedDate = Date()
        } else if let firstPlan = monthPlans.first {
            selectedDate = firstPlan.dueDate
        } else {
            selectedDate = month
        }
    }

    private func handleMonthSwipe(_ value: DragGesture.Value) {
        guard abs(value.translation.width) > abs(value.translation.height), abs(value.translation.width) > 40 else { return }
        shiftMonth(by: value.translation.width < 0 ? 1 : -1)
    }

    private func dayForegroundColor(for day: RepaymentCalendarDay) -> Color {
        if calendar.isDate(day.date, inSameDayAs: selectedDate) {
            return .white
        }
        return day.isInDisplayedMonth ? .primary : .secondary.opacity(0.6)
    }

    @ViewBuilder
    private func dayBackground(for day: RepaymentCalendarDay) -> some View {
        if calendar.isDate(day.date, inSameDayAs: selectedDate) {
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.primaryBlue)
        } else if !day.plans.isEmpty {
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.primaryBlue.opacity(day.isInDisplayedMonth ? 0.12 : 0.06))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(day.isInDisplayedMonth ? Color.gray.opacity(0.06) : Color.gray.opacity(0.03))
        }
    }

    private func dayBorderColor(for day: RepaymentCalendarDay) -> Color {
        if calendar.isDate(day.date, inSameDayAs: selectedDate) {
            return AppColors.primaryBlue
        }
        if calendar.isDate(day.date, inSameDayAs: Date()) {
            return AppColors.primaryBlue.opacity(0.5)
        }
        return day.plans.isEmpty ? Color.clear : AppColors.primaryBlue.opacity(0.18)
    }

    private func dayMarkerColor(for day: RepaymentCalendarDay) -> Color {
        let startOfToday = calendar.startOfDay(for: Date())
        if calendar.startOfDay(for: day.date) < startOfToday {
            return .red.opacity(calendar.isDate(day.date, inSameDayAs: selectedDate) ? 0.9 : 0.75)
        }
        return calendar.isDate(day.date, inSameDayAs: selectedDate) ? .white.opacity(0.95) : AppColors.primaryBlue.opacity(0.8)
    }
}

struct StrategyComparisonSnapshot: Identifiable {
    let id: UUID
    let method: StrategyMethod
    let label: String
    let generatedAt: Date?
    let monthlyBudget: Double?
    let totalInterest: Double
    let payoffDate: Date
    let monthsToPayoff: Int
    let isFeasible: Bool
    let infeasibleReason: String?
    let monthRecords: [FinanceEngine.StrategyTimelinePayload.MonthRecord]

    init(method: StrategyMethod, result: FinanceEngine.StrategyResult) {
        let timeline = FinanceEngine.decodeStrategyTimeline(from: result.timelineJSON)
        let records = timeline?.records ?? []

        self.id = UUID()
        self.method = method
        self.label = method.rawValue
        self.generatedAt = nil
        self.monthlyBudget = nil
        self.totalInterest = result.totalInterest
        self.payoffDate = result.payoffDate
        self.monthsToPayoff = records.count
        self.isFeasible = timeline?.completed ?? false
        self.infeasibleReason = timeline?.infeasibleReason
        self.monthRecords = records
    }

    init(scenario: StrategyScenario) {
        let timeline = FinanceEngine.decodeStrategyTimeline(from: scenario.timelineJSON)
        let records = timeline?.records ?? []

        self.id = scenario.id
        self.method = scenario.method
        self.label = scenario.name
        self.generatedAt = scenario.generatedAt
        self.monthlyBudget = scenario.monthlyBudget
        self.totalInterest = scenario.totalInterest
        self.payoffDate = scenario.payoffDate
        self.monthsToPayoff = records.count
        self.isFeasible = timeline?.completed ?? false
        self.infeasibleReason = timeline?.infeasibleReason
        self.monthRecords = records
    }

    var methodLabel: String { label }

    var methodColor: Color {
        switch method {
        case .avalanche:
            return AppColors.primaryBlue
        case .snowball:
            return AppColors.accentGreen
        case .balanced:
            return .purple
        }
    }

    var displayColor: Color {
        isFeasible ? methodColor : AppColors.warningOrange
    }

    var statusText: String {
        isFeasible ? "可执行" : "不可执行"
    }

    var shortSummary: String {
        if isFeasible {
            return "约 \(monthsToPayoff) 个月 · 结清 \(shortDateText(payoffDate))"
        }
        return infeasibleReason ?? "当前预算或约束下不可执行"
    }

    var previewMonthRecords: [FinanceEngine.StrategyTimelinePayload.MonthRecord] {
        Array(monthRecords.prefix(24))
    }

    var hasTruncatedPreview: Bool {
        monthRecords.count > previewMonthRecords.count
    }

    var averageMonthlyPayment: Double {
        guard !monthRecords.isEmpty else { return 0 }
        return monthRecords.reduce(0) { $0 + $1.paymentApplied } / Double(monthRecords.count)
    }

    var remainingPrincipalAfterTwelveMonths: Double {
        guard !monthRecords.isEmpty else { return 0 }
        if let twelfthMonth = monthRecords.first(where: { $0.monthIndex == 12 }) {
            return twelfthMonth.totalPrincipal
        }
        return monthRecords[min(11, monthRecords.count - 1)].totalPrincipal
    }

    var overdueCoverageRatio: Double? {
        let required = monthRecords.reduce(0) { $0 + $1.overdueRequired }
        guard required > 0 else { return nil }
        let paid = monthRecords.reduce(0) { $0 + $1.overduePaid }
        return min(max(paid / required, 0), 1)
    }

    var remainingOverdueBalance: Double {
        monthRecords.last?.debtActions.reduce(0) { $0 + $1.closingOverdueBalance } ?? 0
    }
}

private struct StrategyChartCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            content()
        }
        .padding()
        .background(AppColors.cardBackground)
        .cornerRadius(16)
    }
}

private enum StrategyComparisonDimension: String, CaseIterable, Identifiable {
    case totalInterest = "总利息"
    case payoffDuration = "结清时间"
    case averageMonthlyPayment = "月还款"
    case remainingPrincipal = "剩余本金"
    case overdueCoverage = "逾期覆盖"

    var id: String { rawValue }
}

private enum StrategyTrendDimension: String, CaseIterable, Identifiable {
    case debtBalance = "债务余额"
    case monthlyPayment = "月还款"
    case minimumRequired = "最低应还"
    case remainingBudget = "预算余量"
    case interestAccrued = "新增利息"
    case overdueCoverage = "逾期覆盖"
    case remainingOverdueBalance = "剩余逾期"

    var id: String { rawValue }
}

private struct ChartDimensionChipBar<Option: CaseIterable & Identifiable & RawRepresentable>: View where Option.AllCases: RandomAccessCollection, Option.RawValue == String {
    @Binding var selection: Option

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(Option.allCases), id: \.id) { option in
                    Button {
                        selection = option
                    } label: {
                        Text(option.rawValue)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selection.id == option.id ? AppColors.primaryBlue : Color.gray.opacity(0.12))
                            .foregroundColor(selection.id == option.id ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
}

struct StrategyComparisonChartsSection: View {
    let snapshots: [StrategyComparisonSnapshot]
    let selectedSnapshotID: UUID?
    @State private var selectedDimension: StrategyComparisonDimension = .totalInterest

    private var selectedSnapshot: StrategyComparisonSnapshot? {
        if let selectedSnapshotID {
            return snapshots.first(where: { $0.id == selectedSnapshotID }) ?? snapshots.first
        }
        return snapshots.first
    }

    private var comparisonTitle: String {
        switch selectedDimension {
        case .totalInterest:
            return "三种策略总利息对比"
        case .payoffDuration:
            return "预计结清时长对比"
        case .averageMonthlyPayment:
            return "月还款压力对比"
        case .remainingPrincipal:
            return "12个月后剩余本金对比"
        case .overdueCoverage:
            return "逾期覆盖率对比"
        }
    }

    private var comparisonSubtitle: String {
        switch selectedDimension {
        case .totalInterest:
            return "橙色表示当前预算或约束下不可执行；推荐策略会用星标标记。"
        case .payoffDuration:
            return "按当前预算和约束测算的月数，越低通常代表越快还清。"
        case .averageMonthlyPayment:
            return "用于观察清偿路径中的平均支付压力，便于评估执行稳定性。"
        case .remainingPrincipal:
            return "比较前12个月本金压降速度，越低通常越能更快降低时间成本和利息成本。"
        case .overdueCoverage:
            return "仅对存在逾期约束的策略显示；无逾期时会显示为 0%。"
        }
    }

    private var selectedPreviewTitle: String {
        guard let selectedSnapshot else { return "趋势预览" }
        switch selectedDimension {
        case .totalInterest, .payoffDuration, .remainingPrincipal:
            return "\(selectedSnapshot.methodLabel) · 前 \(selectedSnapshot.previewMonthRecords.count) 个月债务余额走势"
        case .averageMonthlyPayment:
            return "\(selectedSnapshot.methodLabel) · 前 \(selectedSnapshot.previewMonthRecords.count) 个月月还款走势"
        case .overdueCoverage:
            return "\(selectedSnapshot.methodLabel) · 前 \(selectedSnapshot.previewMonthRecords.count) 个月逾期覆盖走势"
        }
    }

    private var selectedPreviewSubtitle: String {
        guard let selectedSnapshot else { return "" }
        if selectedSnapshot.hasTruncatedPreview {
            return "仅展示前 24 个月趋势，避免长周期策略图表过于拥挤。"
        }
        return selectedSnapshot.shortSummary
    }

    private func comparisonValue(for snapshot: StrategyComparisonSnapshot) -> Double {
        switch selectedDimension {
        case .totalInterest:
            return snapshot.totalInterest
        case .payoffDuration:
            return Double(snapshot.monthsToPayoff)
        case .averageMonthlyPayment:
            return snapshot.averageMonthlyPayment
        case .remainingPrincipal:
            return snapshot.remainingPrincipalAfterTwelveMonths
        case .overdueCoverage:
            return (snapshot.overdueCoverageRatio ?? 0) * 100
        }
    }

    private func comparisonAnnotation(for snapshot: StrategyComparisonSnapshot) -> String {
        switch selectedDimension {
        case .totalInterest:
            return snapshot.isFeasible ? currencyText(snapshot.totalInterest) : "不可执行"
        case .payoffDuration:
            return snapshot.isFeasible ? "\(snapshot.monthsToPayoff)个月" : "不可执行"
        case .averageMonthlyPayment:
            return snapshot.isFeasible ? currencyText(snapshot.averageMonthlyPayment) : "不可执行"
        case .remainingPrincipal:
            return snapshot.isFeasible ? currencyText(snapshot.remainingPrincipalAfterTwelveMonths) : "不可执行"
        case .overdueCoverage:
            if let ratio = snapshot.overdueCoverageRatio {
                return String(format: "%.0f%%", ratio * 100)
            }
            return "无逾期"
        }
    }

    @ViewBuilder
    private func selectedPreviewChart(for snapshot: StrategyComparisonSnapshot) -> some View {
        switch selectedDimension {
        case .totalInterest, .payoffDuration, .remainingPrincipal:
            Chart(snapshot.previewMonthRecords, id: \.monthIndex) { record in
                AreaMark(
                    x: .value("月份", record.monthIndex),
                    y: .value("债务余额", record.totalPrincipal)
                )
                .foregroundStyle(snapshot.displayColor.opacity(0.14))

                LineMark(
                    x: .value("月份", record.monthIndex),
                    y: .value("债务余额", record.totalPrincipal)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(snapshot.displayColor)
                .lineStyle(.init(lineWidth: 3))

                if record.isBudgetShortfall {
                    PointMark(
                        x: .value("月份", record.monthIndex),
                        y: .value("债务余额", record.totalPrincipal)
                    )
                    .foregroundStyle(AppColors.warningOrange)
                    .symbolSize(40)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 220)

        case .averageMonthlyPayment:
            Chart(snapshot.previewMonthRecords, id: \.monthIndex) { record in
                BarMark(
                    x: .value("月份", record.monthIndex),
                    y: .value("月还款", record.paymentApplied)
                )
                .foregroundStyle(snapshot.displayColor.gradient)
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 220)

        case .overdueCoverage:
            let hasOverdueData = snapshot.previewMonthRecords.contains { $0.overdueRequired > 0 }
            if hasOverdueData {
                Chart(snapshot.previewMonthRecords, id: \.monthIndex) { record in
                    let ratio = record.overdueRequired > 0 ? (record.overduePaid / record.overdueRequired) * 100 : 0
                    LineMark(
                        x: .value("月份", record.monthIndex),
                        y: .value("逾期覆盖率", ratio)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(snapshot.displayColor)
                    .lineStyle(.init(lineWidth: 3))

                    PointMark(
                        x: .value("月份", record.monthIndex),
                        y: .value("逾期覆盖率", ratio)
                    )
                    .foregroundStyle(snapshot.displayColor)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 220)
            } else {
                ContentUnavailableView("当前无逾期约束数据", systemImage: "checkmark.shield", description: Text("这组策略数据中没有需要覆盖的逾期成本，因此策略暂无可对比曲线。"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
            }
        }
    }

    @ViewBuilder
    private var comparisonChart: some View {
        let chart = Chart {
            ForEach(snapshots) { snapshot in
                BarMark(
                    x: .value("策略", snapshot.methodLabel),
                    y: .value(comparisonTitle, comparisonValue(for: snapshot))
                )
                .foregroundStyle(snapshot.displayColor.gradient)
                .cornerRadius(8)
                .annotation(position: .top) {
                    Text(comparisonAnnotation(for: snapshot))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }

        if selectedDimension == .overdueCoverage {
            chart
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 220)
        } else {
            chart
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 220)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "图表对比")

            ChartDimensionChipBar(selection: $selectedDimension)
                .padding(.horizontal)

            StrategyChartCard(
                title: comparisonTitle,
                subtitle: comparisonSubtitle
            ) {
                comparisonChart
            }
            .padding(.horizontal)

            if let selectedSnapshot, !selectedSnapshot.previewMonthRecords.isEmpty {
                StrategyChartCard(
                    title: selectedPreviewTitle,
                    subtitle: selectedPreviewSubtitle
                ) {
                    selectedPreviewChart(for: selectedSnapshot)
                }
                .padding(.horizontal)
            }

            VStack(spacing: 8) {
                ForEach(snapshots) { snapshot in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(snapshot.displayColor)
                            .frame(width: 10, height: 10)
                            .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(snapshot.methodLabel)
                                    .font(.caption.weight(.semibold))
                                Text(snapshot.statusText)
                                    .font(.caption2)
                                    .foregroundStyle(snapshot.isFeasible ? AppColors.accentGreen : AppColors.warningOrange)
                            }
                            Text(snapshot.shortSummary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(comparisonAnnotation(for: snapshot))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct StrategyTimelineChartsSection: View {
    let monthRecords: [FinanceEngine.StrategyTimelinePayload.MonthRecord]
    var statusText: String
    @State private var selectedDimension: StrategyTrendDimension = .debtBalance

    private var visibleMonthRecords: [FinanceEngine.StrategyTimelinePayload.MonthRecord] {
        Array(monthRecords.prefix(60))
    }

    private var isTruncated: Bool {
        monthRecords.count > visibleMonthRecords.count
    }

    private var hasOverdueData: Bool {
        visibleMonthRecords.contains { $0.overdueRequired > 0 || $0.debtActions.contains(where: { $0.closingOverdueBalance > 0.01 }) }
    }

    private var chartTitle: String {
        switch selectedDimension {
        case .debtBalance:
            return "债务余额变化"
        case .monthlyPayment:
            return "月还款变化"
        case .minimumRequired:
            return "最低应还变化"
        case .remainingBudget:
            return "预算余量变化"
        case .interestAccrued:
            return "新增利息变化"
        case .overdueCoverage:
            return "逾期覆盖率变化"
        case .remainingOverdueBalance:
            return "剩余逾期余额变化"
        }
    }

    private var chartSubtitle: String {
        switch selectedDimension {
        case .debtBalance:
            return isTruncated ? "仅展示前 60 个月走势，便于观察长期策略变化。" : statusText
        case .monthlyPayment:
            return "用于观察每月支付强度是否平稳，判断策略执行压力。"
        case .minimumRequired:
            return "用于识别哪些月份硬约束更高，帮助你提前安排现金流。"
        case .remainingBudget:
            return "若长期接近 0，说明策略已逼近预算上限；余量越多，执行弹性越好。"
        case .interestAccrued:
            return "利息曲线越快下行，通常代表高成本债务更早得到压降。"
        case .overdueCoverage:
            return "展示每月逾期成本的覆盖程度，100% 表示当月已完全覆盖。"
        case .remainingOverdueBalance:
            return "帮助判断逾期成本是否被及时清理干净。"
        }
    }

    @ViewBuilder
    private var activeChart: some View {
        switch selectedDimension {
        case .debtBalance:
            Chart(visibleMonthRecords, id: \.monthIndex) { record in
                AreaMark(
                    x: .value("月份", record.monthIndex),
                    y: .value("债务余额", record.totalPrincipal)
                )
                .foregroundStyle(AppColors.primaryBlue.opacity(0.12))

                LineMark(
                    x: .value("月份", record.monthIndex),
                    y: .value("债务余额", record.totalPrincipal)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(AppColors.primaryBlue)
                .lineStyle(.init(lineWidth: 3))

                if record.isBudgetShortfall {
                    PointMark(
                        x: .value("月份", record.monthIndex),
                        y: .value("债务余额", record.totalPrincipal)
                    )
                    .foregroundStyle(AppColors.warningOrange)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 220)

        case .monthlyPayment:
            Chart(visibleMonthRecords, id: \.monthIndex) { record in
                BarMark(
                    x: .value("月份", record.monthIndex),
                    y: .value("月还款", record.paymentApplied)
                )
                .foregroundStyle(AppColors.accentGreen.gradient)
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 220)

        case .minimumRequired:
            Chart(visibleMonthRecords, id: \.monthIndex) { record in
                BarMark(
                    x: .value("月份", record.monthIndex),
                    y: .value("最低应还", record.minimumRequired)
                )
                .foregroundStyle(AppColors.primaryBlue.gradient)
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 220)

        case .remainingBudget:
            Chart(visibleMonthRecords, id: \.monthIndex) { record in
                AreaMark(
                    x: .value("月份", record.monthIndex),
                    y: .value("预算余量", record.remainingBudget)
                )
                .foregroundStyle(AppColors.accentGreen.opacity(0.14))

                LineMark(
                    x: .value("月份", record.monthIndex),
                    y: .value("预算余量", record.remainingBudget)
                )
                .foregroundStyle(AppColors.accentGreen)
                .lineStyle(.init(lineWidth: 3))

                if record.isBudgetShortfall {
                    PointMark(
                        x: .value("月份", record.monthIndex),
                        y: .value("预算余量", record.remainingBudget)
                    )
                    .foregroundStyle(AppColors.warningOrange)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 220)

        case .interestAccrued:
            Chart(visibleMonthRecords, id: \.monthIndex) { record in
                LineMark(
                    x: .value("月份", record.monthIndex),
                    y: .value("新增利息", record.interestAccrued)
                )
                .foregroundStyle(AppColors.warningOrange)
                .lineStyle(.init(lineWidth: 3))

                PointMark(
                    x: .value("月份", record.monthIndex),
                    y: .value("新增利息", record.interestAccrued)
                )
                .foregroundStyle(AppColors.warningOrange)
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 220)

        case .overdueCoverage:
            if hasOverdueData {
                Chart(visibleMonthRecords, id: \.monthIndex) { record in
                    let ratio = record.overdueRequired > 0 ? (record.overduePaid / record.overdueRequired) * 100 : 0
                    LineMark(
                        x: .value("月份", record.monthIndex),
                        y: .value("逾期覆盖率", ratio)
                    )
                    .foregroundStyle(.purple)
                    .lineStyle(.init(lineWidth: 3))

                    PointMark(
                        x: .value("月份", record.monthIndex),
                        y: .value("逾期覆盖率", ratio)
                    )
                    .foregroundStyle(.purple)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 220)
            } else {
                ContentUnavailableView("暂无逾期覆盖数据", systemImage: "checkmark.circle", description: Text("当前这条策略时间线中没有需要覆盖的逾期成本，因此该维度暂无图表。"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
            }

        case .remainingOverdueBalance:
            if hasOverdueData {
                Chart(visibleMonthRecords, id: \.monthIndex) { record in
                    let remaining = record.debtActions.reduce(0) { $0 + $1.closingOverdueBalance }
                    AreaMark(
                        x: .value("月份", record.monthIndex),
                        y: .value("剩余逾期余额", remaining)
                    )
                    .foregroundStyle(.red.opacity(0.12))

                    LineMark(
                        x: .value("月份", record.monthIndex),
                        y: .value("剩余逾期余额", remaining)
                    )
                    .foregroundStyle(.red)
                    .lineStyle(.init(lineWidth: 3))
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 220)
            } else {
                ContentUnavailableView("当前没有剩余逾期余额", systemImage: "checkmark.circle", description: Text("这条策略时间线没有残留逾期余额，因此该维度暂无图表。"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "图表趋势")

            ChartDimensionChipBar(selection: $selectedDimension)
                .padding(.horizontal)

            StrategyChartCard(
                title: chartTitle,
                subtitle: chartSubtitle
            ) {
                activeChart
            }
            .padding(.horizontal)
        }
    }
}

private struct SettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 用户简况预览卡片
                HStack(spacing: 16) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(AppColors.primaryBlue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("财富自律用户")
                            .font(.headline)
                        Text("守护您的财务健康")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding()
                .background(AppColors.cardBackground)
                .cornerRadius(16)
                .padding(.horizontal)
                .padding(.top, 12)

                SectionHeader(title: "提醒与通知")
                NotificationSettingsInlineCard()
                    .padding(.horizontal)
                
                VStack(spacing: 1) {
                    SettingsLink(title: "计算规则", icon: "function", color: .indigo) { RuleProfileManagementView() }
                    SettingsLink(title: "订阅管理", icon: "star.fill", color: .orange) { SubscriptionManagementView() }
                }
                .background(AppColors.cardBackground)
                .cornerRadius(16)
                .padding(.horizontal)
                
                VStack(spacing: 1) {
                    SettingsLink(title: "隐私声明", icon: "shield.lefthalf.filled", color: .green) { PrivacyComplianceView() }
                }
                .background(AppColors.cardBackground)
                .cornerRadius(16)
                .padding(.horizontal)
                
                VStack(spacing: 8) {
                    Text("个人债务管理工具")
                    Text("版本 1.0.0 (Build 20260426)")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
            }
            .padding(.bottom, 20)
        }
        .background(AppColors.backgroundGray)
    }
}

private struct NotificationSettingsInlineCard: View {
    @Query(sort: \ReminderTask.remindAt, order: .forward) private var reminders: [ReminderTask]
    @AppStorage("reminderNotificationsEnabled") private var remindersEnabled = true

    var body: some View {
        Toggle("启用通知提醒", isOn: $remindersEnabled)
            .font(.subheadline.weight(.medium))
            .onChange(of: remindersEnabled) { _, newValue in
                Task {
                    await syncReminderPreference(enabled: newValue)
                }
            }
        .padding()
        .background(AppColors.cardBackground)
        .cornerRadius(16)
        .task {
            await syncReminderPreference(enabled: remindersEnabled)
        }
    }

    private func syncReminderPreference(enabled: Bool) async {
        AppPreferenceService.reminderNotificationsEnabled = enabled
        if enabled {
            _ = await ReminderNotificationService.requestAuthorization()
        }
        await ReminderNotificationService.sync(reminders: reminders)
    }
}

struct SettingsLink<Destination: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let destination: () -> Destination
    
    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(color)
                    .cornerRadius(6)
                
                Text(title)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }
}

private struct RuleProfileManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Debt.createdAt, order: .reverse) private var debts: [Debt]
    @Query(sort: \CalculationRuleProfile.name, order: .forward) private var profiles: [CalculationRuleProfile]

    @State private var showDebtSelector = false
    @State private var selectedDebtForCustomRule: Debt?
    @State private var showCustomRuleEditor = false

    private var customRuleItems: [(debt: Debt, rule: DebtCustomRule)] {
        debts.compactMap { debt in
            guard let rule = debt.customRule else { return nil }
            return (debt, rule)
        }
        .sorted { $0.debt.name < $1.debt.name }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "计算规则列表")
                ForEach(DebtType.allCases) { debtType in
                    NavigationLink {
                        DefaultRuleCategoryDetailView(debtType: debtType)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: iconName(for: debtType))
                                .font(.title3)
                                .foregroundStyle(AppColors.primaryBlue)
                                .frame(width: 36, height: 36)
                                .background(AppColors.primaryBlue.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(debtType.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("查看该类别默认计算规则")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(AppColors.cardBackground)
                        .cornerRadius(14)
                    }
                    .padding(.horizontal)
                }

                SectionHeader(title: "自定义计算规则")
                if customRuleItems.isEmpty {
                    Text("当前没有针对具体债务的自定义规则。可点击右下角按钮新增。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColors.cardBackground)
                        .cornerRadius(14)
                        .padding(.horizontal)
                } else {
                    ForEach(customRuleItems, id: \.debt.id) { item in
                        NavigationLink {
                            DebtCustomRuleFormView(rule: item.rule, debt: item.debt) { updatedRule in
                                item.debt.customRule = updatedRule
                                item.debt.calculationRuleName = updatedRule.name
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.debt.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(item.rule.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .background(AppColors.cardBackground)
                            .cornerRadius(14)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 8)
        }
        .background(AppColors.backgroundGray)
        .overlay(alignment: .bottomTrailing) {
            FloatingAddButton {
                showDebtSelector = true
            }
        }
        .task {
            RuleTemplateCatalogService.ensureBuiltInProfiles(modelContext: modelContext)
        }
        .sheet(isPresented: $showDebtSelector) {
            NavigationStack {
                DebtRuleCreationSelectorView { debt in
                    selectedDebtForCustomRule = debt
                    showCustomRuleEditor = true
                }
            }
        }
        .sheet(isPresented: $showCustomRuleEditor) {
            if let selectedDebtForCustomRule {
                NavigationStack {
                    DebtCustomRuleFormView(
                        rule: selectedDebtForCustomRule.customRule,
                        debt: selectedDebtForCustomRule,
                        presetProfile: defaultProfile(for: selectedDebtForCustomRule.type),
                        lockedRuleName: "\(selectedDebtForCustomRule.name)专用计算规则"
                    ) { updatedRule in
                        selectedDebtForCustomRule.customRule = updatedRule
                        selectedDebtForCustomRule.calculationRuleName = updatedRule.name
                    }
                }
            }
        }
    }

    private func iconName(for type: DebtType) -> String {
        switch type {
        case .creditCard:
            return "creditcard"
        case .loan:
            return "building.columns"
        case .privateLending:
            return "person.2"
        }
    }

    private func defaultProfile(for type: DebtType) -> CalculationRuleProfile? {
        RuleTemplateCatalogService.defaultProfile(for: type, in: profiles) ?? profiles.first
    }
}

private struct DefaultRuleCategoryDetailView: View {
    let debtType: DebtType
    @Query(sort: \CalculationRuleProfile.name, order: .forward) private var profiles: [CalculationRuleProfile]

    private struct RuleFieldRow: Identifiable {
        let id = UUID()
        let title: String
        let value: String
    }

    private struct RuleFieldSection: Identifiable {
        let id = UUID()
        let title: String
        let rows: [RuleFieldRow]
    }

    private var matchedProfiles: [CalculationRuleProfile] {
        if let profile = RuleTemplateCatalogService.defaultProfile(for: debtType, in: profiles) {
            return [profile]
        }
        return []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if matchedProfiles.isEmpty {
                    Text("当前类别暂无默认规则。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColors.cardBackground)
                        .cornerRadius(14)
                        .padding(.horizontal)
                } else {
                    ForEach(matchedProfiles) { profile in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(profile.name)
                                .font(.subheadline.weight(.semibold))

                            ForEach(sections(for: profile)) { section in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(section.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)

                                    VStack(spacing: 0) {
                                        ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                                            DetailRow(title: row.title, value: row.value)
                                            if index < section.rows.count - 1 {
                                                DetailDivider()
                                            }
                                        }
                                    }
                                    .background(Color.gray.opacity(0.08))
                                    .cornerRadius(10)
                                }
                            }
                        }
                        .padding()
                        .background(AppColors.cardBackground)
                        .cornerRadius(14)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical, 8)
        }
        .background(AppColors.backgroundGray)
    }

    private func sections(for profile: CalculationRuleProfile) -> [RuleFieldSection] {
        let debtSection = RuleFieldSection(
            title: "债务",
            rows: [
                RuleFieldRow(title: "适用债务类型", value: debtType.rawValue),
                RuleFieldRow(title: "规则来源", value: ruleSourceText(for: profile))
            ]
        )

        var repaymentRows: [RuleFieldRow] = [
            RuleFieldRow(title: "还款分配顺序", value: profile.paymentAllocationOrder.displayText),
            RuleFieldRow(title: "还款提醒提前", value: "\(profile.repaymentReminderLeadDays) 天")
        ]

        var overdueRows: [RuleFieldRow] = [
            RuleFieldRow(title: "逾期罚息模式", value: profile.overduePenaltyMode.rawValue)
        ]

        switch debtType {
        case .creditCard:
            repaymentRows += [
                RuleFieldRow(title: "最低还款比例", value: percentText(profile.defaultCreditCardMinimumRate)),
                RuleFieldRow(title: "最低还款保底", value: currencyText(profile.defaultCreditCardMinimumFloor)),
                RuleFieldRow(title: "最低还款含费用", value: boolText(profile.defaultCreditCardMinimumIncludesFees)),
                RuleFieldRow(title: "最低还款含罚息", value: boolText(profile.defaultCreditCardMinimumIncludesPenalty)),
                RuleFieldRow(title: "最低还款含利息", value: boolText(profile.defaultCreditCardMinimumIncludesInterest)),
                RuleFieldRow(title: "最低还款含分期本金", value: boolText(profile.defaultCreditCardMinimumIncludesInstallmentPrincipal)),
                RuleFieldRow(title: "最低还款含分期手续费", value: boolText(profile.defaultCreditCardMinimumIncludesInstallmentFee)),
                RuleFieldRow(title: "账单提醒偏移", value: "\(profile.creditCardStatementReminderOffsetDays) 天"),
                RuleFieldRow(title: "要求账单更新", value: boolText(profile.requireCreditCardStatementRefresh))
            ]
            overdueRows += [
                RuleFieldRow(title: "逾期计息基数", value: profile.defaultCreditCardOverdueInterestBase.rawValue),
                RuleFieldRow(title: "罚息日利率", value: percentText(profile.defaultCreditCardPenaltyDailyRate)),
                RuleFieldRow(title: "逾期固定费用", value: currencyText(profile.defaultCreditCardOverdueFeeFlat)),
                RuleFieldRow(title: "逾期宽限期", value: "\(profile.defaultCreditCardOverdueGraceDays) 天")
            ]

        case .loan:
            overdueRows += [
                RuleFieldRow(title: "逾期计息基数", value: profile.defaultLoanOverdueInterestBase.rawValue),
                RuleFieldRow(title: "罚息日利率", value: percentText(profile.defaultLoanPenaltyDailyRate)),
                RuleFieldRow(title: "逾期固定费用", value: currencyText(profile.defaultLoanOverdueFeeFlat)),
                RuleFieldRow(title: "逾期宽限期", value: "\(profile.defaultLoanGraceDays) 天")
            ]

        case .privateLending:
            overdueRows += [
                RuleFieldRow(title: "逾期计息基数", value: profile.defaultPrivateLoanOverdueInterestBase.rawValue),
                RuleFieldRow(title: "罚息日利率", value: percentText(profile.defaultPrivateLoanPenaltyDailyRate)),
                RuleFieldRow(title: "逾期固定费用", value: currencyText(profile.defaultPrivateLoanOverdueFeeFlat)),
                RuleFieldRow(title: "逾期宽限期", value: "\(profile.defaultPrivateLoanGraceDays) 天")
            ]
        }

        return [
            debtSection,
            RuleFieldSection(title: "还款", rows: repaymentRows),
            RuleFieldSection(title: "逾期", rows: overdueRows)
        ]
    }

    private func ruleSourceText(for profile: CalculationRuleProfile) -> String {
        _ = profile
        return "\(debtType.rawValue)默认规则"
    }

    private func percentText(_ value: Double) -> String {
        String(format: "%.2f%%", value * 100)
    }

    private func boolText(_ value: Bool) -> String {
        value ? "是" : "否"
    }
}

private struct DebtRuleCreationSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Debt.name, order: .forward) private var debts: [Debt]

    @State private var selectedDebtID: UUID?
    let onConfirm: (Debt) -> Void

    private var uniqueDebts: [Debt] {
        var seenNames = Set<String>()
        return debts.filter { seenNames.insert($0.name).inserted }
    }

    var body: some View {
        Form {
            Section("选择债务名称") {
                Picker("债务名称", selection: $selectedDebtID) {
                    Text("请选择").tag(UUID?.none)
                    ForEach(uniqueDebts) { debt in
                        Text(debt.name).tag(UUID?.some(debt.id))
                    }
                }

                Text("如需单独口径，可在该债务详情中自定义专属计算规则。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("下一步编辑规则") {
                    guard let selectedDebtID,
                          let debt = debts.first(where: { $0.id == selectedDebtID }) else { return }
                    onConfirm(debt)
                    dismiss()
                }
                .disabled(selectedDebtID == nil)
            }
        }
    }
}

private struct RuleProfileFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let profile: CalculationRuleProfile?

    @State private var name = ""
    @State private var overduePenaltyMode: OverduePenaltyMode = .simple
    @State private var paymentAllocationOrder: PaymentAllocationOrder = .overdueFeeFirst
    @State private var defaultCreditCardMinimumRate = 0.1
    @State private var defaultCreditCardMinimumFloor = 100.0
    @State private var defaultCreditCardMinimumIncludesFees = true
    @State private var defaultCreditCardMinimumIncludesPenalty = true
    @State private var defaultCreditCardMinimumIncludesInterest = true
    @State private var defaultCreditCardMinimumIncludesInstallmentPrincipal = true
    @State private var defaultCreditCardMinimumIncludesInstallmentFee = true
    @State private var defaultCreditCardGraceDays = 20
    @State private var defaultCreditCardStatementCycles = 1
    @State private var defaultCreditCardPenaltyDailyRate = 0.0005
    @State private var defaultCreditCardOverdueFeeFlat = 0.0
    @State private var defaultCreditCardOverdueGraceDays = 0
    @State private var defaultCreditCardOverdueInterestBase: OverdueInterestBase = .principalOnly
    @State private var defaultLoanPenaltyDailyRate = 0.0005
    @State private var defaultLoanOverdueFeeFlat = 0.0
    @State private var defaultLoanGraceDays = 0
    @State private var defaultLoanOverdueInterestBase: OverdueInterestBase = .principalOnly
    @State private var defaultPrivateLoanPenaltyDailyRate = 0.0003
    @State private var defaultPrivateLoanOverdueFeeFlat = 0.0
    @State private var defaultPrivateLoanGraceDays = 0
    @State private var defaultPrivateLoanOverdueInterestBase: OverdueInterestBase = .principalOnly

    var body: some View {
        Form {
            Section("基本信息") {
                TitledInputRow(title: "规则名称") {
                    TextField("请输入规则名称", text: $name)
                }
                Picker("逾期罚息模式", selection: $overduePenaltyMode) {
                    ForEach(OverduePenaltyMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                Picker("还款分配顺序", selection: $paymentAllocationOrder) {
                    ForEach(PaymentAllocationOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
            }

            Section("信用卡默认值") {
                TitledInputRow(title: "最低还款比例") {
                    TextField("请输入最低还款比例（%）", value: percentBinding($defaultCreditCardMinimumRate), format: .number)
                        .keyboardType(.decimalPad)
                }
                TitledInputRow(title: "最低还款保底") {
                    TextField("请输入最低还款保底", value: $defaultCreditCardMinimumFloor, format: .number)
                        .keyboardType(.decimalPad)
                }
                Toggle("最低还款包含费用", isOn: $defaultCreditCardMinimumIncludesFees)
                Toggle("最低还款包含罚息", isOn: $defaultCreditCardMinimumIncludesPenalty)
                Toggle("最低还款包含利息", isOn: $defaultCreditCardMinimumIncludesInterest)
                Toggle("最低还款包含分期本金", isOn: $defaultCreditCardMinimumIncludesInstallmentPrincipal)
                Toggle("最低还款包含分期手续费", isOn: $defaultCreditCardMinimumIncludesInstallmentFee)
                Text("默认账单周期：固定每月 1 期")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Picker("默认信用卡逾期计息基数", selection: $defaultCreditCardOverdueInterestBase) {
                    ForEach(OverdueInterestBase.allCases) { base in
                        Text(base.rawValue).tag(base)
                    }
                }
                TitledInputRow(title: "罚息日利率") {
                    TextField("请输入罚息日利率（%）", value: percentBinding($defaultCreditCardPenaltyDailyRate), format: .number)
                        .keyboardType(.decimalPad)
                }
                TitledInputRow(title: "逾期固定费用") {
                    TextField("请输入逾期固定费用", value: $defaultCreditCardOverdueFeeFlat, format: .number)
                        .keyboardType(.decimalPad)
                }
            }

            Section("贷款/个人借贷默认值") {
                TitledInputRow(title: "贷款罚息日利率") {
                    TextField("请输入贷款罚息日利率（%）", value: percentBinding($defaultLoanPenaltyDailyRate), format: .number)
                        .keyboardType(.decimalPad)
                }
                TitledInputRow(title: "贷款逾期固定费用") {
                    TextField("请输入贷款逾期固定费用", value: $defaultLoanOverdueFeeFlat, format: .number)
                        .keyboardType(.decimalPad)
                }
                Picker("贷款逾期计息基数", selection: $defaultLoanOverdueInterestBase) {
                    ForEach(OverdueInterestBase.allCases) { base in
                        Text(base.rawValue).tag(base)
                    }
                }
                TitledInputRow(title: "个人借贷罚息日利率") {
                    TextField("请输入个人借贷罚息日利率（%）", value: percentBinding($defaultPrivateLoanPenaltyDailyRate), format: .number)
                        .keyboardType(.decimalPad)
                }
                TitledInputRow(title: "个人借贷逾期固定费用") {
                    TextField("请输入个人借贷逾期固定费用", value: $defaultPrivateLoanOverdueFeeFlat, format: .number)
                        .keyboardType(.decimalPad)
                }
                Picker("个人借贷逾期计息基数", selection: $defaultPrivateLoanOverdueInterestBase) {
                    ForEach(OverdueInterestBase.allCases) { base in
                        Text(base.rawValue).tag(base)
                    }
                }
            }

            Button(profile == nil ? "保存规则模板" : "更新规则模板") {
                saveProfile()
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onAppear(perform: loadProfile)
    }

    private func loadProfile() {
        guard let profile else { return }
        name = profile.name
        overduePenaltyMode = profile.overduePenaltyMode
        paymentAllocationOrder = profile.paymentAllocationOrder
        defaultCreditCardMinimumRate = profile.defaultCreditCardMinimumRate
        defaultCreditCardMinimumFloor = profile.defaultCreditCardMinimumFloor
        defaultCreditCardMinimumIncludesFees = profile.defaultCreditCardMinimumIncludesFees
        defaultCreditCardMinimumIncludesPenalty = profile.defaultCreditCardMinimumIncludesPenalty
        defaultCreditCardMinimumIncludesInterest = profile.defaultCreditCardMinimumIncludesInterest
        defaultCreditCardMinimumIncludesInstallmentPrincipal = profile.defaultCreditCardMinimumIncludesInstallmentPrincipal
        defaultCreditCardMinimumIncludesInstallmentFee = profile.defaultCreditCardMinimumIncludesInstallmentFee
        defaultCreditCardGraceDays = profile.defaultCreditCardGraceDays
        defaultCreditCardStatementCycles = 1
        defaultCreditCardPenaltyDailyRate = profile.defaultCreditCardPenaltyDailyRate
        defaultCreditCardOverdueFeeFlat = profile.defaultCreditCardOverdueFeeFlat
        defaultCreditCardOverdueGraceDays = profile.defaultCreditCardOverdueGraceDays
        defaultCreditCardOverdueInterestBase = profile.defaultCreditCardOverdueInterestBase
        defaultLoanPenaltyDailyRate = profile.defaultLoanPenaltyDailyRate
        defaultLoanOverdueFeeFlat = profile.defaultLoanOverdueFeeFlat
        defaultLoanGraceDays = profile.defaultLoanGraceDays
        defaultLoanOverdueInterestBase = profile.defaultLoanOverdueInterestBase
        defaultPrivateLoanPenaltyDailyRate = profile.defaultPrivateLoanPenaltyDailyRate
        defaultPrivateLoanOverdueFeeFlat = profile.defaultPrivateLoanOverdueFeeFlat
        defaultPrivateLoanGraceDays = profile.defaultPrivateLoanGraceDays
        defaultPrivateLoanOverdueInterestBase = profile.defaultPrivateLoanOverdueInterestBase
    }

    private func saveProfile() {
        let target = profile ?? CalculationRuleProfile(name: name)
        target.name = name
        target.overduePenaltyMode = overduePenaltyMode
        target.paymentAllocationOrder = paymentAllocationOrder
        target.defaultCreditCardMinimumRate = defaultCreditCardMinimumRate
        target.defaultCreditCardMinimumFloor = defaultCreditCardMinimumFloor
        target.defaultCreditCardMinimumIncludesFees = defaultCreditCardMinimumIncludesFees
        target.defaultCreditCardMinimumIncludesPenalty = defaultCreditCardMinimumIncludesPenalty
        target.defaultCreditCardMinimumIncludesInterest = defaultCreditCardMinimumIncludesInterest
        target.defaultCreditCardMinimumIncludesInstallmentPrincipal = defaultCreditCardMinimumIncludesInstallmentPrincipal
        target.defaultCreditCardMinimumIncludesInstallmentFee = defaultCreditCardMinimumIncludesInstallmentFee
        target.defaultCreditCardGraceDays = defaultCreditCardGraceDays
        target.defaultCreditCardStatementCycles = 1
        target.defaultCreditCardPenaltyDailyRate = defaultCreditCardPenaltyDailyRate
        target.defaultCreditCardOverdueFeeFlat = defaultCreditCardOverdueFeeFlat
        target.defaultCreditCardOverdueGraceDays = defaultCreditCardOverdueGraceDays
        target.defaultCreditCardOverdueInterestBase = defaultCreditCardOverdueInterestBase
        target.defaultLoanPenaltyDailyRate = defaultLoanPenaltyDailyRate
        target.defaultLoanOverdueFeeFlat = defaultLoanOverdueFeeFlat
        target.defaultLoanGraceDays = defaultLoanGraceDays
        target.defaultLoanOverdueInterestBase = defaultLoanOverdueInterestBase
        target.defaultPrivateLoanPenaltyDailyRate = defaultPrivateLoanPenaltyDailyRate
        target.defaultPrivateLoanOverdueFeeFlat = defaultPrivateLoanOverdueFeeFlat
        target.defaultPrivateLoanGraceDays = defaultPrivateLoanGraceDays
        target.defaultPrivateLoanOverdueInterestBase = defaultPrivateLoanOverdueInterestBase
        if profile == nil {
            modelContext.insert(target)
        }
        dismiss()
    }

    private func percentBinding(_ value: Binding<Double>) -> Binding<Double> {
        Binding(
            get: { value.wrappedValue * 100 },
            set: { value.wrappedValue = max($0, 0) / 100 }
        )
    }
}

private struct DebtCustomRuleFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let rule: DebtCustomRule?
    let debt: Debt
    var presetProfile: CalculationRuleProfile? = nil
    var lockedRuleName: String? = nil
    var onSaved: ((DebtCustomRule) -> Void)? = nil

    @State private var name = ""
    @State private var overduePenaltyMode: OverduePenaltyMode = .simple
    @State private var paymentAllocationOrder: PaymentAllocationOrder = .overdueFeeFirst
    @State private var defaultCreditCardMinimumRate = 0.1
    @State private var defaultCreditCardMinimumFloor = 100.0
    @State private var defaultCreditCardMinimumIncludesFees = true
    @State private var defaultCreditCardMinimumIncludesPenalty = true
    @State private var defaultCreditCardMinimumIncludesInterest = true
    @State private var defaultCreditCardMinimumIncludesInstallmentPrincipal = true
    @State private var defaultCreditCardMinimumIncludesInstallmentFee = true
    @State private var defaultCreditCardGraceDays = 20
    @State private var defaultCreditCardStatementCycles = 1
    @State private var defaultCreditCardPenaltyDailyRate = 0.0005
    @State private var defaultCreditCardOverdueFeeFlat = 0.0
    @State private var defaultCreditCardOverdueGraceDays = 0
    @State private var defaultCreditCardOverdueInterestBase: OverdueInterestBase = .principalOnly
    @State private var defaultLoanPenaltyDailyRate = 0.0005
    @State private var defaultLoanOverdueFeeFlat = 0.0
    @State private var defaultLoanGraceDays = 0
    @State private var defaultLoanOverdueInterestBase: OverdueInterestBase = .principalOnly
    @State private var defaultPrivateLoanPenaltyDailyRate = 0.0003
    @State private var defaultPrivateLoanOverdueFeeFlat = 0.0
    @State private var defaultPrivateLoanGraceDays = 0
    @State private var defaultPrivateLoanOverdueInterestBase: OverdueInterestBase = .principalOnly

    var body: some View {
        Form {
            Section("基本信息") {
                TitledInputRow(title: "规则名称") {
                    TextField("请输入规则名称", text: $name)
                        .disabled(lockedRuleName != nil)
                }
                if let lockedRuleName {
                    Text("将保存为：\(lockedRuleName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Picker("逾期罚息模式", selection: $overduePenaltyMode) {
                    ForEach(OverduePenaltyMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                Picker("还款分配顺序", selection: $paymentAllocationOrder) {
                    ForEach(PaymentAllocationOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
            }

            Section("信用卡默认值") {
                TitledInputRow(title: "最低还款比例") {
                    TextField("请输入最低还款比例（%）", value: percentBinding($defaultCreditCardMinimumRate), format: .number)
                        .keyboardType(.decimalPad)
                }
                TitledInputRow(title: "最低还款保底") {
                    TextField("请输入最低还款保底", value: $defaultCreditCardMinimumFloor, format: .number)
                        .keyboardType(.decimalPad)
                }
                Toggle("最低还款包含费用", isOn: $defaultCreditCardMinimumIncludesFees)
                Toggle("最低还款包含罚息", isOn: $defaultCreditCardMinimumIncludesPenalty)
                Toggle("最低还款包含利息", isOn: $defaultCreditCardMinimumIncludesInterest)
                Toggle("最低还款包含分期本金", isOn: $defaultCreditCardMinimumIncludesInstallmentPrincipal)
                Toggle("最低还款包含分期手续费", isOn: $defaultCreditCardMinimumIncludesInstallmentFee)
                Text("默认账单周期：固定每月 1 期")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Picker("默认信用卡逾期计息基数", selection: $defaultCreditCardOverdueInterestBase) {
                    ForEach(OverdueInterestBase.allCases) { base in
                        Text(base.rawValue).tag(base)
                    }
                }
                TitledInputRow(title: "罚息日利率") {
                    TextField("请输入罚息日利率（%）", value: percentBinding($defaultCreditCardPenaltyDailyRate), format: .number)
                        .keyboardType(.decimalPad)
                }
                TitledInputRow(title: "逾期固定费用") {
                    TextField("请输入逾期固定费用", value: $defaultCreditCardOverdueFeeFlat, format: .number)
                        .keyboardType(.decimalPad)
                }
            }

            Section("贷款/个人借贷默认值") {
                TitledInputRow(title: "贷款罚息日利率") {
                    TextField("请输入贷款罚息日利率（%）", value: percentBinding($defaultLoanPenaltyDailyRate), format: .number)
                        .keyboardType(.decimalPad)
                }
                TitledInputRow(title: "贷款逾期固定费用") {
                    TextField("请输入贷款逾期固定费用", value: $defaultLoanOverdueFeeFlat, format: .number)
                        .keyboardType(.decimalPad)
                }
                Picker("贷款逾期计息基数", selection: $defaultLoanOverdueInterestBase) {
                    ForEach(OverdueInterestBase.allCases) { base in
                        Text(base.rawValue).tag(base)
                    }
                }
                TitledInputRow(title: "个人借贷罚息日利率") {
                    TextField("请输入个人借贷罚息日利率（%）", value: percentBinding($defaultPrivateLoanPenaltyDailyRate), format: .number)
                        .keyboardType(.decimalPad)
                }
                TitledInputRow(title: "个人借贷逾期固定费用") {
                    TextField("请输入个人借贷逾期固定费用", value: $defaultPrivateLoanOverdueFeeFlat, format: .number)
                        .keyboardType(.decimalPad)
                }
                Picker("个人借贷逾期计息基数", selection: $defaultPrivateLoanOverdueInterestBase) {
                    ForEach(OverdueInterestBase.allCases) { base in
                        Text(base.rawValue).tag(base)
                    }
                }
            }

            Button("保存债务规则") {
                saveRule()
            }
            .disabled((lockedRuleName ?? name).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onAppear(perform: loadRule)
    }

    private func loadRule() {
        guard let rule else { return }
        name = rule.name
        overduePenaltyMode = rule.overduePenaltyMode
        paymentAllocationOrder = rule.paymentAllocationOrder
        defaultCreditCardMinimumRate = rule.defaultCreditCardMinimumRate
        defaultCreditCardMinimumFloor = rule.defaultCreditCardMinimumFloor
        defaultCreditCardMinimumIncludesFees = rule.defaultCreditCardMinimumIncludesFees
        defaultCreditCardMinimumIncludesPenalty = rule.defaultCreditCardMinimumIncludesPenalty
        defaultCreditCardMinimumIncludesInterest = rule.defaultCreditCardMinimumIncludesInterest
        defaultCreditCardMinimumIncludesInstallmentPrincipal = rule.defaultCreditCardMinimumIncludesInstallmentPrincipal
        defaultCreditCardMinimumIncludesInstallmentFee = rule.defaultCreditCardMinimumIncludesInstallmentFee
        defaultCreditCardGraceDays = rule.defaultCreditCardGraceDays
        defaultCreditCardStatementCycles = 1
        defaultCreditCardPenaltyDailyRate = rule.defaultCreditCardPenaltyDailyRate
        defaultCreditCardOverdueFeeFlat = rule.defaultCreditCardOverdueFeeFlat
        defaultCreditCardOverdueGraceDays = rule.defaultCreditCardOverdueGraceDays
        defaultCreditCardOverdueInterestBase = rule.defaultCreditCardOverdueInterestBase
        defaultLoanPenaltyDailyRate = rule.defaultLoanPenaltyDailyRate
        defaultLoanOverdueFeeFlat = rule.defaultLoanOverdueFeeFlat
        defaultLoanGraceDays = rule.defaultLoanGraceDays
        defaultLoanOverdueInterestBase = rule.defaultLoanOverdueInterestBase
        defaultPrivateLoanPenaltyDailyRate = rule.defaultPrivateLoanPenaltyDailyRate
        defaultPrivateLoanOverdueFeeFlat = rule.defaultPrivateLoanOverdueFeeFlat
        defaultPrivateLoanGraceDays = rule.defaultPrivateLoanGraceDays
        defaultPrivateLoanOverdueInterestBase = rule.defaultPrivateLoanOverdueInterestBase
        if let lockedRuleName {
            name = lockedRuleName
        }
    }

    private func saveRule() {
        let finalName = (lockedRuleName ?? name).trimmingCharacters(in: .whitespacesAndNewlines)
        if let rule {
            rule.name = finalName
            rule.overduePenaltyMode = overduePenaltyMode
            rule.paymentAllocationOrder = paymentAllocationOrder
            rule.defaultCreditCardMinimumRate = defaultCreditCardMinimumRate
            rule.defaultCreditCardMinimumFloor = defaultCreditCardMinimumFloor
            rule.defaultCreditCardMinimumIncludesFees = defaultCreditCardMinimumIncludesFees
            rule.defaultCreditCardMinimumIncludesPenalty = defaultCreditCardMinimumIncludesPenalty
            rule.defaultCreditCardMinimumIncludesInterest = defaultCreditCardMinimumIncludesInterest
            rule.defaultCreditCardMinimumIncludesInstallmentPrincipal = defaultCreditCardMinimumIncludesInstallmentPrincipal
            rule.defaultCreditCardMinimumIncludesInstallmentFee = defaultCreditCardMinimumIncludesInstallmentFee
            rule.defaultCreditCardGraceDays = defaultCreditCardGraceDays
            rule.defaultCreditCardStatementCycles = 1
            rule.defaultCreditCardPenaltyDailyRate = defaultCreditCardPenaltyDailyRate
            rule.defaultCreditCardOverdueFeeFlat = defaultCreditCardOverdueFeeFlat
            rule.defaultCreditCardOverdueGraceDays = defaultCreditCardOverdueGraceDays
            rule.defaultCreditCardOverdueInterestBase = defaultCreditCardOverdueInterestBase
            rule.defaultLoanPenaltyDailyRate = defaultLoanPenaltyDailyRate
            rule.defaultLoanOverdueFeeFlat = defaultLoanOverdueFeeFlat
            rule.defaultLoanGraceDays = defaultLoanGraceDays
            rule.defaultLoanOverdueInterestBase = defaultLoanOverdueInterestBase
            rule.defaultPrivateLoanPenaltyDailyRate = defaultPrivateLoanPenaltyDailyRate
            rule.defaultPrivateLoanOverdueFeeFlat = defaultPrivateLoanOverdueFeeFlat
            rule.defaultPrivateLoanGraceDays = defaultPrivateLoanGraceDays
            rule.defaultPrivateLoanOverdueInterestBase = defaultPrivateLoanOverdueInterestBase
            onSaved?(rule)
            dismiss()
            return
        }

        let created = DebtCustomRule(
            name: finalName,
            overduePenaltyMode: overduePenaltyMode,
            paymentAllocationOrder: paymentAllocationOrder,
            defaultCreditCardMinimumRate: defaultCreditCardMinimumRate,
            defaultCreditCardMinimumFloor: defaultCreditCardMinimumFloor,
            defaultCreditCardMinimumIncludesFees: defaultCreditCardMinimumIncludesFees,
            defaultCreditCardMinimumIncludesPenalty: defaultCreditCardMinimumIncludesPenalty,
            defaultCreditCardMinimumIncludesInterest: defaultCreditCardMinimumIncludesInterest,
            defaultCreditCardMinimumIncludesInstallmentPrincipal: defaultCreditCardMinimumIncludesInstallmentPrincipal,
            defaultCreditCardMinimumIncludesInstallmentFee: defaultCreditCardMinimumIncludesInstallmentFee,
            defaultCreditCardGraceDays: defaultCreditCardGraceDays,
            defaultCreditCardStatementCycles: 1,
            defaultCreditCardPenaltyDailyRate: defaultCreditCardPenaltyDailyRate,
            defaultCreditCardOverdueFeeFlat: defaultCreditCardOverdueFeeFlat,
            defaultCreditCardOverdueGraceDays: defaultCreditCardOverdueGraceDays,
            defaultCreditCardOverdueInterestBase: defaultCreditCardOverdueInterestBase,
            defaultLoanPenaltyDailyRate: defaultLoanPenaltyDailyRate,
            defaultLoanOverdueFeeFlat: defaultLoanOverdueFeeFlat,
            defaultLoanGraceDays: defaultLoanGraceDays,
            defaultLoanOverdueInterestBase: defaultLoanOverdueInterestBase,
            defaultPrivateLoanPenaltyDailyRate: defaultPrivateLoanPenaltyDailyRate,
            defaultPrivateLoanOverdueFeeFlat: defaultPrivateLoanOverdueFeeFlat,
            defaultPrivateLoanGraceDays: defaultPrivateLoanGraceDays,
            defaultPrivateLoanOverdueInterestBase: defaultPrivateLoanOverdueInterestBase
        )
        modelContext.insert(created)
        onSaved?(created)
        dismiss()
    }

    private func percentBinding(_ value: Binding<Double>) -> Binding<Double> {
        Binding(
            get: { value.wrappedValue * 100 },
            set: { value.wrappedValue = max($0, 0) / 100 }
        )
    }
}

private struct CreditCardStatementRefreshFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let debt: Debt

    @State private var refreshedAt = Date()
    @State private var statementBalance = 0.0
    @State private var minimumDue = 0.0
    @State private var installmentFee = 0.0
    @State private var updateResult: CreditCardStatementService.UpdateResult?

    private var pendingStatementReminders: [ReminderTask] {
        debt.reminderTasks.filter { !$0.isCompleted && $0.category == .creditCardStatementRefresh }
    }

    private var canSave: Bool {
        statementBalance >= 0 && minimumDue >= 0 && installmentFee >= 0
    }

    var body: some View {
        Form {
            Section("填写最新账单") {
                DatePicker("账单更新时间", selection: $refreshedAt, displayedComponents: .date)
                TitledInputRow(title: "最新账单本金/账单金额") {
                    TextField("请输入最新账单金额", value: $statementBalance, format: .number)
                        .keyboardType(.decimalPad)
                }
                TitledInputRow(title: "最新最低还款") {
                    TextField("请输入最新最低还款", value: $minimumDue, format: .number)
                        .keyboardType(.decimalPad)
                }
                TitledInputRow(title: "最新分期手续费") {
                    TextField("请输入最新分期手续费", value: $installmentFee, format: .number)
                        .keyboardType(.decimalPad)
                }
            }

            Section("系统说明") {
                Text("保存后会按信用卡月账单口径重建未还计划；若上期未全额还款，系统会自动补计循环利息；若已逾期，系统会自动补计逾期费用和罚息。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let updateResult {
                Section("更新结果") {
                    Label("已重建 \(updateResult.rebuiltPlanCount) 期待还计划", systemImage: "checkmark.circle.fill")
                        .foregroundColor(AppColors.accentGreen)
                    Text("下一期最低应还：\(currencyText(updateResult.nextMinimumDue))")
                    Text("下一期到期日：\(shortDateText(updateResult.nextDueDate))")
                    Text("剩余待更新账单提醒：\(pendingStatementReminders.count) 条")
                        .foregroundStyle(.secondary)

                    if updateResult.rebuiltPlanCount == 0 {
                        Text("当前没有未来待还计划可重建，已仅同步账单信息与提醒状态。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if !updateResult.warnings.isEmpty {
                        ForEach(updateResult.warnings, id: \.self) { warning in
                            BulletNoteRow(text: warning, tint: AppColors.warningOrange)
                        }
                    }
                }
            }

            Section {
                Button(updateResult == nil ? "保存账单更新" : "重新生成待还计划") {
                    updateResult = ReminderDomainService.markCreditCardStatementUpdated(
                        debt: debt,
                        refreshedAt: refreshedAt,
                        statementBalance: statementBalance,
                        minimumDue: minimumDue,
                        installmentFee: installmentFee,
                        modelContext: modelContext
                    )
                }
                .disabled(!canSave)
            }
        }
        .toolbar {
            if updateResult != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            if let detail = debt.creditCardDetail {
                statementBalance = detail.lastStatementBalance > 0 ? detail.lastStatementBalance : debt.outstandingPrincipal
                minimumDue = detail.lastStatementMinimumDue > 0
                    ? detail.lastStatementMinimumDue
                    : debt.repaymentPlans.filter { $0.status != .paid }.sorted(by: { $0.dueDate < $1.dueDate }).first?.minimumDue ?? 0
                installmentFee = detail.lastStatementInstallmentFee
                refreshedAt = detail.lastStatementRefreshedAt ?? Date()
            }
        }
    }
}

private struct PrivacyComplianceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("以下声明用于说明本应用在个人债务记录、提醒、策略测算、通知和订阅场景下的隐私边界与合规注意事项。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ComplianceSectionCard(
                    title: "使用边界与免责声明",
                    iconName: "exclamationmark.shield.fill",
                    tint: AppColors.warningOrange,
                    points: [
                        "本应用仅用于个人债务记账、还款计划整理与清偿策略测算，不构成投资建议、放贷建议、征信修复承诺或法律意见。",
                        "策略结果基于你录入的本金、利率、最低还款、逾期和预算数据自动计算，属于辅助决策信息，不保证一定达到同样结果。",
                        "如合同条款、平台规则、银行账单或司法文件与应用测算结果不一致，应以真实合同和官方账单为准。"
                    ]
                )

                ComplianceSectionCard(
                    title: "数据存储与隐私保护",
                    iconName: "lock.shield.fill",
                    tint: AppColors.accentGreen,
                    points: [
                        "你的债务明细、还款记录、提醒任务和策略快照默认保存在本机数据存储中，便于你离线查看和持续维护。",
                        "除订阅购买、订阅校验、系统通知等依赖苹果系统服务的能力外，应用默认不主动上传你的债务明细到开发者服务器。",
                        "请勿在债务名称、备注、反馈内容中填写身份证号、银行卡号、完整住址、验证码等不必要的敏感信息。"
                    ]
                )

                ComplianceSectionCard(
                    title: "通知、分享与订阅说明",
                    iconName: "bell.badge.fill",
                    tint: AppColors.primaryBlue,
                    points: [
                        "当你开启提醒功能后，应用会调用系统通知能力，在本机生成到期提醒、账单更新提醒等本地通知，用于辅助执行还款计划。",
                        "使用反馈导出、分享或复制文本时，内容会通过系统分享面板发送到你自行选择的目标，发送前请先检查并删除敏感信息。",
                        "订阅为自动续费项目，将在当前订阅期结束前 24 小时内自动扣费；你可随时在 App Store 账户设置中管理、取消或恢复购买。"
                    ]
                )

                ComplianceSectionCard(
                    title: "合规与风险提醒",
                    iconName: "doc.text.magnifyingglass",
                    tint: .purple,
                    points: [
                        "涉及逾期、罚息、协商分期、催收沟通、司法程序、征信异议或债务重组时，请结合实际合同、监管要求和专业意见进行判断。",
                        "若你所在地区对个人信息、消费金融、借贷协商或电子记录保存有特别要求，请自行确认是否需要额外备份、脱敏或留存纸质材料。",
                        "如发现账单、最低还款、逾期费用或订阅权益展示异常，请先核对原始凭证，再决定是否继续依赖应用内数据执行操作。"
                    ]
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("订阅与法务入口")
                        .font(.subheadline.weight(.semibold))
                    Link("管理 App Store 订阅", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                    Link("Apple 媒体服务条款", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/cn/terms.html")!)
                    Link("Apple 隐私政策", destination: URL(string: "https://www.apple.com/legal/privacy/zh-cn/")!)
                }
                .font(.caption)
                .foregroundStyle(AppColors.primaryBlue)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.cardBackground)
                .cornerRadius(16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}

private struct ComplianceSectionCard: View {
    let title: String
    let iconName: String
    let tint: Color
    let points: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(title)
                    .font(.headline)
            }

            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                BulletNoteRow(text: point, tint: tint)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground)
        .cornerRadius(16)
    }
}

private struct DataStatisticsView: View {
    @Query private var debts: [Debt]
    @Query private var records: [RepaymentRecord]
    @Query private var overdueEvents: [OverdueEvent]
    @State private var selectedDisplayOption: StatisticsDisplayOption = .amount

    private enum StatisticsDisplayOption: String, CaseIterable, Identifiable {
        case amount
        case rate
        case debtStructure
        case apr

        var id: String { rawValue }

        var title: String {
            switch self {
            case .amount:
                return "资金规模图表"
            case .rate:
                return "效率与成本图表"
            case .debtStructure:
                return "债务结构图表"
            case .apr:
                return "利率分析"
            }
        }

        var subtitle: String {
            switch self {
            case .amount:
                return "查看本金、利息和逾期费用/罚息的金额统计。"
            case .rate:
                return "查看结清率、回款覆盖率和组合年化指标。"
            case .debtStructure:
                return "查看不同债务类型的剩余余额分布。"
            case .apr:
                return "查看按债务类型的年化对比与高利率暴露。"
            }
        }
    }

    private struct AmountMetric: Identifiable {
        let id = UUID()
        let name: String
        let value: Double
    }

    private struct RateMetric: Identifiable {
        let id = UUID()
        let name: String
        let value: Double
    }

    private struct DebtTypeSlice: Identifiable {
        let id = UUID()
        let type: DebtType
        let amount: Double
    }

    private struct DebtTypeRateSlice: Identifiable {
        let id = UUID()
        let type: DebtType
        let ratePercent: Double
    }

    private var snapshot: DataStatisticsDomainService.Snapshot {
        DataStatisticsDomainService.build(debts: debts, records: records, overdueEvents: overdueEvents)
    }

    private var unresolvedOverdueCount: Int {
        overdueEvents.filter { !$0.isResolved }.count
    }

    private var amountMetrics: [AmountMetric] {
        [
            AmountMetric(name: "剩余本金", value: snapshot.totalOutstanding),
            AmountMetric(name: "累计已还本金", value: snapshot.repaidPrincipal),
            AmountMetric(name: "待还利息", value: snapshot.outstandingInterest),
            AmountMetric(name: "累计已付利息", value: snapshot.paidInterest),
            AmountMetric(name: "未结清逾期费/罚息", value: snapshot.overdueCost),
            AmountMetric(name: "累计已付逾期费/罚息", value: snapshot.paidOverdueFeeAndPenalty)
        ]
    }

    private var rateMetrics: [RateMetric] {
        [
            RateMetric(name: "结清率", value: snapshot.settlementRate * 100),
            RateMetric(name: "回款覆盖率", value: snapshot.repaymentCoverageRate * 100),
            RateMetric(name: "加权实际年化", value: snapshot.weightedAverageAPR * 100),
            RateMetric(name: "加权名义年化", value: snapshot.weightedAverageNominalAPR * 100)
        ]
    }

    private var debtTypeRateSlices: [DebtTypeRateSlice] {
        DebtType.allCases.compactMap { type in
            let rate = snapshot.debtRateByType[type] ?? 0
            guard rate > 0 else { return nil }
            return DebtTypeRateSlice(type: type, ratePercent: rate * 100)
        }
    }

    private var debtTypeSlices: [DebtTypeSlice] {
        DebtType.allCases.compactMap { type in
            let amount = snapshot.debtByType[type] ?? 0
            guard amount > 0 else { return nil }
            return DebtTypeSlice(type: type, amount: amount)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StrategyChartCard(
                    title: "选择你想要查看的统计分析数据",
                    subtitle: selectedDisplayOption.subtitle
                ) {
                    FilterMenu(
                        placeholder: "请选择",
                        selection: selectedDisplayOption,
                        options: Array(StatisticsDisplayOption.allCases),
                        displayText: { $0.title }
                    ) { selection in
                        if let selection {
                            selectedDisplayOption = selection
                        }
                    }
                }
                .padding(.horizontal)

                selectedStatisticsSection
            }
            .padding(.bottom, 20)
            .padding(.top, 4)
        }
        .background(AppColors.backgroundGray)
    }

    @ViewBuilder
    private var selectedStatisticsSection: some View {
        switch selectedDisplayOption {
        case .amount:
            amountSection
        case .rate:
            rateSection
        case .debtStructure:
            debtStructureSection
        case .apr:
            aprSection
        }
    }

    private var amountSection: some View {
        Group {
            SectionHeader(title: "资金规模图表")
            StrategyChartCard(
                title: "本金、利息与逾期成本",
                subtitle: "补充展示剩余本金、逾期费/罚息与利息相关统计。"
            ) {
                Chart(amountMetrics) { metric in
                    BarMark(
                        x: .value("指标", metric.name),
                        y: .value("金额", metric.value)
                    )
                    .foregroundStyle(by: .value("指标", metric.name))
                    .annotation(position: .top) {
                        Text(currencyText(metric.value))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 230)
            }
            .padding(.horizontal)
        }
    }

    private var aprSection: some View {
        Group {
            SectionHeader(title: "利率分析")
            StrategyChartCard(
                title: "债务类型加权年化对比",
                subtitle: debtTypeRateSlices.isEmpty
                    ? "暂无可分析利率数据"
                    : "全组合加权实际年化 \(String(format: "%.2f%%", snapshot.weightedAverageAPR * 100)) · 高利率债务 \(snapshot.highRateDebtCount) 笔"
            ) {
                if debtTypeRateSlices.isEmpty {
                    ContentUnavailableView("暂无可分析的利率数据", systemImage: "percent")
                        .frame(height: 210)
                } else {
                    Chart(debtTypeRateSlices) { slice in
                        BarMark(
                            x: .value("类型", slice.type.rawValue),
                            y: .value("年化", slice.ratePercent)
                        )
                        .foregroundStyle(by: .value("类型", slice.type.rawValue))
                        .annotation(position: .top) {
                            Text(String(format: "%.2f%%", slice.ratePercent))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        RuleMark(y: .value("全组合加权实际年化", snapshot.weightedAverageAPR * 100))
                            .lineStyle(.init(lineWidth: 1.5, dash: [5, 4]))
                            .foregroundStyle(AppColors.warningOrange)
                            .annotation(position: .top, alignment: .trailing) {
                                Text("组合均值")
                                    .font(.caption2)
                                    .foregroundStyle(AppColors.warningOrange)
                            }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .frame(height: 230)

                    HStack(spacing: 12) {
                        MetricMiniCard(
                            title: "最高实际年化",
                            value: String(format: "%.2f%%", snapshot.highestEffectiveAPR * 100),
                            tint: AppColors.warningOrange
                        )
                        MetricMiniCard(
                            title: "最低实际年化",
                            value: String(format: "%.2f%%", snapshot.lowestEffectiveAPR * 100),
                            tint: AppColors.accentGreen
                        )
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var rateSection: some View {
        Group {
            SectionHeader(title: "效率与成本图表")
            StrategyChartCard(
                title: "执行效率指标",
                subtitle: "逾期笔数：\(unresolvedOverdueCount) 笔"
            ) {
                Chart(rateMetrics) { metric in
                    BarMark(
                        x: .value("指标", metric.name),
                        y: .value("比例", metric.value)
                    )
                    .foregroundStyle(AppColors.primaryBlue.gradient)
                    .annotation(position: .top) {
                        Text(String(format: "%.1f%%", metric.value))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 220)
            }
            .padding(.horizontal)
        }
    }

    private var debtStructureSection: some View {
        Group {
            SectionHeader(title: "债务结构图表")
            StrategyChartCard(
                title: "按债务类型分布",
                subtitle: snapshot.totalOutstanding > 0 ? "总余额 \(currencyText(snapshot.totalOutstanding))" : "暂无可绘制数据"
            ) {
                if debtTypeSlices.isEmpty {
                    ContentUnavailableView("暂无可分析的债务数据", systemImage: "chart.pie")
                        .frame(height: 220)
                } else {
                    Chart(debtTypeSlices) { slice in
                        SectorMark(
                            angle: .value("余额", slice.amount),
                            innerRadius: .ratio(0.55),
                            angularInset: 2
                        )
                        .foregroundStyle(by: .value("类型", slice.type.rawValue))
                    }
                    .chartLegend(position: .bottom)
                    .frame(height: 240)
                }
            }
            .padding(.horizontal)
        }
    }

}

#Preview {
    ContentView()
        .modelContainer(for: [
            Debt.self,
            DebtCustomRule.self,
            CalculationRuleProfile.self,
            CreditCardDebtDetail.self,
            LoanDebtDetail.self,
            PrivateLoanDebtDetail.self,
            RepaymentPlan.self,
            RepaymentRecord.self,
            OverdueEvent.self,
            ReminderTask.self,
            StrategyScenario.self,
            SubscriptionEntitlement.self,
            SubscriptionTransactionRecord.self
        ], inMemory: true)
}
