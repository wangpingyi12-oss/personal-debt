import SwiftUI
import SwiftData

struct AnalyticsDashboardView: View {
    @Query private var creditCards: [CreditCardDebt]
    @Query private var loans: [LoanDebt]
    @Query private var personalLendings: [PersonalLendingDebt]
    @Query private var strategySnapshots: [StrategySimulationSnapshot]

    var body: some View {
        NavigationStack {
            List {
                Section("余额与现金流") {
                    Text("余额趋势（简化）：\(totalActualBalance, format: .number.precision(.fractionLength(2)))")
                    Text("月现金流（简化）：\(monthlyCashOut, format: .number.precision(.fractionLength(2)))")
                }

                Section("成本拆分") {
                    Text("本金：\(principalCost, format: .number)")
                    Text("利息：\(interestCost, format: .number)")
                    Text("逾期费用/罚息：\(overdueCost, format: .number)")
                }

                Section("策略对比") {
                    ForEach(strategySnapshots.filter { $0.dataDomain == DataIsolationDomain.simulated.rawValue }) { snapshot in
                        HStack {
                            Text(snapshot.name)
                            Spacer()
                            Text("\(snapshot.totalCost, format: .number)")
                        }
                    }
                }
            }
            .navigationTitle("统计")
        }
    }

    private var totalActualBalance: Double {
        creditCards.filter { $0.dataDomain == DataIsolationDomain.actual.rawValue }.reduce(0) { $0 + $1.currentBalance }
        + loans.filter { $0.dataDomain == DataIsolationDomain.actual.rawValue }.reduce(0) { $0 + $1.remainingPrincipal }
        + personalLendings.filter { $0.dataDomain == DataIsolationDomain.actual.rawValue }.reduce(0) { $0 + $1.remainingPrincipal }
    }

    private var monthlyCashOut: Double {
        creditCards.flatMap(\.transactions).reduce(0) { $0 + $1.amount }
        + loans.flatMap(\.transactions).reduce(0) { $0 + $1.amount }
        + personalLendings.flatMap(\.transactions).reduce(0) { $0 + $1.amount }
    }

    private var principalCost: Double {
        loans.flatMap(\.installments).reduce(0) { $0 + $1.principalDue }
        + personalLendings.flatMap(\.planItems).reduce(0) { $0 + $1.principalDue }
    }

    private var interestCost: Double {
        loans.flatMap(\.installments).reduce(0) { $0 + $1.interestDue }
        + personalLendings.flatMap(\.planItems).reduce(0) { $0 + $1.interestDue }
    }

    private var overdueCost: Double {
        creditCards.flatMap(\.overdues).reduce(0) { $0 + $1.penaltyAmount }
        + loans.flatMap(\.overdues).reduce(0) { $0 + $1.penaltyAmount }
        + personalLendings.flatMap(\.overdues).reduce(0) { $0 + $1.penaltyAmount }
    }
}
