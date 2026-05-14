import Foundation
import SwiftData

// MARK: - PersonalLendingCalculator

enum PersonalLendingCalculator {

    // MARK: Plan Generation

    /// Builds repayment plan items for the given debt based on its repayment method.
    /// Does not mutate the debt; the caller must assign the result to `debt.planItems`.
    static func buildPlan(for debt: PersonalLendingDebt, calendar: Calendar = .current) -> [PersonalLendingPlanItem] {
        let method = PersonalLendingRepaymentMethod(rawValue: debt.repaymentMethod) ?? .noFixedPlan

        switch method {
        case .noFixedPlan:
            return []

        case .lumpSumAtMaturity:
            guard let endDate = debt.endDate else { return [] }
            let item = PersonalLendingPlanItem(
                sequence: 1,
                dueDate: endDate,
                principalDue: debt.principal,
                interestDue: debt.totalInterest,
                totalDue: debt.totalAmountDue
            )
            return [item]

        case .equalInstallments:
            return buildEqualInstallmentsPlan(
                principal: debt.principal,
                totalInterest: debt.totalInterest,
                totalAmountDue: debt.totalAmountDue,
                startDate: debt.startDate,
                monthlyPaymentDay: debt.monthlyPaymentDay,
                totalPeriods: debt.totalPeriods,
                calendar: calendar
            )
        }
    }

    /// Generates equal-installments plan items.
    static func buildEqualInstallmentsPlan(
        principal: Double,
        totalInterest: Double,
        totalAmountDue: Double,
        startDate: Date,
        monthlyPaymentDay: Int,
        totalPeriods: Int,
        calendar: Calendar = .current
    ) -> [PersonalLendingPlanItem] {
        guard totalPeriods > 0, principal > 0 else { return [] }

        let dates = paymentDates(
            startDate: startDate,
            monthlyPaymentDay: monthlyPaymentDay,
            periods: totalPeriods,
            calendar: calendar
        )

        // Distribute principal and interest using round-half-up for first N-1 periods;
        // last period absorbs the remainder to ensure exact totals.
        let regularPrincipal = roundHalfUp(principal / Double(totalPeriods))
        let regularInterest = roundHalfUp(totalInterest / Double(totalPeriods))

        var items: [PersonalLendingPlanItem] = []
        var principalAccum = 0.0
        var interestAccum = 0.0

        for i in 0..<totalPeriods {
            let sequence = i + 1
            let dueDate = dates[i]
            let pDue: Double
            let iDue: Double

            if sequence == totalPeriods {
                // Last period: absorb rounding difference
                pDue = roundHalfUp(principal - principalAccum)
                iDue = roundHalfUp(totalInterest - interestAccum)
            } else {
                pDue = regularPrincipal
                iDue = regularInterest
                principalAccum += pDue
                interestAccum += iDue
            }

            let total = roundHalfUp(pDue + iDue)
            items.append(PersonalLendingPlanItem(
                sequence: sequence,
                dueDate: dueDate,
                principalDue: pDue,
                interestDue: iDue,
                totalDue: total
            ))
        }
        return items
    }

    // MARK: Date Helpers

    /// Returns the first payment date: the first occurrence of `monthlyPaymentDay` that
    /// falls on or after `startDate` (exclusive of same day — i.e. on `startDate.day < paymentDay`
    /// the same month works; otherwise the next month).
    static func firstPaymentDate(startDate: Date, monthlyPaymentDay: Int, calendar: Calendar = .current) -> Date {
        let startComponents = calendar.dateComponents([.year, .month, .day], from: startDate)
        let startDay = startComponents.day ?? 1
        let year = startComponents.year ?? 2000
        let month = startComponents.month ?? 1
        let clampedDay = min(max(monthlyPaymentDay, 1), 31)

        if startDay < clampedDay {
            // Same month – try to place payment on `clampedDay` of this month
            return dateInMonth(year: year, month: month, day: clampedDay, calendar: calendar)
        } else {
            // Next month
            let nextMonth = month % 12 + 1
            let nextYear = month == 12 ? year + 1 : year
            return dateInMonth(year: nextYear, month: nextMonth, day: clampedDay, calendar: calendar)
        }
    }

    /// Returns an array of `periods` payment dates starting from the first payment date.
    static func paymentDates(startDate: Date, monthlyPaymentDay: Int, periods: Int, calendar: Calendar = .current) -> [Date] {
        let first = firstPaymentDate(startDate: startDate, monthlyPaymentDay: monthlyPaymentDay, calendar: calendar)
        var dates: [Date] = [first]

        let firstComponents = calendar.dateComponents([.year, .month], from: first)
        var year = firstComponents.year ?? 2000
        var month = firstComponents.month ?? 1

        for _ in 1..<periods {
            month += 1
            if month > 12 { month = 1; year += 1 }
            dates.append(dateInMonth(year: year, month: month, day: monthlyPaymentDay, calendar: calendar))
        }
        return dates
    }

    /// Returns a date for the given year/month/day, clamping to the last day of the month if the
    /// day doesn't exist (e.g. day=31 in April → April 30).
    static func dateInMonth(year: Int, month: Int, day: Int, calendar: Calendar = .current) -> Date {
        guard let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return Date()
        }
        let range = calendar.range(of: .day, in: .month, for: firstOfMonth)!
        let safeDay = min(max(day, 1), range.upperBound - 1)
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = safeDay
        return calendar.date(from: components) ?? firstOfMonth
    }

    // MARK: Full Recalculate

    /// Full recalculation: resets all plan/debt amounts, replays all transactions in canonical order,
    /// rebuilds allocations (when plan exists), then updates statuses and past-due stats.
    /// Caller is responsible for calling `context.save()` after this returns.
    @MainActor
    static func fullRecalculate(debt: PersonalLendingDebt, context: ModelContext, asOf date: Date = .now) {
        let method = PersonalLendingRepaymentMethod(rawValue: debt.repaymentMethod) ?? .noFixedPlan
        let hasPlan = (method != .noFixedPlan)

        // 1. Delete all allocation records for this debt
        for allocation in debt.allocations {
            context.delete(allocation)
        }
        debt.allocations = []

        // 2. Reset plan items
        for item in debt.planItems {
            item.paidAmount = 0
            item.remainingAmount = item.totalDue
            item.state = RecordState.pending.rawValue
        }

        // 3. Reset debt amounts
        debt.paidAmount = 0
        debt.remainingAmount = debt.totalAmountDue

        // 4. Sort transactions: occurredAt ASC, then createdAt ASC, then id (string) ASC
        let sortedTransactions = debt.transactions
            .filter { $0.isValid }
            .sorted { a, b in
                if a.occurredAt != b.occurredAt { return a.occurredAt < b.occurredAt }
                if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
                return a.id.uuidString < b.id.uuidString
            }

        // 5. Sort plan items for application: dueDate ASC, then sequence ASC
        let sortedPlans = debt.planItems.sorted { a, b in
            if a.dueDate != b.dueDate { return a.dueDate < b.dueDate }
            return a.sequence < b.sequence
        }

        // 6. Replay each transaction
        for tx in sortedTransactions {
            debt.paidAmount += tx.amount

            if hasPlan {
                var txRemaining = tx.amount
                for plan in sortedPlans {
                    guard txRemaining > 0.001 else { break }
                    let contribution = min(plan.remainingAmount, txRemaining)
                    guard contribution > 0.001 else { continue }
                    plan.paidAmount = roundHalfUp(plan.paidAmount + contribution)
                    plan.remainingAmount = roundHalfUp(plan.remainingAmount - contribution)
                    txRemaining -= contribution

                    let allocation = PersonalLendingAllocation(
                        allocatedAmount: roundHalfUp(contribution),
                        transaction: tx,
                        planItem: plan,
                        debt: debt
                    )
                    context.insert(allocation)
                    debt.allocations.append(allocation)
                }
            }
        }

        debt.paidAmount = roundHalfUp(debt.paidAmount)
        debt.remainingAmount = roundHalfUp(max(0, debt.totalAmountDue - debt.paidAmount))

        // 7. Update plan item states
        for item in debt.planItems {
            item.state = resolvePlanStatus(for: item)
        }

        // 8. Update debt status
        debt.status = resolveDebtStatus(for: debt)

        // 9. Update past-due stats
        let (pdAmount, pdPlanCount, pdDebtCount) = computePastDueStats(debt: debt, asOf: date)
        debt.pastDueScheduledAmount = pdAmount
        debt.pastDuePlanCount = pdPlanCount
        debt.pastDueDebtCount = pdDebtCount
    }

    // MARK: Status Resolution

    /// Resolves repayment plan item status purely from amounts.
    static func resolvePlanStatus(for item: PersonalLendingPlanItem) -> String {
        if item.remainingAmount <= 0.001 {
            return RecordState.paid.rawValue
        }
        if item.paidAmount > 0.001 {
            return RecordState.partiallyPaid.rawValue
        }
        return RecordState.pending.rawValue
    }

    /// Resolves debt lifecycle status purely from amounts.
    static func resolveDebtStatus(for debt: PersonalLendingDebt) -> String {
        if debt.remainingAmount <= 0.001 {
            return DebtLifecycleStatus.paidOff.rawValue
        }
        if debt.paidAmount > 0.001 {
            return DebtLifecycleStatus.partiallyPaid.rawValue
        }
        return DebtLifecycleStatus.active.rawValue
    }

    // MARK: Past-Due Statistics

    /// Computes 已过约定日未还 statistics as of `date`.
    static func computePastDueStats(
        debt: PersonalLendingDebt,
        asOf date: Date
    ) -> (amount: Double, planCount: Int, debtCount: Int) {
        let method = PersonalLendingRepaymentMethod(rawValue: debt.repaymentMethod) ?? .noFixedPlan

        if method == .noFixedPlan {
            guard let endDate = debt.endDate, date > endDate, debt.remainingAmount > 0.001 else {
                return (0, 0, 0)
            }
            return (debt.remainingAmount, 0, 1)
        }

        // Has plan: count plan items whose dueDate has passed and still have remaining
        var pastDueAmount = 0.0
        var pastDuePlanCount = 0
        for item in debt.planItems {
            if item.dueDate < date && item.remainingAmount > 0.001 {
                pastDueAmount += item.remainingAmount
                pastDuePlanCount += 1
            }
        }
        let debtCount = pastDuePlanCount > 0 ? 1 : 0
        return (roundHalfUp(pastDueAmount), pastDuePlanCount, debtCount)
    }

    // MARK: Validation

    enum ValidationError: LocalizedError {
        case invalidAmount
        case exceedsRemainingAmount
        case interestRequiresPlan
        case noFixedPlanMustBeInterestFree
        case missingEndDate
        case endDateBeforeStartDate
        case invalidMonthlyPaymentDay
        case invalidTotalPeriods
        case interestMustBePositive

        var errorDescription: String? {
            switch self {
            case .invalidAmount: return "还款金额必须大于 0"
            case .exceedsRemainingAmount: return "还款金额不能超过当前剩余应还金额"
            case .interestRequiresPlan: return "有息债务必须选择有还款计划的还款方式"
            case .noFixedPlanMustBeInterestFree: return "无固定还款计划只支持无息"
            case .missingEndDate: return "约定结束日期必填"
            case .endDateBeforeStartDate: return "约定结束日期不能早于借款日期"
            case .invalidMonthlyPaymentDay: return "每月还款日必须在 1 到 31 之间"
            case .invalidTotalPeriods: return "总期数必须大于 0"
            case .interestMustBePositive: return "有息时固定总利息必须大于 0"
            }
        }
    }

    static func validateDebt(
        principal: Double,
        hasInterest: Bool,
        totalInterest: Double,
        repaymentMethod: PersonalLendingRepaymentMethod,
        startDate: Date,
        endDate: Date?,
        monthlyPaymentDay: Int,
        totalPeriods: Int
    ) throws {
        if repaymentMethod == .noFixedPlan && hasInterest {
            throw ValidationError.noFixedPlanMustBeInterestFree
        }
        if hasInterest && totalInterest <= 0 {
            throw ValidationError.interestMustBePositive
        }
        if repaymentMethod == .lumpSumAtMaturity {
            guard let end = endDate else { throw ValidationError.missingEndDate }
            if end < startDate { throw ValidationError.endDateBeforeStartDate }
        }
        if repaymentMethod == .equalInstallments {
            if monthlyPaymentDay < 1 || monthlyPaymentDay > 31 { throw ValidationError.invalidMonthlyPaymentDay }
            if totalPeriods <= 0 { throw ValidationError.invalidTotalPeriods }
        }
    }

    static func validatePayment(amount: Double, debt: PersonalLendingDebt) throws {
        if amount <= 0 { throw ValidationError.invalidAmount }
        if amount > debt.remainingAmount + 0.001 { throw ValidationError.exceedsRemainingAmount }
    }

    // MARK: Strategy Cost Rate

    /// Simple cost rate for avalanche strategy: totalInterest / principal.
    /// Returns 0 for interest-free debts. No annualisation.
    static func simpleCostRate(for debt: PersonalLendingDebt) -> Double {
        guard debt.principal > 0 else { return 0 }
        return debt.totalInterest / debt.principal
    }

    // MARK: Next Due Info

    struct NextDueInfo {
        let dueDate: Date?
        let dueAmount: Double
    }

    static func nextDueInfo(for debt: PersonalLendingDebt) -> NextDueInfo {
        let method = PersonalLendingRepaymentMethod(rawValue: debt.repaymentMethod) ?? .noFixedPlan
        if method == .noFixedPlan {
            return NextDueInfo(dueDate: debt.endDate, dueAmount: debt.endDate != nil ? debt.remainingAmount : 0)
        }
        // Find earliest plan item with remaining > 0
        if let next = debt.planItems
            .filter({ $0.remainingAmount > 0.001 })
            .min(by: { $0.dueDate < $1.dueDate }) {
            return NextDueInfo(dueDate: next.dueDate, dueAmount: next.remainingAmount)
        }
        return NextDueInfo(dueDate: nil, dueAmount: 0)
    }

    // MARK: Rounding

    static func roundHalfUp(_ value: Double) -> Double {
        (value * 100).rounded(.toNearestOrAwayFromZero) / 100
    }
}

