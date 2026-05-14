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
        for index in offsets {
            let item = creditCards[index]
            item.isValid = false
        }
        try? modelContext.save()
    }

    private func deleteLoan(at offsets: IndexSet) {
        for index in offsets {
            let item = loans[index]
            item.isValid = false
        }
        try? modelContext.save()
    }

    private func deletePersonalLending(at offsets: IndexSet) {
        for index in offsets {
            let item = personalLendings[index]
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
                            creditLimit: max(1000, amount * 1.2),
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
    @State private var name = ""
    @State private var counterparty = ""
    @State private var principal = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("名称", text: $name)
                TextField("对方", text: $counterparty)
                TextField("本金", text: $principal)
                    .keyboardType(.decimalPad)
            }
            .navigationTitle("新增个人借贷")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let amount = Double(principal) ?? 0
                        let snapshot = PersonalLendingCalculator.snapshotFacts(
                            principal: amount,
                            annualRate: 0.06,
                            periods: 12,
                            startDate: .now
                        )
                        let debt = PersonalLendingDebt(
                            name: name.isEmpty ? "个人借贷" : name,
                            counterparty: counterparty.isEmpty ? "未填写" : counterparty,
                            principal: amount,
                            annualRate: 0.06,
                            startDate: .now,
                            remainingPrincipal: amount,
                            userFactSnapshot: snapshot
                        )
                        debt.planItems = PersonalLendingCalculator.rebuildPlan(from: snapshot)
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

private struct PersonalLendingDebtDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var debt: PersonalLendingDebt

    var body: some View {
        List {
            Section("基础信息") {
                Text("对方：\(debt.counterparty)")
                Text("本金：\(debt.principal, format: .number)")
                Text("剩余：\(debt.remainingPrincipal, format: .number)")
                Text("状态：\(debt.status)")
            }
            Section("计划") {
                ForEach(debt.planItems.sorted(by: { $0.sequence < $1.sequence })) { item in
                    Text("第\(item.sequence)期：\(item.totalDue, format: .number)")
                }
            }
            Section("流水") {
                Button("新增还款流水") {
                    try? TransactionOrchestrator.appendPersonalLendingPayment(amount: 200, debt: debt, context: modelContext)
                }
            }
            Section("逾期") {
                Button("新增逾期") {
                    debt.overdues.append(PersonalLendingOverdueRecord(startDate: .now, overdueAmount: 100, debt: debt))
                    debt.status = DebtLifecycleStatus.overdue.rawValue
                    try? modelContext.save()
                }
            }
            Section("统计") {
                Text("计划数：\(debt.planItems.count)")
            }
        }
        .navigationTitle(debt.name)
    }
}
