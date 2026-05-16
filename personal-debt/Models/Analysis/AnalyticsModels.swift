import Foundation

enum AnalyticsOverdueRiskLevel: String, Codable, CaseIterable, Identifiable {
    case none
    case medium
    case high
    case critical

    var id: String { rawValue }
}

enum AnalyticsCostSource: String, Codable, CaseIterable, Identifiable {
    case userProvided
    case systemFallback
    case mixed
    case scheduledPlan
    case none

    var id: String { rawValue }
}

enum AnalyticsSnapshotType: String, Codable, CaseIterable, Identifiable {
    case debt
    case payment
    case overdue
    case cost

    var id: String { rawValue }
}

struct AnalyticsPeriod: Equatable {
    var periodStart: Date
    var periodEndExclusive: Date

    func contains(_ date: Date) -> Bool {
        periodStart <= date && date < periodEndExclusive
    }
}

struct AnalyticsDebtItem: Identifiable, Equatable {
    var id: UUID
    var debtType: DebtType
    var name: String
    var amount: Decimal
    var source: String?
}

struct AnalyticsPaymentItem: Identifiable, Equatable {
    var id: UUID
    var debtID: UUID
    var debtType: DebtType
    var debtName: String
    var paymentDate: Date
    var amount: Decimal
}

struct AnalyticsOverdueItem: Identifiable, Equatable {
    var id: UUID
    var debtID: UUID
    var debtType: DebtType
    var debtName: String
    var dueDate: Date
    var overdueDays: Int
    var overdueAmount: Decimal
    var minimumPaymentGap: Decimal
    var overdueFeeAmount: Decimal
    var penaltyInterestAmount: Decimal
}

struct AnalyticsCostDebtItem: Identifiable, Equatable {
    var id: UUID
    var debtType: DebtType
    var debtName: String
    var costAmount: Decimal
    var primarySource: AnalyticsCostSource
}

struct CostSourceAmounts: Equatable {
    var userProvidedCostAmount: Decimal
    var fallbackCostAmount: Decimal
    var scheduledPlanCostAmount: Decimal
    var mixedCostAmount: Decimal
    var noneCostAmount: Decimal

    static let empty = CostSourceAmounts(
        userProvidedCostAmount: 0,
        fallbackCostAmount: 0,
        scheduledPlanCostAmount: 0,
        mixedCostAmount: 0,
        noneCostAmount: 0
    )

    mutating func add(_ amount: Decimal, source: AnalyticsCostSource) {
        let safeAmount = AnalyticsSupport.nonNegative(amount)
        switch source {
        case .userProvided:
            userProvidedCostAmount += safeAmount
        case .systemFallback:
            fallbackCostAmount += safeAmount
        case .scheduledPlan:
            scheduledPlanCostAmount += safeAmount
        case .mixed:
            mixedCostAmount += safeAmount
        case .none:
            noneCostAmount += safeAmount
        }
    }
}

struct DebtAnalytics: Equatable {
    var totalRemainingAmount: Decimal
    var currentMonthPlannedRepaymentAmount: Decimal
    var creditCardRemainingAmount: Decimal
    var loanRemainingAmount: Decimal
    var personalLendingRemainingAmount: Decimal
    var creditCardShare: Decimal
    var loanShare: Decimal
    var personalLendingShare: Decimal
    var fixedDebtAmount: Decimal
    var revolvingDebtAmount: Decimal
    var totalDebtCount: Int
    var unpaidDebtCount: Int
    var paidOffDebtCount: Int
    var maxSingleDebt: AnalyticsDebtItem?
    var creditCardCurrentStatementPaidAmount: Decimal
    var creditCardCurrentStatementAmount: Decimal

    static let empty = DebtAnalytics(
        totalRemainingAmount: 0,
        currentMonthPlannedRepaymentAmount: 0,
        creditCardRemainingAmount: 0,
        loanRemainingAmount: 0,
        personalLendingRemainingAmount: 0,
        creditCardShare: 0,
        loanShare: 0,
        personalLendingShare: 0,
        fixedDebtAmount: 0,
        revolvingDebtAmount: 0,
        totalDebtCount: 0,
        unpaidDebtCount: 0,
        paidOffDebtCount: 0,
        maxSingleDebt: nil,
        creditCardCurrentStatementPaidAmount: 0,
        creditCardCurrentStatementAmount: 0
    )
}

struct PaymentAnalytics: Equatable {
    var currentMonthPaidAmount: Decimal
    var cumulativePaidAmount: Decimal
    var creditCardCurrentMonthPaidAmount: Decimal
    var loanCurrentMonthPaidAmount: Decimal
    var personalLendingCurrentMonthPaidAmount: Decimal
    var creditCardCumulativePaidAmount: Decimal
    var loanCumulativePaidAmount: Decimal
    var personalLendingCumulativePaidAmount: Decimal
    var currentMonthPaymentRecordCount: Int
    var currentMonthPaymentInputCount: Int
    var creditCardPaymentRecordCount: Int
    var loanPaymentInputCount: Int
    var personalLendingPaymentInputCount: Int
    var latestPayment: AnalyticsPaymentItem?

    static let empty = PaymentAnalytics(
        currentMonthPaidAmount: 0,
        cumulativePaidAmount: 0,
        creditCardCurrentMonthPaidAmount: 0,
        loanCurrentMonthPaidAmount: 0,
        personalLendingCurrentMonthPaidAmount: 0,
        creditCardCumulativePaidAmount: 0,
        loanCumulativePaidAmount: 0,
        personalLendingCumulativePaidAmount: 0,
        currentMonthPaymentRecordCount: 0,
        currentMonthPaymentInputCount: 0,
        creditCardPaymentRecordCount: 0,
        loanPaymentInputCount: 0,
        personalLendingPaymentInputCount: 0,
        latestPayment: nil
    )
}

struct OverdueAnalytics: Equatable {
    var currentOverdueDebtCount: Int
    var currentOverduePeriodCount: Int
    var currentOverdueTotalAmount: Decimal
    var creditCardMinimumPaymentGap: Decimal
    var creditCardOverdueStatementRemainingAmount: Decimal
    var loanOverdueAmount: Decimal
    var personalLendingPastDueAmount: Decimal
    var overdueAmount1To30Days: Decimal
    var overdueAmount31To90Days: Decimal
    var overdueAmountOver90Days: Decimal
    var overdueFeeTotalAmount: Decimal
    var penaltyInterestTotalAmount: Decimal
    var highestRiskItem: AnalyticsOverdueItem?
    var riskLevel: AnalyticsOverdueRiskLevel
    var items: [AnalyticsOverdueItem]

    static let empty = OverdueAnalytics(
        currentOverdueDebtCount: 0,
        currentOverduePeriodCount: 0,
        currentOverdueTotalAmount: 0,
        creditCardMinimumPaymentGap: 0,
        creditCardOverdueStatementRemainingAmount: 0,
        loanOverdueAmount: 0,
        personalLendingPastDueAmount: 0,
        overdueAmount1To30Days: 0,
        overdueAmount31To90Days: 0,
        overdueAmountOver90Days: 0,
        overdueFeeTotalAmount: 0,
        penaltyInterestTotalAmount: 0,
        highestRiskItem: nil,
        riskLevel: .none,
        items: []
    )
}

struct CostAnalytics: Equatable {
    var totalCostAmount: Decimal
    var totalInterestAmount: Decimal
    var totalInstallmentFeeAmount: Decimal
    var totalOverdueFeeAmount: Decimal
    var totalPenaltyInterestAmount: Decimal
    var otherFeeAmount: Decimal
    var creditCardCostAmount: Decimal
    var loanCostAmount: Decimal
    var personalLendingInterestAmount: Decimal
    var loanAppAllocatedPaidInterestAmount: Decimal
    var highCostDebts: [AnalyticsCostDebtItem]
    var sourceAmounts: CostSourceAmounts
    var creditCardBreakdownConflictCount: Int

    static let empty = CostAnalytics(
        totalCostAmount: 0,
        totalInterestAmount: 0,
        totalInstallmentFeeAmount: 0,
        totalOverdueFeeAmount: 0,
        totalPenaltyInterestAmount: 0,
        otherFeeAmount: 0,
        creditCardCostAmount: 0,
        loanCostAmount: 0,
        personalLendingInterestAmount: 0,
        loanAppAllocatedPaidInterestAmount: 0,
        highCostDebts: [],
        sourceAmounts: .empty,
        creditCardBreakdownConflictCount: 0
    )
}

struct AnalyticsSummary: Equatable {
    var debtAnalytics: DebtAnalytics
    var paymentAnalytics: PaymentAnalytics
    var overdueAnalytics: OverdueAnalytics
    var costAnalytics: CostAnalytics
    var overallRepaymentProgress: Decimal
    var fixedDebtProgress: Decimal
    var creditCardCurrentStatementProgress: Decimal
    var generatedAt: Date

    static let empty = AnalyticsSummary(
        debtAnalytics: .empty,
        paymentAnalytics: .empty,
        overdueAnalytics: .empty,
        costAnalytics: .empty,
        overallRepaymentProgress: 0,
        fixedDebtProgress: 0,
        creditCardCurrentStatementProgress: 0,
        generatedAt: Date(timeIntervalSince1970: 0)
    )
}
