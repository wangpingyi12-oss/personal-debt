import Charts
import SwiftData
import SwiftUI

struct DebtUXRootView: View {
    @Bindable var settings: AppUserSettings

    var body: some View {
        Group {
            if settings.onboardingCompleted {
                MainDebtTabView(settings: settings)
            } else {
                OnboardingFlow(settings: settings)
            }
        }
    }
}

private struct MainDebtTabView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Bindable var settings: AppUserSettings

    @Query private var creditCards: [CreditCardDebt]
    @Query private var cardRules: [CreditCardCalculationRule]
    @Query private var cardStatements: [CreditCardStatement]
    @Query private var cardPlans: [CreditCardRepaymentPlan]
    @Query private var cardBreakdowns: [CreditCardStatementBreakdown]
    @Query private var cardPayments: [CreditCardPaymentRecord]
    @Query private var cardOverdues: [CreditCardOverdueRecord]
    @Query private var cardInstallments: [CreditCardInstallmentPlan]

    @Query private var loans: [LoanDebt]
    @Query private var loanPlans: [LoanRepaymentPlan]
    @Query private var loanPayments: [LoanPaymentRecord]
    @Query private var loanAllocations: [LoanPaymentAllocationDetail]
    @Query private var loanOverdues: [LoanOverdueRecord]
    @Query private var loanRules: [LoanCalculationRule]

    @Query private var personalDebts: [PersonalLendingDebt]
    @Query private var personalPlans: [PersonalLendingPlan]
    @Query private var personalPayments: [PersonalLendingPaymentRecord]
    @Query private var personalAllocations: [PersonalLendingAllocationDetail]
    @Query private var personalOverdues: [PersonalLendingOverdueRecord]

    @Query private var strategyBatches: [StrategyComparisonBatch]
    @Query private var strategySimulations: [StrategySimulation]
    @Query private var strategyMonthSnapshots: [StrategyMonthSnapshot]
    @Query private var strategyAllocations: [StrategyDebtAllocation]

    @State private var selectedTab: AppTab = .overview
    @State private var showingAddDebt = false
    @State private var showingPayment = false
    @State private var showingStatementUpdate = false
    @State private var showingSettings = false
    @State private var showingOverdues = false
    @State private var showingManualOverdue = false
    @State private var preselectedPayment: DebtSelection?
    @State private var preselectedCardForStatement: UUID?
    @State private var message: UXMessage?

    private let readService = DebtReadService()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                OverviewTab(
                    settings: settings,
                    summary: analyticsSummary,
                    debtItems: debtItems,
                    onAddDebt: { showingAddDebt = true },
                    onOpenOverdues: { showingOverdues = true },
                    onOpenSettings: { showingSettings = true }
                )
                .tabItem { Label("tab.dashboard", systemImage: "chart.pie.fill") }
                .tag(AppTab.overview)

                DebtListTab(
                    debtItems: debtItems,
                    creditCards: creditCards,
                    cardRules: cardRules,
                    cardStatements: cardStatements,
                    cardPlans: cardPlans,
                    cardBreakdowns: cardBreakdowns,
                    cardPayments: cardPayments,
                    cardOverdues: cardOverdues,
                    cardInstallments: cardInstallments,
                    loans: loans,
                    loanPlans: loanPlans,
                    loanPayments: loanPayments,
                    loanAllocations: loanAllocations,
                    loanOverdues: loanOverdues,
                    loanRules: loanRules,
                    personalDebts: personalDebts,
                    personalPlans: personalPlans,
                    personalPayments: personalPayments,
                    personalAllocations: personalAllocations,
                    personalOverdues: personalOverdues,
                    settings: settings,
                    onAddDebt: { showingAddDebt = true },
                    onRecordPayment: { selection in
                        preselectedPayment = selection
                        showingPayment = true
                    },
                    onUpdateStatement: { cardID in
                        preselectedCardForStatement = cardID
                        showingStatementUpdate = true
                    },
                    onResult: showResult
                )
                .tabItem { Label("tab.debts", systemImage: "creditcard.fill") }
                .tag(AppTab.debts)

                PaymentLedgerTab(
                    creditCards: activeCreditCards,
                    loans: activeLoans,
                    personalDebts: activePersonalDebts,
                    cardPayments: cardPayments,
                    loanPayments: loanPayments,
                    personalPayments: personalPayments,
                    onRecordPayment: {
                        preselectedPayment = nil
                        showingPayment = true
                    }
                )
                .tabItem { Label("tab.payments", systemImage: "arrow.left.arrow.right.circle.fill") }
                .tag(AppTab.payments)

                StrategyTab(
                    settings: settings,
                    batches: strategyBatches,
                    simulations: strategySimulations,
                    monthSnapshots: strategyMonthSnapshots,
                    allocations: strategyAllocations,
                    onResult: showResult
                )
                .tabItem { Label("tab.strategy", systemImage: "sparkles") }
                .tag(AppTab.strategy)

                StatisticsTab(
                    creditCards: creditCards,
                    cardStatements: cardStatements,
                    cardBreakdowns: cardBreakdowns,
                    cardPayments: cardPayments,
                    loans: loans,
                    loanPlans: loanPlans,
                    loanPayments: loanPayments,
                    loanOverdues: loanOverdues,
                    personalDebts: personalDebts,
                    personalPlans: personalPlans,
                    personalPayments: personalPayments,
                    personalOverdues: personalOverdues,
                    onOpenOverdues: { showingOverdues = true }
                )
                .tabItem { Label("tab.statistics", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppTab.statistics)
            }

            FloatingAddMenu(
                onAddDebt: { showingAddDebt = true },
                onRecordPayment: {
                    preselectedPayment = nil
                    showingPayment = true
                },
                onAddOverdue: { showingManualOverdue = true }
            )
            .padding(.trailing, 18)
            .padding(.bottom, 84)
        }
        .tint(DebtTheme.primary)
        .sheet(isPresented: $showingAddDebt) {
            AddDebtSheet(
                settings: settings,
                cardStatements: cardStatements,
                cardPlans: cardPlans,
                cardBreakdowns: cardBreakdowns,
                onResult: showResult
            )
            .environmentObject(subscriptionStore)
        }
        .sheet(isPresented: $showingPayment) {
            PaymentEntrySheet(
                settings: settings,
                preselected: preselectedPayment,
                creditCards: activeCreditCards,
                cardRules: cardRules,
                cardStatements: cardStatements,
                cardPlans: cardPlans,
                cardPayments: cardPayments,
                cardOverdues: cardOverdues,
                loans: activeLoans,
                loanPlans: loanPlans,
                loanPayments: loanPayments,
                loanAllocations: loanAllocations,
                loanOverdues: loanOverdues,
                loanRules: loanRules,
                personalDebts: activePersonalDebts,
                personalPlans: personalPlans,
                personalPayments: personalPayments,
                personalAllocations: personalAllocations,
                personalOverdues: personalOverdues,
                onResult: showResult
            )
            .environmentObject(subscriptionStore)
        }
        .sheet(isPresented: $showingStatementUpdate) {
            CreditCardStatementSheet(
                settings: settings,
                preselectedCardID: preselectedCardForStatement,
                creditCards: activeCreditCards,
                cardRules: cardRules,
                statements: cardStatements,
                plans: cardPlans,
                breakdowns: cardBreakdowns,
                payments: cardPayments,
                overdues: cardOverdues,
                onResult: showResult
            )
            .environmentObject(subscriptionStore)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                settings: settings,
                creditCards: activeCreditCards,
                cardRules: cardRules,
                loans: activeLoans,
                loanRules: loanRules
            )
                .environmentObject(subscriptionStore)
        }
        .sheet(isPresented: $showingManualOverdue) {
            ManualOverdueEntrySheet(
                settings: settings,
                creditCards: activeCreditCards,
                cardStatements: cardStatements,
                cardPlans: cardPlans,
                cardOverdues: cardOverdues,
                loans: activeLoans,
                loanPlans: loanPlans,
                loanOverdues: loanOverdues,
                personalDebts: activePersonalDebts,
                personalPlans: personalPlans,
                personalOverdues: personalOverdues,
                onResult: showResult
            )
            .environmentObject(subscriptionStore)
        }
        .sheet(isPresented: $showingOverdues) {
            OverdueListView(
                summary: analyticsSummary.overdueAnalytics,
                creditCards: activeCreditCards,
                loans: activeLoans,
                personalDebts: activePersonalDebts
            )
        }
        .alert(item: $message) { message in
            Alert(
                title: Text(message.title),
                message: Text(message.detail),
                dismissButton: .default(Text("common.ok"))
            )
        }
        .task {
            refreshSystemOverduesIfNeeded()
        }
    }

    private var activeCreditCards: [CreditCardDebt] {
        AnalyticsSupport.activeCreditCardDebts(creditCards)
    }

    private var activeLoans: [LoanDebt] {
        AnalyticsSupport.activeLoanDebts(loans)
    }

    private var activePersonalDebts: [PersonalLendingDebt] {
        AnalyticsSupport.activePersonalLendingDebts(personalDebts)
    }

    private var debtItems: [DebtListItem] {
        readService.debtListItems(
            creditCards: creditCards,
            statements: cardStatements,
            loans: loans,
            loanPlans: loanPlans,
            personalDebts: personalDebts,
            personalPlans: personalPlans,
            personalOverdues: personalOverdues
        )
    }

    private var paymentRows: [PaymentDisplayRow] {
        makePaymentRows(
            creditCards: activeCreditCards,
            loans: activeLoans,
            personalDebts: activePersonalDebts,
            cardPayments: cardPayments,
            loanPayments: loanPayments,
            personalPayments: personalPayments
        )
    }

    private var analyticsSummary: AnalyticsSummary {
        let period = AnalyticsSupport.monthPeriod(containing: Date())
        let debtAnalytics = DebtAnalyticsService().generate(
            creditCardDebts: creditCards,
            creditCardStatements: cardStatements,
            loanDebts: loans,
            loanPlans: loanPlans,
            personalLendingDebts: personalDebts,
            personalLendingPlans: personalPlans,
            period: period
        )
        let paymentAnalytics = PaymentAnalyticsService().generate(
            creditCardDebts: creditCards,
            creditCardPayments: cardPayments,
            loanDebts: loans,
            loanPayments: loanPayments,
            personalLendingDebts: personalDebts,
            personalLendingPayments: personalPayments,
            period: period
        )
        let overdueAnalytics = OverdueAnalyticsService().generate(
            creditCardDebts: creditCards,
            creditCardStatements: cardStatements,
            creditCardBreakdowns: cardBreakdowns,
            loanDebts: loans,
            loanPlans: loanPlans,
            loanOverdues: loanOverdues,
            personalLendingDebts: personalDebts,
            personalLendingPlans: personalPlans,
            personalLendingOverdues: personalOverdues,
            today: Date()
        )
        let costAnalytics = CostAnalyticsService().generate(
            creditCardDebts: creditCards,
            creditCardStatements: cardStatements,
            creditCardBreakdowns: cardBreakdowns,
            loanDebts: loans,
            loanPlans: loanPlans,
            loanOverdues: loanOverdues,
            personalLendingDebts: personalDebts,
            personalLendingPlans: personalPlans
        )
        let fixedPaidAmount = paymentAnalytics.loanCumulativePaidAmount + paymentAnalytics.personalLendingCumulativePaidAmount
        return AnalyticsSummary(
            debtAnalytics: debtAnalytics,
            paymentAnalytics: paymentAnalytics,
            overdueAnalytics: overdueAnalytics,
            costAnalytics: costAnalytics,
            overallRepaymentProgress: AnalyticsSupport.ratio(
                paymentAnalytics.cumulativePaidAmount,
                paymentAnalytics.cumulativePaidAmount + debtAnalytics.totalRemainingAmount
            ),
            fixedDebtProgress: AnalyticsSupport.ratio(
                fixedPaidAmount,
                fixedPaidAmount + debtAnalytics.fixedDebtAmount
            ),
            creditCardCurrentStatementProgress: AnalyticsSupport.ratio(
                debtAnalytics.creditCardCurrentStatementPaidAmount,
                debtAnalytics.creditCardCurrentStatementAmount
            ),
            generatedAt: Date()
        )
    }

    private func refreshSystemOverduesIfNeeded() {
        guard subscriptionStore.hasFullAccess else { return }
        do {
            let today = Date()
            let cardService = CreditCardDebtService(modelContext: modelContext, writeAccessAuthorizer: subscriptionStore)
            var mutableCardOverdues = cardOverdues
            for card in activeCreditCards {
                guard let statement = latestStatement(for: card.id),
                      let rule = cardRules.first(where: { $0.debtID == card.id }) else { continue }
                let plan = cardPlans.first { $0.statementID == statement.id && $0.isActive }
                let payments = cardPayments.filter { $0.statementID == statement.id && $0.isActive }
                _ = try cardService.refreshStatementOverdue(
                    debt: card,
                    statement: statement,
                    plan: plan,
                    payments: payments,
                    overdues: &mutableCardOverdues,
                    rule: rule,
                    today: today
                )
            }

            let loanService = LoanDebtService(modelContext: modelContext, writeAccessAuthorizer: subscriptionStore)
            var mutableLoanOverdues = loanOverdues
            for loan in activeLoans {
                _ = try loanService.refreshOverdues(
                    debt: loan,
                    plans: loanPlans.filter { $0.debtID == loan.id },
                    overdues: &mutableLoanOverdues,
                    calculationRules: loanRules,
                    today: today
                )
            }

            let personalService = PersonalLendingDebtService(modelContext: modelContext, writeAccessAuthorizer: subscriptionStore)
            var mutablePersonalOverdues = personalOverdues
            for debt in activePersonalDebts {
                _ = try personalService.refreshOverdues(
                    debt: debt,
                    plans: personalPlans.filter { $0.debtID == debt.id },
                    overdues: &mutablePersonalOverdues,
                    today: today
                )
            }
        } catch {
            showResult(.failure(error))
        }
    }

    private func latestStatement(for debtID: UUID) -> CreditCardStatement? {
        AnalyticsSupport.latestEffectiveStatementByDebt(
            cardStatements,
            debtIDs: Set([debtID])
        )[debtID]
    }

    private func showResult(_ result: Result<Void, Error>) {
        switch result {
        case .success:
            message = UXMessage(
                title: AppText.string("message.saved.title", defaultValue: "Saved"),
                detail: AppText.string("message.saved.detail", defaultValue: "The change has been saved.")
            )
        case .failure(let error):
            message = UXMessage(
                title: AppText.string("message.error.title", defaultValue: "Could not complete action"),
                detail: uxErrorDescription(error)
            )
        }
    }
}

private enum AppTab: Hashable {
    case overview
    case debts
    case payments
    case strategy
    case statistics
}

private struct OverviewTab: View {
    @Bindable var settings: AppUserSettings
    var summary: AnalyticsSummary
    var debtItems: [DebtListItem]
    var onAddDebt: () -> Void
    var onOpenOverdues: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        NavigationStack {
            AppScroll(title: AppText.string("tab.dashboard", defaultValue: "Overview")) {
                VStack(spacing: 16) {
                    HeroAmountCard(
                        title: AppText.string("metric.totalRemaining", defaultValue: "Total Remaining"),
                        amount: summary.debtAnalytics.totalRemainingAmount,
                        progress: summary.overallRepaymentProgress,
                        caption: AppText.string("overview.totalCaption", defaultValue: "Based on app records and confirmed statements.")
                    )

                    LazyVGrid(columns: twoColumns, spacing: 12) {
                        MetricTile(
                            title: AppText.string("metric.monthPlanned", defaultValue: "Planned This Month"),
                            value: AppText.money(summary.debtAnalytics.currentMonthPlannedRepaymentAmount),
                            icon: "calendar.badge.clock",
                            color: DebtTheme.primary
                        )
                        MetricTile(
                            title: AppText.string("metric.monthPaid", defaultValue: "Paid This Month"),
                            value: AppText.money(summary.paymentAnalytics.currentMonthPaidAmount),
                            icon: "checkmark.circle.fill",
                            color: DebtTheme.success
                        )
                        MetricTile(
                            title: AppText.string("overview.overdueNow", defaultValue: "Overdue"),
                            value: "\(summary.overdueAnalytics.currentOverduePeriodCount)",
                            icon: "exclamationmark.triangle.fill",
                            color: DebtTheme.danger
                        )
                        MetricTile(
                            title: AppText.string("field.monthlyBudget", defaultValue: "Monthly Budget"),
                            value: AppText.money(settings.monthlyRepaymentBudget),
                            icon: "wallet.pass.fill",
                            color: DebtTheme.strategy
                        )
                    }

                    SectionCard(
                        title: AppText.string("overview.todo", defaultValue: "This Month"),
                        actionTitle: summary.overdueAnalytics.items.isEmpty ? nil : AppText.string("overview.viewOverdues", defaultValue: "View Overdue"),
                        action: onOpenOverdues
                    ) {
                        if debtItems.isEmpty {
                            EmptyStateView(
                                icon: "tray",
                                title: AppText.string("empty.noDebts", defaultValue: "No debts yet"),
                                message: AppText.string("overview.emptyDebtMessage", defaultValue: "Add the first debt and the app will help organize a repayment plan."),
                                buttonTitle: AppText.string("debt.add", defaultValue: "Add Debt"),
                                action: onAddDebt
                            )
                        } else {
                            VStack(spacing: 10) {
                                ForEach(Array(debtItems.prefix(4))) { item in
                                    TodoRow(item: item)
                                }
                            }
                        }
                    }

                    InlineNotice(
                        style: summary.overdueAnalytics.currentOverduePeriodCount > 0 ? .risk : .info,
                        title: summary.overdueAnalytics.currentOverduePeriodCount > 0
                            ? AppText.string("overview.riskTitle", defaultValue: "A few items need attention")
                            : AppText.string("overview.calmTitle", defaultValue: "Records are organized"),
                        message: summary.overdueAnalytics.currentOverduePeriodCount > 0
                            ? AppText.string("overview.riskCopy", defaultValue: "Start with overdue and minimum payments. Amounts here are app estimates, not creditor results.")
                            : AppText.string("overview.calmCopy", defaultValue: "Keep records updated to make monthly planning easier.")
                    )

                    SectionCard(title: AppText.string("overview.recent", defaultValue: "Recent Activity")) {
                        if let latest = debtItems.first {
                            TodoRow(item: latest)
                        } else {
                            Text(AppText.string("overview.noRecent", defaultValue: "No recent activity yet."))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel(Text("tab.settings"))
                }
            }
        }
    }
}

private struct DebtListTab: View {
    var debtItems: [DebtListItem]
    var creditCards: [CreditCardDebt]
    var cardRules: [CreditCardCalculationRule]
    var cardStatements: [CreditCardStatement]
    var cardPlans: [CreditCardRepaymentPlan]
    var cardBreakdowns: [CreditCardStatementBreakdown]
    var cardPayments: [CreditCardPaymentRecord]
    var cardOverdues: [CreditCardOverdueRecord]
    var cardInstallments: [CreditCardInstallmentPlan]
    var loans: [LoanDebt]
    var loanPlans: [LoanRepaymentPlan]
    var loanPayments: [LoanPaymentRecord]
    var loanAllocations: [LoanPaymentAllocationDetail]
    var loanOverdues: [LoanOverdueRecord]
    var loanRules: [LoanCalculationRule]
    var personalDebts: [PersonalLendingDebt]
    var personalPlans: [PersonalLendingPlan]
    var personalPayments: [PersonalLendingPaymentRecord]
    var personalAllocations: [PersonalLendingAllocationDetail]
    var personalOverdues: [PersonalLendingOverdueRecord]
    @Bindable var settings: AppUserSettings
    var onAddDebt: () -> Void
    var onRecordPayment: (DebtSelection) -> Void
    var onUpdateStatement: (UUID) -> Void
    var onResult: (Result<Void, Error>) -> Void

    @State private var filter: DebtListFilter = .all

    var body: some View {
        NavigationStack {
            AppScroll(title: AppText.string("tab.debts", defaultValue: "Debts")) {
                Picker(AppText.string("common.filter", defaultValue: "Filter"), selection: $filter) {
                    ForEach(DebtListFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                if filteredItems.isEmpty {
                    EmptyStateView(
                        icon: "creditcard",
                        title: AppText.string("empty.noDebts", defaultValue: "No debts yet"),
                        message: AppText.string("debt.emptyFiltered", defaultValue: "No debt records match the current filter."),
                        buttonTitle: AppText.string("debt.add", defaultValue: "Add Debt"),
                        action: onAddDebt
                    )
                } else {
                    VStack(spacing: 12) {
                        ForEach(filteredItems) { item in
                            NavigationLink {
                                DebtDetailScreen(
                                    item: item,
                                    creditCards: creditCards,
                                    cardRules: cardRules,
                                    cardStatements: cardStatements,
                                    cardPlans: cardPlans,
                                    cardBreakdowns: cardBreakdowns,
                                    cardPayments: cardPayments,
                                    cardOverdues: cardOverdues,
                                    cardInstallments: cardInstallments,
                                    loans: loans,
                                    loanPlans: loanPlans,
                                    loanPayments: loanPayments,
                                    loanAllocations: loanAllocations,
                                    loanOverdues: loanOverdues,
                                    loanRules: loanRules,
                                    personalDebts: personalDebts,
                                    personalPlans: personalPlans,
                                    personalPayments: personalPayments,
                                    personalAllocations: personalAllocations,
                                    personalOverdues: personalOverdues,
                                    settings: settings,
                                    onRecordPayment: onRecordPayment,
                                    onUpdateStatement: onUpdateStatement,
                                    onResult: onResult
                                )
                            } label: {
                                DebtCardView(
                                    item: item,
                                    primaryAction: { onRecordPayment(DebtSelection(type: item.debtType, id: item.id)) }
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onAddDebt) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel(Text("debt.add"))
                }
            }
        }
    }

    private var filteredItems: [DebtListItem] {
        debtItems.filter { item in
            switch filter {
            case .all:
                return true
            case .creditCard:
                return item.debtType == .creditCard
            case .loan:
                return item.debtType == .loan
            case .personalLending:
                return item.debtType == .personalLending
            case .overdue:
                return item.status == .overdue || item.overdueDays > 0
            case .paidOff:
                return item.status == .paidOff
            }
        }
    }
}

private struct DebtDetailScreen: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) private var dismiss

    var item: DebtListItem
    var creditCards: [CreditCardDebt]
    var cardRules: [CreditCardCalculationRule]
    var cardStatements: [CreditCardStatement]
    var cardPlans: [CreditCardRepaymentPlan]
    var cardBreakdowns: [CreditCardStatementBreakdown]
    var cardPayments: [CreditCardPaymentRecord]
    var cardOverdues: [CreditCardOverdueRecord]
    var cardInstallments: [CreditCardInstallmentPlan]
    var loans: [LoanDebt]
    var loanPlans: [LoanRepaymentPlan]
    var loanPayments: [LoanPaymentRecord]
    var loanAllocations: [LoanPaymentAllocationDetail]
    var loanOverdues: [LoanOverdueRecord]
    var loanRules: [LoanCalculationRule]
    var personalDebts: [PersonalLendingDebt]
    var personalPlans: [PersonalLendingPlan]
    var personalPayments: [PersonalLendingPaymentRecord]
    var personalAllocations: [PersonalLendingAllocationDetail]
    var personalOverdues: [PersonalLendingOverdueRecord]
    @Bindable var settings: AppUserSettings
    var onRecordPayment: (DebtSelection) -> Void
    var onUpdateStatement: (UUID) -> Void
    var onResult: (Result<Void, Error>) -> Void

    @State private var showingEdit = false
    @State private var confirmingDelete = false

    private let readService = DebtReadService()

    var body: some View {
        AppScroll(title: item.name) {
            VStack(spacing: 14) {
                SummaryHeader(item: item)

                HStack(spacing: 10) {
                    Button {
                        onRecordPayment(DebtSelection(type: item.debtType, id: item.id))
                    } label: {
                        Label(AppText.string("payments.record", defaultValue: "Record Payment"), systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button {
                        showingEdit = true
                    } label: {
                        Image(systemName: "pencil")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(SecondaryIconButtonStyle())
                }

                switch item.debtType {
                case .creditCard:
                    creditCardDetail
                case .loan:
                    loanDetail
                case .personalLending:
                    personalDetail
                }

                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label(AppText.string("common.archive", defaultValue: "Archive"), systemImage: "archivebox")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DangerButtonStyle())
            }
        }
        .sheet(isPresented: $showingEdit) {
            EditDebtSheet(
                selection: DebtSelection(type: item.debtType, id: item.id),
                creditCards: creditCards,
                loans: loans,
                personalDebts: personalDebts,
                settings: settings,
                onResult: onResult
            )
            .environmentObject(subscriptionStore)
        }
        .confirmationDialog(
            AppText.string("debt.deleteTitle", defaultValue: "Archive this debt?"),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button(AppText.string("common.archive", defaultValue: "Archive"), role: .destructive) {
                archiveDebt()
            }
            Button(AppText.string("common.cancel", defaultValue: "Cancel"), role: .cancel) {}
        } message: {
            Text(AppText.string("debt.deleteCopy", defaultValue: "Related plans, payments, overdue records and statistics will no longer be active in the app."))
        }
    }

    @ViewBuilder
    private var creditCardDetail: some View {
        if let debt = creditCards.first(where: { $0.id == item.id }) {
            let detail = readService.creditCardDetail(
                debt: debt,
                statements: cardStatements,
                payments: cardPayments,
                overdues: cardOverdues,
                rules: cardRules
            )
            let breakdown = detail.currentStatement.flatMap { statement in
                cardBreakdowns.first { $0.statementID == statement.id && $0.isActive }
            }

            SectionCard(
                title: AppText.string("detail.cardInfo", defaultValue: "Card Info"),
                actionTitle: AppText.string("statement.update", defaultValue: "Update Statement"),
                action: { onUpdateStatement(debt.id) }
            ) {
                VStack(spacing: 10) {
                    DetailRow(title: AppText.string("field.bank", defaultValue: "Bank"), value: debt.bankName.isEmpty ? AppText.string("common.none") : debt.bankName)
                    DetailRow(title: AppText.string("field.billingDay", defaultValue: "Billing Day"), value: "\(debt.billingDay)")
                    DetailRow(title: AppText.string("field.dueDay", defaultValue: "Due Day"), value: "\(debt.dueDay)")
                    if let creditLimit = debt.creditLimit {
                        DetailRow(title: AppText.string("field.creditLimit", defaultValue: "Credit Limit"), value: AppText.money(creditLimit, currencyCode: debt.currencyCode))
                    }
                }
            }

            SectionCard(title: AppText.string("field.currentStatement", defaultValue: "Current Statement")) {
                if let statement = detail.currentStatement {
                    VStack(spacing: 10) {
                        HStack {
                            StatusChip(title: statement.source == .fallback ? AppText.string("statement.pendingConfirm", defaultValue: "Needs Confirm") : AppText.statementStatus(statement.status), color: statement.source == .fallback ? DebtTheme.fallback : statusColor(statement.status))
                            Spacer()
                            Text(AppText.date(statement.dueDate))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        DetailRow(title: AppText.string("field.statementAmount", defaultValue: "Statement Amount"), value: AppText.money(statement.statementAmount, currencyCode: debt.currencyCode))
                        DetailRow(title: AppText.string("field.minimumPayment", defaultValue: "Minimum Payment"), value: AppText.money(statement.minimumPaymentAmount, currencyCode: debt.currencyCode))
                        DetailRow(title: AppText.string("statement.paidAmount", defaultValue: "Paid Amount"), value: AppText.money(statement.paidAmount, currencyCode: debt.currencyCode))
                        DetailRow(title: AppText.string("statement.remainingAmount", defaultValue: "Remaining Due"), value: AppText.money(statement.remainingAmount, currencyCode: debt.currencyCode))
                        if statement.source == .fallback {
                            InlineNotice(
                                style: .info,
                                title: AppText.string("statement.fallbackTitle", defaultValue: "Fallback statement"),
                                message: AppText.string("statement.fallbackCopy", defaultValue: "This statement is app-generated fallback data. Please confirm it with the real statement.")
                            )
                        }
                    }
                } else {
                    EmptyStateView(
                        icon: "doc.text",
                        title: AppText.string("empty.noStatements", defaultValue: "No statements"),
                        message: AppText.string("statement.emptyCopy", defaultValue: "Update the current credit card statement to start tracking this card."),
                        buttonTitle: AppText.string("statement.update", defaultValue: "Update Statement"),
                        action: { onUpdateStatement(debt.id) }
                    )
                }
            }
            .accessibilityIdentifier("debt.detail.currentStatement")

            if let breakdown {
                SectionCard(title: AppText.string("statement.breakdown", defaultValue: "Statement Breakdown")) {
                    VStack(spacing: 10) {
                        DetailRow(title: AppText.string("breakdown.normalSpending", defaultValue: "Normal Spending"), value: AppText.money(breakdown.normalSpending, currencyCode: debt.currencyCode))
                        DetailRow(title: AppText.string("breakdown.installment", defaultValue: "Installments"), value: AppText.money(breakdown.installmentPrincipal + breakdown.installmentFee + breakdown.installmentInterest, currencyCode: debt.currencyCode))
                        DetailRow(title: AppText.string("breakdown.interestFees", defaultValue: "Interest and Fees"), value: AppText.money(breakdown.revolvingInterest + breakdown.overdueFee + breakdown.penaltyInterest, currencyCode: debt.currencyCode))
                        InlineNotice(
                            style: .info,
                            title: AppText.string("statement.breakdownNoticeTitle", defaultValue: "For analysis only"),
                            message: AppText.string("statement.breakdownNotice", defaultValue: "Breakdown details help statistics and do not recalculate the statement amount.")
                        )
                    }
                }
            }

            PaymentHistoryCard(
                title: AppText.string("detail.payments", defaultValue: "Payments"),
                rows: detail.payments.map { PaymentDisplayRow(id: $0.id, type: .creditCard, name: debt.name, date: $0.paymentDate, amount: $0.amount, note: $0.note) },
                currencyCode: debt.currencyCode
            )

            OverdueRecordCard(overdues: detail.overdues, currencyCode: debt.currencyCode)
        }
    }

    @ViewBuilder
    private var loanDetail: some View {
        if let debt = loans.first(where: { $0.id == item.id }) {
            let detail = readService.loanDetail(
                debt: debt,
                plans: loanPlans,
                payments: loanPayments,
                allocationDetails: loanAllocations,
                overdues: loanOverdues,
                rules: loanRules
            )
            let nextPlan = detail.plans.first { $0.status != .paid && $0.remainingTotalAmount > 0 }

            SectionCard(title: AppText.string("detail.loanInfo", defaultValue: "Loan Info")) {
                VStack(spacing: 10) {
                    DetailRow(title: AppText.string("field.creditor", defaultValue: "Creditor"), value: debt.creditorName.isEmpty ? AppText.string("common.none") : debt.creditorName)
                    DetailRow(title: AppText.string("loan.remainingPrincipal", defaultValue: "Remaining Principal"), value: AppText.money(debt.outstandingPrincipal, currencyCode: debt.currencyCode))
                    DetailRow(title: AppText.string("field.interestRate", defaultValue: "Interest Rate"), value: AppText.percent(debt.annualInterestRate))
                    DetailRow(title: AppText.string("field.repaymentMethod", defaultValue: "Repayment Method"), value: AppText.string("loanMethod.\(debt.repaymentMethod.rawValue)", defaultValue: debt.repaymentMethod.rawValue))
                    if let nextPlan {
                        DetailRow(title: AppText.string("loan.currentDue", defaultValue: "Current Due"), value: AppText.money(nextPlan.remainingTotalAmount, currencyCode: debt.currencyCode))
                    }
                }
            }

            TimelineSection(
                title: AppText.string("detail.plans", defaultValue: "Repayment Plan"),
                rows: detail.plans.prefix(12).map {
                    TimelineRowData(
                        title: String(format: AppText.string("format.period", defaultValue: "Period %d"), $0.periodIndex),
                        date: $0.dueDate,
                        amount: $0.remainingTotalAmount,
                        status: AppText.planStatus($0.status),
                        color: planStatusColor($0.status)
                    )
                },
                currencyCode: debt.currencyCode
            )

            PaymentHistoryCard(
                title: AppText.string("detail.payments", defaultValue: "Payments"),
                rows: detail.payments.map { PaymentDisplayRow(id: $0.id, type: .loan, name: debt.name, date: $0.paymentDate, amount: $0.totalAmount, note: $0.note) },
                currencyCode: debt.currencyCode
            )

            LoanOverdueRecordCard(overdues: detail.overdues, currencyCode: debt.currencyCode)
        }
    }

    @ViewBuilder
    private var personalDetail: some View {
        if let debt = personalDebts.first(where: { $0.id == item.id }) {
            let detail = readService.personalLendingDetail(
                debt: debt,
                plans: personalPlans,
                payments: personalPayments,
                allocationDetails: personalAllocations,
                overdues: personalOverdues
            )

            SectionCard(title: AppText.string("detail.personalInfo", defaultValue: "Personal Lending Info")) {
                VStack(spacing: 10) {
                    DetailRow(title: AppText.string("field.lender", defaultValue: "Lender"), value: debt.lenderName.isEmpty ? AppText.string("common.none") : debt.lenderName)
                    DetailRow(title: AppText.string("personal.totalAmount", defaultValue: "Borrowed Total"), value: AppText.money(debt.totalPayableAmount))
                    DetailRow(title: AppText.string("statement.paidAmount", defaultValue: "Paid Amount"), value: AppText.money(debt.paidAmount))
                    DetailRow(title: AppText.string("personal.remainingAmount", defaultValue: "Remaining Amount"), value: AppText.money(debt.remainingAmount))
                    DetailRow(title: AppText.string("field.repaymentMethod", defaultValue: "Repayment Method"), value: AppText.string("personalMethod.\(debt.repaymentMethod.rawValue)", defaultValue: debt.repaymentMethod.rawValue))
                }
            }

            if detail.plans.isEmpty {
                SectionCard(title: AppText.string("detail.payments", defaultValue: "Payments")) {
                    Text(AppText.string("personal.noFixedPlanCopy", defaultValue: "This no-fixed-plan debt is tracked by total, paid, remaining amount and recent payments."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                TimelineSection(
                    title: AppText.string("detail.plans", defaultValue: "Repayment Plan"),
                    rows: detail.plans.prefix(12).map {
                        TimelineRowData(
                            title: String(format: AppText.string("format.period", defaultValue: "Period %d"), $0.periodIndex),
                            date: $0.dueDate,
                            amount: $0.remainingAmount,
                            status: AppText.personalPlanStatus($0.status),
                            color: personalPlanStatusColor($0.status)
                        )
                    },
                    currencyCode: Locale.current.currency?.identifier ?? "USD"
                )
            }

            PaymentHistoryCard(
                title: AppText.string("detail.payments", defaultValue: "Payments"),
                rows: detail.payments.map { PaymentDisplayRow(id: $0.id, type: .personalLending, name: debt.name, date: $0.paymentDate, amount: $0.amount, note: $0.note) },
                currencyCode: Locale.current.currency?.identifier ?? "USD"
            )

            PersonalOverdueRecordCard(overdues: detail.overdues)
        }
    }

    private func archiveDebt() {
        do {
            switch item.debtType {
            case .creditCard:
                guard let debt = creditCards.first(where: { $0.id == item.id }) else { return }
                _ = try CreditCardDebtService(modelContext: modelContext, writeAccessAuthorizer: subscriptionStore).softDeleteDebt(
                    debt,
                    statements: cardStatements,
                    plans: cardPlans,
                    breakdowns: cardBreakdowns,
                    payments: cardPayments,
                    overdues: cardOverdues,
                    installments: cardInstallments
                )
            case .loan:
                guard let debt = loans.first(where: { $0.id == item.id }) else { return }
                _ = try LoanDebtService(modelContext: modelContext, writeAccessAuthorizer: subscriptionStore).softDeleteDebt(debt, overdues: loanOverdues)
            case .personalLending:
                guard let debt = personalDebts.first(where: { $0.id == item.id }) else { return }
                _ = try PersonalLendingDebtService(modelContext: modelContext, writeAccessAuthorizer: subscriptionStore).softDeleteDebt(debt, overdues: personalOverdues)
            }
            markStrategyDirty(settings, in: modelContext)
            onResult(.success(()))
            dismiss()
        } catch {
            onResult(.failure(error))
        }
    }
}

private struct PaymentLedgerTab: View {
    var creditCards: [CreditCardDebt]
    var loans: [LoanDebt]
    var personalDebts: [PersonalLendingDebt]
    var cardPayments: [CreditCardPaymentRecord]
    var loanPayments: [LoanPaymentRecord]
    var personalPayments: [PersonalLendingPaymentRecord]
    var onRecordPayment: () -> Void

    @State private var filter: PaymentFilter = .all

    var body: some View {
        NavigationStack {
            AppScroll(title: AppText.string("tab.payments", defaultValue: "Transactions")) {
                Picker(AppText.string("common.filter", defaultValue: "Filter"), selection: $filter) {
                    ForEach(PaymentFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                SectionCard(title: AppText.string("payments.month", defaultValue: "This Month")) {
                    let monthRows = filteredRows.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }
                    VStack(spacing: 10) {
                        DetailRow(title: AppText.string("metric.monthPaid", defaultValue: "Paid This Month"), value: AppText.money(monthRows.reduce(Decimal(0)) { $0 + $1.amount }))
                        DetailRow(title: AppText.string("payments.count", defaultValue: "Records"), value: "\(monthRows.count)")
                    }
                }

                SectionCard(title: AppText.string("payments.recent", defaultValue: "Recent Payments")) {
                    if filteredRows.isEmpty {
                        EmptyStateView(
                            icon: "arrow.left.arrow.right.circle",
                            title: AppText.string("empty.noPayments", defaultValue: "No payments"),
                            message: AppText.string("payments.emptyCopy", defaultValue: "Record the first payment to see progress and history here."),
                            buttonTitle: AppText.string("payments.record", defaultValue: "Record Payment"),
                            action: onRecordPayment
                        )
                    } else {
                        VStack(spacing: 12) {
                            ForEach(filteredRows.prefix(40)) { row in
                                PaymentRow(row: row)
                            }
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onRecordPayment) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel(Text("payments.record"))
                }
            }
        }
    }

    private var filteredRows: [PaymentDisplayRow] {
        makePaymentRows(
            creditCards: creditCards,
            loans: loans,
            personalDebts: personalDebts,
            cardPayments: cardPayments,
            loanPayments: loanPayments,
            personalPayments: personalPayments
        )
        .filter { row in
            switch filter {
            case .all:
                return true
            case .currentMonth:
                return Calendar.current.isDate(row.date, equalTo: Date(), toGranularity: .month)
            case .creditCard:
                return row.type == .creditCard
            case .loan:
                return row.type == .loan
            case .personalLending:
                return row.type == .personalLending
            }
        }
    }
}

private struct StrategyTab: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Bindable var settings: AppUserSettings
    var batches: [StrategyComparisonBatch]
    var simulations: [StrategySimulation]
    var monthSnapshots: [StrategyMonthSnapshot]
    var allocations: [StrategyDebtAllocation]
    var onResult: (Result<Void, Error>) -> Void

    @State private var monthlyBudgetText = ""
    @State private var latestResult: StrategyComparisonResult?
    @State private var selectedStrategy: StrategyType?
    @State private var savedBatchID: UUID?
    @FocusState private var budgetFocused: Bool

    var body: some View {
        NavigationStack {
            AppScroll(title: AppText.string("tab.strategy", defaultValue: "Strategy")) {
                HeroAmountCard(
                    title: AppText.string("field.monthlyBudget", defaultValue: "Monthly Budget"),
                    amount: decimal(from: monthlyBudgetText).isZero ? settings.monthlyRepaymentBudget : decimal(from: monthlyBudgetText),
                    progress: 0,
                    caption: AppText.string("settings.strategyDisclaimer", defaultValue: "Strategy results are internal simulations and do not change real debt records.")
                )

                if settings.strategyDataChanged {
                    InlineNotice(
                        style: .info,
                        title: AppText.string("strategy.dataChangedTitle", defaultValue: "Debt data changed"),
                        message: AppText.string("strategy.dataChangedCopy", defaultValue: "Generate a new strategy when you are ready. Long-term simulations are not recalculated automatically.")
                    )
                }

                SectionCard(title: AppText.string("strategy.generate", defaultValue: "Generate Strategy")) {
                    VStack(spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            FormFieldTitle(title: AppText.string("field.monthlyBudget", defaultValue: "Monthly Budget"))
                            TextField("", text: $monthlyBudgetText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(1)
                                .focused($budgetFocused)
                                .accessibilityLabel(Text(AppText.string("field.monthlyBudget", defaultValue: "Monthly Budget")))
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(DebtTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))

                        Button {
                            generate()
                        } label: {
                            Label(AppText.string("strategy.generateNow", defaultValue: "Generate Strategy"), systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }

                if let latestResult {
                    SectionCard(title: AppText.string("strategy.latest", defaultValue: "Latest Comparison")) {
                        VStack(spacing: 14) {
                            StrategyComparisonTable(
                                summaries: latestResult.summaries,
                                recommendedStrategy: hasSavedLatest ? nil : latestResult.comparisonBatch.recommendedStrategy,
                                selectedStrategy: $selectedStrategy,
                                isSelectable: hasSavedLatest == false
                            )

                            if selectedStrategy == nil, hasSavedLatest == false {
                                InlineNotice(
                                    style: .info,
                                    title: AppText.string("strategy.selectTitle", defaultValue: "Select a strategy"),
                                    message: AppText.string("strategy.selectCopy", defaultValue: "Choose one strategy from the comparison table before saving.")
                                )
                            }

                            if hasSavedLatest {
                                NavigationLink {
                                    StrategyDetailView(
                                        batch: latestResult.comparisonBatch,
                                        simulations: latestResult.simulations.map(\.simulation),
                                        monthSnapshots: latestResult.simulations.flatMap(\.monthSnapshots),
                                        allocations: latestResult.simulations.flatMap(\.allocations)
                                    )
                                } label: {
                                    Label(AppText.string("strategy.viewDetail", defaultValue: "View Strategy Details"), systemImage: "doc.text.magnifyingglass")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(SecondaryActionButtonStyle())
                            } else {
                                Button {
                                    saveSelectedStrategy()
                                } label: {
                                    Label(AppText.string("strategy.saveSelected", defaultValue: "Save Selected Strategy"), systemImage: "checkmark.circle.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(selectedStrategy == nil)
                                .opacity(selectedStrategy == nil ? 0.45 : 1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                SectionCard(title: AppText.string("strategy.history", defaultValue: "Snapshots")) {
                    if batches.isEmpty {
                        EmptyStateView(
                            icon: "clock",
                            title: AppText.string("empty.noStrategies", defaultValue: "No strategy snapshots"),
                            message: AppText.string("strategy.emptyCopy", defaultValue: "Enter a budget to compare snowball, avalanche and balanced strategies."),
                            buttonTitle: nil,
                            action: nil
                        )
                    } else {
                        VStack(spacing: 12) {
                            ForEach(Array(batches.sorted { $0.generatedAt > $1.generatedAt }.prefix(10))) { batch in
                                NavigationLink {
                                    StrategyDetailView(
                                        batch: batch,
                                        simulations: batchSimulations(for: batch),
                                        monthSnapshots: monthSnapshots,
                                        allocations: allocations
                                    )
                                } label: {
                                    StrategyHistoryRow(batch: batch)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .onAppear {
                if monthlyBudgetText.isEmpty, settings.monthlyRepaymentBudget > 0 {
                    monthlyBudgetText = plainNumber(settings.monthlyRepaymentBudget)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(AppText.string("common.done", defaultValue: "Done")) {
                        budgetFocused = false
                    }
                }
            }
        }
    }

    private var hasSavedLatest: Bool {
        guard let latestResult, let savedBatchID else { return false }
        return latestResult.comparisonBatch.id == savedBatchID
    }

    private func generate() {
        budgetFocused = false
        do {
            let budget = decimal(from: monthlyBudgetText)
            let request = StrategySimulationRequest(
                monthlyBudget: budget > 0 ? budget : settings.monthlyRepaymentBudget
            )
            let result = try StrategySimulationService(modelContext: modelContext).previewComparison(request: request)
            latestResult = result
            selectedStrategy = nil
            savedBatchID = nil
        } catch {
            onResult(.failure(error))
        }
    }

    private func saveSelectedStrategy() {
        budgetFocused = false
        guard let latestResult, let selectedStrategy else { return }

        do {
            try subscriptionStore.requireWriteAccess()
            settings.strategyDataChanged = false
            settings.updatedAt = Date()
            let savedResult = try StrategySimulationService(modelContext: modelContext).saveComparisonResult(
                latestResult,
                selectedStrategy: selectedStrategy
            )
            self.latestResult = savedResult
            savedBatchID = savedResult.comparisonBatch.id
            onResult(.success(()))
        } catch {
            onResult(.failure(error))
        }
    }

    private func batchSimulations(for batch: StrategyComparisonBatch) -> [StrategySimulation] {
        simulations
            .filter { $0.comparisonBatchID == batch.id }
            .sorted { $0.strategyType.rawValue < $1.strategyType.rawValue }
    }
}

private struct StatisticsTab: View {
    var creditCards: [CreditCardDebt]
    var cardStatements: [CreditCardStatement]
    var cardBreakdowns: [CreditCardStatementBreakdown]
    var cardPayments: [CreditCardPaymentRecord]
    var loans: [LoanDebt]
    var loanPlans: [LoanRepaymentPlan]
    var loanPayments: [LoanPaymentRecord]
    var loanOverdues: [LoanOverdueRecord]
    var personalDebts: [PersonalLendingDebt]
    var personalPlans: [PersonalLendingPlan]
    var personalPayments: [PersonalLendingPaymentRecord]
    var personalOverdues: [PersonalLendingOverdueRecord]
    var onOpenOverdues: () -> Void

    @State private var period: StatisticsPeriod = .sixMonths
    @State private var category: StatisticsCategory = .overview

    private let calendar = Calendar(identifier: .gregorian)

    var body: some View {
        NavigationStack {
            AppScroll(title: AppText.string("tab.statistics", defaultValue: "Statistics")) {
                StatisticsControlPanel(period: $period, category: $category)
                categoryContent
            }
        }
    }

    @ViewBuilder
    private var categoryContent: some View {
        switch category {
        case .overview:
            overviewContent
        case .debtStructure:
            debtStructureContent
        case .paymentAnalysis:
            paymentAnalysisContent
        case .overdueRisk:
            overdueRiskContent
        case .cost:
            costContent
        case .focus:
            focusContent
        }
    }

    @ViewBuilder
    private var overviewContent: some View {
        let summary = periodSummary
        HeroAmountCard(
            title: AppText.string("metric.totalRemaining", defaultValue: "Total Remaining"),
            amount: summary.debtAnalytics.totalRemainingAmount,
            progress: summary.overallRepaymentProgress,
            caption: AppText.string("statistics.overviewCaption", defaultValue: "Current remaining balance with progress based on recorded repayments.")
        )

        StatisticsMetricGrid(metrics: [
            StatisticsMetric(
                title: AppText.string("statistics.periodPlanned", defaultValue: "Planned in Period"),
                value: AppText.money(summary.debtAnalytics.currentMonthPlannedRepaymentAmount),
                caption: period.title,
                icon: "calendar.badge.clock",
                color: DebtTheme.primary
            ),
            StatisticsMetric(
                title: AppText.string("statistics.periodPaid", defaultValue: "Paid in Period"),
                value: AppText.money(summary.paymentAnalytics.currentMonthPaidAmount),
                caption: "\(summary.paymentAnalytics.currentMonthPaymentRecordCount + summary.paymentAnalytics.currentMonthPaymentInputCount) " + AppText.string("payments.count", defaultValue: "Records"),
                icon: "checkmark.circle.fill",
                color: DebtTheme.success
            ),
            StatisticsMetric(
                title: AppText.string("statistics.currentRisk", defaultValue: "Current Risk"),
                value: overdueRiskTitle(summary.overdueAnalytics.riskLevel),
                caption: "\(summary.overdueAnalytics.currentOverduePeriodCount) " + AppText.string("metric.overduePeriodCount", defaultValue: "Overdue Periods"),
                icon: "exclamationmark.triangle.fill",
                color: overdueRiskColor(summary.overdueAnalytics.riskLevel)
            ),
            StatisticsMetric(
                title: AppText.string("cost.total", defaultValue: "Interest and Fees"),
                value: AppText.money(summary.costAnalytics.totalCostAmount),
                caption: AppText.string("statistics.currentCostCaption", defaultValue: "Current app-side estimate"),
                icon: "banknote.fill",
                color: DebtTheme.warning
            )
        ])

        SectionCard(title: AppText.string("statistics.progress", defaultValue: "Progress")) {
            VStack(spacing: 12) {
                ProgressStatRow(
                    title: AppText.string("metric.overallProgress", defaultValue: "Overall Progress"),
                    value: summary.overallRepaymentProgress,
                    color: DebtTheme.primary
                )
                ProgressStatRow(
                    title: AppText.string("statistics.fixedDebtProgress", defaultValue: "Fixed Debt Progress"),
                    value: summary.fixedDebtProgress,
                    color: DebtTheme.strategy
                )
                ProgressStatRow(
                    title: AppText.string("statistics.statementProgress", defaultValue: "Credit Card Statement Progress"),
                    value: summary.creditCardCurrentStatementProgress,
                    color: DebtTheme.success
                )
                DetailRow(title: AppText.string("statistics.generatedAt", defaultValue: "Generated"), value: AppText.date(summary.generatedAt))
            }
        }
    }

    @ViewBuilder
    private var debtStructureContent: some View {
        let summary = periodSummary
        let total = chartTotal(debtMix)

        ChartCard(
            title: AppText.string("statistics.debtStructure", defaultValue: "Debt Structure"),
            explanation: AppText.string("statistics.debtStructureExplain", defaultValue: "Current remaining balance by debt type."),
            isEmpty: debtMix.isEmpty
        ) {
            Chart(debtMix) { item in
                SectorMark(
                    angle: .value(AppText.string("field.amount", defaultValue: "Amount"), item.amount.doubleValue),
                    innerRadius: .ratio(0.58),
                    angularInset: 1.2
                )
                .foregroundStyle(item.color)
            }
        }

        SectionCard(title: AppText.string("statistics.typeBreakdown", defaultValue: "Type Breakdown")) {
            VStack(spacing: 10) {
                ForEach(debtMix) { item in
                    LegendAmountRow(item: item, total: total)
                }
                if debtMix.isEmpty {
                    EmptyChartState(title: AppText.string("statistics.emptyDebt", defaultValue: "No debt balance to chart."))
                }
            }
        }

        StatisticsMetricGrid(metrics: [
            StatisticsMetric(title: AppText.string("statistics.fixedDebt", defaultValue: "Fixed Debt"), value: AppText.money(summary.debtAnalytics.fixedDebtAmount), caption: AppText.percent(AnalyticsSupport.ratio(summary.debtAnalytics.fixedDebtAmount, summary.debtAnalytics.totalRemainingAmount)), icon: "building.columns.fill", color: DebtTheme.strategy),
            StatisticsMetric(title: AppText.string("statistics.revolvingDebt", defaultValue: "Revolving Debt"), value: AppText.money(summary.debtAnalytics.revolvingDebtAmount), caption: AppText.percent(AnalyticsSupport.ratio(summary.debtAnalytics.revolvingDebtAmount, summary.debtAnalytics.totalRemainingAmount)), icon: "creditcard.fill", color: DebtTheme.primary),
            StatisticsMetric(title: AppText.string("statistics.unpaidDebts", defaultValue: "Unpaid Debts"), value: "\(summary.debtAnalytics.unpaidDebtCount)", caption: "\(summary.debtAnalytics.totalDebtCount) " + AppText.string("statistics.totalDebts", defaultValue: "Total Debts"), icon: "list.bullet.rectangle.fill", color: DebtTheme.neutral),
            StatisticsMetric(title: AppText.string("statistics.paidOffDebts", defaultValue: "Paid Off Debts"), value: "\(summary.debtAnalytics.paidOffDebtCount)", caption: AppText.string("debtStatus.paidOff", defaultValue: "Paid off"), icon: "checkmark.seal.fill", color: DebtTheme.success)
        ])

        if let maxDebt = summary.debtAnalytics.maxSingleDebt {
            SectionCard(title: AppText.string("statistics.maxSingleDebt", defaultValue: "Largest Single Debt")) {
                RankAmountRow(
                    title: maxDebt.name,
                    subtitle: AppText.debtType(maxDebt.debtType),
                    amount: maxDebt.amount,
                    color: typeColor(maxDebt.debtType)
                )
            }
        }
    }

    @ViewBuilder
    private var paymentAnalysisContent: some View {
        let summary = periodSummary
        let periodRows = currentPaymentRows
        let total = chartTotal(paymentMix)

        StatisticsMetricGrid(metrics: [
            StatisticsMetric(title: AppText.string("statistics.periodPaid", defaultValue: "Paid in Period"), value: AppText.money(summary.paymentAnalytics.currentMonthPaidAmount), caption: period.title, icon: "checkmark.circle.fill", color: DebtTheme.success),
            StatisticsMetric(title: AppText.string("statistics.cumulativePaid", defaultValue: "Cumulative Paid"), value: AppText.money(summary.paymentAnalytics.cumulativePaidAmount), caption: AppText.string("statistics.allTime", defaultValue: "All time"), icon: "sum", color: DebtTheme.primary),
            StatisticsMetric(title: AppText.string("payments.count", defaultValue: "Records"), value: "\(summary.paymentAnalytics.currentMonthPaymentRecordCount + summary.paymentAnalytics.currentMonthPaymentInputCount)", caption: AppText.string("statistics.selectedPeriod", defaultValue: "Selected period"), icon: "number.circle.fill", color: DebtTheme.strategy),
            StatisticsMetric(title: AppText.string("statistics.latestPayment", defaultValue: "Latest Payment"), value: periodRows.first.map { AppText.money($0.amount) } ?? AppText.string("common.none"), caption: periodRows.first?.name ?? AppText.string("empty.noPayments", defaultValue: "No payments"), icon: "clock.arrow.circlepath", color: DebtTheme.warning)
        ])

        ChartCard(
            title: AppText.string("statistics.paymentByType", defaultValue: "Payment by Type"),
            explanation: AppText.string("statistics.paymentByTypeExplain", defaultValue: "Repayments recorded in the selected period."),
            isEmpty: paymentMix.isEmpty
        ) {
            Chart(paymentMix) { item in
                BarMark(
                    x: .value(AppText.string("field.type", defaultValue: "Type"), item.title),
                    y: .value(AppText.string("field.amount", defaultValue: "Amount"), item.amount.doubleValue)
                )
                .foregroundStyle(item.color)
            }
        }

        ChartCard(
            title: AppText.string("statistics.paymentTrend", defaultValue: "Payment Trend"),
            explanation: AppText.string("statistics.paymentTrendExplain", defaultValue: "Monthly repayments in the selected range."),
            isEmpty: monthlyPaymentTrend.allSatisfy { $0.amount <= 0 }
        ) {
            Chart(monthlyPaymentTrend) { point in
                AreaMark(
                    x: .value(AppText.string("statistics.month", defaultValue: "Month"), point.monthStart, unit: .month),
                    y: .value(AppText.string("field.amount", defaultValue: "Amount"), point.amount.doubleValue)
                )
                .foregroundStyle(DebtTheme.primary.opacity(0.18))
                LineMark(
                    x: .value(AppText.string("statistics.month", defaultValue: "Month"), point.monthStart, unit: .month),
                    y: .value(AppText.string("field.amount", defaultValue: "Amount"), point.amount.doubleValue)
                )
                .foregroundStyle(DebtTheme.primary)
                .interpolationMethod(.catmullRom)
                PointMark(
                    x: .value(AppText.string("statistics.month", defaultValue: "Month"), point.monthStart, unit: .month),
                    y: .value(AppText.string("field.amount", defaultValue: "Amount"), point.amount.doubleValue)
                )
                .foregroundStyle(DebtTheme.primary)
            }
        }

        SectionCard(title: AppText.string("statistics.paymentBreakdown", defaultValue: "Payment Breakdown")) {
            VStack(spacing: 10) {
                ForEach(paymentMix) { item in
                    LegendAmountRow(item: item, total: total)
                }
                Divider()
                DetailRow(title: AppText.debtType(.creditCard), value: AppText.money(summary.paymentAnalytics.creditCardCumulativePaidAmount))
                DetailRow(title: AppText.debtType(.loan), value: AppText.money(summary.paymentAnalytics.loanCumulativePaidAmount))
                DetailRow(title: AppText.debtType(.personalLending), value: AppText.money(summary.paymentAnalytics.personalLendingCumulativePaidAmount))
            }
        }
    }

    @ViewBuilder
    private var overdueRiskContent: some View {
        let summary = periodSummary

        StatisticsMetricGrid(metrics: [
            StatisticsMetric(title: AppText.string("statistics.riskLevel", defaultValue: "Risk Level"), value: overdueRiskTitle(summary.overdueAnalytics.riskLevel), caption: AppText.string("statistics.currentState", defaultValue: "Current state"), icon: "exclamationmark.triangle.fill", color: overdueRiskColor(summary.overdueAnalytics.riskLevel)),
            StatisticsMetric(title: AppText.string("metric.overdueAmount", defaultValue: "Overdue Amount"), value: AppText.money(summary.overdueAnalytics.currentOverdueTotalAmount), caption: "\(summary.overdueAnalytics.currentOverdueDebtCount) " + AppText.string("metric.overdueDebtCount", defaultValue: "Overdue Debts"), icon: "calendar.badge.exclamationmark", color: DebtTheme.danger),
            StatisticsMetric(title: AppText.string("statistics.minimumGap", defaultValue: "Minimum Gap"), value: AppText.money(summary.overdueAnalytics.creditCardMinimumPaymentGap), caption: AppText.debtType(.creditCard), icon: "creditcard.trianglebadge.exclamationmark", color: DebtTheme.warning),
            StatisticsMetric(title: AppText.string("metric.overdueCost", defaultValue: "Overdue Cost"), value: AppText.money(summary.overdueAnalytics.overdueFeeTotalAmount + summary.overdueAnalytics.penaltyInterestTotalAmount), caption: AppText.string("statistics.feesAndPenalty", defaultValue: "Fees and penalty interest"), icon: "banknote.fill", color: DebtTheme.danger)
        ])

        ChartCard(
            title: AppText.string("statistics.overdueAging", defaultValue: "Overdue Aging"),
            explanation: AppText.string("statistics.overdueExplain", defaultValue: "Overdue amounts are app-side analysis and may differ from creditor records."),
            isEmpty: overdueBuckets.isEmpty
        ) {
            Chart(overdueBuckets) { item in
                BarMark(
                    x: .value(AppText.string("statistics.bucket", defaultValue: "Bucket"), item.title),
                    y: .value(AppText.string("field.amount", defaultValue: "Amount"), item.amount.doubleValue)
                )
                .foregroundStyle(item.color)
            }
        }

        ChartCard(
            title: AppText.string("statistics.overdueByType", defaultValue: "Overdue by Type"),
            explanation: AppText.string("statistics.overdueByTypeExplain", defaultValue: "Current overdue amount split by debt type."),
            isEmpty: overdueTypeMix.isEmpty
        ) {
            Chart(overdueTypeMix) { item in
                SectorMark(
                    angle: .value(AppText.string("field.amount", defaultValue: "Amount"), item.amount.doubleValue),
                    innerRadius: .ratio(0.56),
                    angularInset: 1.2
                )
                .foregroundStyle(item.color)
            }
        }

        SectionCard(
            title: AppText.string("statistics.riskItems", defaultValue: "Risk Items"),
            actionTitle: summary.overdueAnalytics.items.isEmpty ? nil : AppText.string("overview.viewOverdues", defaultValue: "View Overdue"),
            action: onOpenOverdues
        ) {
            if summary.overdueAnalytics.items.isEmpty {
                EmptyChartState(title: AppText.string("overdue.emptyCopy", defaultValue: "No current overdue items were found in app records."))
            } else {
                VStack(spacing: 10) {
                    ForEach(sortedOverdueItems.prefix(6)) { item in
                        RankAmountRow(
                            title: item.debtName,
                            subtitle: AppText.debtType(item.debtType) + " · " + String(format: AppText.string("format.overdueDays", defaultValue: "%d days overdue"), item.overdueDays),
                            amount: item.overdueAmount,
                            color: typeColor(item.debtType)
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var costContent: some View {
        let summary = periodSummary

        StatisticsMetricGrid(metrics: [
            StatisticsMetric(title: AppText.string("cost.total", defaultValue: "Interest and Fees"), value: AppText.money(summary.costAnalytics.totalCostAmount), caption: AppText.string("statistics.currentCostCaption", defaultValue: "Current app-side estimate"), icon: "banknote.fill", color: DebtTheme.warning),
            StatisticsMetric(title: AppText.string("statistics.totalInterest", defaultValue: "Interest"), value: AppText.money(summary.costAnalytics.totalInterestAmount), caption: AppText.string("statistics.allSources", defaultValue: "All sources"), icon: "percent", color: DebtTheme.primary),
            StatisticsMetric(title: AppText.string("statistics.overdueFee", defaultValue: "Overdue Fee"), value: AppText.money(summary.costAnalytics.totalOverdueFeeAmount), caption: AppText.string("field.overdueFee", defaultValue: "Overdue Fee"), icon: "exclamationmark.triangle.fill", color: DebtTheme.danger),
            StatisticsMetric(title: AppText.string("statistics.penaltyInterest", defaultValue: "Penalty Interest"), value: AppText.money(summary.costAnalytics.totalPenaltyInterestAmount), caption: AppText.string("statistics.penaltyCaption", defaultValue: "Late-payment interest"), icon: "bolt.trianglebadge.exclamationmark.fill", color: DebtTheme.strategy)
        ])

        ChartCard(
            title: AppText.string("statistics.costComposition", defaultValue: "Cost Composition"),
            explanation: AppText.string("statistics.costCompositionExplain", defaultValue: "Interest, fees and penalties from app-side records."),
            isEmpty: costComposition.isEmpty
        ) {
            Chart(costComposition) { item in
                SectorMark(
                    angle: .value(AppText.string("field.amount", defaultValue: "Amount"), item.amount.doubleValue),
                    innerRadius: .ratio(0.58),
                    angularInset: 1.2
                )
                .foregroundStyle(item.color)
            }
        }

        ChartCard(
            title: AppText.string("statistics.costByType", defaultValue: "Cost by Debt Type"),
            explanation: AppText.string("statistics.costByTypeExplain", defaultValue: "Current cost estimate grouped by debt type."),
            isEmpty: costTypeMix.isEmpty
        ) {
            Chart(costTypeMix) { item in
                BarMark(
                    x: .value(AppText.string("field.type", defaultValue: "Type"), item.title),
                    y: .value(AppText.string("field.amount", defaultValue: "Amount"), item.amount.doubleValue)
                )
                .foregroundStyle(item.color)
            }
        }

        ChartCard(
            title: AppText.string("statistics.costSource", defaultValue: "Cost Source"),
            explanation: AppText.string("statistics.costSourceExplain", defaultValue: "Where the cost estimate came from."),
            isEmpty: costSourceMix.isEmpty
        ) {
            Chart(costSourceMix) { item in
                SectorMark(
                    angle: .value(AppText.string("field.amount", defaultValue: "Amount"), item.amount.doubleValue),
                    innerRadius: .ratio(0.58),
                    angularInset: 1.2
                )
                .foregroundStyle(item.color)
            }
        }

        SectionCard(title: AppText.string("statistics.highCostDebts", defaultValue: "High-Cost Debts")) {
            if summary.costAnalytics.highCostDebts.isEmpty {
                EmptyChartState(title: AppText.string("statistics.emptyCost", defaultValue: "No cost data to chart."))
            } else {
                VStack(spacing: 10) {
                    ForEach(summary.costAnalytics.highCostDebts.prefix(6)) { item in
                        RankAmountRow(
                            title: item.debtName,
                            subtitle: AppText.debtType(item.debtType) + " · " + costSourceTitle(item.primarySource),
                            amount: item.costAmount,
                            color: typeColor(item.debtType)
                        )
                    }
                    Divider()
                    DetailRow(title: AppText.string("statistics.installmentFee", defaultValue: "Installment Fee"), value: AppText.money(summary.costAnalytics.totalInstallmentFeeAmount))
                    DetailRow(title: AppText.string("statistics.otherFee", defaultValue: "Other Fee"), value: AppText.money(summary.costAnalytics.otherFeeAmount))
                    DetailRow(title: AppText.string("statistics.paidLoanInterest", defaultValue: "Paid Loan Interest"), value: AppText.money(summary.costAnalytics.loanAppAllocatedPaidInterestAmount))
                    DetailRow(title: AppText.string("statistics.breakdownConflicts", defaultValue: "Breakdown Conflicts"), value: "\(summary.costAnalytics.creditCardBreakdownConflictCount)")
                }
            }
        }
    }

    @ViewBuilder
    private var focusContent: some View {
        let summary = periodSummary

        ChartCard(
            title: AppText.string("statistics.focusRanking", defaultValue: "Focus Ranking"),
            explanation: AppText.string("statistics.focusRankingExplain", defaultValue: "Largest balance, cost, risk and recent payment signals."),
            isEmpty: focusItems.isEmpty
        ) {
            Chart(focusItems) { item in
                BarMark(
                    x: .value(AppText.string("field.amount", defaultValue: "Amount"), item.amount.doubleValue),
                    y: .value(AppText.string("statistics.item", defaultValue: "Item"), item.title)
                )
                .foregroundStyle(item.color)
            }
        }

        SectionCard(title: AppText.string("statistics.focus", defaultValue: "Focus")) {
            if focusItems.isEmpty {
                EmptyChartState(title: AppText.string("statistics.emptyFocus", defaultValue: "No focus items yet."))
            } else {
                VStack(spacing: 10) {
                    ForEach(focusItems) { item in
                        RankAmountRow(title: item.title, subtitle: item.subtitle ?? "", amount: item.amount, color: item.color)
                    }
                }
            }
        }

        StatisticsMetricGrid(metrics: [
            StatisticsMetric(title: AppText.string("statistics.maxSingleDebt", defaultValue: "Largest Single Debt"), value: summary.debtAnalytics.maxSingleDebt.map { AppText.money($0.amount) } ?? AppText.string("common.none"), caption: summary.debtAnalytics.maxSingleDebt?.name ?? AppText.string("statistics.emptyDebt", defaultValue: "No debt balance to chart."), icon: "arrow.up.forward.circle.fill", color: DebtTheme.primary),
            StatisticsMetric(title: AppText.string("statistics.highestCost", defaultValue: "Highest Cost"), value: summary.costAnalytics.highCostDebts.first.map { AppText.money($0.costAmount) } ?? AppText.string("common.none"), caption: summary.costAnalytics.highCostDebts.first?.debtName ?? AppText.string("statistics.emptyCost", defaultValue: "No cost data to chart."), icon: "banknote.fill", color: DebtTheme.warning),
            StatisticsMetric(title: AppText.string("statistics.highestRisk", defaultValue: "Highest Risk"), value: summary.overdueAnalytics.highestRiskItem.map { AppText.money($0.overdueAmount) } ?? AppText.string("common.none"), caption: summary.overdueAnalytics.highestRiskItem?.debtName ?? AppText.string("overdue.emptyCopy", defaultValue: "No current overdue items were found in app records."), icon: "exclamationmark.triangle.fill", color: overdueRiskColor(summary.overdueAnalytics.riskLevel)),
            StatisticsMetric(title: AppText.string("statistics.recentPaymentTarget", defaultValue: "Recent Payment Target"), value: currentPaymentRows.first.map { AppText.money($0.amount) } ?? AppText.string("common.none"), caption: currentPaymentRows.first?.name ?? AppText.string("empty.noPayments", defaultValue: "No payments"), icon: "clock.arrow.circlepath", color: DebtTheme.success)
        ])
    }

    private var selectedAnalyticsPeriod: AnalyticsPeriod {
        period.analyticsPeriod(containing: Date(), calendar: calendar)
    }

    private var periodSummary: AnalyticsSummary {
        let analyticsPeriod = selectedAnalyticsPeriod
        let debtAnalytics = DebtAnalyticsService(calendar: calendar).generate(
            creditCardDebts: creditCards,
            creditCardStatements: cardStatements,
            loanDebts: loans,
            loanPlans: loanPlans,
            personalLendingDebts: personalDebts,
            personalLendingPlans: personalPlans,
            period: analyticsPeriod
        )
        let paymentAnalytics = PaymentAnalyticsService().generate(
            creditCardDebts: creditCards,
            creditCardPayments: cardPayments,
            loanDebts: loans,
            loanPayments: loanPayments,
            personalLendingDebts: personalDebts,
            personalLendingPayments: personalPayments,
            period: analyticsPeriod
        )
        let overdueAnalytics = OverdueAnalyticsService(datePolicy: DateCalculationPolicy(calendar: calendar)).generate(
            creditCardDebts: creditCards,
            creditCardStatements: cardStatements,
            creditCardBreakdowns: cardBreakdowns,
            loanDebts: loans,
            loanPlans: loanPlans,
            loanOverdues: loanOverdues,
            personalLendingDebts: personalDebts,
            personalLendingPlans: personalPlans,
            personalLendingOverdues: personalOverdues,
            today: Date()
        )
        let costAnalytics = CostAnalyticsService().generate(
            creditCardDebts: creditCards,
            creditCardStatements: cardStatements,
            creditCardBreakdowns: cardBreakdowns,
            loanDebts: loans,
            loanPlans: loanPlans,
            loanOverdues: loanOverdues,
            personalLendingDebts: personalDebts,
            personalLendingPlans: personalPlans
        )
        let fixedPaidAmount = paymentAnalytics.loanCumulativePaidAmount + paymentAnalytics.personalLendingCumulativePaidAmount
        return AnalyticsSummary(
            debtAnalytics: debtAnalytics,
            paymentAnalytics: paymentAnalytics,
            overdueAnalytics: overdueAnalytics,
            costAnalytics: costAnalytics,
            overallRepaymentProgress: AnalyticsSupport.ratio(
                paymentAnalytics.cumulativePaidAmount,
                paymentAnalytics.cumulativePaidAmount + debtAnalytics.totalRemainingAmount
            ),
            fixedDebtProgress: AnalyticsSupport.ratio(
                fixedPaidAmount,
                fixedPaidAmount + debtAnalytics.fixedDebtAmount
            ),
            creditCardCurrentStatementProgress: AnalyticsSupport.ratio(
                debtAnalytics.creditCardCurrentStatementPaidAmount,
                debtAnalytics.creditCardCurrentStatementAmount
            ),
            generatedAt: Date()
        )
    }

    private var paymentRows: [PaymentDisplayRow] {
        makePaymentRows(
            creditCards: AnalyticsSupport.activeCreditCardDebts(creditCards),
            loans: AnalyticsSupport.activeLoanDebts(loans),
            personalDebts: AnalyticsSupport.activePersonalLendingDebts(personalDebts),
            cardPayments: cardPayments,
            loanPayments: loanPayments,
            personalPayments: personalPayments
        )
    }

    private var currentPaymentRows: [PaymentDisplayRow] {
        let analyticsPeriod = selectedAnalyticsPeriod
        return paymentRows.filter { analyticsPeriod.contains($0.date) }
    }

    private var debtMix: [ChartAmount] {
        let summary = periodSummary
        return [
            ChartAmount(title: AppText.debtType(.creditCard), amount: summary.debtAnalytics.creditCardRemainingAmount, color: DebtTheme.primary),
            ChartAmount(title: AppText.debtType(.loan), amount: summary.debtAnalytics.loanRemainingAmount, color: DebtTheme.strategy),
            ChartAmount(title: AppText.debtType(.personalLending), amount: summary.debtAnalytics.personalLendingRemainingAmount, color: DebtTheme.success)
        ]
        .positiveAmounts
    }

    private var paymentMix: [ChartAmount] {
        let rows = currentPaymentRows
        return [
            ChartAmount(title: AppText.debtType(.creditCard), amount: rows.filter { $0.type == .creditCard }.reduce(Decimal(0)) { $0 + $1.amount }, color: DebtTheme.primary),
            ChartAmount(title: AppText.debtType(.loan), amount: rows.filter { $0.type == .loan }.reduce(Decimal(0)) { $0 + $1.amount }, color: DebtTheme.strategy),
            ChartAmount(title: AppText.debtType(.personalLending), amount: rows.filter { $0.type == .personalLending }.reduce(Decimal(0)) { $0 + $1.amount }, color: DebtTheme.success)
        ]
        .positiveAmounts
    }

    private var overdueBuckets: [ChartAmount] {
        let summary = periodSummary
        return [
            ChartAmount(title: "1-30", amount: summary.overdueAnalytics.overdueAmount1To30Days, color: DebtTheme.warning),
            ChartAmount(title: "31-90", amount: summary.overdueAnalytics.overdueAmount31To90Days, color: DebtTheme.danger.opacity(0.82)),
            ChartAmount(title: "90+", amount: summary.overdueAnalytics.overdueAmountOver90Days, color: DebtTheme.danger)
        ]
        .positiveAmounts
    }

    private var overdueTypeMix: [ChartAmount] {
        let summary = periodSummary
        return [
            ChartAmount(title: AppText.debtType(.creditCard), amount: summary.overdueAnalytics.creditCardOverdueStatementRemainingAmount, color: DebtTheme.primary),
            ChartAmount(title: AppText.debtType(.loan), amount: summary.overdueAnalytics.loanOverdueAmount, color: DebtTheme.strategy),
            ChartAmount(title: AppText.debtType(.personalLending), amount: summary.overdueAnalytics.personalLendingPastDueAmount, color: DebtTheme.success)
        ]
        .positiveAmounts
    }

    private var costComposition: [ChartAmount] {
        let cost = periodSummary.costAnalytics
        return [
            ChartAmount(title: AppText.string("statistics.totalInterest", defaultValue: "Interest"), amount: cost.totalInterestAmount, color: DebtTheme.primary),
            ChartAmount(title: AppText.string("statistics.installmentFee", defaultValue: "Installment Fee"), amount: cost.totalInstallmentFeeAmount, color: DebtTheme.strategy),
            ChartAmount(title: AppText.string("statistics.overdueFee", defaultValue: "Overdue Fee"), amount: cost.totalOverdueFeeAmount, color: DebtTheme.warning),
            ChartAmount(title: AppText.string("statistics.penaltyInterest", defaultValue: "Penalty Interest"), amount: cost.totalPenaltyInterestAmount, color: DebtTheme.danger),
            ChartAmount(title: AppText.string("statistics.otherFee", defaultValue: "Other Fee"), amount: cost.otherFeeAmount, color: DebtTheme.neutral)
        ]
        .positiveAmounts
    }

    private var costTypeMix: [ChartAmount] {
        let cost = periodSummary.costAnalytics
        return [
            ChartAmount(title: AppText.debtType(.creditCard), amount: cost.creditCardCostAmount, color: DebtTheme.primary),
            ChartAmount(title: AppText.debtType(.loan), amount: cost.loanCostAmount, color: DebtTheme.strategy),
            ChartAmount(title: AppText.debtType(.personalLending), amount: cost.personalLendingInterestAmount, color: DebtTheme.success)
        ]
        .positiveAmounts
    }

    private var costSourceMix: [ChartAmount] {
        let amounts = periodSummary.costAnalytics.sourceAmounts
        return [
            ChartAmount(title: costSourceTitle(.userProvided), amount: amounts.userProvidedCostAmount, color: DebtTheme.primary),
            ChartAmount(title: costSourceTitle(.systemFallback), amount: amounts.fallbackCostAmount, color: DebtTheme.fallback),
            ChartAmount(title: costSourceTitle(.scheduledPlan), amount: amounts.scheduledPlanCostAmount, color: DebtTheme.strategy),
            ChartAmount(title: costSourceTitle(.mixed), amount: amounts.mixedCostAmount, color: DebtTheme.warning),
            ChartAmount(title: costSourceTitle(.none), amount: amounts.noneCostAmount, color: DebtTheme.neutral)
        ]
        .positiveAmounts
    }

    private var monthlyPaymentTrend: [MonthlyPaymentPoint] {
        let analyticsPeriod = selectedAnalyticsPeriod
        let rows = currentPaymentRows
        let grouped = Dictionary(grouping: rows) { row -> Date in
            let components = calendar.dateComponents([.year, .month], from: row.date)
            return calendar.date(from: DateComponents(year: components.year, month: components.month, day: 1)) ?? row.date
        }
        var points: [MonthlyPaymentPoint] = []
        var cursor = analyticsPeriod.periodStart
        while cursor < analyticsPeriod.periodEndExclusive {
            let amount = grouped[cursor]?.reduce(Decimal(0)) { $0 + $1.amount } ?? 0
            points.append(MonthlyPaymentPoint(monthStart: cursor, amount: amount))
            cursor = calendar.date(byAdding: .month, value: 1, to: cursor) ?? analyticsPeriod.periodEndExclusive
        }
        return points
    }

    private var sortedOverdueItems: [AnalyticsOverdueItem] {
        periodSummary.overdueAnalytics.items.sorted {
            if $0.overdueDays == $1.overdueDays {
                if $0.overdueAmount == $1.overdueAmount { return $0.debtName < $1.debtName }
                return $0.overdueAmount > $1.overdueAmount
            }
            return $0.overdueDays > $1.overdueDays
        }
    }

    private var focusItems: [FocusChartAmount] {
        let summary = periodSummary
        var items: [FocusChartAmount] = []
        if let maxDebt = summary.debtAnalytics.maxSingleDebt {
            items.append(
                FocusChartAmount(
                    title: AppText.string("statistics.maxSingleDebt", defaultValue: "Largest Single Debt"),
                    subtitle: maxDebt.name,
                    amount: maxDebt.amount,
                    color: typeColor(maxDebt.debtType)
                )
            )
        }
        if let highCost = summary.costAnalytics.highCostDebts.first {
            items.append(
                FocusChartAmount(
                    title: AppText.string("statistics.highestCost", defaultValue: "Highest Cost"),
                    subtitle: highCost.debtName,
                    amount: highCost.costAmount,
                    color: typeColor(highCost.debtType)
                )
            )
        }
        if let risk = summary.overdueAnalytics.highestRiskItem {
            items.append(
                FocusChartAmount(
                    title: AppText.string("statistics.highestRisk", defaultValue: "Highest Risk"),
                    subtitle: risk.debtName,
                    amount: risk.overdueAmount,
                    color: DebtTheme.danger
                )
            )
        }
        if let recent = currentPaymentRows.first {
            items.append(
                FocusChartAmount(
                    title: AppText.string("statistics.recentPaymentTarget", defaultValue: "Recent Payment Target"),
                    subtitle: recent.name,
                    amount: recent.amount,
                    color: typeColor(recent.type)
                )
            )
        }
        return items.filter { $0.amount > 0 }
    }
}

private struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings: AppUserSettings
    var creditCards: [CreditCardDebt]
    var cardRules: [CreditCardCalculationRule]
    var loans: [LoanDebt]
    var loanRules: [LoanCalculationRule]

    @State private var budgetText = ""
    @State private var showingSubscription = false

    var body: some View {
        NavigationStack {
            Form {
                Section(AppText.string("settings.budget", defaultValue: "Budget")) {
                    FormTextInputRow(
                        title: AppText.string("field.monthlyBudget", defaultValue: "Monthly Budget"),
                        text: $budgetText,
                        keyboardType: .decimalPad
                    )
                    Button(AppText.string("common.save", defaultValue: "Save")) {
                        settings.monthlyRepaymentBudget = decimal(from: budgetText)
                        settings.updatedAt = Date()
                        try? modelContext.save()
                    }
                }

                Section(AppText.string("settings.access", defaultValue: "Access")) {
                    Label(subscriptionStore.accessState.statusTitle, systemImage: subscriptionStore.hasFullAccess ? "checkmark.seal.fill" : "lock.fill")
                    Text(subscriptionStore.accessState.statusDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        showingSubscription = true
                    } label: {
                        Label(subscriptionStore.hasFullAccess ? AppText.string("subscription.manage", defaultValue: "Manage Subscription") : AppText.string("subscription.unlock", defaultValue: "Unlock Editing"), systemImage: "creditcard")
                    }
                }

                Section(AppText.string("settings.rules", defaultValue: "Calculation Rules")) {
                    NavigationLink {
                        CalculationRulesView(
                            creditCards: creditCards,
                            cardRules: cardRules,
                            loans: loans,
                            loanRules: loanRules,
                            settings: settings
                        )
                        .environmentObject(subscriptionStore)
                    } label: {
                        Label(AppText.string("settings.customRules", defaultValue: "Custom Calculation Rules"), systemImage: "slider.horizontal.3")
                    }
                    Text(AppText.string("settings.rulesCopy", defaultValue: "Customize minimum payment, overdue fee, penalty interest and allocation rules."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section(AppText.string("settings.privacy", defaultValue: "Privacy")) {
                    Label(AppText.string("settings.localOnly", defaultValue: "Data is stored locally on this device."), systemImage: "hand.raised.fill")
                    FormToggleRow(
                        title: AppText.string("settings.reminders", defaultValue: "Payment Reminders"),
                        isOn: Binding(
                            get: { settings.remindersEnabled },
                            set: {
                                settings.remindersEnabled = $0
                                settings.updatedAt = Date()
                                try? modelContext.save()
                            }
                        )
                    )
                }

                Section(AppText.string("settings.data", defaultValue: "Data")) {
                    DetailRow(title: AppText.string("strategy.dataChangedTitle", defaultValue: "Debt data changed"), value: settings.strategyDataChanged ? AppText.string("common.yes", defaultValue: "Yes") : AppText.string("common.no", defaultValue: "No"))
                    Button(AppText.string("strategy.markClean", defaultValue: "Clear Strategy Reminder")) {
                        settings.strategyDataChanged = false
                        settings.updatedAt = Date()
                        try? modelContext.save()
                    }
                }

                Section(AppText.string("settings.about", defaultValue: "About")) {
                    Text(AppText.string("app.disclaimer", defaultValue: "This app helps organize debts and repayment plans. It is not a financial institution and does not replace creditor records."))
                }
            }
            .navigationTitle("tab.settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
            .onAppear {
                budgetText = plainNumber(settings.monthlyRepaymentBudget)
            }
            .sheet(isPresented: $showingSubscription) {
                SubscriptionView()
                    .environmentObject(subscriptionStore)
            }
        }
    }
}

private struct CalculationRulesView: View {
    var creditCards: [CreditCardDebt]
    var cardRules: [CreditCardCalculationRule]
    var loans: [LoanDebt]
    var loanRules: [LoanCalculationRule]
    @Bindable var settings: AppUserSettings

    private var globalLoanRule: LoanCalculationRule? {
        loanRules.first { $0.debtID == nil }
    }

    var body: some View {
        List {
            Section {
                Text(AppText.string("rules.disclaimer", defaultValue: "Rules are app-side calculation assumptions. They help previews, overdue estimates, statistics and strategy simulations, and do not change creditor records."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section(AppText.string("debtType.creditCard", defaultValue: "Credit Card")) {
                if creditCards.isEmpty {
                    Text(AppText.string("empty.noDebts", defaultValue: "No debts yet"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(creditCards) { debt in
                        if let rule = cardRules.first(where: { $0.debtID == debt.id }) {
                            NavigationLink {
                                CreditCardRuleEditor(debt: debt, rule: rule, settings: settings)
                            } label: {
                                RuleRow(title: debt.name, subtitle: AppText.string("rules.creditCardSubtitle", defaultValue: "Minimum payment, revolving interest and overdue penalty"))
                            }
                        } else {
                            RuleRow(title: debt.name, subtitle: AppText.string("rules.noRule", defaultValue: "No editable rule found"))
                        }
                    }
                }
            }

            Section(AppText.string("debtType.loan", defaultValue: "Loan")) {
                NavigationLink {
                    LoanRuleEditor(
                        title: AppText.string("rules.globalLoanDefault", defaultValue: "Global Loan Default"),
                        debtID: nil,
                        existingRule: globalLoanRule,
                        settings: settings
                    )
                } label: {
                    RuleRow(title: AppText.string("rules.globalLoanDefault", defaultValue: "Global Loan Default"), subtitle: AppText.string("rules.globalLoanSubtitle", defaultValue: "Used when a loan has no custom rule"))
                }

                ForEach(loans) { debt in
                    NavigationLink {
                        LoanRuleEditor(
                            title: debt.name,
                            debtID: debt.id,
                            existingRule: loanRules.first { $0.debtID == debt.id },
                            settings: settings
                        )
                    } label: {
                        let hasCustomRule = loanRules.contains { $0.debtID == debt.id }
                        RuleRow(
                            title: debt.name,
                            subtitle: hasCustomRule ? AppText.string("rules.customLoanRule", defaultValue: "Custom loan rule") : AppText.string("rules.usesGlobalRule", defaultValue: "Uses global or built-in default")
                        )
                    }
                }
            }
        }
        .navigationTitle("settings.customRules")
    }
}

private struct RuleRow: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body.weight(.medium))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct CreditCardRuleEditor: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    var debt: CreditCardDebt
    @Bindable var rule: CreditCardCalculationRule
    @Bindable var settings: AppUserSettings

    @State private var minimumPaymentRatioText = ""
    @State private var minimumPaymentFloorText = ""
    @State private var revolvingInterestEnabled = true
    @State private var revolvingDailyRateText = ""
    @State private var overdueFeeRateText = ""
    @State private var minimumOverdueFeeText = ""
    @State private var fixedOverdueFeeText = ""
    @State private var penaltyBaseType: LoanPenaltyBaseType = .unpaidAmount
    @State private var penaltyDailyRateText = ""
    @State private var message: UXMessage?

    var body: some View {
        Form {
            Section(AppText.string("rules.minimumPayment", defaultValue: "Minimum Payment")) {
                FormTextInputRow(
                    title: AppText.string("rules.minimumPaymentRatio", defaultValue: "Minimum payment ratio (%)"),
                    text: $minimumPaymentRatioText,
                    keyboardType: .decimalPad
                )
                FormTextInputRow(
                    title: AppText.string("rules.minimumPaymentFloor", defaultValue: "Minimum payment floor"),
                    text: $minimumPaymentFloorText,
                    keyboardType: .decimalPad
                )
            }

            Section(AppText.string("rules.revolvingInterest", defaultValue: "Revolving Interest")) {
                FormToggleRow(
                    title: AppText.string("rules.revolvingEnabled", defaultValue: "Enable revolving interest"),
                    isOn: $revolvingInterestEnabled
                )
                FormTextInputRow(
                    title: AppText.string("rules.dailyRatePercent", defaultValue: "Daily rate (%)"),
                    text: $revolvingDailyRateText,
                    keyboardType: .decimalPad
                )
            }

            Section(AppText.string("rules.overduePenalty", defaultValue: "Overdue Penalty")) {
                FormTextInputRow(
                    title: AppText.string("rules.overdueFeeRate", defaultValue: "Overdue fee rate (%)"),
                    text: $overdueFeeRateText,
                    keyboardType: .decimalPad
                )
                FormTextInputRow(
                    title: AppText.string("rules.minimumOverdueFee", defaultValue: "Minimum overdue fee"),
                    text: $minimumOverdueFeeText,
                    keyboardType: .decimalPad
                )
                FormTextInputRow(
                    title: AppText.string("rules.fixedOverdueFeeOptional", defaultValue: "Fixed overdue fee, optional"),
                    text: $fixedOverdueFeeText,
                    keyboardType: .decimalPad
                )
                FormPickerRow(title: AppText.string("rules.penaltyBase", defaultValue: "Penalty base"), selection: $penaltyBaseType) {
                    ForEach(LoanPenaltyBaseType.allCases) { type in
                        Text(ruleText("loanPenaltyBase.\(type.rawValue)", fallback: type.rawValue)).tag(type)
                    }
                }
                FormTextInputRow(
                    title: AppText.string("rules.penaltyDailyRatePercent", defaultValue: "Penalty daily rate (%)"),
                    text: $penaltyDailyRateText,
                    keyboardType: .decimalPad
                )
            }
        }
        .navigationTitle(debt.name)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("common.save") { save() }
            }
        }
        .onAppear(perform: load)
        .alert(item: $message) { message in
            Alert(title: Text(message.title), message: Text(message.detail), dismissButton: .default(Text("common.ok")))
        }
    }

    private func load() {
        minimumPaymentRatioText = plainNumber(rule.minimumPaymentRatio * 100)
        minimumPaymentFloorText = plainNumber(rule.minimumPaymentFloor)
        revolvingInterestEnabled = rule.revolvingInterestEnabled
        revolvingDailyRateText = plainNumber(rule.revolvingDailyRate * 100)
        overdueFeeRateText = plainNumber(rule.overdueFeeRate * 100)
        minimumOverdueFeeText = plainNumber(rule.minimumOverdueFee)
        fixedOverdueFeeText = rule.fixedOverdueFee.map(plainNumber) ?? ""
        penaltyBaseType = rule.penaltyBaseType
        penaltyDailyRateText = plainNumber(rule.penaltyDailyRate * 100)
    }

    private func save() {
        do {
            try subscriptionStore.requireWriteAccess()
            rule.minimumPaymentRatio = decimal(from: minimumPaymentRatioText) / 100
            rule.minimumPaymentFloor = decimal(from: minimumPaymentFloorText)
            rule.revolvingInterestEnabled = revolvingInterestEnabled
            rule.revolvingDailyRate = decimal(from: revolvingDailyRateText) / 100
            rule.overdueFeeRate = decimal(from: overdueFeeRateText) / 100
            rule.minimumOverdueFee = decimal(from: minimumOverdueFeeText)
            rule.fixedOverdueFee = decimalOptional(from: fixedOverdueFeeText)
            rule.penaltyBaseType = penaltyBaseType
            rule.penaltyDailyRate = decimal(from: penaltyDailyRateText) / 100
            markStrategyDirty(settings, in: modelContext)
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            message = UXMessage(title: AppText.string("message.error.title", defaultValue: "Could not complete action"), detail: uxErrorDescription(error))
        }
    }
}

private struct LoanRuleEditor: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    var title: String
    var debtID: UUID?
    var existingRule: LoanCalculationRule?
    @Bindable var settings: AppUserSettings

    @State private var overdueBaseType: LoanOverdueBaseType = .currentUnpaidPrincipal
    @State private var overdueFeeMode: LoanOverdueFeeMode = .zero
    @State private var fixedOverdueFeeText = ""
    @State private var overdueFeeRateText = ""
    @State private var penaltyInterestMode: LoanPenaltyInterestMode = .loanDailyRateMultiplier
    @State private var penaltyRateMultiplierText = ""
    @State private var fixedPenaltyDailyRateText = ""
    @State private var paymentAllocationMode: LoanPaymentAllocationMode = .feeFirst
    @State private var message: UXMessage?

    private var baseRule: LoanCalculationRule {
        existingRule ?? LoanCalculationRule.builtInDefault(debtID: debtID)
    }

    var body: some View {
        Form {
            Section(AppText.string("rules.overdueFee", defaultValue: "Overdue Fee")) {
                FormPickerRow(title: AppText.string("rules.overdueBase", defaultValue: "Overdue base"), selection: $overdueBaseType) {
                    ForEach(LoanOverdueBaseType.allCases) { type in
                        Text(ruleText("loanOverdueBase.\(type.rawValue)", fallback: type.rawValue)).tag(type)
                    }
                }
                FormPickerRow(title: AppText.string("rules.overdueFeeMode", defaultValue: "Overdue fee mode"), selection: $overdueFeeMode) {
                    ForEach(LoanOverdueFeeMode.allCases) { mode in
                        Text(ruleText("loanOverdueFeeMode.\(mode.rawValue)", fallback: mode.rawValue)).tag(mode)
                    }
                }
                FormTextInputRow(
                    title: AppText.string("rules.fixedOverdueFeeOptional", defaultValue: "Fixed overdue fee, optional"),
                    text: $fixedOverdueFeeText,
                    keyboardType: .decimalPad
                )
                FormTextInputRow(
                    title: AppText.string("rules.overdueFeeRate", defaultValue: "Overdue fee rate (%)"),
                    text: $overdueFeeRateText,
                    keyboardType: .decimalPad
                )
            }

            Section(AppText.string("rules.penaltyInterest", defaultValue: "Penalty Interest")) {
                FormPickerRow(title: AppText.string("rules.penaltyMode", defaultValue: "Penalty mode"), selection: $penaltyInterestMode) {
                    ForEach(LoanPenaltyInterestMode.allCases) { mode in
                        Text(ruleText("loanPenaltyMode.\(mode.rawValue)", fallback: mode.rawValue)).tag(mode)
                    }
                }
                FormTextInputRow(
                    title: AppText.string("rules.penaltyMultiplier", defaultValue: "Penalty rate multiplier"),
                    text: $penaltyRateMultiplierText,
                    keyboardType: .decimalPad
                )
                FormTextInputRow(
                    title: AppText.string("rules.fixedPenaltyDailyRatePercent", defaultValue: "Fixed penalty daily rate (%)"),
                    text: $fixedPenaltyDailyRateText,
                    keyboardType: .decimalPad
                )
            }

            Section(AppText.string("rules.paymentAllocation", defaultValue: "Payment Allocation")) {
                FormPickerRow(title: AppText.string("rules.paymentAllocation", defaultValue: "Payment Allocation"), selection: $paymentAllocationMode) {
                    ForEach(LoanPaymentAllocationMode.allCases) { mode in
                        Text(ruleText("loanAllocationMode.\(mode.rawValue)", fallback: mode.rawValue)).tag(mode)
                    }
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("common.save") { save() }
            }
        }
        .onAppear(perform: load)
        .alert(item: $message) { message in
            Alert(title: Text(message.title), message: Text(message.detail), dismissButton: .default(Text("common.ok")))
        }
    }

    private func load() {
        overdueBaseType = baseRule.overdueBaseType
        overdueFeeMode = baseRule.overdueFeeMode
        fixedOverdueFeeText = baseRule.fixedOverdueFee.map(plainNumber) ?? ""
        overdueFeeRateText = baseRule.overdueFeeRate.map { plainNumber($0 * 100) } ?? ""
        penaltyInterestMode = baseRule.penaltyInterestMode
        penaltyRateMultiplierText = plainNumber(baseRule.penaltyRateMultiplier)
        fixedPenaltyDailyRateText = baseRule.fixedPenaltyDailyRate.map { plainNumber($0 * 100) } ?? ""
        paymentAllocationMode = baseRule.paymentAllocationMode
    }

    private func save() {
        do {
            _ = try LoanDebtService(modelContext: modelContext, writeAccessAuthorizer: subscriptionStore).upsertCalculationRule(
                existingRule: existingRule,
                input: LoanCalculationRuleInput(
                    debtID: debtID,
                    overdueBaseType: overdueBaseType,
                    overdueFeeMode: overdueFeeMode,
                    fixedOverdueFee: decimalOptional(from: fixedOverdueFeeText),
                    overdueFeeRate: decimalOptional(from: overdueFeeRateText).map { $0 / 100 },
                    penaltyInterestMode: penaltyInterestMode,
                    penaltyRateMultiplier: decimal(from: penaltyRateMultiplierText),
                    fixedPenaltyDailyRate: decimalOptional(from: fixedPenaltyDailyRateText).map { $0 / 100 },
                    paymentAllocationMode: paymentAllocationMode
                )
            )
            markStrategyDirty(settings, in: modelContext)
            dismiss()
        } catch {
            message = UXMessage(title: AppText.string("message.error.title", defaultValue: "Could not complete action"), detail: uxErrorDescription(error))
        }
    }
}

private struct OverdueListView: View {
    var summary: OverdueAnalytics
    var creditCards: [CreditCardDebt]
    var loans: [LoanDebt]
    var personalDebts: [PersonalLendingDebt]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AppScroll(title: AppText.string("tab.overdues", defaultValue: "Overdue")) {
                InlineNotice(
                    style: .risk,
                    title: AppText.string("overdue.disclaimerTitle", defaultValue: "App analysis only"),
                    message: AppText.string("overdue.disclaimer", defaultValue: "Overdue amounts, fees and days are app-side estimates and do not represent creditor processing results.")
                )

                SectionCard(title: AppText.string("overdue.summary", defaultValue: "Summary")) {
                    VStack(spacing: 10) {
                        DetailRow(title: AppText.string("metric.overdueDebtCount", defaultValue: "Overdue Debts"), value: "\(summary.currentOverdueDebtCount)")
                        DetailRow(title: AppText.string("metric.overduePeriodCount", defaultValue: "Overdue Periods"), value: "\(summary.currentOverduePeriodCount)")
                        DetailRow(title: AppText.string("metric.overdueAmount", defaultValue: "Overdue Amount"), value: AppText.money(summary.currentOverdueTotalAmount))
                        DetailRow(title: AppText.string("metric.overdueCost", defaultValue: "Overdue Cost"), value: AppText.money(summary.overdueFeeTotalAmount + summary.penaltyInterestTotalAmount))
                    }
                }

                SectionCard(title: AppText.string("overdue.active", defaultValue: "Current Overdue")) {
                    if summary.items.isEmpty {
                        EmptyStateView(
                            icon: "checkmark.circle",
                            title: AppText.string("empty.noOverdues", defaultValue: "No overdue records"),
                            message: AppText.string("overdue.emptyCopy", defaultValue: "No current overdue items were found in app records."),
                            buttonTitle: nil,
                            action: nil
                        )
                    } else {
                        VStack(spacing: 12) {
                            ForEach(summary.items) { item in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(item.debtName)
                                            .font(.headline)
                                        Spacer()
                                        DebtTypeChip(type: item.debtType)
                                    }
                                    DetailRow(title: AppText.string("field.overdueDays", defaultValue: "Overdue Days"), value: "\(item.overdueDays)")
                                    DetailRow(title: AppText.string("field.overdueAmount", defaultValue: "Overdue Amount"), value: AppText.money(item.overdueAmount))
                                    DetailRow(title: AppText.string("field.overdueCost", defaultValue: "Overdue Cost"), value: AppText.money(item.overdueFeeAmount + item.penaltyInterestAmount))
                                }
                                .padding(12)
                                .background(DebtTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
    }
}

private struct AddDebtSheet: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings: AppUserSettings

    var cardStatements: [CreditCardStatement]
    var cardPlans: [CreditCardRepaymentPlan]
    var cardBreakdowns: [CreditCardStatementBreakdown]
    var onResult: (Result<Void, Error>) -> Void

    @State private var debtType: DebtType = .creditCard
    @State private var name = ""
    @State private var counterparty = ""
    @State private var note = ""
    @State private var amountText = ""
    @State private var interestText = "0"
    @State private var fixedInterestText = "0"
    @State private var creditLimitText = ""
    @State private var lastFourDigits = ""
    @State private var billingDay = 1
    @State private var dueDay = 20
    @State private var repaymentDay = 20
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .month, value: 12, to: Date()) ?? Date()
    @State private var termCount = 12
    @State private var statementAmountText = ""
    @State private var minimumPaymentText = ""
    @State private var loanMethod: LoanRepaymentMethod = .equalPayment
    @State private var personalMethod: PersonalLendingRepaymentMethod = .noFixedPlan
    @State private var isInterestBearing = false

    var body: some View {
        NavigationStack {
            Form {
                Section(AppText.string("form.basic", defaultValue: "Basic")) {
                    FormPickerRow(title: AppText.string("field.type", defaultValue: "Type"), selection: $debtType) {
                        ForEach(DebtType.allCases) { type in
                            Text(AppText.debtType(type)).tag(type)
                        }
                    }
                    FormTextInputRow(title: AppText.string("field.name", defaultValue: "Name"), text: $name)
                    FormTextInputRow(title: counterpartyTitle, text: $counterparty)
                    FormTextInputRow(title: AppText.string("field.note", defaultValue: "Note"), text: $note, isMultiline: true)
                }

                typeSpecificFields

                Section(AppText.string("form.preview", defaultValue: "Preview")) {
                    ImpactPreviewCard(
                        beforeTitle: AppText.string("field.type", defaultValue: "Type"),
                        beforeValue: AppText.debtType(debtType),
                        changeTitle: AppText.string("field.amount", defaultValue: "Amount"),
                        changeValue: previewAmount,
                        afterTitle: AppText.string("field.status", defaultValue: "Status"),
                        afterValue: AppText.string("debt.previewReady", defaultValue: "Ready to save")
                    )
                }
            }
            .navigationTitle("debt.add")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") { save() }
                }
            }
        }
    }

    private var counterpartyTitle: String {
        switch debtType {
        case .creditCard:
            return AppText.string("field.bank", defaultValue: "Bank")
        case .loan:
            return AppText.string("field.creditor", defaultValue: "Creditor")
        case .personalLending:
            return AppText.string("field.lender", defaultValue: "Lender")
        }
    }

    private var previewAmount: String {
        switch debtType {
        case .creditCard:
            return AppText.money(decimal(from: statementAmountText), currencyCode: settings.currencyCode)
        case .loan, .personalLending:
            return AppText.money(decimal(from: amountText), currencyCode: settings.currencyCode)
        }
    }

    @ViewBuilder
    private var typeSpecificFields: some View {
        switch debtType {
        case .creditCard:
            Section(AppText.string("debtType.creditCard", defaultValue: "Credit Card")) {
                FormStepperRow(title: AppText.string("field.billingDay", defaultValue: "Billing Day"), value: $billingDay, range: 1...31)
                FormStepperRow(title: AppText.string("field.dueDay", defaultValue: "Due Day"), value: $dueDay, range: 1...31)
                FormTextInputRow(
                    title: AppText.string("field.statementAmount", defaultValue: "Statement Amount"),
                    text: $statementAmountText,
                    keyboardType: .decimalPad
                )
                FormTextInputRow(
                    title: AppText.string("field.minimumPayment", defaultValue: "Minimum Payment"),
                    text: $minimumPaymentText,
                    keyboardType: .decimalPad
                )
                DisclosureGroup(AppText.string("form.advanced", defaultValue: "Advanced Settings, Optional")) {
                    FormTextInputRow(
                        title: AppText.string("field.creditLimit", defaultValue: "Credit Limit"),
                        text: $creditLimitText,
                        keyboardType: .decimalPad
                    )
                    FormTextInputRow(title: AppText.string("field.lastFour", defaultValue: "Card Last 4 Digits"), text: $lastFourDigits)
                }
            }
        case .loan:
            Section(AppText.string("debtType.loan", defaultValue: "Loan")) {
                FormTextInputRow(
                    title: AppText.string("field.principal", defaultValue: "Principal"),
                    text: $amountText,
                    keyboardType: .decimalPad
                )
                FormTextInputRow(
                    title: AppText.string("field.annualRatePercent", defaultValue: "Annual Rate (%)"),
                    text: $interestText,
                    keyboardType: .decimalPad
                )
                WheelDateFieldRow(title: AppText.string("field.startDate", defaultValue: "Start Date"), date: $startDate)
                WheelDateFieldRow(title: AppText.string("field.endDate", defaultValue: "End Date"), date: $endDate)
                FormStepperRow(title: AppText.string("field.repaymentDay", defaultValue: "Repayment Day"), value: $repaymentDay, range: 1...31)
                FormStepperRow(title: AppText.string("field.termCount", defaultValue: "Term Count"), value: $termCount, range: 1...360)
                FormPickerRow(title: AppText.string("field.repaymentMethod", defaultValue: "Repayment Method"), selection: $loanMethod) {
                    ForEach(LoanRepaymentMethod.allCases) { method in
                        Text(AppText.string("loanMethod.\(method.rawValue)", defaultValue: method.rawValue)).tag(method)
                    }
                }
            }
        case .personalLending:
            Section(AppText.string("debtType.personalLending", defaultValue: "Personal Lending")) {
                FormTextInputRow(
                    title: AppText.string("field.amount", defaultValue: "Amount"),
                    text: $amountText,
                    keyboardType: .decimalPad
                )
                FormToggleRow(title: AppText.string("field.interestBearing", defaultValue: "Interest Bearing"), isOn: $isInterestBearing)
                if isInterestBearing {
                    FormTextInputRow(
                        title: AppText.string("field.fixedInterest", defaultValue: "Fixed Interest"),
                        text: $fixedInterestText,
                        keyboardType: .decimalPad
                    )
                }
                WheelDateFieldRow(title: AppText.string("field.borrowedDate", defaultValue: "Borrowed Date"), date: $startDate)
                if isInterestBearing || personalMethod != .noFixedPlan {
                    WheelDateFieldRow(title: AppText.string("field.endDate", defaultValue: "End Date"), date: $endDate)
                }
                FormPickerRow(title: AppText.string("field.repaymentMethod", defaultValue: "Repayment Method"), selection: $personalMethod) {
                    ForEach(PersonalLendingRepaymentMethod.allCases) { method in
                        Text(AppText.string("personalMethod.\(method.rawValue)", defaultValue: method.rawValue)).tag(method)
                    }
                }
                if personalMethod == .equalPrincipalEqualInterest {
                    FormStepperRow(title: AppText.string("field.repaymentDay", defaultValue: "Repayment Day"), value: $repaymentDay, range: 1...31)
                    FormStepperRow(title: AppText.string("field.termCount", defaultValue: "Term Count"), value: $termCount, range: 1...360)
                }
            }
            .onChange(of: isInterestBearing) {
                if isInterestBearing && personalMethod == .noFixedPlan {
                    personalMethod = .principalAndInterestAtMaturity
                }
            }
        }
    }

    private func save() {
        do {
            switch debtType {
            case .creditCard:
                guard decimal(from: statementAmountText) > 0 else {
                    throw DebtServiceError.validationFailed(AppText.string("error.statementRequired", defaultValue: "Statement amount must be greater than 0."))
                }
                let service = CreditCardDebtService(modelContext: modelContext, writeAccessAuthorizer: subscriptionStore)
                let (_, debt, rule) = try service.createDebt(
                    CreditCardDebtInput(
                        name: name,
                        bankName: counterparty,
                        lastFourDigits: lastFourDigits,
                        creditLimit: decimalOptional(from: creditLimitText),
                        note: note,
                        billingDay: billingDay,
                        dueDay: dueDay,
                        currencyCode: settings.currencyCode
                    )
                )
                _ = try service.createUserConfirmedStatement(
                    debt: debt,
                    input: CreditCardStatementInput(
                        billingDate: startDate,
                        dueDate: endDate,
                        statementAmount: decimal(from: statementAmountText),
                        minimumPaymentAmount: decimalOptional(from: minimumPaymentText)
                    ),
                    rule: rule,
                    fallbackStatements: cardStatements,
                    fallbackPlans: cardPlans,
                    fallbackBreakdowns: cardBreakdowns
                )
            case .loan:
                _ = try LoanDebtService(modelContext: modelContext, writeAccessAuthorizer: subscriptionStore).createDebt(
                    LoanDebtInput(
                        name: name,
                        creditorName: counterparty,
                        note: note,
                        entryMode: .newLoan,
                        repaymentMethod: loanMethod,
                        originalPrincipal: decimal(from: amountText),
                        annualInterestRate: decimal(from: interestText) / 100,
                        startDate: startDate,
                        endDate: endDate,
                        repaymentDay: repaymentDay,
                        termCount: termCount,
                        currencyCode: settings.currencyCode
                    )
                )
            case .personalLending:
                let repaymentMethod = isInterestBearing && personalMethod == .noFixedPlan ? PersonalLendingRepaymentMethod.principalAndInterestAtMaturity : personalMethod
                _ = try PersonalLendingDebtService(modelContext: modelContext, writeAccessAuthorizer: subscriptionStore).createDebt(
                    PersonalLendingDebtInput(
                        name: name,
                        lenderName: counterparty,
                        note: note,
                        principalAmount: decimal(from: amountText),
                        fixedInterestAmount: isInterestBearing ? decimal(from: fixedInterestText) : 0,
                        borrowedDate: startDate,
                        agreedEndDate: repaymentMethod == .noFixedPlan ? nil : endDate,
                        repaymentMethod: repaymentMethod,
                        isInterestBearing: isInterestBearing,
                        monthlyRepaymentDay: repaymentMethod == .equalPrincipalEqualInterest ? repaymentDay : nil,
                        termCount: repaymentMethod == .equalPrincipalEqualInterest ? termCount : 0
                    )
                )
            }
            markStrategyDirty(settings, in: modelContext)
            onResult(.success(()))
            dismiss()
        } catch {
            onResult(.failure(error))
        }
    }
}

private struct ManualOverdueEntrySheet: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings: AppUserSettings

    var creditCards: [CreditCardDebt]
    var cardStatements: [CreditCardStatement]
    var cardPlans: [CreditCardRepaymentPlan]
    var cardOverdues: [CreditCardOverdueRecord]
    var loans: [LoanDebt]
    var loanPlans: [LoanRepaymentPlan]
    var loanOverdues: [LoanOverdueRecord]
    var personalDebts: [PersonalLendingDebt]
    var personalPlans: [PersonalLendingPlan]
    var personalOverdues: [PersonalLendingOverdueRecord]
    var onResult: (Result<Void, Error>) -> Void

    @State private var debtType: DebtType = .creditCard
    @State private var selectedDebtID: UUID?
    @State private var selectedTargetID: UUID?
    @State private var amountText = ""
    @State private var overdueFeeText = "0"
    @State private var penaltyInterestText = "0"
    @State private var startDate = Date()
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(AppText.string("overdue.addManual", defaultValue: "Add Manual Overdue")) {
                    FormPickerRow(title: AppText.string("field.type", defaultValue: "Type"), selection: $debtType) {
                        ForEach(DebtType.allCases) { type in
                            Text(AppText.debtType(type)).tag(type)
                        }
                    }

                    debtPicker
                    targetPicker
                }

                Section(AppText.string("form.basic", defaultValue: "Basic")) {
                    if debtType != .loan {
                        FormTextInputRow(
                            title: AppText.string("field.overdueAmount", defaultValue: "Overdue Amount"),
                            text: $amountText,
                            keyboardType: .decimalPad
                        )
                    } else {
                        DetailRow(title: AppText.string("field.overdueAmount", defaultValue: "Overdue Amount"), value: AppText.money(defaultOverdueAmount, currencyCode: settings.currencyCode))
                    }
                    FormTextInputRow(
                        title: AppText.string("field.overdueFee", defaultValue: "Overdue Fee"),
                        text: $overdueFeeText,
                        keyboardType: .decimalPad
                    )
                    FormTextInputRow(
                        title: AppText.string("field.penaltyInterest", defaultValue: "Penalty Interest"),
                        text: $penaltyInterestText,
                        keyboardType: .decimalPad
                    )
                    WheelDateFieldRow(title: AppText.string("field.startDate", defaultValue: "Start Date"), date: $startDate)
                    FormToggleRow(title: AppText.string("field.hasEndDate", defaultValue: "Has end date"), isOn: $hasEndDate)
                    if hasEndDate {
                        WheelDateFieldRow(title: AppText.string("field.endDate", defaultValue: "End Date"), date: $endDate)
                    }
                    FormTextInputRow(title: AppText.string("field.note", defaultValue: "Note"), text: $note, isMultiline: true)
                }

                Section(AppText.string("preview.impact", defaultValue: "Impact Preview")) {
                    ImpactPreviewCard(
                        beforeTitle: AppText.string("field.debt", defaultValue: "Debt"),
                        beforeValue: selectedDebtName,
                        changeTitle: AppText.string("field.overdueAmount", defaultValue: "Overdue Amount"),
                        changeValue: AppText.money(previewOverdueAmount, currencyCode: settings.currencyCode),
                        afterTitle: AppText.string("field.status", defaultValue: "Status"),
                        afterValue: AppText.string("debtStatus.overdue", defaultValue: "Overdue")
                    )
                    InlineNotice(
                        style: .risk,
                        title: AppText.string("overdue.manualNoticeTitle", defaultValue: "Manual overdue record"),
                        message: AppText.string("overdue.manualNoticeCopy", defaultValue: "Manual overdue entries affect overdue statistics and strategy reminders, but creditor records are not changed.")
                    )
                }
            }
            .navigationTitle("overdue.addManual")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") { save() }
                }
            }
            .onAppear(perform: resetSelectionForType)
            .onChange(of: debtType) {
                resetSelectionForType()
            }
            .onChange(of: selectedDebtID) {
                resetTargetForDebt()
            }
            .onChange(of: selectedTargetID) {
                syncDefaultAmountIfNeeded(force: true)
            }
        }
    }

    @ViewBuilder
    private var debtPicker: some View {
        switch debtType {
        case .creditCard:
            FormPickerRow(title: AppText.string("field.debt", defaultValue: "Debt"), selection: $selectedDebtID) {
                ForEach(creditCards) { debt in
                    Text(debt.name).tag(Optional(debt.id))
                }
            }
        case .loan:
            FormPickerRow(title: AppText.string("field.debt", defaultValue: "Debt"), selection: $selectedDebtID) {
                ForEach(loans) { debt in
                    Text(debt.name).tag(Optional(debt.id))
                }
            }
        case .personalLending:
            FormPickerRow(title: AppText.string("field.debt", defaultValue: "Debt"), selection: $selectedDebtID) {
                ForEach(personalDebts) { debt in
                    Text(debt.name).tag(Optional(debt.id))
                }
            }
        }
    }

    @ViewBuilder
    private var targetPicker: some View {
        switch debtType {
        case .creditCard:
            FormPickerRow(title: AppText.string("field.currentStatement", defaultValue: "Current Statement"), selection: $selectedTargetID) {
                ForEach(availableCardStatements) { statement in
                    Text(statement.billingDate.formatted(date: .abbreviated, time: .omitted))
                        .tag(Optional(statement.id))
                }
            }
        case .loan:
            FormPickerRow(title: AppText.string("field.plan", defaultValue: "Plan"), selection: $selectedTargetID) {
                ForEach(availableLoanPlans) { plan in
                    Text(String(format: AppText.string("format.period", defaultValue: "Period %d"), plan.periodIndex))
                        .tag(Optional(plan.id))
                }
            }
        case .personalLending:
            if availablePersonalPlans.isEmpty {
                DetailRow(title: AppText.string("field.plan", defaultValue: "Plan"), value: AppText.string("personal.noFixedPlanTarget", defaultValue: "Debt-level overdue"))
            } else {
                FormPickerRow(title: AppText.string("field.plan", defaultValue: "Plan"), selection: $selectedTargetID) {
                    ForEach(availablePersonalPlans) { plan in
                        Text(String(format: AppText.string("format.period", defaultValue: "Period %d"), plan.periodIndex))
                            .tag(Optional(plan.id))
                    }
                }
            }
        }
    }

    private var selectedDebtName: String {
        switch debtType {
        case .creditCard:
            return creditCards.first { $0.id == selectedDebtID }?.name ?? AppText.string("common.none", defaultValue: "None")
        case .loan:
            return loans.first { $0.id == selectedDebtID }?.name ?? AppText.string("common.none", defaultValue: "None")
        case .personalLending:
            return personalDebts.first { $0.id == selectedDebtID }?.name ?? AppText.string("common.none", defaultValue: "None")
        }
    }

    private var availableCardStatements: [CreditCardStatement] {
        cardStatements
            .filter { $0.debtID == selectedDebtID && $0.source == .userConfirmed && $0.isActive && $0.status != .replaced }
            .sorted { $0.billingDate > $1.billingDate }
    }

    private var availableLoanPlans: [LoanRepaymentPlan] {
        loanPlans
            .filter { $0.debtID == selectedDebtID && $0.status != .paid }
            .sorted { $0.periodIndex < $1.periodIndex }
    }

    private var availablePersonalPlans: [PersonalLendingPlan] {
        personalPlans
            .filter { $0.debtID == selectedDebtID && $0.status != .paid }
            .sorted { $0.periodIndex < $1.periodIndex }
    }

    private var selectedCardStatement: CreditCardStatement? {
        availableCardStatements.first { $0.id == selectedTargetID }
    }

    private var selectedCardPlan: CreditCardRepaymentPlan? {
        guard let statementID = selectedTargetID else { return nil }
        return cardPlans.first { $0.statementID == statementID }
    }

    private var selectedLoanPlan: LoanRepaymentPlan? {
        availableLoanPlans.first { $0.id == selectedTargetID }
    }

    private var selectedPersonalPlan: PersonalLendingPlan? {
        availablePersonalPlans.first { $0.id == selectedTargetID }
    }

    private var selectedPersonalDebt: PersonalLendingDebt? {
        personalDebts.first { $0.id == selectedDebtID }
    }

    private var defaultOverdueAmount: Decimal {
        switch debtType {
        case .creditCard:
            return selectedCardStatement?.remainingAmount ?? 0
        case .loan:
            guard let plan = selectedLoanPlan else { return 0 }
            return plan.remainingPrincipal + plan.remainingInterest
        case .personalLending:
            return selectedPersonalPlan?.remainingAmount ?? selectedPersonalDebt?.remainingAmount ?? 0
        }
    }

    private var previewOverdueAmount: Decimal {
        debtType == .loan ? defaultOverdueAmount : decimal(from: amountText)
    }

    private func resetSelectionForType() {
        switch debtType {
        case .creditCard:
            selectedDebtID = creditCards.first?.id
        case .loan:
            selectedDebtID = loans.first?.id
        case .personalLending:
            selectedDebtID = personalDebts.first?.id
        }
        resetTargetForDebt()
    }

    private func resetTargetForDebt() {
        switch debtType {
        case .creditCard:
            selectedTargetID = availableCardStatements.first?.id
        case .loan:
            selectedTargetID = availableLoanPlans.first?.id
        case .personalLending:
            selectedTargetID = availablePersonalPlans.first?.id
        }
        syncDefaultAmountIfNeeded(force: true)
    }

    private func syncDefaultAmountIfNeeded(force: Bool = false) {
        guard debtType != .loan else { return }
        if force || amountText.isEmpty || decimal(from: amountText) == 0 {
            amountText = plainNumber(defaultOverdueAmount)
        }
    }

    private func save() {
        do {
            switch debtType {
            case .creditCard:
                guard let debt = creditCards.first(where: { $0.id == selectedDebtID }), let statement = selectedCardStatement else {
                    throw DebtServiceError.notFound(AppText.string("error.noStatementSelected", defaultValue: "No active statement selected."))
                }
                var overdues = cardOverdues
                _ = try CreditCardDebtService(modelContext: modelContext, writeAccessAuthorizer: subscriptionStore).createManualOverdue(
                    debt: debt,
                    statement: statement,
                    plan: selectedCardPlan,
                    allStatements: cardStatements,
                    existingOverdues: &overdues,
                    input: CreditCardManualOverdueInput(
                        overdueAmount: decimal(from: amountText),
                        overdueFee: decimal(from: overdueFeeText),
                        penaltyInterest: decimal(from: penaltyInterestText),
                        startDate: startDate,
                        endDate: hasEndDate ? endDate : nil,
                        note: note
                    )
                )
            case .loan:
                guard let debt = loans.first(where: { $0.id == selectedDebtID }), let plan = selectedLoanPlan else {
                    throw DebtServiceError.notFound(AppText.string("error.noPlanSelected", defaultValue: "No repayment plan selected."))
                }
                var overdues = loanOverdues
                _ = try LoanDebtService(modelContext: modelContext, writeAccessAuthorizer: subscriptionStore).createManualOverdue(
                    debt: debt,
                    plan: plan,
                    existingOverdues: &overdues,
                    input: LoanManualOverdueInput(
                        overdueFee: decimal(from: overdueFeeText),
                        penaltyInterest: decimal(from: penaltyInterestText),
                        startDate: startDate,
                        endDate: hasEndDate ? endDate : nil,
                        note: note
                    )
                )
            case .personalLending:
                guard let debt = selectedPersonalDebt else {
                    throw DebtServiceError.notFound(AppText.string("error.noDebtSelected", defaultValue: "No debt selected."))
                }
                var overdues = personalOverdues
                _ = try PersonalLendingDebtService(modelContext: modelContext, writeAccessAuthorizer: subscriptionStore).createManualOverdue(
                    debt: debt,
                    plan: selectedPersonalPlan,
                    existingOverdues: &overdues,
                    input: PersonalLendingManualOverdueInput(
                        overdueAmount: decimal(from: amountText),
                        overdueFee: decimal(from: overdueFeeText),
                        penaltyInterest: decimal(from: penaltyInterestText),
                        startDate: startDate,
                        endDate: hasEndDate ? endDate : nil,
                        note: note
                    )
                )
            }
            markStrategyDirty(settings, in: modelContext)
            onResult(.success(()))
            dismiss()
        } catch {
            onResult(.failure(error))
        }
    }
}

private struct PaymentEntrySheet: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings: AppUserSettings

    var preselected: DebtSelection?
    var creditCards: [CreditCardDebt]
    var cardRules: [CreditCardCalculationRule]
    var cardStatements: [CreditCardStatement]
    var cardPlans: [CreditCardRepaymentPlan]
    var cardPayments: [CreditCardPaymentRecord]
    var cardOverdues: [CreditCardOverdueRecord]
    var loans: [LoanDebt]
    var loanPlans: [LoanRepaymentPlan]
    var loanPayments: [LoanPaymentRecord]
    var loanAllocations: [LoanPaymentAllocationDetail]
    var loanOverdues: [LoanOverdueRecord]
    var loanRules: [LoanCalculationRule]
    var personalDebts: [PersonalLendingDebt]
    var personalPlans: [PersonalLendingPlan]
    var personalPayments: [PersonalLendingPaymentRecord]
    var personalAllocations: [PersonalLendingAllocationDetail]
    var personalOverdues: [PersonalLendingOverdueRecord]
    var onResult: (Result<Void, Error>) -> Void

    @State private var debtType: DebtType = .creditCard
    @State private var selectedDebtID: UUID?
    @State private var amountText = ""
    @State private var paymentDate = Date()
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(AppText.string("payments.record", defaultValue: "Record Payment")) {
                    FormPickerRow(title: AppText.string("field.type", defaultValue: "Type"), selection: $debtType) {
                        ForEach(DebtType.allCases) { type in
                            Text(AppText.debtType(type)).tag(type)
                        }
                    }
                    FormPickerRow(title: AppText.string("field.debt", defaultValue: "Debt"), selection: $selectedDebtID) {
                        ForEach(currentDebts, id: \.id) { debt in
                            Text(debt.name).tag(Optional(debt.id))
                        }
                    }
                    FormTextInputRow(
                        title: AppText.string("field.amount", defaultValue: "Amount"),
                        text: $amountText,
                        keyboardType: .decimalPad
                    )
                    WheelDateFieldRow(title: AppText.string("field.paymentDate", defaultValue: "Payment Date"), date: $paymentDate)
                    FormTextInputRow(title: AppText.string("field.note", defaultValue: "Note"), text: $note, isMultiline: true)
                }

                Section(AppText.string("preview.impact", defaultValue: "Impact Preview")) {
                    ImpactPreviewCard(
                        beforeTitle: AppText.string("preview.beforeRemaining", defaultValue: "Before"),
                        beforeValue: AppText.money(currentRemaining, currencyCode: selectedCurrency),
                        changeTitle: AppText.string("preview.thisPayment", defaultValue: "This Payment"),
                        changeValue: AppText.money(decimal(from: amountText), currencyCode: selectedCurrency),
                        afterTitle: AppText.string("preview.afterRemaining", defaultValue: "After"),
                        afterValue: AppText.money(maxDecimal(currentRemaining - decimal(from: amountText), 0), currencyCode: selectedCurrency)
                    )
                }
            }
            .navigationTitle("payments.record")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("common.save") { save() } }
            }
        }
        .onAppear {
            if let preselected {
                debtType = preselected.type
                selectedDebtID = preselected.id
            } else {
                selectedDebtID = currentDebts.first?.id
            }
        }
        .onChange(of: debtType) {
            selectedDebtID = currentDebts.first?.id
        }
    }

    private var currentDebts: [DebtPickerItem] {
        switch debtType {
        case .creditCard:
            return creditCards.map { DebtPickerItem(id: $0.id, name: $0.name) }
        case .loan:
            return loans.map { DebtPickerItem(id: $0.id, name: $0.name) }
        case .personalLending:
            return personalDebts.map { DebtPickerItem(id: $0.id, name: $0.name) }
        }
    }

    private var currentRemaining: Decimal {
        guard let selectedDebtID else { return 0 }
        switch debtType {
        case .creditCard:
            return AnalyticsSupport.latestEffectiveStatementByDebt(cardStatements, debtIDs: Set([selectedDebtID]))[selectedDebtID]?.remainingAmount ?? 0
        case .loan:
            return loanPlans.filter { $0.debtID == selectedDebtID && $0.status != .paid }.reduce(Decimal(0)) { $0 + $1.remainingTotalAmount }
        case .personalLending:
            return personalDebts.first { $0.id == selectedDebtID }?.remainingAmount ?? 0
        }
    }

    private var selectedCurrency: String {
        guard let selectedDebtID else { return settings.currencyCode }
        switch debtType {
        case .creditCard:
            return creditCards.first { $0.id == selectedDebtID }?.currencyCode ?? settings.currencyCode
        case .loan:
            return loans.first { $0.id == selectedDebtID }?.currencyCode ?? settings.currencyCode
        case .personalLending:
            return settings.currencyCode
        }
    }

    private func save() {
        do {
            guard let selectedDebtID else {
                throw DebtServiceError.notFound(AppText.string("error.noDebtSelected", defaultValue: "No debt selected."))
            }
            switch debtType {
            case .creditCard:
                guard let debt = creditCards.first(where: { $0.id == selectedDebtID }),
                      let statement = AnalyticsSupport.latestEffectiveStatementByDebt(cardStatements, debtIDs: Set([selectedDebtID]))[selectedDebtID],
                      let rule = cardRules.first(where: { $0.debtID == selectedDebtID }) else {
                    throw DebtServiceError.notFound(AppText.string("error.noStatementSelected", defaultValue: "No active statement selected."))
                }
                var overdues = cardOverdues
                var payments = cardPayments
                _ = try CreditCardDebtService(modelContext: modelContext, writeAccessAuthorizer: subscriptionStore).recordPayment(
                    debt: debt,
                    statement: statement,
                    plan: cardPlans.first { $0.statementID == statement.id && $0.isActive },
                    payments: &payments,
                    overdues: &overdues,
                    input: CreditCardPaymentInput(paymentDate: paymentDate, amount: decimal(from: amountText), note: note),
                    rule: rule,
                    today: paymentDate
                )
            case .loan:
                guard let debt = loans.first(where: { $0.id == selectedDebtID }) else {
                    throw DebtServiceError.notFound(AppText.string("error.noDebtSelected", defaultValue: "No debt selected."))
                }
                var payments = loanPayments
                var allocations = loanAllocations
                _ = try LoanDebtService(modelContext: modelContext, writeAccessAuthorizer: subscriptionStore).recordPayment(
                    debt: debt,
                    plans: loanPlans.filter { $0.debtID == debt.id },
                    payments: &payments,
                    allocationDetails: &allocations,
                    overdues: loanOverdues.filter { $0.debtID == debt.id },
                    input: LoanPaymentInput(paymentDate: paymentDate, totalAmount: decimal(from: amountText), note: note),
                    rule: LoanDebtService().effectiveCalculationRule(for: debt, rules: loanRules),
                    today: paymentDate
                )
            case .personalLending:
                guard let debt = personalDebts.first(where: { $0.id == selectedDebtID }) else {
                    throw DebtServiceError.notFound(AppText.string("error.noDebtSelected", defaultValue: "No debt selected."))
                }
                var payments = personalPayments
                var allocations = personalAllocations
                var overdues = personalOverdues
                let service = PersonalLendingDebtService(modelContext: modelContext, writeAccessAuthorizer: subscriptionStore)
                _ = try service.recordPayment(
                    debt: debt,
                    plans: personalPlans.filter { $0.debtID == debt.id },
                    payments: &payments,
                    allocationDetails: &allocations,
                    input: PersonalLendingPaymentInput(paymentDate: paymentDate, amount: decimal(from: amountText), note: note),
                    today: paymentDate
                )
                _ = try service.refreshOverdues(
                    debt: debt,
                    plans: personalPlans.filter { $0.debtID == debt.id },
                    overdues: &overdues,
                    today: paymentDate
                )
            }
            markStrategyDirty(settings, in: modelContext)
            onResult(.success(()))
            dismiss()
        } catch {
            onResult(.failure(error))
        }
    }
}

private struct CreditCardStatementSheet: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @Bindable var settings: AppUserSettings

    var preselectedCardID: UUID?
    var creditCards: [CreditCardDebt]
    var cardRules: [CreditCardCalculationRule]
    var statements: [CreditCardStatement]
    var plans: [CreditCardRepaymentPlan]
    var breakdowns: [CreditCardStatementBreakdown]
    var payments: [CreditCardPaymentRecord]
    var overdues: [CreditCardOverdueRecord]
    var onResult: (Result<Void, Error>) -> Void

    @State private var selectedCardID: UUID?
    @State private var billingDate = Date()
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 20, to: Date()) ?? Date()
    @State private var statementAmountText = ""
    @State private var minimumPaymentText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section(AppText.string("statement.update", defaultValue: "Update Statement")) {
                    FormPickerRow(title: AppText.string("field.debt", defaultValue: "Debt"), selection: $selectedCardID) {
                        ForEach(creditCards, id: \.id) { card in
                            Text(card.name).tag(Optional(card.id))
                        }
                    }
                    WheelDateFieldRow(title: AppText.string("field.currentStatement", defaultValue: "Billing Date"), date: $billingDate)
                    WheelDateFieldRow(title: AppText.string("field.dueDate", defaultValue: "Due Date"), date: $dueDate)
                    FormTextInputRow(
                        title: AppText.string("field.statementAmount", defaultValue: "Statement Amount"),
                        text: $statementAmountText,
                        keyboardType: .decimalPad
                    )
                    FormTextInputRow(
                        title: AppText.string("field.minimumPayment", defaultValue: "Minimum Payment"),
                        text: $minimumPaymentText,
                        keyboardType: .decimalPad
                    )
                }

                Section(AppText.string("preview.impact", defaultValue: "Impact Preview")) {
                    ImpactPreviewCard(
                        beforeTitle: AppText.string("statement.oldStatement", defaultValue: "Old Statement"),
                        beforeValue: AppText.money(currentStatement?.statementAmount ?? 0, currencyCode: selectedCurrency),
                        changeTitle: AppText.string("statement.newStatement", defaultValue: "New Statement"),
                        changeValue: AppText.money(decimal(from: statementAmountText), currencyCode: selectedCurrency),
                        afterTitle: AppText.string("field.minimumPayment", defaultValue: "Minimum Payment"),
                        afterValue: minimumPaymentPreview
                    )
                    if currentStatement?.source == .fallback {
                        InlineNotice(
                            style: .info,
                            title: AppText.string("statement.replaceFallbackTitle", defaultValue: "Will replace fallback data"),
                            message: AppText.string("statement.replaceFallbackCopy", defaultValue: "Saving a confirmed statement will retire matching fallback data.")
                        )
                    }
                }
            }
            .navigationTitle("statement.update")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("common.save") { save() } }
            }
        }
        .onAppear {
            selectedCardID = preselectedCardID ?? creditCards.first?.id
            if let statement = currentStatement {
                billingDate = statement.billingDate
                dueDate = statement.dueDate
                statementAmountText = plainNumber(statement.statementAmount)
                minimumPaymentText = plainNumber(statement.minimumPaymentAmount)
            }
        }
        .onChange(of: selectedCardID) {
            if let statement = currentStatement {
                billingDate = statement.billingDate
                dueDate = statement.dueDate
                statementAmountText = plainNumber(statement.statementAmount)
                minimumPaymentText = plainNumber(statement.minimumPaymentAmount)
            }
        }
    }

    private var currentStatement: CreditCardStatement? {
        guard let selectedCardID else { return nil }
        return AnalyticsSupport.latestEffectiveStatementByDebt(statements, debtIDs: Set([selectedCardID]))[selectedCardID]
    }

    private var selectedCurrency: String {
        guard let selectedCardID else { return settings.currencyCode }
        return creditCards.first { $0.id == selectedCardID }?.currencyCode ?? settings.currencyCode
    }

    private var minimumPaymentPreview: String {
        let minimum = decimalOptional(from: minimumPaymentText) ?? max(decimal(from: statementAmountText) * Decimal(string: "0.10")!, 0)
        return AppText.money(minimum, currencyCode: selectedCurrency)
    }

    private func save() {
        do {
            guard let selectedCardID,
                  let debt = creditCards.first(where: { $0.id == selectedCardID }),
                  let rule = cardRules.first(where: { $0.debtID == selectedCardID }) else {
                throw DebtServiceError.notFound(AppText.string("error.noDebtSelected", defaultValue: "No debt selected."))
            }
            let input = CreditCardStatementInput(
                billingDate: billingDate,
                dueDate: dueDate,
                statementAmount: decimal(from: statementAmountText),
                minimumPaymentAmount: decimalOptional(from: minimumPaymentText)
            )
            let service = CreditCardDebtService(modelContext: modelContext, writeAccessAuthorizer: subscriptionStore)
            var mutableOverdues = overdues
            if let statement = currentStatement, statement.source == .userConfirmed {
                _ = try service.updateUserConfirmedStatement(
                    statement,
                    input: input,
                    debt: debt,
                    plan: plans.first { $0.statementID == statement.id && $0.isActive },
                    payments: payments.filter { $0.statementID == statement.id && $0.isActive },
                    overdues: &mutableOverdues,
                    rule: rule
                )
            } else {
                _ = try service.createUserConfirmedStatement(
                    debt: debt,
                    input: input,
                    rule: rule,
                    fallbackStatements: statements.filter { $0.source == .fallback },
                    fallbackPlans: plans,
                    fallbackBreakdowns: breakdowns
                )
            }
            markStrategyDirty(settings, in: modelContext)
            onResult(.success(()))
            dismiss()
        } catch {
            onResult(.failure(error))
        }
    }
}

private struct EditDebtSheet: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    var selection: DebtSelection
    var creditCards: [CreditCardDebt]
    var loans: [LoanDebt]
    var personalDebts: [PersonalLendingDebt]
    @Bindable var settings: AppUserSettings
    var onResult: (Result<Void, Error>) -> Void

    @State private var name = ""
    @State private var counterparty = ""
    @State private var note = ""
    @State private var billingDay = 1
    @State private var dueDay = 20

    var body: some View {
        NavigationStack {
            Form {
                Section(AppText.string("form.basic", defaultValue: "Basic")) {
                    FormTextInputRow(title: AppText.string("field.name", defaultValue: "Name"), text: $name)
                    FormTextInputRow(title: counterpartyTitle, text: $counterparty)
                    if selection.type == .creditCard {
                        FormStepperRow(title: AppText.string("field.billingDay", defaultValue: "Billing Day"), value: $billingDay, range: 1...31)
                        FormStepperRow(title: AppText.string("field.dueDay", defaultValue: "Due Day"), value: $dueDay, range: 1...31)
                    }
                    FormTextInputRow(title: AppText.string("field.note", defaultValue: "Note"), text: $note, isMultiline: true)
                }
            }
            .navigationTitle(AppText.string("debt.edit", defaultValue: "Edit Debt"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("common.save") { save() } }
            }
            .onAppear(perform: load)
        }
    }

    private var counterpartyTitle: String {
        switch selection.type {
        case .creditCard:
            return AppText.string("field.bank", defaultValue: "Bank")
        case .loan:
            return AppText.string("field.creditor", defaultValue: "Creditor")
        case .personalLending:
            return AppText.string("field.lender", defaultValue: "Lender")
        }
    }

    private func load() {
        switch selection.type {
        case .creditCard:
            guard let debt = creditCards.first(where: { $0.id == selection.id }) else { return }
            name = debt.name
            counterparty = debt.bankName
            note = debt.note
            billingDay = debt.billingDay
            dueDay = debt.dueDay
        case .loan:
            guard let debt = loans.first(where: { $0.id == selection.id }) else { return }
            name = debt.name
            counterparty = debt.creditorName
            note = debt.note
        case .personalLending:
            guard let debt = personalDebts.first(where: { $0.id == selection.id }) else { return }
            name = debt.name
            counterparty = debt.lenderName
            note = debt.note
        }
    }

    private func save() {
        do {
            switch selection.type {
            case .creditCard:
                guard let debt = creditCards.first(where: { $0.id == selection.id }) else { return }
                _ = try CreditCardDebtService(modelContext: modelContext, writeAccessAuthorizer: subscriptionStore).updateDebt(
                    debt,
                    input: CreditCardDebtInput(
                        name: name,
                        bankName: counterparty,
                        lastFourDigits: debt.lastFourDigits,
                        creditLimit: debt.creditLimit,
                        note: note,
                        billingDay: billingDay,
                        dueDay: dueDay,
                        currencyCode: debt.currencyCode
                    )
                )
            case .loan:
                guard let debt = loans.first(where: { $0.id == selection.id }) else { return }
                _ = try LoanDebtService(modelContext: modelContext, writeAccessAuthorizer: subscriptionStore).updateDisplayFields(
                    debt: debt,
                    name: name,
                    creditorName: counterparty,
                    note: note
                )
            case .personalLending:
                guard let debt = personalDebts.first(where: { $0.id == selection.id }) else { return }
                _ = try PersonalLendingDebtService(modelContext: modelContext, writeAccessAuthorizer: subscriptionStore).updateDisplayFields(
                    debt: debt,
                    name: name,
                    lenderName: counterparty,
                    note: note
                )
            }
            markStrategyDirty(settings, in: modelContext)
            onResult(.success(()))
            dismiss()
        } catch {
            onResult(.failure(error))
        }
    }
}

private struct OnboardingFlow: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var settings: AppUserSettings
    @State private var page = 0
    @State private var budgetText = ""

    var body: some View {
        VStack(spacing: 24) {
            TabView(selection: $page) {
                OnboardingPage(
                    icon: "square.grid.2x2.fill",
                    title: AppText.string("onboarding.welcomeTitle", defaultValue: "Organize debt clearly"),
                    message: AppText.string("onboarding.welcomeCopy", defaultValue: "This app helps you record debts, understand the current state and plan repayments. It is not a bank or creditor.")
                )
                .tag(0)

                OnboardingPage(
                    icon: "hand.raised.fill",
                    title: AppText.string("onboarding.privacyTitle", defaultValue: "Local and private"),
                    message: AppText.string("onboarding.privacyCopy", defaultValue: "Your debt records are stored locally on this device and used only for app-side tracking and analysis.")
                )
                .tag(1)

                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "wallet.pass.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(DebtTheme.primary)
                    Text(AppText.string("onboarding.budgetTitle", defaultValue: "Set a monthly repayment budget"))
                        .font(.largeTitle.bold())
                    Text(AppText.string("onboarding.budgetCopy", defaultValue: "This is used for strategy generation and monthly planning. You can change it later."))
                        .font(.body)
                        .foregroundStyle(.secondary)
                    FormTextInputRow(
                        title: AppText.string("field.monthlyBudget", defaultValue: "Monthly Budget"),
                        text: $budgetText,
                        keyboardType: .decimalPad
                    )
                    .padding(12)
                    .background(DebtTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(24)
                .tag(2)
            }
            .tabViewStyle(.page)

            Button {
                if page < 2 {
                    withAnimation { page += 1 }
                } else {
                    settings.monthlyRepaymentBudget = decimal(from: budgetText)
                    settings.onboardingCompleted = true
                    settings.updatedAt = Date()
                    try? modelContext.save()
                }
            } label: {
                Text(page < 2 ? AppText.string("common.next", defaultValue: "Next") : AppText.string("common.done", defaultValue: "Done"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(DebtTheme.background.ignoresSafeArea())
    }
}

private struct OnboardingPage: View {
    var icon: String
    var title: String
    var message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(DebtTheme.primary)
            Text(title)
                .font(.largeTitle.bold())
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
    }
}

private struct AppScroll<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.system(size: 32, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                content
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DebtTheme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SectionCard<Content: View>: View {
    var title: String
    var actionTitle: String?
    var action: (() -> Void)?
    @ViewBuilder var content: Content

    init(
        title: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DebtTheme.primary)
                }
            }
            content
        }
        .padding(16)
        .background(DebtTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(DebtTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HeroAmountCard: View {
    var title: String
    var amount: Decimal
    var progress: Decimal
    var caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chart.pie.fill")
                    .foregroundStyle(DebtTheme.primary)
            }
            Text(AppText.money(amount))
                .font(.system(size: 38, weight: .bold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            if progress > 0 {
                ProgressView(value: progress.doubleValue)
                    .tint(DebtTheme.primary)
            }
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(DebtTheme.cardBackground, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(DebtTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MetricTile: View {
    var title: String
    var value: String
    var icon: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(value)
                .font(.title3.weight(.semibold))
                .minimumScaleFactor(0.75)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(DebtTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DebtTheme.border, lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DebtCardView: View {
    var item: DebtListItem
    var primaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                DebtTypeIcon(type: item.debtType)
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        DebtTypeChip(type: item.debtType)
                        if item.source == StatementSource.fallback.rawValue {
                            StatusChip(title: AppText.string("statement.pendingConfirm", defaultValue: "Needs Confirm"), color: DebtTheme.fallback)
                        }
                    }
                    Text(AppText.string("field.nextDueDate", defaultValue: "Next Due") + ": " + AppText.date(item.nextDueDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusChip(title: item.overdueDays > 0 ? AppText.debtStatus(.overdue) : AppText.debtStatus(item.status), color: item.overdueDays > 0 ? DebtTheme.danger : debtStatusColor(item.status))
            }

            Text(AppText.money(item.remainingAmount))
                .font(.title2.weight(.bold))
                .minimumScaleFactor(0.75)
                .lineLimit(1)

            ProgressView(value: item.progress.doubleValue)
                .tint(item.overdueDays > 0 ? DebtTheme.danger : DebtTheme.primary)

            HStack {
                Button(AppText.string("debt.viewDetail", defaultValue: "View Detail")) {}
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DebtTheme.primary)
                    .allowsHitTesting(false)
                Spacer()
                Button(action: primaryAction) {
                    Label(AppText.string("payments.record", defaultValue: "Record Payment"), systemImage: "checkmark.circle")
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(DebtTheme.primary)
            }
        }
        .padding(16)
        .background(DebtTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(DebtTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SummaryHeader: View {
    var item: DebtListItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                DebtTypeChip(type: item.debtType)
                Spacer()
                StatusChip(title: AppText.debtStatus(item.status), color: debtStatusColor(item.status))
            }
            Text(AppText.money(item.remainingAmount))
                .font(.system(size: 34, weight: .bold))
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            DetailRow(title: AppText.string("field.nextDueDate", defaultValue: "Next Due Date"), value: AppText.date(item.nextDueDate))
            ProgressView(value: item.progress.doubleValue)
                .tint(item.status == .overdue ? DebtTheme.danger : DebtTheme.primary)
        }
        .padding(18)
        .background(DebtTheme.cardBackground, in: RoundedRectangle(cornerRadius: 20))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DetailRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .fontWeight(.medium)
                .lineLimit(2)
                .minimumScaleFactor(0.76)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FormTextInputRow: View {
    var title: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var isMultiline = false

    var body: some View {
        HStack(alignment: isMultiline ? .top : .firstTextBaseline, spacing: 12) {
            FormFieldTitle(title: title)

            if isMultiline {
                TextField("", text: $text, axis: .vertical)
                    .keyboardType(keyboardType)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2...5)
                    .accessibilityLabel(Text(title))
            } else {
                TextField("", text: $text)
                    .keyboardType(keyboardType)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .accessibilityLabel(Text(title))
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FormPickerRow<SelectionValue: Hashable, Content: View>: View {
    var title: String
    @Binding var selection: SelectionValue
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 12) {
            FormFieldTitle(title: title)
            Picker("", selection: $selection) {
                content()
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FormToggleRow: View {
    var title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            FormFieldTitle(title: title)
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FormStepperRow: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 12) {
            FormFieldTitle(title: title)
            Spacer(minLength: 8)
            Text("\(value)")
                .fontWeight(.medium)
                .monospacedDigit()
            Stepper("", value: $value, in: range)
                .labelsHidden()
        }
        .font(.subheadline)
    }
}

private struct WheelDateFieldRow: View {
    var title: String
    @Binding var date: Date
    @State private var showingPicker = false

    var body: some View {
        Button {
            showingPicker = true
        } label: {
            HStack(spacing: 12) {
                FormFieldTitle(title: title)
                Spacer(minLength: 8)
                Text(AppText.date(date))
                    .fontWeight(.medium)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.subheadline)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(AppText.date(date)))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(title)
        .sheet(isPresented: $showingPicker) {
            NavigationStack {
                VStack {
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .padding(.horizontal)
                    Spacer(minLength: 0)
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("common.done") { showingPicker = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

private struct FormFieldTitle: View {
    var title: String

    var body: some View {
        Text(title)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.82)
            .frame(minWidth: 118, maxWidth: 150, alignment: .leading)
    }
}

private struct TodoRow: View {
    var item: DebtListItem

    var body: some View {
        HStack(spacing: 12) {
            DebtTypeIcon(type: item.debtType)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                Text(AppText.date(item.nextDueDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(AppText.money(item.nextDueAmount))
                    .font(.subheadline.weight(.semibold))
                if item.overdueDays > 0 {
                    Text(String(format: AppText.string("format.overdueDays", defaultValue: "%d days overdue"), item.overdueDays))
                        .font(.caption)
                        .foregroundStyle(DebtTheme.danger)
                }
            }
        }
        .padding(10)
        .background(DebtTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FloatingAddMenu: View {
    var onAddDebt: () -> Void
    var onRecordPayment: () -> Void
    var onAddOverdue: () -> Void

    var body: some View {
        Menu {
            Button(action: onAddDebt) {
                Label(AppText.string("debt.add", defaultValue: "Add Debt"), systemImage: "creditcard")
            }
            Button(action: onRecordPayment) {
                Label(AppText.string("payments.record", defaultValue: "Record Payment"), systemImage: "arrow.left.arrow.right.circle")
            }
            Button(action: onAddOverdue) {
                Label(AppText.string("overdue.addManual", defaultValue: "Add Manual Overdue"), systemImage: "exclamationmark.triangle")
            }
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(DebtTheme.primary, in: Circle())
                .shadow(color: DebtTheme.primary.opacity(0.35), radius: 14, x: 0, y: 8)
        }
        .accessibilityLabel(Text("common.add"))
    }
}

private struct QuickActionButton: View {
    var title: String
    var icon: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 78)
        }
        .buttonStyle(.plain)
        .foregroundStyle(DebtTheme.primary)
        .background(DebtTheme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: .infinity)
    }
}

private struct ImpactPreviewCard: View {
    var beforeTitle: String
    var beforeValue: String
    var changeTitle: String
    var changeValue: String
    var afterTitle: String
    var afterValue: String

    var body: some View {
        VStack(spacing: 10) {
            DetailRow(title: beforeTitle, value: beforeValue)
            DetailRow(title: changeTitle, value: changeValue)
            Divider()
            DetailRow(title: afterTitle, value: afterValue)
        }
        .padding(12)
        .background(DebtTheme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct EmptyStateView: View {
    var icon: String
    var title: String
    var message: String
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(DebtTheme.fallback)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

private struct InlineNotice: View {
    enum Style {
        case info
        case risk
    }

    var style: Style
    var title: String
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: style == .risk ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(style == .risk ? DebtTheme.danger : DebtTheme.primary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background((style == .risk ? DebtTheme.danger : DebtTheme.primary).opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatusChip: View {
    var title: String
    var color: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}

private struct DebtTypeChip: View {
    var type: DebtType

    var body: some View {
        StatusChip(title: AppText.debtType(type), color: typeColor(type))
    }
}

private struct DebtTypeIcon: View {
    var type: DebtType

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 20, weight: .semibold))
            .frame(width: 42, height: 42)
            .foregroundStyle(typeColor(type))
            .background(typeColor(type).opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
    }

    private var icon: String {
        switch type {
        case .creditCard:
            return "creditcard.fill"
        case .loan:
            return "building.columns.fill"
        case .personalLending:
            return "person.2.fill"
        }
    }
}

private struct PaymentRow: View {
    var row: PaymentDisplayRow

    var body: some View {
        HStack(spacing: 12) {
            DebtTypeIcon(type: row.type)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name)
                    .font(.subheadline.weight(.semibold))
                Text(AppText.date(row.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(AppText.money(row.amount))
                .font(.subheadline.weight(.semibold))
        }
        .padding(10)
        .background(DebtTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PaymentHistoryCard: View {
    var title: String
    var rows: [PaymentDisplayRow]
    var currencyCode: String

    var body: some View {
        SectionCard(title: title) {
            if rows.isEmpty {
                EmptyStateView(
                    icon: "arrow.left.arrow.right.circle",
                    title: AppText.string("empty.noPayments", defaultValue: "No payments"),
                    message: AppText.string("payments.emptyCopy", defaultValue: "Record the first payment to see progress and history here."),
                    buttonTitle: nil,
                    action: nil
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(rows.prefix(8)) { row in
                        PaymentRow(row: row)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct OverdueRecordCard: View {
    var overdues: [CreditCardOverdueRecord]
    var currencyCode: String

    var body: some View {
        SectionCard(title: AppText.string("detail.overdues", defaultValue: "Overdue Records")) {
            if overdues.isEmpty {
                Text(AppText.string("empty.noOverdues", defaultValue: "No overdue records"))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(overdues) { overdue in
                        DetailRow(title: AppText.date(overdue.startDate), value: AppText.money(overdue.overdueAmount + overdue.overdueFee + overdue.penaltyInterest, currencyCode: currencyCode))
                    }
                }
            }
        }
    }
}

private struct LoanOverdueRecordCard: View {
    var overdues: [LoanOverdueRecord]
    var currencyCode: String

    var body: some View {
        SectionCard(title: AppText.string("detail.overdues", defaultValue: "Overdue Records")) {
            if overdues.isEmpty {
                Text(AppText.string("empty.noOverdues", defaultValue: "No overdue records"))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(overdues) { overdue in
                        DetailRow(title: AppText.date(overdue.overdueStartDate), value: AppText.money(overdue.overdueFee + overdue.penaltyInterest, currencyCode: currencyCode))
                    }
                }
            }
        }
    }
}

private struct PersonalOverdueRecordCard: View {
    var overdues: [PersonalLendingOverdueRecord]

    var body: some View {
        SectionCard(title: AppText.string("detail.overdues", defaultValue: "Overdue Records")) {
            if overdues.isEmpty {
                Text(AppText.string("empty.noOverdues", defaultValue: "No overdue records"))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ForEach(overdues) { overdue in
                        DetailRow(title: AppText.date(overdue.overdueStartDate), value: AppText.money(overdue.overdueAmount + overdue.overdueFee + overdue.penaltyInterest))
                    }
                }
            }
        }
    }
}

private struct TimelineSection: View {
    var title: String
    var rows: [TimelineRowData]
    var currencyCode: String

    var body: some View {
        SectionCard(title: title) {
            if rows.isEmpty {
                Text(AppText.string("empty.noPlans", defaultValue: "No plans"))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 0) {
                                Circle()
                                    .fill(row.color)
                                    .frame(width: 10, height: 10)
                                Rectangle()
                                    .fill(DebtTheme.border)
                                    .frame(width: 1)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(row.title)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    StatusChip(title: row.status, color: row.color)
                                }
                                Text(AppText.date(row.date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(AppText.money(row.amount, currencyCode: currencyCode))
                                    .font(.subheadline.weight(.semibold))
                            }
                            .padding(.bottom, 12)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct ChartCard<Content: View>: View {
    var title: String
    var explanation: String
    var isEmpty: Bool
    var emptyTitle: String
    var height: CGFloat
    @ViewBuilder var content: Content

    init(
        title: String,
        explanation: String,
        isEmpty: Bool = false,
        emptyTitle: String = AppText.string("statistics.emptyChart", defaultValue: "No data to chart yet."),
        height: CGFloat = 220,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.explanation = explanation
        self.isEmpty = isEmpty
        self.emptyTitle = emptyTitle
        self.height = height
        self.content = content()
    }

    var body: some View {
        SectionCard(title: title) {
            VStack(alignment: .leading, spacing: 12) {
                if isEmpty {
                    EmptyChartState(title: emptyTitle, minHeight: height)
                } else {
                    content
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                }
                Text(explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct StatisticsControlPanel: View {
    @Binding var period: StatisticsPeriod
    @Binding var category: StatisticsCategory

    var body: some View {
        SectionCard(title: AppText.string("statistics.controls", defaultValue: "Analysis Controls")) {
            VStack(spacing: 10) {
                controlRow(
                    title: AppText.string("statistics.period", defaultValue: "Period"),
                    icon: "calendar"
                ) {
                    Picker("", selection: $period) {
                        ForEach(StatisticsPeriod.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                controlRow(
                    title: AppText.string("statistics.category", defaultValue: "Category"),
                    icon: "chart.pie.fill"
                ) {
                    Picker("", selection: $category) {
                        ForEach(StatisticsCategory.allCases) { category in
                            Label(category.title, systemImage: category.icon).tag(category)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private func controlRow<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            content()
                .font(.subheadline.weight(.semibold))
                .tint(DebtTheme.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DebtTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct StatisticsMetric: Identifiable {
    let id = UUID()
    var title: String
    var value: String
    var caption: String
    var icon: String
    var color: Color
}

private struct StatisticsMetricGrid: View {
    var metrics: [StatisticsMetric]

    private let columns = [
        GridItem(.adaptive(minimum: 158), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(metrics) { metric in
                StatisticsMetricCard(metric: metric)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StatisticsMetricCard: View {
    var metric: StatisticsMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: metric.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(metric.color)
                    .background(metric.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                Spacer(minLength: 8)
            }
            Text(metric.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
            Text(metric.value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(metric.caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .background(DebtTheme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DebtTheme.border, lineWidth: 1)
        )
    }
}

private struct ProgressStatRow: View {
    var title: String
    var value: Decimal
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 12)
                Text(AppText.percent(value))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
            }
            ProgressView(value: minDecimal(maxDecimal(value, 0), 1).doubleValue)
                .tint(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LegendAmountRow: View {
    var item: ChartAmount
    var total: Decimal

    var body: some View {
        let ratio = AnalyticsSupport.ratio(item.amount, total)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle()
                    .fill(item.color)
                    .frame(width: 10, height: 10)
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(AppText.money(item.amount))
                        .font(.subheadline.weight(.semibold))
                    Text(AppText.percent(ratio))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: minDecimal(maxDecimal(ratio, 0), 1).doubleValue)
                .tint(item.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RankAmountRow: View {
    var title: String
    var subtitle: String
    var amount: Decimal
    var color: Color

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(title.isEmpty ? AppText.string("common.none") : title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                if subtitle.isEmpty == false {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(AppText.money(amount))
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DebtTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct EmptyChartState: View {
    var title: String
    var minHeight: CGFloat = 120

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title2.weight(.semibold))
                .foregroundStyle(DebtTheme.fallback)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .background(DebtTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct StrategyComparisonTable: View {
    var summaries: [StrategySummary]
    var recommendedStrategy: StrategyType?
    @Binding var selectedStrategy: StrategyType?
    var isSelectable: Bool

    private var orderedSummaries: [StrategySummary] {
        StrategyType.allCases.compactMap { type in
            summaries.first { $0.strategyType == type }
        }
    }

    private var metricRows: [StrategyMetricRow] {
        [
            StrategyMetricRow(
                id: "payoff",
                title: AppText.string("strategy.payoffMonth", defaultValue: "Payoff Month"),
                value: { strategyPayoffText($0.payoffMonth) }
            ),
            StrategyMetricRow(
                id: "totalPayment",
                title: AppText.string("strategy.totalPayment", defaultValue: "Total Payment"),
                value: { AppText.money($0.totalPayment) }
            ),
            StrategyMetricRow(
                id: "estimatedCost",
                title: AppText.string("field.estimatedCost", defaultValue: "Estimated Cost"),
                value: { AppText.money($0.totalEstimatedCost) }
            ),
            StrategyMetricRow(
                id: "monthlyPayment",
                title: AppText.string("strategy.monthlyPayment", defaultValue: "Suggested Payment"),
                value: { AppText.money($0.averageMonthlyPayment) }
            ),
            StrategyMetricRow(
                id: "interest",
                title: AppText.string("strategy.interest", defaultValue: "Interest"),
                value: { AppText.money($0.estimatedInterest) }
            ),
            StrategyMetricRow(
                id: "overdueCost",
                title: AppText.string("field.overdueCost", defaultValue: "Overdue Cost"),
                value: { AppText.money($0.estimatedOverdueFee + $0.estimatedPenaltyInterest) }
            ),
            StrategyMetricRow(
                id: "risk",
                title: AppText.string("statistics.riskLevel", defaultValue: "Risk Level"),
                value: { strategyRiskTitle($0.riskLevel) }
            ),
            StrategyMetricRow(
                id: "feature",
                title: AppText.string("strategy.feature", defaultValue: "Feature"),
                value: { $0.featureDescription }
            ),
        ]
    }

    var body: some View {
        if orderedSummaries.isEmpty {
            EmptyStateView(
                icon: "tablecells",
                title: AppText.string("strategy.noComparison", defaultValue: "No comparison data"),
                message: AppText.string("strategy.noComparisonCopy", defaultValue: "Generate a strategy comparison to see repayment options."),
                buttonTitle: nil,
                action: nil
            )
        } else {
            ViewThatFits(in: .horizontal) {
                tableBody
                    .frame(maxWidth: .infinity)

                ScrollView(.horizontal, showsIndicators: false) {
                    tableBody
                        .frame(minWidth: 680)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var tableBody: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                StrategyMetricTitleCell(
                    title: AppText.string("strategy.metric", defaultValue: "Metric"),
                    isHeader: true
                )
                ForEach(orderedSummaries, id: \.strategyType) { summary in
                    StrategyHeaderCell(
                        summary: summary,
                        isRecommended: recommendedStrategy == summary.strategyType,
                        isSelected: selectedStrategy == summary.strategyType,
                        isSelectable: isSelectable
                    )
                    .onTapGesture {
                        select(summary.strategyType)
                    }
                }
            }

            ForEach(metricRows) { row in
                GridRow {
                    StrategyMetricTitleCell(title: row.title, isHeader: false)
                    ForEach(orderedSummaries, id: \.strategyType) { summary in
                        StrategyMetricValueCell(
                            value: row.value(summary),
                            isSelected: selectedStrategy == summary.strategyType
                        )
                        .onTapGesture {
                            select(summary.strategyType)
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DebtTheme.border, lineWidth: 1)
        )
    }

    private func select(_ strategyType: StrategyType) {
        guard isSelectable else { return }
        selectedStrategy = strategyType
    }
}

private struct StrategyMetricRow: Identifiable {
    var id: String
    var title: String
    var value: (StrategySummary) -> String
}

private struct StrategyMetricTitleCell: View {
    var title: String
    var isHeader: Bool

    var body: some View {
        Text(title)
            .font(isHeader ? .caption.weight(.bold) : .caption.weight(.semibold))
            .foregroundStyle(isHeader ? DebtTheme.primary : .secondary)
            .lineLimit(2)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(minWidth: 104, maxWidth: .infinity, minHeight: isHeader ? 70 : 52, alignment: .leading)
            .background(isHeader ? DebtTheme.primary.opacity(0.08) : DebtTheme.secondaryBackground)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(DebtTheme.border)
                    .frame(width: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(DebtTheme.border)
                    .frame(height: 1)
            }
    }
}

private struct StrategyHeaderCell: View {
    var summary: StrategySummary
    var isRecommended: Bool
    var isSelected: Bool
    var isSelectable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(strategyTitle(summary.strategyType))
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            HStack(spacing: 6) {
                if isSelected {
                    StatusChip(title: AppText.string("strategy.selected", defaultValue: "Selected"), color: DebtTheme.primary)
                }
                if isRecommended {
                    StatusChip(title: AppText.string("strategy.recommended", defaultValue: "Recommended"), color: DebtTheme.strategy)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(minWidth: 144, maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background(isSelected ? DebtTheme.primary.opacity(0.14) : DebtTheme.cardBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(DebtTheme.border)
                .frame(width: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DebtTheme.border)
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelectable ? .isButton : [])
    }
}

private struct StrategyMetricValueCell: View {
    var value: String
    var isSelected: Bool

    var body: some View {
        Text(value)
            .font(.callout.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? DebtTheme.primary : .primary)
            .monospacedDigit()
            .lineLimit(3)
            .minimumScaleFactor(0.68)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(minWidth: 144, maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(isSelected ? DebtTheme.primary.opacity(0.08) : DebtTheme.cardBackground)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(DebtTheme.border)
                    .frame(width: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(DebtTheme.border)
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
    }
}

private struct StrategyHistoryRow: View {
    var batch: StrategyComparisonBatch

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(AppText.date(batch.generatedAt))
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                StatusChip(title: AppText.string("strategy.assistive", defaultValue: "Simulation"), color: DebtTheme.strategy)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            DetailRow(title: AppText.string("field.monthlyBudget", defaultValue: "Monthly Budget"), value: AppText.money(batch.monthlyBudget))
            DetailRow(
                title: AppText.string("strategy.savedStrategy", defaultValue: "Saved Strategy"),
                value: batch.recommendedStrategy.map { strategyTitle($0) } ?? AppText.string("common.none")
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DebtTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct StrategyDetailView: View {
    var batch: StrategyComparisonBatch
    var simulations: [StrategySimulation]
    var monthSnapshots: [StrategyMonthSnapshot]
    var allocations: [StrategyDebtAllocation]

    private var orderedSimulations: [StrategySimulation] {
        StrategyType.allCases.compactMap { type in
            simulations.first { $0.comparisonBatchID == batch.id && $0.strategyType == type }
        }
    }

    private var summaries: [StrategySummary] {
        orderedSimulations.map(strategySummary)
    }

    private var savedStrategy: StrategyType? {
        batch.recommendedStrategy
    }

    private var selectedSimulation: StrategySimulation? {
        guard let savedStrategy else { return orderedSimulations.first }
        return orderedSimulations.first { $0.strategyType == savedStrategy } ?? orderedSimulations.first
    }

    private var selectedSummary: StrategySummary? {
        guard let selectedSimulation else { return nil }
        return strategySummary(from: selectedSimulation)
    }

    private var selectedMonthSnapshots: [StrategyMonthSnapshot] {
        guard let selectedSimulation else { return [] }
        return monthSnapshots
            .filter { $0.simulationID == selectedSimulation.id }
            .sorted { $0.monthIndex < $1.monthIndex }
    }

    private var selectedAllocations: [StrategyDebtAllocation] {
        guard let selectedSimulation else { return [] }
        return allocations
            .filter { $0.simulationID == selectedSimulation.id }
            .sorted {
                if $0.monthIndex == $1.monthIndex {
                    return $0.priorityRank < $1.priorityRank
                }
                return $0.monthIndex < $1.monthIndex
            }
    }

    var body: some View {
        AppScroll(title: AppText.string("strategy.detail", defaultValue: "Strategy Details")) {
            SectionCard(title: AppText.string("strategy.detailSummary", defaultValue: "Summary")) {
                VStack(spacing: 10) {
                    DetailRow(title: AppText.string("strategy.generatedAt", defaultValue: "Generated At"), value: AppText.date(batch.generatedAt))
                    DetailRow(title: AppText.string("field.monthlyBudget", defaultValue: "Monthly Budget"), value: AppText.money(batch.monthlyBudget))
                    DetailRow(
                        title: AppText.string("strategy.savedStrategy", defaultValue: "Saved Strategy"),
                        value: savedStrategy.map { strategyTitle($0) } ?? AppText.string("common.none")
                    )
                    if let selectedSummary {
                        DetailRow(title: AppText.string("strategy.payoffMonth", defaultValue: "Payoff Month"), value: strategyPayoffText(selectedSummary.payoffMonth))
                        DetailRow(title: AppText.string("strategy.totalPayment", defaultValue: "Total Payment"), value: AppText.money(selectedSummary.totalPayment))
                        DetailRow(title: AppText.string("statistics.riskLevel", defaultValue: "Risk Level"), value: strategyRiskTitle(selectedSummary.riskLevel))
                    }
                }
            }

            SectionCard(title: AppText.string("strategy.comparisonTable", defaultValue: "Comparison Table")) {
                StrategyComparisonTable(
                    summaries: summaries,
                    recommendedStrategy: nil,
                    selectedStrategy: .constant(savedStrategy),
                    isSelectable: false
                )
            }

            SectionCard(title: AppText.string("strategy.monthlyTimeline", defaultValue: "Monthly Timeline")) {
                if selectedMonthSnapshots.isEmpty {
                    EmptyStateView(
                        icon: "calendar",
                        title: AppText.string("strategy.noTimeline", defaultValue: "No monthly details"),
                        message: AppText.string("strategy.noTimelineCopy", defaultValue: "This saved strategy has no monthly repayment snapshots."),
                        buttonTitle: nil,
                        action: nil
                    )
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(selectedMonthSnapshots) { snapshot in
                            StrategyMonthTimelineRow(snapshot: snapshot)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            SectionCard(title: AppText.string("strategy.allocationDetails", defaultValue: "Allocation Details")) {
                let firstMonthAllocations = selectedAllocations.filter { $0.monthIndex == 1 }
                if firstMonthAllocations.isEmpty {
                    EmptyStateView(
                        icon: "list.bullet.rectangle",
                        title: AppText.string("strategy.noAllocations", defaultValue: "No allocation details"),
                        message: AppText.string("strategy.noAllocationsCopy", defaultValue: "This saved strategy has no debt-level allocation rows."),
                        buttonTitle: nil,
                        action: nil
                    )
                } else {
                    VStack(spacing: 10) {
                        ForEach(firstMonthAllocations) { allocation in
                            StrategyAllocationRow(allocation: allocation)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct StrategyMonthTimelineRow: View {
    var snapshot: StrategyMonthSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: AppText.string("strategy.monthFormat", defaultValue: "Month %d"), snapshot.monthIndex))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(monthRange)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            HStack(spacing: 10) {
                StrategyMiniMetric(title: AppText.string("strategy.allocated", defaultValue: "Allocated"), value: AppText.money(snapshot.allocatedAmount))
                StrategyMiniMetric(title: AppText.string("field.remaining", defaultValue: "Remaining"), value: AppText.money(snapshot.remainingAmountAfterPayment))
            }
            HStack(spacing: 10) {
                StrategyMiniMetric(title: AppText.string("strategy.addedCost", defaultValue: "Added Cost"), value: AppText.money(snapshot.addedInterestAmount + snapshot.addedOverdueFee + snapshot.addedPenaltyInterest))
                StrategyMiniMetric(title: AppText.string("strategy.unusedBudget", defaultValue: "Unused Budget"), value: AppText.money(snapshot.unusedBudget))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DebtTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
    }

    private var monthRange: String {
        "\(AppText.date(snapshot.monthStartDate)) - \(AppText.date(snapshot.monthEndDate))"
    }
}

private struct StrategyMiniMetric: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DebtTheme.cardBackground, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct StrategyAllocationRow: View {
    var allocation: StrategyDebtAllocation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(allocation.debtName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(AppText.debtType(allocation.debtType))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(AppText.money(allocation.allocatedAmount))
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(DebtTheme.primary)
            }
            DetailRow(title: AppText.string("strategy.priorityRank", defaultValue: "Priority"), value: "\(allocation.priorityRank)")
            DetailRow(title: AppText.string("field.remaining", defaultValue: "Remaining"), value: AppText.money(allocation.remainingAmountAfterPayment))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DebtTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                DebtTheme.primary.opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.42),
                in: RoundedRectangle(cornerRadius: 16)
            )
    }
}

private struct SecondaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(DebtTheme.primary.opacity(isEnabled ? 1 : 0.45))
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                DebtTheme.primary.opacity(isEnabled ? (configuration.isPressed ? 0.16 : 0.10) : 0.06),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(DebtTheme.primary.opacity(isEnabled ? 0.22 : 0.10), lineWidth: 1)
            )
    }
}

private struct SecondaryIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(DebtTheme.primary)
            .background(DebtTheme.primary.opacity(configuration.isPressed ? 0.16 : 0.10), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(DebtTheme.danger)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(DebtTheme.danger.opacity(configuration.isPressed ? 0.16 : 0.09), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct UXTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(DebtTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(DebtTheme.border, lineWidth: 1)
            )
    }
}

private enum DebtTheme {
    static let primary = Color(red: 0.23, green: 0.51, blue: 0.96)
    static let secondary = Color(red: 0.39, green: 0.40, blue: 0.95)
    static let strategy = Color(red: 0.55, green: 0.36, blue: 0.96)
    static let success = Color(red: 0.13, green: 0.77, blue: 0.37)
    static let warning = Color(red: 0.96, green: 0.62, blue: 0.04)
    static let danger = Color(red: 0.94, green: 0.27, blue: 0.27)
    static let fallback = Color(red: 0.39, green: 0.45, blue: 0.55)
    static let neutral = Color(red: 0.42, green: 0.45, blue: 0.50)
    static let border = Color(.separator).opacity(0.16)
    static let background = Color(.systemGroupedBackground)
    static let secondaryBackground = Color(.secondarySystemGroupedBackground)
    static let cardBackground = Color(.systemBackground)
}

private let twoColumns = [
    GridItem(.flexible(), spacing: 12),
    GridItem(.flexible(), spacing: 12)
]

private enum DebtListFilter: String, CaseIterable, Identifiable {
    case all
    case creditCard
    case loan
    case personalLending
    case overdue
    case paidOff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return AppText.string("filter.all", defaultValue: "All")
        case .creditCard:
            return AppText.debtType(.creditCard)
        case .loan:
            return AppText.debtType(.loan)
        case .personalLending:
            return AppText.debtType(.personalLending)
        case .overdue:
            return AppText.debtStatus(.overdue)
        case .paidOff:
            return AppText.debtStatus(.paidOff)
        }
    }
}

private enum PaymentFilter: String, CaseIterable, Identifiable {
    case all
    case currentMonth
    case creditCard
    case loan
    case personalLending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return AppText.string("filter.all", defaultValue: "All")
        case .currentMonth:
            return AppText.string("filter.thisMonth", defaultValue: "This Month")
        case .creditCard:
            return AppText.debtType(.creditCard)
        case .loan:
            return AppText.debtType(.loan)
        case .personalLending:
            return AppText.debtType(.personalLending)
        }
    }
}

private enum StatisticsPeriod: String, CaseIterable, Identifiable {
    case month
    case threeMonths
    case sixMonths
    case twelveMonths

    var id: String { rawValue }

    var title: String {
        switch self {
        case .month:
            return AppText.string("period.month", defaultValue: "Month")
        case .threeMonths:
            return AppText.string("period.threeMonths", defaultValue: "3 Months")
        case .sixMonths:
            return AppText.string("period.sixMonths", defaultValue: "6 Months")
        case .twelveMonths:
            return AppText.string("period.twelveMonths", defaultValue: "12 Months")
        }
    }

    private var monthCount: Int {
        switch self {
        case .month:
            return 1
        case .threeMonths:
            return 3
        case .sixMonths:
            return 6
        case .twelveMonths:
            return 12
        }
    }

    func analyticsPeriod(containing date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> AnalyticsPeriod {
        let currentMonth = AnalyticsSupport.monthPeriod(containing: date, calendar: calendar)
        let start = calendar.date(byAdding: .month, value: -(monthCount - 1), to: currentMonth.periodStart) ?? currentMonth.periodStart
        return AnalyticsPeriod(periodStart: start, periodEndExclusive: currentMonth.periodEndExclusive)
    }
}

private enum StatisticsCategory: String, CaseIterable, Identifiable {
    case overview
    case debtStructure
    case paymentAnalysis
    case overdueRisk
    case cost
    case focus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return AppText.string("statistics.category.overview", defaultValue: "Overview")
        case .debtStructure:
            return AppText.string("statistics.category.debtStructure", defaultValue: "Debt Structure")
        case .paymentAnalysis:
            return AppText.string("statistics.category.paymentAnalysis", defaultValue: "Payment Analysis")
        case .overdueRisk:
            return AppText.string("statistics.category.overdueRisk", defaultValue: "Overdue Risk")
        case .cost:
            return AppText.string("statistics.category.cost", defaultValue: "Cost")
        case .focus:
            return AppText.string("statistics.category.focus", defaultValue: "Focus Debts")
        }
    }

    var icon: String {
        switch self {
        case .overview:
            return "speedometer"
        case .debtStructure:
            return "chart.pie.fill"
        case .paymentAnalysis:
            return "chart.line.uptrend.xyaxis"
        case .overdueRisk:
            return "exclamationmark.triangle.fill"
        case .cost:
            return "banknote.fill"
        case .focus:
            return "scope"
        }
    }
}

private struct DebtSelection: Equatable {
    var type: DebtType
    var id: UUID
}

private struct DebtPickerItem: Identifiable {
    var id: UUID
    var name: String
}

private struct PaymentDisplayRow: Identifiable {
    var id: UUID
    var type: DebtType
    var name: String
    var date: Date
    var amount: Decimal
    var note: String
}

private struct ChartAmount: Identifiable {
    let id = UUID()
    var title: String
    var amount: Decimal
    var color: Color
}

private struct FocusChartAmount: Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String?
    var amount: Decimal
    var color: Color
}

private struct MonthlyPaymentPoint: Identifiable {
    var id: Date { monthStart }
    var monthStart: Date
    var amount: Decimal
}

private struct TimelineRowData: Identifiable {
    let id = UUID()
    var title: String
    var date: Date
    var amount: Decimal
    var status: String
    var color: Color
}

private struct UXMessage: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
}

private func makePaymentRows(
    creditCards: [CreditCardDebt],
    loans: [LoanDebt],
    personalDebts: [PersonalLendingDebt],
    cardPayments: [CreditCardPaymentRecord],
    loanPayments: [LoanPaymentRecord],
    personalPayments: [PersonalLendingPaymentRecord]
) -> [PaymentDisplayRow] {
    let cardNames = Dictionary(uniqueKeysWithValues: creditCards.map { ($0.id, $0.name) })
    let loanNames = Dictionary(uniqueKeysWithValues: loans.map { ($0.id, $0.name) })
    let personalNames = Dictionary(uniqueKeysWithValues: personalDebts.map { ($0.id, $0.name) })
    let cards = cardPayments.filter(\.isActive).map {
        PaymentDisplayRow(id: $0.id, type: .creditCard, name: cardNames[$0.debtID] ?? "", date: $0.paymentDate, amount: $0.amount, note: $0.note)
    }
    let loanRows = loanPayments.map {
        PaymentDisplayRow(id: $0.id, type: .loan, name: loanNames[$0.debtID] ?? "", date: $0.paymentDate, amount: $0.totalAmount, note: $0.note)
    }
    let personalRows = personalPayments.map {
        PaymentDisplayRow(id: $0.id, type: .personalLending, name: personalNames[$0.debtID] ?? "", date: $0.paymentDate, amount: $0.amount, note: $0.note)
    }
    return (cards + loanRows + personalRows).sorted { $0.date > $1.date }
}

private extension Array where Element == ChartAmount {
    var positiveAmounts: [ChartAmount] {
        filter { $0.amount > 0 }
    }
}

private func chartTotal(_ items: [ChartAmount]) -> Decimal {
    items.reduce(Decimal(0)) { $0 + AnalyticsSupport.nonNegative($1.amount) }
}

private func overdueRiskTitle(_ level: AnalyticsOverdueRiskLevel) -> String {
    switch level {
    case .none:
        return AppText.string("risk.none", defaultValue: "None")
    case .medium:
        return AppText.string("risk.medium", defaultValue: "Medium")
    case .high:
        return AppText.string("risk.high", defaultValue: "High")
    case .critical:
        return AppText.string("risk.critical", defaultValue: "Critical")
    }
}

private func overdueRiskColor(_ level: AnalyticsOverdueRiskLevel) -> Color {
    switch level {
    case .none:
        return DebtTheme.success
    case .medium:
        return DebtTheme.warning
    case .high:
        return DebtTheme.danger.opacity(0.82)
    case .critical:
        return DebtTheme.danger
    }
}

private func costSourceTitle(_ source: AnalyticsCostSource) -> String {
    switch source {
    case .userProvided:
        return AppText.string("costSource.userProvided", defaultValue: "User Provided")
    case .systemFallback:
        return AppText.string("costSource.systemFallback", defaultValue: "System Fallback")
    case .mixed:
        return AppText.string("costSource.mixed", defaultValue: "Mixed")
    case .scheduledPlan:
        return AppText.string("costSource.scheduledPlan", defaultValue: "Scheduled Plan")
    case .none:
        return AppText.string("costSource.none", defaultValue: "No Source")
    }
}

private func decimal(from text: String) -> Decimal {
    Decimal(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
}

private func decimalOptional(from text: String) -> Decimal? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else { return nil }
    return Decimal(string: trimmed)
}

private func plainNumber(_ value: Decimal) -> String {
    NSDecimalNumber(decimal: value).stringValue
}

private func markStrategyDirty(_ settings: AppUserSettings, in modelContext: ModelContext) {
    settings.strategyDataChanged = true
    settings.updatedAt = Date()
    try? modelContext.save()
}

private func strategyTitle(_ type: StrategyType) -> String {
    AppText.string("strategyType.\(type.rawValue)", defaultValue: type.rawValue.capitalized)
}

private func strategySummary(from simulation: StrategySimulation) -> StrategySummary {
    StrategySummary(
        strategyType: simulation.strategyType,
        payoffMonth: simulation.estimatedPayoffMonth,
        payoffDate: simulation.estimatedPayoffDate,
        totalPayment: simulation.totalAllocatedAmount,
        totalEstimatedCost: simulation.totalEstimatedCost,
        estimatedInterest: simulation.estimatedInterestAmount,
        estimatedOverdueFee: simulation.estimatedOverdueFee,
        estimatedPenaltyInterest: simulation.estimatedPenaltyInterest,
        endingRemainingAmount: simulation.endingRemainingAmount,
        highestMonthlyPayment: simulation.highestMonthlyPayment,
        averageMonthlyPayment: simulation.averageMonthlyPayment,
        overdueMonthCount: simulation.overdueMonthCount,
        highestOverdueDebtCount: simulation.highestOverdueDebtCount,
        riskLevel: simulation.riskLevel,
        featureDescription: simulation.featureDescription
    )
}

private func strategyPayoffText(_ payoffMonth: Int?) -> String {
    guard let payoffMonth else {
        return AppText.string("strategy.notPaidOffWithinLimit", defaultValue: "Not paid off within simulation window")
    }
    return String(format: AppText.string("strategy.payoffMonthFormat", defaultValue: "Month %d"), payoffMonth)
}

private func strategyRiskTitle(_ level: StrategyRiskLevel) -> String {
    switch level {
    case .low:
        return AppText.string("risk.low", defaultValue: "Low")
    case .medium:
        return AppText.string("risk.medium", defaultValue: "Medium")
    case .high:
        return AppText.string("risk.high", defaultValue: "High")
    case .critical:
        return AppText.string("risk.critical", defaultValue: "Critical")
    }
}

private func ruleText(_ key: String, fallback: String) -> String {
    AppText.string(key, defaultValue: fallback)
}

private func typeColor(_ type: DebtType) -> Color {
    switch type {
    case .creditCard:
        return Color(red: 0.15, green: 0.39, blue: 0.92)
    case .loan:
        return Color(red: 0.49, green: 0.23, blue: 0.93)
    case .personalLending:
        return Color(red: 0.09, green: 0.64, blue: 0.29)
    }
}

private func debtStatusColor(_ status: DebtStatus) -> Color {
    switch status {
    case .active:
        return DebtTheme.success
    case .partiallyPaid:
        return DebtTheme.primary
    case .overdue:
        return DebtTheme.danger
    case .paidOff:
        return DebtTheme.success
    case .archived:
        return DebtTheme.neutral
    }
}

private func statusColor(_ status: CreditCardStatementStatus) -> Color {
    switch status {
    case .pending:
        return DebtTheme.neutral
    case .partiallyPaid:
        return DebtTheme.primary
    case .paid:
        return DebtTheme.success
    case .carriedForward:
        return DebtTheme.warning
    case .overdue:
        return DebtTheme.danger
    case .replaced:
        return DebtTheme.neutral
    }
}

private func planStatusColor(_ status: PlanStatus) -> Color {
    switch status {
    case .pending:
        return DebtTheme.neutral
    case .partiallyPaid:
        return DebtTheme.primary
    case .paid:
        return DebtTheme.success
    case .overdue:
        return DebtTheme.danger
    }
}

private func personalPlanStatusColor(_ status: PersonalLendingPlanStatus) -> Color {
    switch status {
    case .pending:
        return DebtTheme.neutral
    case .partiallyPaid:
        return DebtTheme.primary
    case .paid:
        return DebtTheme.success
    case .overdue:
        return DebtTheme.danger
    }
}

private func uxErrorDescription(_ error: Error) -> String {
    if let error = error as? DebtServiceError {
        switch error {
        case .validationFailed(let message), .notFound(let message), .unsupported(let message):
            return message
        }
    }
    if let error = error as? SubscriptionAccessError {
        return error.errorDescription ?? String(describing: error)
    }
    if let error = error as? PersonalLendingPaymentError {
        return String(describing: error)
    }
    return error.localizedDescription
}
