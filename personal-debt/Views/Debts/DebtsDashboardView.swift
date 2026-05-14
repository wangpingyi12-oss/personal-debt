import SwiftUI
import SwiftData

struct DebtsDashboardView: View {
    enum AddKind: String, CaseIterable, Identifiable {
        case creditCard
        case loan
        case personalLending

        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CreditCardDebt.createdAt, order: .reverse) private var creditCards: [CreditCardDebt]
    @Query private var loans: [LoanDebt]
    @Query private var personalLendings: [PersonalLendingDebt]

    @State private var addKind: AddKind?

    var body: some View {
        NavigationStack {
            List {
                Section("信用卡") {
                    ForEach(creditCards.filter { $0.isValid && $0.dataDomain == DataIsolationDomain.actual.rawValue }) { debt in
                        NavigationLink(debt.name) {
                            CreditCardDebtDetailView(debt: debt)
                        }
                    }
                    .onDelete(perform: deleteCreditCard)
                }

                Section("贷款") {
                    ForEach(loans.filter { $0.isValid && $0.dataDomain == DataIsolationDomain.actual.rawValue }) { debt in
                        NavigationLink(debt.name) {
                            LoanDebtDetailView(debt: debt)
                        }
                    }
                    .onDelete(perform: deleteLoan)
                }

                Section("个人借贷") {
                    ForEach(personalLendings.filter { $0.isValid && $0.dataDomain == DataIsolationDomain.actual.rawValue }) { debt in
                        NavigationLink(debt.name) {
                            PersonalLendingDebtDetailView(debt: debt)
                        }
                    }
                    .onDelete(perform: deletePersonalLending)
                }
            }
            .navigationTitle("债务")
            .toolbar {
                Menu("新增") {
                    Button("新增信用卡债务") { addKind = .creditCard }
                    Button("新增贷款") { addKind = .loan }
                    Button("新增个人借贷") { addKind = .personalLending }
                }
            }
            .sheet(item: $addKind) { kind in
                switch kind {
                case .creditCard:
                    AddCreditCardDebtView()
                case .loan:
                    AddLoanDebtView()
                case .personalLending:
                    AddPersonalLendingDebtView()
                }
            }
        }
    }

    private func deleteCreditCard(at offsets: IndexSet) {
        let visibleItems = creditCards.filter { $0.isValid && $0.dataDomain == DataIsolationDomain.actual.rawValue }
        for index in offsets {
            let item = visibleItems[index]
            item.isValid = false
        }
        try? modelContext.save()
    }

    private func deleteLoan(at offsets: IndexSet) {
        let visibleItems = loans.filter { $0.isValid && $0.dataDomain == DataIsolationDomain.actual.rawValue }
        for index in offsets {
            let item = visibleItems[index]
            item.isValid = false
        }
        try? modelContext.save()
    }

    private func deletePersonalLending(at offsets: IndexSet) {
        let visibleItems = personalLendings.filter { $0.isValid && $0.dataDomain == DataIsolationDomain.actual.rawValue }
        for index in offsets {
            let item = visibleItems[index]
            item.isValid = false
        }
        try? modelContext.save()
    }
}

private struct AddCreditCardDebtView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var issuer = ""
    @State private var balance = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("名称", text: $name)
                TextField("发卡行", text: $issuer)
                TextField("当前余额", text: $balance)
                    .keyboardType(.decimalPad)
            }
            .navigationTitle("新增信用卡")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let amount = Double(balance) ?? 0
                        let debt = CreditCardDebt(
                            name: name.isEmpty ? "信用卡" : name,
                            issuer: issuer.isEmpty ? "未填写" : issuer,
                            creditLimit: max(DebtBusinessRules.minimumCreditLimit, amount * DebtBusinessRules.creditLimitMultiplier),
                            annualRate: 0.18,
                            statementDay: 1,
                            dueDay: 20,
                            currentBalance: amount
                        )
                        modelContext.insert(debt)
                        _ = CreditCardCalculator.ensureCurrentBill(for: debt)
                        try? modelContext.save()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

private struct AddLoanDebtView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var principal = ""
    @State private var periods = "12"
    @State private var method: LoanRepaymentMethod = .equalPrincipalAndInterest

    var body: some View {
        NavigationStack {
            Form {
                TextField("名称", text: $name)
                TextField("本金", text: $principal)
                    .keyboardType(.decimalPad)
                TextField("期数", text: $periods)
                    .keyboardType(.numberPad)
                Picker("还款方式", selection: $method) {
                    ForEach(LoanRepaymentMethod.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
            }
            .navigationTitle("新增贷款")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let amount = Double(principal) ?? 0
                        let p = max(1, Int(periods) ?? 12)
                        let debt = LoanDebt(
                            name: name.isEmpty ? "贷款" : name,
                            principal: amount,
                            annualRate: 0.08,
                            totalPeriods: p,
                            startDate: .now,
                            repaymentMethod: method.rawValue,
                            remainingPrincipal: amount
                        )
                        debt.installments = LoanCalculator.buildInstallments(
                            principal: amount,
                            annualRate: 0.08,
                            periods: p,
                            startDate: debt.startDate,
                            method: method
                        )
                        modelContext.insert(debt)
                        try? modelContext.save()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

private struct AddPersonalLendingDebtView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // Basic info
    @State private var name = ""
    @State private var lenderName = ""
    @State private var note = ""
    @State private var principal = ""
    @State private var startDate = Date()

    // Interest
    @State private var hasInterest = false
    @State private var totalInterest = ""

    // Repayment method
    @State private var repaymentMethod: PersonalLendingRepaymentMethod = .noFixedPlan

    // For lumpSumAtMaturity
    @State private var endDate = Date()

    // For equalInstallments
    @State private var monthlyPaymentDay = "1"
    @State private var totalPeriods = "12"

    // Optional endDate for noFixedPlan
    @State private var hasEndDate = false
    @State private var noFixedPlanEndDate = Date()

    @State private var errorMessage: String?

    private var parsedPrincipal: Double { Double(principal) ?? 0 }
    private var parsedInterest: Double { Double(totalInterest) ?? 0 }
    private var parsedPaymentDay: Int { Int(monthlyPaymentDay) ?? 1 }
    private var parsedPeriods: Int { max(1, Int(totalPeriods) ?? 12) }

    var body: some View {
        NavigationStack {
            Form {
                Section("基础信息") {
                    TextField("债务名称", text: $name)
                    TextField("出借人", text: $lenderName)
                    TextField("备注（选填）", text: $note)
                    TextField("借款本金", text: $principal)
                        .keyboardType(.decimalPad)
                    DatePicker("借款日期", selection: $startDate, displayedComponents: .date)
                }

                Section("还款方式") {
                    Picker("还款方式", selection: $repaymentMethod) {
                        ForEach(PersonalLendingRepaymentMethod.allCases) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                    .onChange(of: repaymentMethod) { _, newValue in
                        if newValue == .noFixedPlan { hasInterest = false }
                    }

                    if repaymentMethod == .lumpSumAtMaturity {
                        DatePicker("约定结束日期", selection: $endDate, displayedComponents: .date)
                    }

                    if repaymentMethod == .equalInstallments {
                        TextField("每月还款日（1–31）", text: $monthlyPaymentDay)
                            .keyboardType(.numberPad)
                        TextField("总期数", text: $totalPeriods)
                            .keyboardType(.numberPad)
                    }

                    if repaymentMethod == .noFixedPlan {
                        Toggle("填写约定结束日期", isOn: $hasEndDate)
                        if hasEndDate {
                            DatePicker("约定结束日期", selection: $noFixedPlanEndDate, displayedComponents: .date)
                        }
                    }
                }

                Section("利息设置") {
                    Toggle("有息", isOn: $hasInterest)
                        .disabled(repaymentMethod == .noFixedPlan)
                    if hasInterest {
                        TextField("固定总利息", text: $totalInterest)
                            .keyboardType(.decimalPad)
                    }
                }

                if let msg = errorMessage {
                    Section {
                        Text(msg).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("新增个人借贷")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func save() {
        let p = parsedPrincipal
        let interest = hasInterest ? parsedInterest : 0.0
        let computedEndDate: Date? = {
            switch repaymentMethod {
            case .lumpSumAtMaturity: return endDate
            case .noFixedPlan: return hasEndDate ? noFixedPlanEndDate : nil
            case .equalInstallments: return nil
            }
        }()

        do {
            try PersonalLendingCalculator.validateDebt(
                principal: p,
                hasInterest: hasInterest,
                totalInterest: interest,
                repaymentMethod: repaymentMethod,
                startDate: startDate,
                endDate: computedEndDate,
                monthlyPaymentDay: parsedPaymentDay,
                totalPeriods: parsedPeriods
            )
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let debt = PersonalLendingDebt(
            name: name.isEmpty ? "个人借贷" : name,
            lenderName: lenderName,
            note: note,
            principal: p,
            hasInterest: hasInterest,
            totalInterest: interest,
            startDate: startDate,
            endDate: computedEndDate,
            repaymentMethod: repaymentMethod.rawValue,
            monthlyPaymentDay: parsedPaymentDay,
            totalPeriods: parsedPeriods
        )

        // For equalInstallments, derive endDate from generated plan
        let planItems = PersonalLendingCalculator.buildPlan(for: debt)
        debt.planItems = planItems
        if repaymentMethod == .equalInstallments, let lastDate = planItems.last?.dueDate {
            debt.endDate = lastDate
        }

        modelContext.insert(debt)
        PersonalLendingCalculator.fullRecalculate(debt: debt, context: modelContext)
        try? modelContext.save()
        dismiss()
    }
}

private struct PersonalLendingDebtDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var debt: PersonalLendingDebt

    @State private var showingAddPayment = false
    @State private var paymentAmount = ""
    @State private var paymentDate = Date()
    @State private var paymentNote = ""
    @State private var paymentError: String?

    private var method: PersonalLendingRepaymentMethod {
        PersonalLendingRepaymentMethod(rawValue: debt.repaymentMethod) ?? .noFixedPlan
    }

    private var nextDue: PersonalLendingCalculator.NextDueInfo {
        PersonalLendingCalculator.nextDueInfo(for: debt)
    }

    private var isPastDue: Bool { debt.pastDueDebtCount > 0 }

    var body: some View {
        List {
            Section("基础信息") {
                LabeledContent("出借人", value: debt.lenderName.isEmpty ? "—" : debt.lenderName)
                LabeledContent("还款方式", value: method.displayName)
                LabeledContent("借款本金", value: debt.principal, format: .currency(code: currencyCode))
                if debt.hasInterest {
                    LabeledContent("固定总利息", value: debt.totalInterest, format: .currency(code: currencyCode))
                }
                LabeledContent("总应还金额", value: debt.totalAmountDue, format: .currency(code: currencyCode))
                LabeledContent("已还金额", value: debt.paidAmount, format: .currency(code: currencyCode))
                LabeledContent("剩余金额", value: debt.remainingAmount, format: .currency(code: currencyCode))
                LabeledContent("状态", value: debt.status)
                if let endDate = debt.endDate {
                    LabeledContent("约定结束日期", value: endDate, format: .dateTime.year().month().day())
                }
                if !debt.note.isEmpty {
                    LabeledContent("备注", value: debt.note)
                }
            }

            if isPastDue {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Text("已超过约定还款日")
                            .foregroundStyle(.orange)
                    }
                    LabeledContent("已过约定日未还金额",
                                   value: debt.pastDueScheduledAmount,
                                   format: .currency(code: currencyCode))
                }
            }

            if let dueDate = nextDue.dueDate, nextDue.dueAmount > 0 {
                Section("下一期待还") {
                    LabeledContent("日期", value: dueDate, format: .dateTime.year().month().day())
                    LabeledContent("金额", value: nextDue.dueAmount, format: .currency(code: currencyCode))
                }
            }

            if !debt.planItems.isEmpty {
                Section("还款计划") {
                    ForEach(debt.planItems.sorted(by: { $0.sequence < $1.sequence })) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("第\(item.sequence)期")
                                    .font(.subheadline)
                                Spacer()
                                Text(item.dueDate, format: .dateTime.year().month().day())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Text("应还：\(item.totalDue, format: .currency(code: currencyCode))")
                                    .font(.caption)
                                Spacer()
                                Text("剩余：\(item.remainingAmount, format: .currency(code: currencyCode))")
                                    .font(.caption)
                                    .foregroundStyle(item.remainingAmount > 0 ? .primary : .secondary)
                            }
                            Text("状态：\(item.state)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section("还款流水") {
                Button("新增还款流水") {
                    paymentAmount = ""
                    paymentDate = Date()
                    paymentNote = ""
                    paymentError = nil
                    showingAddPayment = true
                }
                .disabled(debt.remainingAmount <= 0.001)

                ForEach(debt.transactions.filter { $0.isValid }.sorted(by: { $0.occurredAt > $1.occurredAt })) { tx in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tx.amount, format: .currency(code: currencyCode))
                                .font(.subheadline)
                            if !tx.note.isEmpty {
                                Text(tx.note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(tx.occurredAt, format: .dateTime.year().month().day())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("删除", role: .destructive) {
                            try? TransactionOrchestrator.deletePersonalLendingPayment(
                                transaction: tx,
                                debt: debt,
                                context: modelContext
                            )
                        }
                    }
                }
            }

            Section("统计") {
                LabeledContent("还款进度") {
                    let progress = debt.totalAmountDue > 0 ? debt.paidAmount / debt.totalAmountDue : 0
                    Text("\(Int(progress * 100))%")
                }
                if debt.pastDuePlanCount > 0 {
                    LabeledContent("已过约定日未还计划数", value: "\(debt.pastDuePlanCount)")
                }
            }
        }
        .navigationTitle(debt.name)
        .sheet(isPresented: $showingAddPayment) {
            addPaymentSheet
        }
    }

    @ViewBuilder
    private var addPaymentSheet: some View {
        NavigationStack {
            Form {
                Section("还款信息") {
                    TextField("还款金额", text: $paymentAmount)
                        .keyboardType(.decimalPad)
                    DatePicker("还款日期", selection: $paymentDate, displayedComponents: .date)
                    TextField("备注（选填）", text: $paymentNote)
                }
                if let err = paymentError {
                    Section {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle("新增还款流水")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let amount = Double(paymentAmount) ?? 0
                        do {
                            try TransactionOrchestrator.addPersonalLendingPayment(
                                amount: amount,
                                occurredAt: paymentDate,
                                note: paymentNote,
                                debt: debt,
                                context: modelContext
                            )
                            showingAddPayment = false
                        } catch {
                            paymentError = error.localizedDescription
                        }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showingAddPayment = false }
                }
            }
        }
    }

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "CNY"
    }
}

private struct CreditCardDebtDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var debt: CreditCardDebt

    var body: some View {
        List {
            Section("基础信息") {
                Text("发卡行：\(debt.issuer)")
                Text("余额：\(debt.currentBalance, format: .currency(code: Locale.current.currency?.identifier ?? "CNY"))")
                Text("状态：\(debt.status)")
            }
            Section("账单") {
                ForEach(debt.bills.sorted(by: { $0.statementDate > $1.statementDate })) { bill in
                    VStack(alignment: .leading) {
                        Text(bill.periodKey)
                        Text("应还：\(bill.principalDue, format: .number.precision(.fractionLength(2)))")
                            .font(.caption)
                    }
                }
            }
            Section("流水") {
                Button("新增还款流水") {
                    try? TransactionOrchestrator.appendCreditCardPayment(amount: 100, debt: debt, context: modelContext)
                }
                ForEach(debt.transactions.sorted(by: { $0.occurredAt > $1.occurredAt })) { tx in
                    Text("\(tx.amount, format: .number) @ \(tx.occurredAt.formatted(date: .abbreviated, time: .omitted))")
                }
            }
            Section("逾期") {
                Button("新增逾期") {
                    debt.overdues.append(CreditCardOverdueRecord(startDate: .now, overdueAmount: 200, debt: debt))
                    debt.status = DebtLifecycleStatus.overdue.rawValue
                    try? modelContext.save()
                }
                ForEach(debt.overdues) { overdue in
                    HStack {
                        Text("\(overdue.overdueAmount, format: .number)")
                        Spacer()
                        if overdue.isActive {
                            Button("结束") {
                                overdue.isActive = false
                                overdue.endDate = .now
                                debt.status = CreditCardCalculator.evaluateStatus(for: debt)
                                try? modelContext.save()
                            }
                        }
                    }
                }
            }
            Section("统计") {
                Text("交易数：\(debt.transactions.count)")
                Text("逾期次数：\(debt.overdues.count)")
            }
        }
        .navigationTitle(debt.name)
    }
}

private struct LoanDebtDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var debt: LoanDebt

    var body: some View {
        List {
            Section("基础信息") {
                Text("本金：\(debt.principal, format: .number)")
                Text("剩余：\(debt.remainingPrincipal, format: .number)")
                Text("状态：\(debt.status)")
            }
            Section("计划") {
                ForEach(debt.installments.sorted(by: { $0.periodNumber < $1.periodNumber })) { plan in
                    Text("第\(plan.periodNumber)期：\(plan.totalDue, format: .number)")
                }
            }
            Section("流水") {
                Button("新增还款流水") {
                    try? TransactionOrchestrator.appendLoanPayment(amount: 300, debt: debt, context: modelContext)
                }
            }
            Section("逾期") {
                Button("新增逾期") {
                    debt.overdues.append(LoanOverdueRecord(startDate: .now, overdueAmount: 300, debt: debt))
                    debt.status = DebtLifecycleStatus.overdue.rawValue
                    try? modelContext.save()
                }
            }
            Section("统计") {
                Text("计划数：\(debt.installments.count)")
            }
        }
        .navigationTitle(debt.name)
    }
}


