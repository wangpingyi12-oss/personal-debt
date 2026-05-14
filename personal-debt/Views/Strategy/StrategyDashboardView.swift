import SwiftUI
import SwiftData

struct StrategyDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var creditCards: [CreditCardDebt]
    @Query private var loans: [LoanDebt]
    @Query private var personalLendings: [PersonalLendingDebt]
    @Query(sort: \StrategySimulationSnapshot.createdAt, order: .reverse) private var snapshots: [StrategySimulationSnapshot]

    @State private var budgetText = "3000"
    @State private var quickSuggestion = ""

    var body: some View {
        NavigationStack {
            List {
                Section("模拟控制") {
                    TextField("月预算", text: $budgetText)
                        .keyboardType(.decimalPad)
                    Text("模拟结果为 Simulated，不会覆盖真实账。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack {
                        ForEach(StrategyMode.allCases) { mode in
                            Button(mode.displayName) {
                                runSimulation(mode: mode)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                if !quickSuggestion.isEmpty {
                    Section("本月+次月建议") {
                        Text(quickSuggestion)
                    }
                }

                Section("已保存策略") {
                    ForEach(snapshots.filter { $0.dataDomain == DataIsolationDomain.simulated.rawValue }) { snapshot in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(snapshot.name).font(.headline)
                            Text("总成本：\(snapshot.totalCost, format: .number.precision(.fractionLength(2)))")
                            Text("还清月数：\(snapshot.monthsToDebtFree)")
                            if !snapshot.riskWarning.isEmpty {
                                Text(snapshot.riskWarning)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .onDelete(perform: deleteSnapshot)
                }
            }
            .navigationTitle("策略")
        }
    }

    private func runSimulation(mode: StrategyMode) {
        let budget = max(0, Double(budgetText) ?? 0)
        let inputs = creditCards.filter { $0.isValid && $0.dataDomain == DataIsolationDomain.actual.rawValue }.map {
            SimulatedDebtInput(
                id: $0.id,
                name: $0.name,
                debtKind: .creditCard,
                balance: $0.currentBalance,
                monthlyRate: $0.annualRate / 12,
                overdueAmount: $0.overdues.filter { $0.isActive }.reduce(0) { $0 + $1.overdueAmount + $1.penaltyAmount }
            )
        } + loans.filter { $0.isValid && $0.dataDomain == DataIsolationDomain.actual.rawValue }.map {
            SimulatedDebtInput(
                id: $0.id,
                name: $0.name,
                debtKind: .loan,
                balance: $0.remainingPrincipal,
                monthlyRate: $0.annualRate / 12,
                overdueAmount: $0.overdues.filter { $0.isActive }.reduce(0) { $0 + $1.overdueAmount + $1.penaltyAmount }
            )
        } + personalLendings.filter { $0.isValid && $0.dataDomain == DataIsolationDomain.actual.rawValue }.map {
            SimulatedDebtInput(
                id: $0.id,
                name: $0.name,
                debtKind: .personalLending,
                balance: $0.remainingPrincipal,
                monthlyRate: $0.annualRate / 12,
                overdueAmount: $0.overdues.filter { $0.isActive }.reduce(0) { $0 + $1.overdueAmount + $1.penaltyAmount }
            )
        }

        let result = StrategySimulator.simulate(inputs: inputs, mode: mode, monthlyBudget: budget)
        quickSuggestion = "本月优先处理 \(mode.displayName)，次月复核预算与逾期风险。"

        let snapshot = StrategySimulationSnapshot(
            name: "\(mode.displayName)-\(Date.now.formatted(date: .abbreviated, time: .shortened))",
            mode: mode.rawValue,
            monthlyBudget: budget,
            totalCost: result.totalCost,
            monthsToDebtFree: result.monthsToDebtFree,
            riskWarning: result.riskWarning
        )
        snapshot.months = result.months.map {
            StrategySimulationMonth(
                sequence: $0.sequence,
                principalPaid: $0.principalPaid,
                interestPaid: $0.interestPaid,
                overduePaid: $0.overduePaid,
                remainingBalance: $0.remainingBalance,
                pressureIndex: $0.pressureIndex,
                snapshot: snapshot
            )
        }
        modelContext.insert(snapshot)
        try? modelContext.save()
    }

    private func deleteSnapshot(at offsets: IndexSet) {
        let simulated = snapshots.filter { $0.dataDomain == DataIsolationDomain.simulated.rawValue }
        for idx in offsets {
            modelContext.delete(simulated[idx])
        }
        try? modelContext.save()
    }
}
