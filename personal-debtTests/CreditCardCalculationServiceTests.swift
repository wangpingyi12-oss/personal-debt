import Foundation
import Testing
@testable import personal_debt

// MARK: - CreditCardCalculationServiceTests

struct CreditCardCalculationServiceTests {

    // MARK: Helpers

    private static let rule = CreditCardCalculationRule()

    private static func makeCalendar() -> Calendar { Calendar.current }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        return makeCalendar().date(from: c)!
    }

    // MARK: - daysBetween

    @Test func daysBetweenSameDay() {
        let d = date(2026, 5, 1)
        #expect(CreditCardCalculationService.daysBetween(d, d) == 0)
    }

    @Test func daysBetweenPositive() {
        let start = date(2026, 5, 1)
        let end = date(2026, 5, 31)
        #expect(CreditCardCalculationService.daysBetween(start, end) == 30)
    }

    @Test func daysBetweenNegativeReturnsZero() {
        let start = date(2026, 5, 31)
        let end = date(2026, 5, 1)
        #expect(CreditCardCalculationService.daysBetween(start, end) == 0)
    }

    // MARK: - calculateSystemMinimumPayment

    @Test func minimumPaymentDefaultRatioTenPercent() {
        // normalAmount = 1000, installmentAmount = 200
        // expected = 200 + 1000 * 0.10 = 300
        let result = CreditCardCalculationService.calculateSystemMinimumPayment(
            normalAmount: 1000,
            installmentAmount: 200,
            rule: rule
        )
        #expect(result == 300)
    }

    @Test func minimumPaymentWithCustomRatio() {
        var customRule = CreditCardCalculationRule()
        customRule.minimumPaymentRatio = 0.05
        // normalAmount = 2000, installmentAmount = 0
        // expected = 0 + 2000 * 0.05 = 100
        let result = CreditCardCalculationService.calculateSystemMinimumPayment(
            normalAmount: 2000,
            installmentAmount: 0,
            rule: customRule
        )
        #expect(result == 100)
    }

    // MARK: - determineStatementStatus

    @Test func statusPaidWhenFullyPaid() {
        let dueDate = date(2026, 5, 25)
        let today = date(2026, 5, 20)
        let status = CreditCardCalculationService.determineStatementStatus(
            statementAmount: 1000,
            minimumPaymentAmount: 100,
            paidAmount: 1000,
            dueDate: dueDate,
            today: today
        )
        #expect(status == .paid)
    }

    @Test func statusPaidEvenAfterDueDate() {
        let dueDate = date(2026, 5, 25)
        let today = date(2026, 6, 1)
        let status = CreditCardCalculationService.determineStatementStatus(
            statementAmount: 1000,
            minimumPaymentAmount: 100,
            paidAmount: 1000,
            dueDate: dueDate,
            today: today
        )
        #expect(status == .paid)
    }

    @Test func statusPendingWhenNothingPaidBeforeDue() {
        let dueDate = date(2026, 5, 25)
        let today = date(2026, 5, 20)
        let status = CreditCardCalculationService.determineStatementStatus(
            statementAmount: 1000,
            minimumPaymentAmount: 100,
            paidAmount: 0,
            dueDate: dueDate,
            today: today
        )
        #expect(status == .pending)
    }

    @Test func statusPartiallyPaidBeforeDueDate() {
        let dueDate = date(2026, 5, 25)
        let today = date(2026, 5, 20)
        let status = CreditCardCalculationService.determineStatementStatus(
            statementAmount: 1000,
            minimumPaymentAmount: 100,
            paidAmount: 500,
            dueDate: dueDate,
            today: today
        )
        #expect(status == .partiallyPaid)
    }

    @Test func statusCarriedForwardAfterDueDateWithMinimumPaid() {
        let dueDate = date(2026, 5, 25)
        let today = date(2026, 5, 26)
        // paidAmount (300) >= minimumPayment (100) but < statementAmount (1000)
        let status = CreditCardCalculationService.determineStatementStatus(
            statementAmount: 1000,
            minimumPaymentAmount: 100,
            paidAmount: 300,
            dueDate: dueDate,
            today: today
        )
        #expect(status == .carriedForward)
    }

    @Test func statusOverdueAfterDueDateBelowMinimum() {
        let dueDate = date(2026, 5, 25)
        let today = date(2026, 5, 26)
        // paidAmount (50) < minimumPayment (100)
        let status = CreditCardCalculationService.determineStatementStatus(
            statementAmount: 1000,
            minimumPaymentAmount: 100,
            paidAmount: 50,
            dueDate: dueDate,
            today: today
        )
        #expect(status == .overdue)
    }

    @Test func statusOverdueWhenNothingPaidAfterDueDate() {
        let dueDate = date(2026, 5, 25)
        let today = date(2026, 5, 26)
        let status = CreditCardCalculationService.determineStatementStatus(
            statementAmount: 1000,
            minimumPaymentAmount: 100,
            paidAmount: 0,
            dueDate: dueDate,
            today: today
        )
        #expect(status == .overdue)
    }

    // MARK: - calculateRevolvingInterest

    @Test func revolvingInterestZeroWhenDisabled() {
        var customRule = CreditCardCalculationRule()
        customRule.revolvingInterestEnabled = false
        let interest = CreditCardCalculationService.calculateRevolvingInterest(
            unpaidAmount: 1000,
            rule: customRule,
            billingDate: date(2026, 5, 1),
            today: date(2026, 5, 31)
        )
        #expect(interest == 0)
    }

    @Test func revolvingInterestCalculation() {
        // unpaid = 1000, dailyRate = 0.0005, days = 30 → 1000 * 0.0005 * 30 = 15
        let interest = CreditCardCalculationService.calculateRevolvingInterest(
            unpaidAmount: 1000,
            rule: rule,
            billingDate: date(2026, 5, 1),
            today: date(2026, 5, 31)
        )
        #expect(interest == 15.0)
    }

    @Test func revolvingInterestZeroWhenUnpaidAmountIsZero() {
        let interest = CreditCardCalculationService.calculateRevolvingInterest(
            unpaidAmount: 0,
            rule: rule,
            billingDate: date(2026, 5, 1),
            today: date(2026, 5, 31)
        )
        #expect(interest == 0)
    }

    // MARK: - calculateOverdueFee

    @Test func overdueFeePercentageWithMinimumAboveFloor() {
        // overdueAmount = 10000, rate = 0.005 → 50 >= minimumFee (25) → 50
        let fee = CreditCardCalculationService.calculateOverdueFee(
            overdueAmount: 10000,
            rule: rule
        )
        #expect(fee == 50.0)
    }

    @Test func overdueFeePercentageWithMinimumBelowFloor() {
        // overdueAmount = 100, rate = 0.005 → 0.5 < minimumFee (25) → 25
        let fee = CreditCardCalculationService.calculateOverdueFee(
            overdueAmount: 100,
            rule: rule
        )
        #expect(fee == 25.0)
    }

    @Test func overdueFeeFixed() {
        var customRule = CreditCardCalculationRule()
        customRule.overdueFeeType = .fixed
        customRule.fixedOverdueFee = 50
        let fee = CreditCardCalculationService.calculateOverdueFee(
            overdueAmount: 10000,
            rule: customRule
        )
        #expect(fee == 50.0)
    }

    @Test func overdueFeeNone() {
        var customRule = CreditCardCalculationRule()
        customRule.overdueFeeType = .none
        let fee = CreditCardCalculationService.calculateOverdueFee(
            overdueAmount: 10000,
            rule: customRule
        )
        #expect(fee == 0)
    }

    // MARK: - calculatePenaltyInterest

    @Test func penaltyInterestCalculation() {
        // base = 1000, dailyRate = 0.0005, days = 30 → 15
        let penalty = CreditCardCalculationService.calculatePenaltyInterest(
            base: 1000,
            rule: rule,
            billingDate: date(2026, 5, 1),
            today: date(2026, 5, 31)
        )
        #expect(penalty == 15.0)
    }

    @Test func penaltyInterestZeroBaseReturnsZero() {
        let penalty = CreditCardCalculationService.calculatePenaltyInterest(
            base: 0,
            rule: rule,
            billingDate: date(2026, 5, 1),
            today: date(2026, 5, 31)
        )
        #expect(penalty == 0)
    }

    // MARK: - calculateFallbackStatementAmount

    @Test func fallbackStatementAmountComputedCorrectly() {
        // previousUnpaid = 500, overdueFee = 25, interest = 15, installment = 200
        // normalFallback = 500 + 25 + 15 = 540
        // total = 540 + 200 = 740
        let amount = CreditCardCalculationService.calculateFallbackStatementAmount(
            previousUnpaidAmount: 500,
            overdueFee: 25,
            interestOrPenalty: 15,
            currentInstallmentAmount: 200
        )
        #expect(amount == 740.0)
    }

    // MARK: - calculateFallbackMinimumPayment

    @Test func fallbackMinimumPaymentComputedCorrectly() {
        // fallbackNormal = 540, installment = 200, ratio = 0.10
        // expected = 200 + 540 * 0.10 = 254
        let minimum = CreditCardCalculationService.calculateFallbackMinimumPayment(
            fallbackNormalAmount: 540,
            installmentAmount: 200,
            rule: rule
        )
        #expect(minimum == 254.0)
    }

    // MARK: - penaltyBase

    @Test func penaltyBaseUsesUnpaidAmountByDefault() {
        let base = CreditCardCalculationService.penaltyBase(
            unpaidAmount: 800,
            statementAmount: 1000,
            rule: rule
        )
        #expect(base == 800)
    }

    @Test func penaltyBaseUsesStatementAmountWhenConfigured() {
        var customRule = CreditCardCalculationRule()
        customRule.penaltyBaseType = .statementAmount
        let base = CreditCardCalculationService.penaltyBase(
            unpaidAmount: 800,
            statementAmount: 1000,
            rule: customRule
        )
        #expect(base == 1000)
    }

    // MARK: - CreditCardInstallmentPlan equal-principal-equal-interest

    @Test func installmentPlanEqualPrincipalEqualInterest() {
        let plan = CreditCardInstallmentPlan(
            totalPrincipal: 3000,
            totalFee: 300,
            totalInterest: 150,
            totalPeriods: 3,
            startBillingDate: date(2026, 5, 1)
        )
        #expect(plan.perPeriodPrincipal == 1000)
        #expect(plan.perPeriodFee == 100)
        #expect(plan.perPeriodInterest == 50)
    }

    @Test func installmentPlanGuardsAgainstZeroPeriods() {
        let plan = CreditCardInstallmentPlan(
            totalPrincipal: 3000,
            totalFee: 300,
            totalInterest: 150,
            totalPeriods: 0,
            startBillingDate: date(2026, 5, 1)
        )
        // totalPeriods is clamped to 1 in the model init
        #expect(plan.perPeriodPrincipal == 3000)
        #expect(plan.perPeriodFee == 300)
        #expect(plan.perPeriodInterest == 150)
    }

    // MARK: - repaymentPlanStatus mapping

    @Test func repaymentPlanStatusMapping() {
        #expect(CreditCardCalculationService.repaymentPlanStatus(from: .pending) == .pending)
        #expect(CreditCardCalculationService.repaymentPlanStatus(from: .partiallyPaid) == .partiallyPaid)
        #expect(CreditCardCalculationService.repaymentPlanStatus(from: .paid) == .paid)
        #expect(CreditCardCalculationService.repaymentPlanStatus(from: .carriedForward) == .partiallyPaid)
        #expect(CreditCardCalculationService.repaymentPlanStatus(from: .overdue) == .overdue)
        #expect(CreditCardCalculationService.repaymentPlanStatus(from: .replaced) == .voided)
    }
}
