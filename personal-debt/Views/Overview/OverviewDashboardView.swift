import SwiftUI
import SwiftData

struct OverviewDashboardView: View {
    @Query(sort: \CreditCardDebt.createdAt, order: .reverse) private var creditCards: [CreditCardDebt]
    @Query private var loans: [LoanDebt]
    @Query private var personalLendings: [PersonalLendingDebt]

    private var metrics: OverviewMetrics {
        OverviewViewModel.makeMetrics(
            creditCards: creditCards.filter { $0.dataDomain == DataIsolationDomain.actual.rawValue },
            loans: loans.filter { $0.dataDomain == DataIsolationDomain.actual.rawValue },
            personalLendings: personalLendings.filter { $0.dataDomain == DataIsolationDomain.actual.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    CardSection {
                        SectionHeader(title: "总览", subtitle: "仅显示真实数据（Actual），与模拟结果隔离。")
                        metricRow("本月应还", metrics.currentMonthDue)
                        metricRow("最低需还", metrics.minimumDue)
                        metricRow("逾期金额", metrics.overdueAmount)
                        metricRow("总剩余", metrics.totalRemaining)
                        HStack {
                            Text("还款进度")
                            Spacer()
                            Text("\(Int(metrics.completionProgress * 100))%")
                        }
                        ProgressView(value: metrics.completionProgress)
                        Text("待办提醒：\(metrics.todoCount)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .background(AppColors.backgroundGray)
            .navigationTitle("总览")
        }
    }

    private func metricRow(_ label: String, _ value: Double) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value, format: .currency(code: Locale.current.currency?.identifier ?? "CNY"))
                .bold()
        }
    }
}
