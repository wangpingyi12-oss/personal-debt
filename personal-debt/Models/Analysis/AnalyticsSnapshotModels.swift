import Foundation
import SwiftData

@Model
final class DebtAnalyticsSnapshot {
    var id: UUID
    var snapshotTypeRawValue: String
    var asOfDate: Date
    var periodStart: Date
    var periodEndExclusive: Date
    var generatedAt: Date
    var totalRemainingAmount: Decimal
    var currentMonthPlannedRepaymentAmount: Decimal
    var creditCardRemainingAmount: Decimal
    var loanRemainingAmount: Decimal
    var personalLendingRemainingAmount: Decimal
    var fixedDebtAmount: Decimal
    var revolvingDebtAmount: Decimal
    var totalDebtCount: Int
    var unpaidDebtCount: Int
    var paidOffDebtCount: Int
    var maxDebtID: UUID?
    var maxDebtTypeRawValue: String?
    var maxDebtName: String
    var maxDebtAmount: Decimal

    var snapshotType: AnalyticsSnapshotType {
        get { .value(from: snapshotTypeRawValue, default: .debt) }
        set { snapshotTypeRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        asOfDate: Date,
        period: AnalyticsPeriod,
        analytics: DebtAnalytics,
        generatedAt: Date
    ) {
        self.id = id
        self.snapshotTypeRawValue = AnalyticsSnapshotType.debt.rawValue
        self.asOfDate = asOfDate
        self.periodStart = period.periodStart
        self.periodEndExclusive = period.periodEndExclusive
        self.generatedAt = generatedAt
        self.totalRemainingAmount = analytics.totalRemainingAmount
        self.currentMonthPlannedRepaymentAmount = analytics.currentMonthPlannedRepaymentAmount
        self.creditCardRemainingAmount = analytics.creditCardRemainingAmount
        self.loanRemainingAmount = analytics.loanRemainingAmount
        self.personalLendingRemainingAmount = analytics.personalLendingRemainingAmount
        self.fixedDebtAmount = analytics.fixedDebtAmount
        self.revolvingDebtAmount = analytics.revolvingDebtAmount
        self.totalDebtCount = analytics.totalDebtCount
        self.unpaidDebtCount = analytics.unpaidDebtCount
        self.paidOffDebtCount = analytics.paidOffDebtCount
        self.maxDebtID = analytics.maxSingleDebt?.id
        self.maxDebtTypeRawValue = analytics.maxSingleDebt?.debtType.rawValue
        self.maxDebtName = analytics.maxSingleDebt?.name ?? ""
        self.maxDebtAmount = analytics.maxSingleDebt?.amount ?? 0
    }

    func update(period: AnalyticsPeriod, analytics: DebtAnalytics, generatedAt: Date) {
        self.periodStart = period.periodStart
        self.periodEndExclusive = period.periodEndExclusive
        self.generatedAt = generatedAt
        self.totalRemainingAmount = analytics.totalRemainingAmount
        self.currentMonthPlannedRepaymentAmount = analytics.currentMonthPlannedRepaymentAmount
        self.creditCardRemainingAmount = analytics.creditCardRemainingAmount
        self.loanRemainingAmount = analytics.loanRemainingAmount
        self.personalLendingRemainingAmount = analytics.personalLendingRemainingAmount
        self.fixedDebtAmount = analytics.fixedDebtAmount
        self.revolvingDebtAmount = analytics.revolvingDebtAmount
        self.totalDebtCount = analytics.totalDebtCount
        self.unpaidDebtCount = analytics.unpaidDebtCount
        self.paidOffDebtCount = analytics.paidOffDebtCount
        self.maxDebtID = analytics.maxSingleDebt?.id
        self.maxDebtTypeRawValue = analytics.maxSingleDebt?.debtType.rawValue
        self.maxDebtName = analytics.maxSingleDebt?.name ?? ""
        self.maxDebtAmount = analytics.maxSingleDebt?.amount ?? 0
    }
}

@Model
final class PaymentAnalyticsSnapshot {
    var id: UUID
    var snapshotTypeRawValue: String
    var asOfDate: Date
    var periodStart: Date
    var periodEndExclusive: Date
    var generatedAt: Date
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
    var latestPaymentID: UUID?
    var latestPaymentDebtTypeRawValue: String?
    var latestPaymentDebtName: String
    var latestPaymentDate: Date?
    var latestPaymentAmount: Decimal

    var snapshotType: AnalyticsSnapshotType {
        get { .value(from: snapshotTypeRawValue, default: .payment) }
        set { snapshotTypeRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        asOfDate: Date,
        period: AnalyticsPeriod,
        analytics: PaymentAnalytics,
        generatedAt: Date
    ) {
        self.id = id
        self.snapshotTypeRawValue = AnalyticsSnapshotType.payment.rawValue
        self.asOfDate = asOfDate
        self.periodStart = period.periodStart
        self.periodEndExclusive = period.periodEndExclusive
        self.generatedAt = generatedAt
        self.currentMonthPaidAmount = analytics.currentMonthPaidAmount
        self.cumulativePaidAmount = analytics.cumulativePaidAmount
        self.creditCardCurrentMonthPaidAmount = analytics.creditCardCurrentMonthPaidAmount
        self.loanCurrentMonthPaidAmount = analytics.loanCurrentMonthPaidAmount
        self.personalLendingCurrentMonthPaidAmount = analytics.personalLendingCurrentMonthPaidAmount
        self.creditCardCumulativePaidAmount = analytics.creditCardCumulativePaidAmount
        self.loanCumulativePaidAmount = analytics.loanCumulativePaidAmount
        self.personalLendingCumulativePaidAmount = analytics.personalLendingCumulativePaidAmount
        self.currentMonthPaymentRecordCount = analytics.currentMonthPaymentRecordCount
        self.currentMonthPaymentInputCount = analytics.currentMonthPaymentInputCount
        self.latestPaymentID = analytics.latestPayment?.id
        self.latestPaymentDebtTypeRawValue = analytics.latestPayment?.debtType.rawValue
        self.latestPaymentDebtName = analytics.latestPayment?.debtName ?? ""
        self.latestPaymentDate = analytics.latestPayment?.paymentDate
        self.latestPaymentAmount = analytics.latestPayment?.amount ?? 0
    }

    func update(period: AnalyticsPeriod, analytics: PaymentAnalytics, generatedAt: Date) {
        self.periodStart = period.periodStart
        self.periodEndExclusive = period.periodEndExclusive
        self.generatedAt = generatedAt
        self.currentMonthPaidAmount = analytics.currentMonthPaidAmount
        self.cumulativePaidAmount = analytics.cumulativePaidAmount
        self.creditCardCurrentMonthPaidAmount = analytics.creditCardCurrentMonthPaidAmount
        self.loanCurrentMonthPaidAmount = analytics.loanCurrentMonthPaidAmount
        self.personalLendingCurrentMonthPaidAmount = analytics.personalLendingCurrentMonthPaidAmount
        self.creditCardCumulativePaidAmount = analytics.creditCardCumulativePaidAmount
        self.loanCumulativePaidAmount = analytics.loanCumulativePaidAmount
        self.personalLendingCumulativePaidAmount = analytics.personalLendingCumulativePaidAmount
        self.currentMonthPaymentRecordCount = analytics.currentMonthPaymentRecordCount
        self.currentMonthPaymentInputCount = analytics.currentMonthPaymentInputCount
        self.latestPaymentID = analytics.latestPayment?.id
        self.latestPaymentDebtTypeRawValue = analytics.latestPayment?.debtType.rawValue
        self.latestPaymentDebtName = analytics.latestPayment?.debtName ?? ""
        self.latestPaymentDate = analytics.latestPayment?.paymentDate
        self.latestPaymentAmount = analytics.latestPayment?.amount ?? 0
    }
}

@Model
final class OverdueAnalyticsSnapshot {
    var id: UUID
    var snapshotTypeRawValue: String
    var asOfDate: Date
    var periodStart: Date
    var periodEndExclusive: Date
    var generatedAt: Date
    var currentOverdueDebtCount: Int
    var currentOverduePeriodCount: Int
    var currentOverdueTotalAmount: Decimal
    var creditCardMinimumPaymentGap: Decimal
    var loanOverdueAmount: Decimal
    var personalLendingPastDueAmount: Decimal
    var overdueAmount1To30Days: Decimal
    var overdueAmount31To90Days: Decimal
    var overdueAmountOver90Days: Decimal
    var overdueFeeTotalAmount: Decimal
    var penaltyInterestTotalAmount: Decimal
    var riskLevelRawValue: String
    var highestRiskDebtID: UUID?
    var highestRiskDebtTypeRawValue: String?
    var highestRiskDebtName: String
    var highestRiskAmount: Decimal
    var highestRiskOverdueDays: Int

    var snapshotType: AnalyticsSnapshotType {
        get { .value(from: snapshotTypeRawValue, default: .overdue) }
        set { snapshotTypeRawValue = newValue.rawValue }
    }

    var riskLevel: AnalyticsOverdueRiskLevel {
        get { .value(from: riskLevelRawValue, default: .none) }
        set { riskLevelRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        asOfDate: Date,
        period: AnalyticsPeriod,
        analytics: OverdueAnalytics,
        generatedAt: Date
    ) {
        self.id = id
        self.snapshotTypeRawValue = AnalyticsSnapshotType.overdue.rawValue
        self.asOfDate = asOfDate
        self.periodStart = period.periodStart
        self.periodEndExclusive = period.periodEndExclusive
        self.generatedAt = generatedAt
        self.currentOverdueDebtCount = analytics.currentOverdueDebtCount
        self.currentOverduePeriodCount = analytics.currentOverduePeriodCount
        self.currentOverdueTotalAmount = analytics.currentOverdueTotalAmount
        self.creditCardMinimumPaymentGap = analytics.creditCardMinimumPaymentGap
        self.loanOverdueAmount = analytics.loanOverdueAmount
        self.personalLendingPastDueAmount = analytics.personalLendingPastDueAmount
        self.overdueAmount1To30Days = analytics.overdueAmount1To30Days
        self.overdueAmount31To90Days = analytics.overdueAmount31To90Days
        self.overdueAmountOver90Days = analytics.overdueAmountOver90Days
        self.overdueFeeTotalAmount = analytics.overdueFeeTotalAmount
        self.penaltyInterestTotalAmount = analytics.penaltyInterestTotalAmount
        self.riskLevelRawValue = analytics.riskLevel.rawValue
        self.highestRiskDebtID = analytics.highestRiskItem?.debtID
        self.highestRiskDebtTypeRawValue = analytics.highestRiskItem?.debtType.rawValue
        self.highestRiskDebtName = analytics.highestRiskItem?.debtName ?? ""
        self.highestRiskAmount = analytics.highestRiskItem?.overdueAmount ?? 0
        self.highestRiskOverdueDays = analytics.highestRiskItem?.overdueDays ?? 0
    }

    func update(period: AnalyticsPeriod, analytics: OverdueAnalytics, generatedAt: Date) {
        self.periodStart = period.periodStart
        self.periodEndExclusive = period.periodEndExclusive
        self.generatedAt = generatedAt
        self.currentOverdueDebtCount = analytics.currentOverdueDebtCount
        self.currentOverduePeriodCount = analytics.currentOverduePeriodCount
        self.currentOverdueTotalAmount = analytics.currentOverdueTotalAmount
        self.creditCardMinimumPaymentGap = analytics.creditCardMinimumPaymentGap
        self.loanOverdueAmount = analytics.loanOverdueAmount
        self.personalLendingPastDueAmount = analytics.personalLendingPastDueAmount
        self.overdueAmount1To30Days = analytics.overdueAmount1To30Days
        self.overdueAmount31To90Days = analytics.overdueAmount31To90Days
        self.overdueAmountOver90Days = analytics.overdueAmountOver90Days
        self.overdueFeeTotalAmount = analytics.overdueFeeTotalAmount
        self.penaltyInterestTotalAmount = analytics.penaltyInterestTotalAmount
        self.riskLevelRawValue = analytics.riskLevel.rawValue
        self.highestRiskDebtID = analytics.highestRiskItem?.debtID
        self.highestRiskDebtTypeRawValue = analytics.highestRiskItem?.debtType.rawValue
        self.highestRiskDebtName = analytics.highestRiskItem?.debtName ?? ""
        self.highestRiskAmount = analytics.highestRiskItem?.overdueAmount ?? 0
        self.highestRiskOverdueDays = analytics.highestRiskItem?.overdueDays ?? 0
    }
}

@Model
final class CostAnalyticsSnapshot {
    var id: UUID
    var snapshotTypeRawValue: String
    var asOfDate: Date
    var periodStart: Date
    var periodEndExclusive: Date
    var generatedAt: Date
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
    var userProvidedCostAmount: Decimal
    var fallbackCostAmount: Decimal
    var scheduledPlanCostAmount: Decimal
    var mixedCostAmount: Decimal
    var creditCardBreakdownConflictCount: Int

    var snapshotType: AnalyticsSnapshotType {
        get { .value(from: snapshotTypeRawValue, default: .cost) }
        set { snapshotTypeRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        asOfDate: Date,
        period: AnalyticsPeriod,
        analytics: CostAnalytics,
        generatedAt: Date
    ) {
        self.id = id
        self.snapshotTypeRawValue = AnalyticsSnapshotType.cost.rawValue
        self.asOfDate = asOfDate
        self.periodStart = period.periodStart
        self.periodEndExclusive = period.periodEndExclusive
        self.generatedAt = generatedAt
        self.totalCostAmount = analytics.totalCostAmount
        self.totalInterestAmount = analytics.totalInterestAmount
        self.totalInstallmentFeeAmount = analytics.totalInstallmentFeeAmount
        self.totalOverdueFeeAmount = analytics.totalOverdueFeeAmount
        self.totalPenaltyInterestAmount = analytics.totalPenaltyInterestAmount
        self.otherFeeAmount = analytics.otherFeeAmount
        self.creditCardCostAmount = analytics.creditCardCostAmount
        self.loanCostAmount = analytics.loanCostAmount
        self.personalLendingInterestAmount = analytics.personalLendingInterestAmount
        self.loanAppAllocatedPaidInterestAmount = analytics.loanAppAllocatedPaidInterestAmount
        self.userProvidedCostAmount = analytics.sourceAmounts.userProvidedCostAmount
        self.fallbackCostAmount = analytics.sourceAmounts.fallbackCostAmount
        self.scheduledPlanCostAmount = analytics.sourceAmounts.scheduledPlanCostAmount
        self.mixedCostAmount = analytics.sourceAmounts.mixedCostAmount
        self.creditCardBreakdownConflictCount = analytics.creditCardBreakdownConflictCount
    }

    func update(period: AnalyticsPeriod, analytics: CostAnalytics, generatedAt: Date) {
        self.periodStart = period.periodStart
        self.periodEndExclusive = period.periodEndExclusive
        self.generatedAt = generatedAt
        self.totalCostAmount = analytics.totalCostAmount
        self.totalInterestAmount = analytics.totalInterestAmount
        self.totalInstallmentFeeAmount = analytics.totalInstallmentFeeAmount
        self.totalOverdueFeeAmount = analytics.totalOverdueFeeAmount
        self.totalPenaltyInterestAmount = analytics.totalPenaltyInterestAmount
        self.otherFeeAmount = analytics.otherFeeAmount
        self.creditCardCostAmount = analytics.creditCardCostAmount
        self.loanCostAmount = analytics.loanCostAmount
        self.personalLendingInterestAmount = analytics.personalLendingInterestAmount
        self.loanAppAllocatedPaidInterestAmount = analytics.loanAppAllocatedPaidInterestAmount
        self.userProvidedCostAmount = analytics.sourceAmounts.userProvidedCostAmount
        self.fallbackCostAmount = analytics.sourceAmounts.fallbackCostAmount
        self.scheduledPlanCostAmount = analytics.sourceAmounts.scheduledPlanCostAmount
        self.mixedCostAmount = analytics.sourceAmounts.mixedCostAmount
        self.creditCardBreakdownConflictCount = analytics.creditCardBreakdownConflictCount
    }
}

@Model
final class AnalyticsInvalidationState {
    var id: UUID
    var isDebtAnalyticsDirty: Bool
    var isPaymentAnalyticsDirty: Bool
    var isOverdueAnalyticsDirty: Bool
    var isCostAnalyticsDirty: Bool
    var lastAnalyticsGeneratedDate: Date?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        isDebtAnalyticsDirty: Bool = true,
        isPaymentAnalyticsDirty: Bool = true,
        isOverdueAnalyticsDirty: Bool = true,
        isCostAnalyticsDirty: Bool = true,
        lastAnalyticsGeneratedDate: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.isDebtAnalyticsDirty = isDebtAnalyticsDirty
        self.isPaymentAnalyticsDirty = isPaymentAnalyticsDirty
        self.isOverdueAnalyticsDirty = isOverdueAnalyticsDirty
        self.isCostAnalyticsDirty = isCostAnalyticsDirty
        self.lastAnalyticsGeneratedDate = lastAnalyticsGeneratedDate
        self.updatedAt = updatedAt
    }
}
