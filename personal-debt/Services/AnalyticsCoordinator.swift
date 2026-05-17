import Foundation
import SwiftData

@MainActor
final class AnalyticsCoordinator {
    private let modelContext: ModelContext
    private let debtAnalyticsService: DebtAnalyticsService
    private let paymentAnalyticsService: PaymentAnalyticsService
    private let overdueAnalyticsService: OverdueAnalyticsService
    private let costAnalyticsService: CostAnalyticsService
    private let invalidationStore: AnalyticsInvalidationStore
    private let datePolicy: DateCalculationPolicy
    private let writeAccessAuthorizer: WriteAccessAuthorizing

    init(
        modelContext: ModelContext,
        debtAnalyticsService: DebtAnalyticsService? = nil,
        paymentAnalyticsService: PaymentAnalyticsService? = nil,
        overdueAnalyticsService: OverdueAnalyticsService? = nil,
        costAnalyticsService: CostAnalyticsService? = nil,
        invalidationStore: AnalyticsInvalidationStore? = nil,
        datePolicy: DateCalculationPolicy? = nil,
        writeAccessAuthorizer: WriteAccessAuthorizing? = nil
    ) {
        self.modelContext = modelContext
        self.debtAnalyticsService = debtAnalyticsService ?? DebtAnalyticsService()
        self.paymentAnalyticsService = paymentAnalyticsService ?? PaymentAnalyticsService()
        self.overdueAnalyticsService = overdueAnalyticsService ?? OverdueAnalyticsService()
        self.costAnalyticsService = costAnalyticsService ?? CostAnalyticsService()
        self.invalidationStore = invalidationStore ?? AnalyticsInvalidationStore(modelContext: modelContext, autosaves: false)
        self.datePolicy = datePolicy ?? .standard
        self.writeAccessAuthorizer = writeAccessAuthorizer ?? UnrestrictedWriteAccessAuthorizer.shared
    }

    func generateSummary(today: Date = Date(), saveSnapshots: Bool = false) throws -> AnalyticsSummary {
        let period = AnalyticsSupport.monthPeriod(containing: today, calendar: datePolicy.calendar)
        let generatedAt = Date()

        let creditCardDebts = try modelContext.fetch(FetchDescriptor<CreditCardDebt>())
        let creditCardStatements = try modelContext.fetch(FetchDescriptor<CreditCardStatement>())
        let creditCardBreakdowns = try modelContext.fetch(FetchDescriptor<CreditCardStatementBreakdown>())
        let creditCardPayments = try modelContext.fetch(FetchDescriptor<CreditCardPaymentRecord>())

        let loanDebts = try modelContext.fetch(FetchDescriptor<LoanDebt>())
        let loanPlans = try modelContext.fetch(FetchDescriptor<LoanRepaymentPlan>())
        let loanPayments = try modelContext.fetch(FetchDescriptor<LoanPaymentRecord>())
        let loanOverdues = try modelContext.fetch(FetchDescriptor<LoanOverdueRecord>())

        let personalLendingDebts = try modelContext.fetch(FetchDescriptor<PersonalLendingDebt>())
        let personalLendingPlans = try modelContext.fetch(FetchDescriptor<PersonalLendingPlan>())
        let personalLendingPayments = try modelContext.fetch(FetchDescriptor<PersonalLendingPaymentRecord>())
        let personalLendingOverdues = try modelContext.fetch(FetchDescriptor<PersonalLendingOverdueRecord>())

        let debtAnalytics = debtAnalyticsService.generate(
            creditCardDebts: creditCardDebts,
            creditCardStatements: creditCardStatements,
            loanDebts: loanDebts,
            loanPlans: loanPlans,
            personalLendingDebts: personalLendingDebts,
            personalLendingPlans: personalLendingPlans,
            period: period
        )
        let paymentAnalytics = paymentAnalyticsService.generate(
            creditCardDebts: creditCardDebts,
            creditCardPayments: creditCardPayments,
            loanDebts: loanDebts,
            loanPayments: loanPayments,
            personalLendingDebts: personalLendingDebts,
            personalLendingPayments: personalLendingPayments,
            period: period
        )
        let overdueAnalytics = overdueAnalyticsService.generate(
            creditCardDebts: creditCardDebts,
            creditCardStatements: creditCardStatements,
            creditCardBreakdowns: creditCardBreakdowns,
            loanDebts: loanDebts,
            loanPlans: loanPlans,
            loanOverdues: loanOverdues,
            personalLendingDebts: personalLendingDebts,
            personalLendingPlans: personalLendingPlans,
            personalLendingOverdues: personalLendingOverdues,
            today: today
        )
        let costAnalytics = costAnalyticsService.generate(
            creditCardDebts: creditCardDebts,
            creditCardStatements: creditCardStatements,
            creditCardBreakdowns: creditCardBreakdowns,
            loanDebts: loanDebts,
            loanPlans: loanPlans,
            loanOverdues: loanOverdues,
            personalLendingDebts: personalLendingDebts,
            personalLendingPlans: personalLendingPlans
        )

        let fixedPaidAmount = paymentAnalytics.loanCumulativePaidAmount + paymentAnalytics.personalLendingCumulativePaidAmount
        let summary = AnalyticsSummary(
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
            generatedAt: generatedAt
        )

        if saveSnapshots {
            try writeAccessAuthorizer.requireWriteAccess()
            try upsertSnapshots(summary: summary, period: period, asOfDate: datePolicy.startOfDay(today))
            try invalidationStore.markAnalyticsGenerated(on: datePolicy.startOfDay(today))
            try modelContext.save()
        }

        return summary
    }

    private func upsertSnapshots(summary: AnalyticsSummary, period: AnalyticsPeriod, asOfDate: Date) throws {
        let debtSnapshots = try modelContext.fetch(FetchDescriptor<DebtAnalyticsSnapshot>())
        if let existing = debtSnapshots.first(where: { matches($0.asOfDate, $0.periodStart, $0.periodEndExclusive, asOfDate: asOfDate, period: period) }) {
            existing.update(period: period, analytics: summary.debtAnalytics, generatedAt: summary.generatedAt)
        } else {
            modelContext.insert(
                DebtAnalyticsSnapshot(
                    asOfDate: asOfDate,
                    period: period,
                    analytics: summary.debtAnalytics,
                    generatedAt: summary.generatedAt
                )
            )
        }

        let paymentSnapshots = try modelContext.fetch(FetchDescriptor<PaymentAnalyticsSnapshot>())
        if let existing = paymentSnapshots.first(where: { matches($0.asOfDate, $0.periodStart, $0.periodEndExclusive, asOfDate: asOfDate, period: period) }) {
            existing.update(period: period, analytics: summary.paymentAnalytics, generatedAt: summary.generatedAt)
        } else {
            modelContext.insert(
                PaymentAnalyticsSnapshot(
                    asOfDate: asOfDate,
                    period: period,
                    analytics: summary.paymentAnalytics,
                    generatedAt: summary.generatedAt
                )
            )
        }

        let overdueSnapshots = try modelContext.fetch(FetchDescriptor<OverdueAnalyticsSnapshot>())
        if let existing = overdueSnapshots.first(where: { matches($0.asOfDate, $0.periodStart, $0.periodEndExclusive, asOfDate: asOfDate, period: period) }) {
            existing.update(period: period, analytics: summary.overdueAnalytics, generatedAt: summary.generatedAt)
        } else {
            modelContext.insert(
                OverdueAnalyticsSnapshot(
                    asOfDate: asOfDate,
                    period: period,
                    analytics: summary.overdueAnalytics,
                    generatedAt: summary.generatedAt
                )
            )
        }

        let costSnapshots = try modelContext.fetch(FetchDescriptor<CostAnalyticsSnapshot>())
        if let existing = costSnapshots.first(where: { matches($0.asOfDate, $0.periodStart, $0.periodEndExclusive, asOfDate: asOfDate, period: period) }) {
            existing.update(period: period, analytics: summary.costAnalytics, generatedAt: summary.generatedAt)
        } else {
            modelContext.insert(
                CostAnalyticsSnapshot(
                    asOfDate: asOfDate,
                    period: period,
                    analytics: summary.costAnalytics,
                    generatedAt: summary.generatedAt
                )
            )
        }
    }

    private func matches(
        _ snapshotAsOfDate: Date,
        _ snapshotPeriodStart: Date,
        _ snapshotPeriodEndExclusive: Date,
        asOfDate: Date,
        period: AnalyticsPeriod
    ) -> Bool {
        datePolicy.isSameDay(snapshotAsOfDate, asOfDate)
            && snapshotPeriodStart == period.periodStart
            && snapshotPeriodEndExclusive == period.periodEndExclusive
    }
}
