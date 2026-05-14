import Foundation

struct OverviewMetrics {
    let currentMonthDue: Double
    let minimumDue: Double
    let overdueAmount: Double
    let totalRemaining: Double
    let completionProgress: Double
    let todoCount: Int
}

struct AnalyticsPoint: Identifiable {
    let id = UUID()
    let monthLabel: String
    let balance: Double
    let cashFlow: Double
}
