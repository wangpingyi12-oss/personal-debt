#if DEBUG
import Foundation
import SwiftData

@MainActor
struct FortyDebtScenario {
    var settings: AppUserSettings
    var creditCards: [CreditCardDebt]
    var cardRules: [CreditCardCalculationRule]
    var cardStatements: [CreditCardStatement]
    var cardPlans: [CreditCardRepaymentPlan]
    var cardBreakdowns: [CreditCardStatementBreakdown]
    var cardPayments: [CreditCardPaymentRecord]
    var cardOverdues: [CreditCardOverdueRecord]
    var cardInstallments: [CreditCardInstallmentPlan]
    var loans: [LoanDebt]
    var loanPlans: [LoanRepaymentPlan]
    var loanPayments: [LoanPaymentRecord]
    var loanAllocations: [LoanPaymentAllocationDetail]
    var loanOverdues: [LoanOverdueRecord]
    var loanRules: [LoanCalculationRule]
    var personalDebts: [PersonalLendingDebt]
    var personalPlans: [PersonalLendingPlan]
    var personalPayments: [PersonalLendingPaymentRecord]
    var personalAllocations: [PersonalLendingAllocationDetail]
    var personalOverdues: [PersonalLendingOverdueRecord]
    var expected: FortyDebtScenarioExpected

    var allDebtCount: Int {
        creditCards.count + loans.count + personalDebts.count
    }
}

struct FortyDebtScenarioExpected {
    var creditCardCount: Int
    var loanCount: Int
    var personalLendingCount: Int
    var totalDebtCount: Int
    var creditCardRemainingAmount: Decimal
    var loanRemainingAmount: Decimal
    var personalLendingRemainingAmount: Decimal
    var totalRemainingAmount: Decimal
    var currentMonthPlannedRepaymentAmount: Decimal
    var creditCardCurrentStatementAmount: Decimal
    var creditCardCurrentStatementPaidAmount: Decimal
    var currentMonthPaidAmount: Decimal
    var cumulativePaidAmount: Decimal
    var creditCardCurrentMonthPaidAmount: Decimal
    var loanCurrentMonthPaidAmount: Decimal
    var personalLendingCurrentMonthPaidAmount: Decimal
    var currentMonthCreditCardPaymentRecordCount: Int
    var currentMonthFixedPaymentInputCount: Int
    var currentOverdueDebtCount: Int
    var currentOverduePeriodCount: Int
    var currentOverdueTotalAmount: Decimal
    var creditCardMinimumPaymentGap: Decimal
    var creditCardOverdueStatementRemainingAmount: Decimal
    var loanOverdueAmount: Decimal
    var personalLendingPastDueAmount: Decimal
    var overdueFeeTotalAmount: Decimal
    var penaltyInterestTotalAmount: Decimal
    var totalCostAmount: Decimal
    var creditCardCostAmount: Decimal
    var loanCostAmount: Decimal
    var personalLendingInterestAmount: Decimal
    var creditCardBreakdownConflictCount: Int
}

@MainActor
enum FortyDebtScenarioFixtures {
    static let sentinelDebtName = "CC-01 Grocery Visa"

    static func makeScenario(today: Date = Date()) -> FortyDebtScenario {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: today)
        let settings = AppUserSettings(
            onboardingCompleted: true,
            monthlyRepaymentBudget: 50_000,
            currencyCode: "USD",
            languagePreference: .english,
            remindersEnabled: true,
            strategyDataChanged: true,
            createdAt: today,
            updatedAt: today
        )

        var creditCards: [CreditCardDebt] = []
        var cardRules: [CreditCardCalculationRule] = []
        var cardStatements: [CreditCardStatement] = []
        var cardPlans: [CreditCardRepaymentPlan] = []
        var cardBreakdowns: [CreditCardStatementBreakdown] = []
        var cardPayments: [CreditCardPaymentRecord] = []
        var cardOverdues: [CreditCardOverdueRecord] = []
        var cardInstallments: [CreditCardInstallmentPlan] = []

        let cardNames = [
            "Grocery Visa", "Travel Master", "Office Amex", "Fuel Card",
            "Family Reserve", "Online Shopping", "Health Card", "Tuition Card",
            "Home Supplies", "Backup Visa", "Cloud Services", "Dining Card",
            "Utilities Card", "Paid Rewards"
        ]

        for index in 1...14 {
            let statementAmount = Decimal(900 + index * 110)
            let rawPaidAmount: Decimal
            if index == 14 {
                rawPaidAmount = statementAmount
            } else if index % 4 == 0 {
                rawPaidAmount = statementAmount * Decimal(string: "0.20")!
            } else {
                rawPaidAmount = Decimal(index * 25)
            }
            let paidAmount = round(rawPaidAmount)
            let remainingAmount = round(maxDecimal(statementAmount - paidAmount, 0))
            let minimumPayment = index == 14 ? Decimal(0) : round(statementAmount * Decimal(string: "0.10")!)
            let dueDate: Date
            if index <= 4 {
                dueDate = day(-index * 5, from: today, calendar: calendar)
            } else if index <= 8 {
                dueDate = day((index - 4) * 3, from: today, calendar: calendar)
            } else if index <= 11 {
                dueDate = day(25 + index, from: today, calendar: calendar)
            } else {
                dueDate = day(-(index - 8) * 3, from: today, calendar: calendar)
            }
            let billingDate = day(-20, from: dueDate, calendar: calendar)
            let status = cardStatus(
                dueDate: dueDate,
                today: today,
                paidAmount: paidAmount,
                remainingAmount: remainingAmount,
                minimumPayment: minimumPayment
            )
            let debtStatus: DebtStatus = remainingAmount == 0 ? .paidOff : (status == .overdue ? .overdue : .active)
            let debt = CreditCardDebt(
                name: "CC-\(twoDigit(index)) \(cardNames[index - 1])",
                bankName: "Scenario Bank \(index)",
                lastFourDigits: String(format: "%04d", 4100 + index),
                creditLimit: Decimal(5_000 + index * 500),
                note: "Seeded 40-debt UI scenario credit card \(index)",
                billingDay: min(index + 1, 28),
                dueDay: min(index + 15, 28),
                currencyCode: "USD",
                status: debtStatus,
                createdAt: day(-120, from: today, calendar: calendar),
                updatedAt: today
            )
            let rule = CreditCardCalculationRule(
                debtID: debt.id,
                minimumPaymentRatio: Decimal(string: "0.10")!,
                minimumPaymentFloor: 20,
                revolvingDailyRate: Decimal(string: "0.0005")! + Decimal(index) / Decimal(1_000_000),
                overdueFeeRate: Decimal(string: "0.005")!,
                minimumOverdueFee: 25,
                penaltyDailyRate: Decimal(string: "0.0006")!
            )
            let statement = CreditCardStatement(
                debtID: debt.id,
                billingDate: billingDate,
                dueDate: dueDate,
                statementAmount: statementAmount,
                minimumPaymentAmount: minimumPayment,
                minimumPaymentSource: "scenario",
                paidAmount: paidAmount,
                remainingAmount: remainingAmount,
                status: status,
                source: index % 5 == 0 ? .fallback : .userConfirmed,
                createdAt: billingDate,
                updatedAt: today
            )
            let plan = CreditCardRepaymentPlan(
                debtID: debt.id,
                statementID: statement.id,
                dueDate: dueDate,
                scheduledAmount: statementAmount,
                paidAmount: paidAmount,
                remainingAmount: remainingAmount,
                status: planStatus(from: status),
                source: statement.source
            )
            let isMinimumOverdue = dueDate < today && paidAmount < minimumPayment && remainingAmount > 0
            let breakdown = CreditCardStatementBreakdown(
                statementID: statement.id,
                source: statement.source == .fallback ? .fallback : .userProvided,
                normalSpending: maxDecimal(statementAmount - Decimal(index * 12), 0),
                previousCycleRemainingAmount: index % 3 == 0 ? Decimal(index * 20) : 0,
                installmentPrincipal: index % 3 == 0 ? Decimal(60 + index) : 0,
                installmentFee: Decimal(index * 2),
                installmentInterest: Decimal(index * 3),
                revolvingInterest: Decimal(index * 4),
                overdueFee: isMinimumOverdue ? Decimal(index * 5) : 0,
                penaltyInterest: isMinimumOverdue ? Decimal(index * 3) : 0,
                unclassifiedAmount: index % 6 == 0 ? 7 : 0,
                hasBreakdownConflict: index % 6 == 0
            )

            creditCards.append(debt)
            cardRules.append(rule)
            cardStatements.append(statement)
            cardPlans.append(plan)
            cardBreakdowns.append(breakdown)

            if paidAmount > 0 {
                cardPayments.append(
                    CreditCardPaymentRecord(
                        debtID: debt.id,
                        statementID: statement.id,
                        paymentDate: index % 2 == 0 ? day(-index, from: today, calendar: calendar) : day(-45 - index, from: today, calendar: calendar),
                        amount: paidAmount,
                        note: "Scenario card payment \(index)"
                    )
                )
            }

            if isMinimumOverdue {
                cardOverdues.append(
                    CreditCardOverdueRecord(
                        debtID: debt.id,
                        statementID: statement.id,
                        overdueAmount: remainingAmount,
                        overdueFee: Decimal(index * 5),
                        penaltyInterest: Decimal(index * 3),
                        startDate: day(1, from: dueDate, calendar: calendar),
                        systemCalculatedOverdueAmount: remainingAmount,
                        systemCalculatedOverdueFee: Decimal(index * 5),
                        systemCalculatedPenaltyInterest: Decimal(index * 3),
                        updatedAt: today
                    )
                )
            }

            if index % 3 == 0 {
                cardInstallments.append(
                    CreditCardInstallmentPlan(
                        debtID: debt.id,
                        nextBillingDate: billingDate,
                        principalPerTerm: Decimal(60 + index),
                        feePerTerm: Decimal(index * 2),
                        interestPerTerm: Decimal(index * 3),
                        totalTerms: 6,
                        paidTerms: index % 2
                    )
                )
            }
        }

        var loans: [LoanDebt] = []
        var loanPlans: [LoanRepaymentPlan] = []
        var loanPayments: [LoanPaymentRecord] = []
        let loanAllocations: [LoanPaymentAllocationDetail] = []
        var loanOverdues: [LoanOverdueRecord] = []
        var loanRules: [LoanCalculationRule] = []
        let loanMethods: [LoanRepaymentMethod] = [.equalPrincipal, .equalPayment, .interestFirst, .principalAtEnd]

        for index in 1...14 {
            let method = loanMethods[(index - 1) % loanMethods.count]
            let debt = LoanDebt(
                name: "Loan-\(twoDigit(index)) \(loanTitle(method))",
                creditorName: "Scenario Lender \(index)",
                note: "Seeded 40-debt UI scenario loan \(index)",
                entryMode: index % 5 == 0 ? .inProgressLoan : .newLoan,
                repaymentMethod: method,
                originalPrincipal: Decimal(3_000 + index * 400),
                openingPrincipalForManagement: index % 5 == 0 ? Decimal(2_000 + index * 250) : nil,
                annualInterestRate: Decimal(3 + index % 8) / Decimal(100),
                startDate: day(-180, from: today, calendar: calendar),
                managementStartDate: index % 5 == 0 ? day(-60, from: today, calendar: calendar) : nil,
                endDate: day(180 + index * 5, from: today, calendar: calendar),
                repaymentDay: min(5 + index, 28),
                termCount: 12,
                status: index == 14 ? .paidOff : (index <= 5 ? .overdue : .active),
                currencyCode: "USD",
                createdAt: day(-180, from: today, calendar: calendar),
                updatedAt: today
            )
            let rule = LoanCalculationRule(
                debtID: debt.id,
                overdueBaseType: index % 2 == 0 ? .currentRemainingScheduledAmount : .currentUnpaidPrincipal,
                overdueFeeMode: index % 3 == 0 ? .percentage : .fixed,
                fixedOverdueFee: Decimal(15 + index),
                overdueFeeRate: Decimal(string: "0.02")!,
                penaltyInterestMode: .fixedDailyRate,
                fixedPenaltyDailyRate: Decimal(string: "0.0008")!,
                paymentAllocationMode: index % 2 == 0 ? .currentPeriodFirst : .feeFirst,
                createdAt: today,
                updatedAt: today
            )
            let firstDueDate: Date
            if index <= 5 {
                firstDueDate = day(-index * 10, from: today, calendar: calendar)
            } else if index <= 10 {
                firstDueDate = day((index - 5) * 2, from: today, calendar: calendar)
            } else {
                firstDueDate = day(35 + index, from: today, calendar: calendar)
            }
            let secondDueDate = day(30, from: firstDueDate, calendar: calendar)
            let firstPlan = makeLoanPlan(
                debtID: debt.id,
                periodIndex: 1,
                dueDate: firstDueDate,
                scheduledPrincipal: Decimal(300 + index * 20),
                scheduledInterest: Decimal(30 + index),
                remainingPrincipalBeforePayment: Decimal(800 + index * 90)
            )
            let secondPlan = makeLoanPlan(
                debtID: debt.id,
                periodIndex: 2,
                dueDate: secondDueDate,
                scheduledPrincipal: Decimal(400 + index * 25),
                scheduledInterest: Decimal(35 + index),
                remainingPrincipalBeforePayment: Decimal(500 + index * 70)
            )

            if index == 14 {
                markLoanPlanPaid(firstPlan)
                markLoanPlanPaid(secondPlan)
            } else if index <= 5 {
                firstPlan.status = .overdue
                let fee = Decimal(index * 12)
                let penalty = Decimal(index * 7)
                firstPlan.overdueStartDate = day(1, from: firstDueDate, calendar: calendar)
                firstPlan.overdueDays = daysBetween(firstDueDate, today, calendar: calendar)
                firstPlan.remainingOverdueFee = fee
                firstPlan.remainingPenaltyInterest = penalty
                firstPlan.remainingTotalAmount = firstPlan.remainingPrincipal + firstPlan.remainingInterest + fee + penalty
                loanOverdues.append(
                    LoanOverdueRecord(
                        debtID: debt.id,
                        planID: firstPlan.id,
                        overdueStartDate: day(1, from: firstDueDate, calendar: calendar),
                        overdueDays: firstPlan.overdueDays,
                        overdueBaseAmount: firstPlan.remainingPrincipal + firstPlan.remainingInterest,
                        overdueFee: fee,
                        penaltyInterest: penalty,
                        createdAt: today,
                        updatedAt: today
                    )
                )
            } else if index <= 10 && index % 2 == 0 {
                applyLoanPayment(to: firstPlan, principal: Decimal(80 + index), interest: Decimal(10))
                loanPayments.append(
                    LoanPaymentRecord(
                        debtID: debt.id,
                        paymentDate: day(-index + 5, from: today, calendar: calendar),
                        totalAmount: Decimal(90 + index),
                        note: "Scenario loan payment \(index)"
                    )
                )
            }

            loans.append(debt)
            loanRules.append(rule)
            loanPlans.append(contentsOf: [firstPlan, secondPlan])
        }

        var personalDebts: [PersonalLendingDebt] = []
        var personalPlans: [PersonalLendingPlan] = []
        var personalPayments: [PersonalLendingPaymentRecord] = []
        let personalAllocations: [PersonalLendingAllocationDetail] = []
        var personalOverdues: [PersonalLendingOverdueRecord] = []

        for index in 1...12 {
            if index <= 4 {
                let principal = Decimal(800 + index * 150)
                let paid = Decimal(index * 80)
                let dueDate = index <= 2 ? day(-index * 25, from: today, calendar: calendar) : day(35 + index, from: today, calendar: calendar)
                let debt = PersonalLendingDebt(
                    name: "Friend-\(twoDigit(index)) No Fixed Plan",
                    lenderName: "Friend \(index)",
                    note: "Seeded no-fixed-plan personal lending \(index)",
                    principalAmount: principal,
                    paidAmount: paid,
                    borrowedDate: day(-150, from: today, calendar: calendar),
                    agreedEndDate: dueDate,
                    repaymentMethod: .noFixedPlan,
                    status: index <= 2 ? .overdue : .active,
                    createdAt: day(-150, from: today, calendar: calendar),
                    updatedAt: today
                )
                personalDebts.append(debt)
                personalPayments.append(
                    PersonalLendingPaymentRecord(
                        debtID: debt.id,
                        paymentDate: index % 2 == 0 ? day(-index, from: today, calendar: calendar) : day(-55, from: today, calendar: calendar),
                        amount: paid,
                        note: "Scenario friend payment \(index)"
                    )
                )
                if index <= 2 {
                    personalOverdues.append(
                        PersonalLendingOverdueRecord(
                            debtID: debt.id,
                            overdueStartDate: day(1, from: dueDate, calendar: calendar),
                            overdueDays: daysBetween(dueDate, today, calendar: calendar),
                            overdueAmount: debt.remainingAmount,
                            overdueFee: Decimal(index * 5),
                            penaltyInterest: Decimal(index * 3),
                            createdAt: today,
                            updatedAt: today
                        )
                    )
                }
            } else if index <= 8 {
                let principal = Decimal(1_000 + index * 120)
                let interest = Decimal(100 + index * 10)
                let dueDate = index <= 6 ? day(-(index - 4) * 20, from: today, calendar: calendar) : day(10 + index, from: today, calendar: calendar)
                let debt = PersonalLendingDebt(
                    name: "Friend-\(twoDigit(index)) Maturity",
                    lenderName: "Relative \(index)",
                    note: "Seeded maturity personal lending \(index)",
                    principalAmount: principal,
                    fixedInterestAmount: interest,
                    borrowedDate: day(-120, from: today, calendar: calendar),
                    agreedEndDate: dueDate,
                    repaymentMethod: .principalAndInterestAtMaturity,
                    isInterestBearing: true,
                    status: index <= 6 ? .overdue : .active,
                    createdAt: day(-120, from: today, calendar: calendar),
                    updatedAt: today
                )
                let plan = PersonalLendingPlan(
                    debtID: debt.id,
                    periodIndex: 1,
                    dueDate: dueDate,
                    scheduledPrincipal: principal,
                    scheduledInterest: interest,
                    paidAmount: index == 8 ? Decimal(300) : 0,
                    status: index <= 6 ? .overdue : (index == 8 ? .partiallyPaid : .pending)
                )
                debt.paidAmount = plan.paidAmount
                debt.remainingAmount = plan.remainingAmount
                personalDebts.append(debt)
                personalPlans.append(plan)
                if plan.paidAmount > 0 {
                    personalPayments.append(
                        PersonalLendingPaymentRecord(
                            debtID: debt.id,
                            paymentDate: day(-3, from: today, calendar: calendar),
                            amount: plan.paidAmount,
                            note: "Scenario maturity payment \(index)"
                        )
                    )
                }
                if index <= 6 {
                    personalOverdues.append(
                        PersonalLendingOverdueRecord(
                            debtID: debt.id,
                            planID: plan.id,
                            overdueStartDate: day(1, from: dueDate, calendar: calendar),
                            overdueDays: daysBetween(dueDate, today, calendar: calendar),
                            overdueAmount: plan.remainingAmount,
                            overdueFee: Decimal(index * 4),
                            penaltyInterest: Decimal(index * 2),
                            createdAt: today,
                            updatedAt: today
                        )
                    )
                }
            } else {
                let principal = Decimal(1_200 + index * 100)
                let interest = Decimal(120 + index * 8)
                let debt = PersonalLendingDebt(
                    name: "Friend-\(twoDigit(index)) Installments",
                    lenderName: "Peer \(index)",
                    note: "Seeded installment personal lending \(index)",
                    principalAmount: principal,
                    fixedInterestAmount: interest,
                    borrowedDate: day(-100, from: today, calendar: calendar),
                    agreedEndDate: day(70, from: today, calendar: calendar),
                    repaymentMethod: .equalPrincipalEqualInterest,
                    isInterestBearing: true,
                    monthlyRepaymentDay: 15,
                    termCount: 3,
                    status: index == 12 ? .paidOff : (index == 9 ? .overdue : .active),
                    createdAt: day(-100, from: today, calendar: calendar),
                    updatedAt: today
                )
                var remainingFromPlans: Decimal = 0
                for period in 1...3 {
                    let dueDate = period == 1 ? day(index == 9 ? -15 : 5, from: today, calendar: calendar) : day(30 * period, from: today, calendar: calendar)
                    let plan = PersonalLendingPlan(
                        debtID: debt.id,
                        periodIndex: period,
                        dueDate: dueDate,
                        scheduledPrincipal: round(principal / Decimal(3)),
                        scheduledInterest: round(interest / Decimal(3)),
                        paidAmount: index == 12 ? round(principal / Decimal(3) + interest / Decimal(3)) : (period == 1 && index == 10 ? 100 : 0),
                        status: index == 12 ? .paid : (period == 1 && index == 9 ? .overdue : (period == 1 && index == 10 ? .partiallyPaid : .pending))
                    )
                    remainingFromPlans += plan.remainingAmount
                    personalPlans.append(plan)
                    if period == 1 && index == 9 {
                        personalOverdues.append(
                            PersonalLendingOverdueRecord(
                                debtID: debt.id,
                                planID: plan.id,
                                overdueStartDate: day(1, from: dueDate, calendar: calendar),
                                overdueDays: daysBetween(dueDate, today, calendar: calendar),
                                overdueAmount: plan.remainingAmount,
                                overdueFee: 18,
                                penaltyInterest: 9,
                                createdAt: today,
                                updatedAt: today
                            )
                        )
                    }
                }
                debt.paidAmount = round(debt.totalPayableAmount - remainingFromPlans)
                debt.remainingAmount = round(remainingFromPlans)
                if debt.paidAmount > 0 {
                    personalPayments.append(
                        PersonalLendingPaymentRecord(
                            debtID: debt.id,
                            paymentDate: index == 12 ? day(-70, from: today, calendar: calendar) : day(-2, from: today, calendar: calendar),
                            amount: debt.paidAmount,
                            note: "Scenario installment payment \(index)"
                        )
                    )
                }
                personalDebts.append(debt)
            }
        }

        let scenarioWithoutExpected = FortyDebtScenario(
            settings: settings,
            creditCards: creditCards,
            cardRules: cardRules,
            cardStatements: cardStatements,
            cardPlans: cardPlans,
            cardBreakdowns: cardBreakdowns,
            cardPayments: cardPayments,
            cardOverdues: cardOverdues,
            cardInstallments: cardInstallments,
            loans: loans,
            loanPlans: loanPlans,
            loanPayments: loanPayments,
            loanAllocations: loanAllocations,
            loanOverdues: loanOverdues,
            loanRules: loanRules,
            personalDebts: personalDebts,
            personalPlans: personalPlans,
            personalPayments: personalPayments,
            personalAllocations: personalAllocations,
            personalOverdues: personalOverdues,
            expected: FortyDebtScenarioExpected.empty
        )
        var scenario = scenarioWithoutExpected
        scenario.expected = expectedValues(for: scenarioWithoutExpected, today: today, calendar: calendar)
        return scenario
    }

    static func insert(_ scenario: FortyDebtScenario, into modelContext: ModelContext) throws {
        modelContext.insert(scenario.settings)
        scenario.creditCards.forEach(modelContext.insert)
        scenario.cardRules.forEach(modelContext.insert)
        scenario.cardStatements.forEach(modelContext.insert)
        scenario.cardPlans.forEach(modelContext.insert)
        scenario.cardBreakdowns.forEach(modelContext.insert)
        scenario.cardPayments.forEach(modelContext.insert)
        scenario.cardOverdues.forEach(modelContext.insert)
        scenario.cardInstallments.forEach(modelContext.insert)
        scenario.loans.forEach(modelContext.insert)
        scenario.loanPlans.forEach(modelContext.insert)
        scenario.loanPayments.forEach(modelContext.insert)
        scenario.loanAllocations.forEach(modelContext.insert)
        scenario.loanOverdues.forEach(modelContext.insert)
        scenario.loanRules.forEach(modelContext.insert)
        scenario.personalDebts.forEach(modelContext.insert)
        scenario.personalPlans.forEach(modelContext.insert)
        scenario.personalPayments.forEach(modelContext.insert)
        scenario.personalAllocations.forEach(modelContext.insert)
        scenario.personalOverdues.forEach(modelContext.insert)
        try modelContext.save()
    }

    private static func expectedValues(
        for scenario: FortyDebtScenario,
        today: Date,
        calendar: Calendar
    ) -> FortyDebtScenarioExpected {
        let period = AnalyticsSupport.monthPeriod(containing: today, calendar: calendar)
        let cardStatements = scenario.cardStatements.filter { $0.isActive && $0.status != .replaced }
        let latestStatements = Dictionary(uniqueKeysWithValues: cardStatements.map { ($0.debtID, $0) })
        let activeCardIDs = Set(scenario.creditCards.filter { $0.isActive && $0.status != .archived }.map(\.id))
        let activeLoanIDs = Set(scenario.loans.filter { $0.status != .archived }.map(\.id))
        let activePersonalIDs = Set(scenario.personalDebts.filter { !$0.isArchived && $0.status != .archived }.map(\.id))

        let creditRemaining = sum(latestStatements.values.map(\.remainingAmount))
        let loanRemaining = sum(scenario.loanPlans.filter { activeLoanIDs.contains($0.debtID) }.map { $0.remainingPrincipal + $0.remainingInterest })
        let personalPlansByDebt = Dictionary(grouping: scenario.personalPlans.filter { activePersonalIDs.contains($0.debtID) }, by: \.debtID)
        let personalRemaining = sum(scenario.personalDebts.filter { activePersonalIDs.contains($0.id) }.map { debt in
            if let plans = personalPlansByDebt[debt.id], plans.isEmpty == false {
                return sum(plans.map(\.remainingAmount))
            }
            return debt.remainingAmount
        })

        let currentMonthPlanned = sum(cardStatements.filter { period.contains($0.dueDate) }.map(\.remainingAmount))
            + sum(scenario.loanPlans.filter { activeLoanIDs.contains($0.debtID) && period.contains($0.dueDate) }.map { $0.remainingPrincipal + $0.remainingInterest })
            + sum(scenario.personalPlans.filter { activePersonalIDs.contains($0.debtID) && period.contains($0.dueDate) }.map(\.remainingAmount))

        let currentCardPayments = scenario.cardPayments.filter { $0.isActive && activeCardIDs.contains($0.debtID) && period.contains($0.paymentDate) }
        let currentLoanPayments = scenario.loanPayments.filter { activeLoanIDs.contains($0.debtID) && period.contains($0.paymentDate) }
        let currentPersonalPayments = scenario.personalPayments.filter { activePersonalIDs.contains($0.debtID) && period.contains($0.paymentDate) }

        let cardOverdueItems = cardStatements.filter { statement in
            statement.dueDate < today && statement.paidAmount < statement.minimumPaymentAmount && statement.remainingAmount > 0
        }
        let loanOverduePlans = scenario.loanPlans.filter { activeLoanIDs.contains($0.debtID) && $0.dueDate < today && $0.remainingPrincipal + $0.remainingInterest > 0 }
        let personalOverduePlanItems = scenario.personalPlans.filter { activePersonalIDs.contains($0.debtID) && $0.dueDate < today && $0.remainingAmount > 0 }
        let personalPlanDebtIDs = Set(scenario.personalPlans.map(\.debtID))
        let personalDebtLevelOverdues = scenario.personalDebts.filter {
            activePersonalIDs.contains($0.id)
                && !personalPlanDebtIDs.contains($0.id)
                && ($0.agreedEndDate ?? .distantFuture) < today
                && $0.remainingAmount > 0
        }

        let cardCosts = scenario.cardBreakdowns.filter { breakdown in
            guard let statement = cardStatements.first(where: { $0.id == breakdown.statementID }) else { return false }
            return activeCardIDs.contains(statement.debtID)
        }
        let creditCardCost = sum(cardCosts.map { $0.installmentFee + $0.installmentInterest + $0.revolvingInterest + $0.overdueFee + $0.penaltyInterest + $0.unclassifiedAmount })
        let loanScheduledInterest = sum(scenario.loanPlans.filter { activeLoanIDs.contains($0.debtID) }.map(\.scheduledInterest))
        let loanOverdueCost = sum(scenario.loanOverdues.filter { activeLoanIDs.contains($0.debtID) && $0.status != .waived }.map {
            ($0.generatesOverdueFee ? $0.overdueFee : 0) + ($0.generatesPenaltyInterest ? $0.penaltyInterest : 0)
        })
        let personalInterest = sum(scenario.personalPlans.filter { activePersonalIDs.contains($0.debtID) }.map(\.scheduledInterest))

        return FortyDebtScenarioExpected(
            creditCardCount: scenario.creditCards.count,
            loanCount: scenario.loans.count,
            personalLendingCount: scenario.personalDebts.count,
            totalDebtCount: scenario.creditCards.count + scenario.loans.count + scenario.personalDebts.count,
            creditCardRemainingAmount: creditRemaining,
            loanRemainingAmount: loanRemaining,
            personalLendingRemainingAmount: personalRemaining,
            totalRemainingAmount: round(creditRemaining + loanRemaining + personalRemaining),
            currentMonthPlannedRepaymentAmount: round(currentMonthPlanned),
            creditCardCurrentStatementAmount: sum(latestStatements.values.map(\.statementAmount)),
            creditCardCurrentStatementPaidAmount: sum(latestStatements.values.map(\.paidAmount)),
            currentMonthPaidAmount: sum(currentCardPayments.map(\.amount)) + sum(currentLoanPayments.map(\.totalAmount)) + sum(currentPersonalPayments.map(\.amount)),
            cumulativePaidAmount: sum(scenario.cardPayments.map(\.amount)) + sum(scenario.loanPayments.map(\.totalAmount)) + sum(scenario.personalPayments.map(\.amount)),
            creditCardCurrentMonthPaidAmount: sum(currentCardPayments.map(\.amount)),
            loanCurrentMonthPaidAmount: sum(currentLoanPayments.map(\.totalAmount)),
            personalLendingCurrentMonthPaidAmount: sum(currentPersonalPayments.map(\.amount)),
            currentMonthCreditCardPaymentRecordCount: currentCardPayments.count,
            currentMonthFixedPaymentInputCount: currentLoanPayments.count + currentPersonalPayments.count,
            currentOverdueDebtCount: Set(cardOverdueItems.map(\.debtID) + loanOverduePlans.map(\.debtID) + personalOverduePlanItems.map(\.debtID) + personalDebtLevelOverdues.map(\.id)).count,
            currentOverduePeriodCount: cardOverdueItems.count + loanOverduePlans.count + personalOverduePlanItems.count + personalDebtLevelOverdues.count,
            currentOverdueTotalAmount: sum(cardOverdueItems.map(\.remainingAmount)) + sum(loanOverduePlans.map { $0.remainingPrincipal + $0.remainingInterest }) + sum(personalOverduePlanItems.map(\.remainingAmount)) + sum(personalDebtLevelOverdues.map(\.remainingAmount)),
            creditCardMinimumPaymentGap: sum(cardOverdueItems.map { $0.minimumPaymentAmount - $0.paidAmount }),
            creditCardOverdueStatementRemainingAmount: sum(cardOverdueItems.map(\.remainingAmount)),
            loanOverdueAmount: sum(loanOverduePlans.map { $0.remainingPrincipal + $0.remainingInterest }),
            personalLendingPastDueAmount: sum(personalOverduePlanItems.map(\.remainingAmount)) + sum(personalDebtLevelOverdues.map(\.remainingAmount)),
            overdueFeeTotalAmount: sum(cardOverdueItems.map { statement in
                scenario.cardBreakdowns.filter { $0.statementID == statement.id }.reduce(Decimal(0)) { $0 + $1.overdueFee }
            }) + sum(scenario.loanOverdues.map(\.overdueFee)) + sum(scenario.personalOverdues.map(\.overdueFee)),
            penaltyInterestTotalAmount: sum(cardOverdueItems.map { statement in
                scenario.cardBreakdowns.filter { $0.statementID == statement.id }.reduce(Decimal(0)) { $0 + $1.penaltyInterest }
            }) + sum(scenario.loanOverdues.map(\.penaltyInterest)) + sum(scenario.personalOverdues.map(\.penaltyInterest)),
            totalCostAmount: round(creditCardCost + loanScheduledInterest + loanOverdueCost + personalInterest),
            creditCardCostAmount: creditCardCost,
            loanCostAmount: round(loanScheduledInterest + loanOverdueCost),
            personalLendingInterestAmount: personalInterest,
            creditCardBreakdownConflictCount: cardCosts.filter(\.hasBreakdownConflict).count
        )
    }

    private static func makeLoanPlan(
        debtID: UUID,
        periodIndex: Int,
        dueDate: Date,
        scheduledPrincipal: Decimal,
        scheduledInterest: Decimal,
        remainingPrincipalBeforePayment: Decimal
    ) -> LoanRepaymentPlan {
        LoanRepaymentPlan(
            debtID: debtID,
            periodIndex: periodIndex,
            periodType: .regular,
            periodStartDate: day(-30, from: dueDate, calendar: Calendar(identifier: .gregorian)),
            periodEndDate: dueDate,
            dueDate: dueDate,
            scheduledPrincipal: scheduledPrincipal,
            scheduledInterest: scheduledInterest,
            remainingPrincipalBeforePayment: remainingPrincipalBeforePayment,
            remainingPrincipalAfterScheduledPayment: maxDecimal(remainingPrincipalBeforePayment - scheduledPrincipal, 0)
        )
    }

    private static func markLoanPlanPaid(_ plan: LoanRepaymentPlan) {
        plan.paidPrincipal = plan.scheduledPrincipal
        plan.paidInterest = plan.scheduledInterest
        plan.paidTotalAmount = plan.scheduledTotalAmount
        plan.remainingPrincipal = 0
        plan.remainingInterest = 0
        plan.remainingTotalAmount = 0
        plan.status = .paid
    }

    private static func applyLoanPayment(to plan: LoanRepaymentPlan, principal: Decimal, interest: Decimal) {
        plan.paidPrincipal = minDecimal(principal, plan.scheduledPrincipal)
        plan.paidInterest = minDecimal(interest, plan.scheduledInterest)
        plan.paidTotalAmount = plan.paidPrincipal + plan.paidInterest
        plan.remainingPrincipal = maxDecimal(plan.scheduledPrincipal - plan.paidPrincipal, 0)
        plan.remainingInterest = maxDecimal(plan.scheduledInterest - plan.paidInterest, 0)
        plan.remainingTotalAmount = plan.remainingPrincipal + plan.remainingInterest
        plan.status = plan.remainingTotalAmount == 0 ? .paid : .partiallyPaid
    }

    private static func cardStatus(
        dueDate: Date,
        today: Date,
        paidAmount: Decimal,
        remainingAmount: Decimal,
        minimumPayment: Decimal
    ) -> CreditCardStatementStatus {
        if remainingAmount == 0 { return .paid }
        if dueDate < today {
            return paidAmount < minimumPayment ? .overdue : .carriedForward
        }
        return paidAmount > 0 ? .partiallyPaid : .pending
    }

    private static func planStatus(from statementStatus: CreditCardStatementStatus) -> PlanStatus {
        switch statementStatus {
        case .paid:
            return .paid
        case .overdue:
            return .overdue
        case .partiallyPaid, .carriedForward:
            return .partiallyPaid
        case .pending, .replaced:
            return .pending
        }
    }

    private static func loanTitle(_ method: LoanRepaymentMethod) -> String {
        switch method {
        case .equalPrincipal:
            return "Equal Principal"
        case .equalPayment:
            return "Equal Payment"
        case .interestFirst:
            return "Interest First"
        case .principalAtEnd:
            return "Principal At End"
        }
    }

    private static func twoDigit(_ value: Int) -> String {
        String(format: "%02d", value)
    }

    private static func day(_ offset: Int, from date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: offset, to: date) ?? date
    }

    private static func daysBetween(_ start: Date, _ end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }

    private static func sum(_ values: [Decimal]) -> Decimal {
        round(values.reduce(Decimal(0)) { $0 + maxDecimal($1, 0) })
    }

    private static func round(_ value: Decimal) -> Decimal {
        MoneyRoundingPolicy.standard.round(maxDecimal(value, 0))
    }
}

extension FortyDebtScenarioExpected {
    static let empty = FortyDebtScenarioExpected(
        creditCardCount: 0,
        loanCount: 0,
        personalLendingCount: 0,
        totalDebtCount: 0,
        creditCardRemainingAmount: 0,
        loanRemainingAmount: 0,
        personalLendingRemainingAmount: 0,
        totalRemainingAmount: 0,
        currentMonthPlannedRepaymentAmount: 0,
        creditCardCurrentStatementAmount: 0,
        creditCardCurrentStatementPaidAmount: 0,
        currentMonthPaidAmount: 0,
        cumulativePaidAmount: 0,
        creditCardCurrentMonthPaidAmount: 0,
        loanCurrentMonthPaidAmount: 0,
        personalLendingCurrentMonthPaidAmount: 0,
        currentMonthCreditCardPaymentRecordCount: 0,
        currentMonthFixedPaymentInputCount: 0,
        currentOverdueDebtCount: 0,
        currentOverduePeriodCount: 0,
        currentOverdueTotalAmount: 0,
        creditCardMinimumPaymentGap: 0,
        creditCardOverdueStatementRemainingAmount: 0,
        loanOverdueAmount: 0,
        personalLendingPastDueAmount: 0,
        overdueFeeTotalAmount: 0,
        penaltyInterestTotalAmount: 0,
        totalCostAmount: 0,
        creditCardCostAmount: 0,
        loanCostAmount: 0,
        personalLendingInterestAmount: 0,
        creditCardBreakdownConflictCount: 0
    )
}

@MainActor
enum UITestDebtScenarioSeeder {
    private static var didPrepare = false

    static func resetDataOnlyIfRequested(modelContext: ModelContext, onboardingCompleted: Bool) -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-UITestResetData"),
              !arguments.contains("-UITestSeedFortyDebtScenario") else { return false }
        guard !didPrepare else { return true }
        didPrepare = true

        do {
            try resetScenarioData(in: modelContext)
            modelContext.insert(AppUserSettings(onboardingCompleted: onboardingCompleted))
            try modelContext.save()
        } catch {
            assertionFailure("Could not reset UI test data: \(error)")
        }
        return true
    }

    static func prepareIfRequested(modelContext: ModelContext) {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-UITestSeedFortyDebtScenario") else { return }
        guard !didPrepare else { return }
        didPrepare = true

        do {
            let shouldReset = arguments.contains("-UITestResetData")
            let hasScenario = shouldReset ? false : try hasExistingScenario(in: modelContext)
            let shouldSeed = shouldReset || !hasScenario
            if shouldSeed {
                try resetScenarioData(in: modelContext)
                let scenario = FortyDebtScenarioFixtures.makeScenario()
                try FortyDebtScenarioFixtures.insert(scenario, into: modelContext)
            } else {
                try updateSettingsForUITest(in: modelContext)
            }
        } catch {
            assertionFailure("Could not seed forty-debt UI scenario: \(error)")
        }
    }

    private static func hasExistingScenario(in modelContext: ModelContext) throws -> Bool {
        let cards = try modelContext.fetch(FetchDescriptor<CreditCardDebt>())
        return cards.contains { $0.name == FortyDebtScenarioFixtures.sentinelDebtName }
    }

    private static func resetScenarioData(in modelContext: ModelContext) throws {
        try deleteAll(StrategyRiskEvent.self, in: modelContext)
        try deleteAll(StrategyCostEvent.self, in: modelContext)
        try deleteAll(StrategyDebtAllocation.self, in: modelContext)
        try deleteAll(StrategyMonthSnapshot.self, in: modelContext)
        try deleteAll(StrategySimulation.self, in: modelContext)
        try deleteAll(StrategyComparisonBatch.self, in: modelContext)
        try deleteAll(DebtAnalyticsSnapshot.self, in: modelContext)
        try deleteAll(PaymentAnalyticsSnapshot.self, in: modelContext)
        try deleteAll(OverdueAnalyticsSnapshot.self, in: modelContext)
        try deleteAll(CostAnalyticsSnapshot.self, in: modelContext)
        try deleteAll(AnalyticsInvalidationState.self, in: modelContext)
        try deleteAll(CreditCardInstallmentPlan.self, in: modelContext)
        try deleteAll(CreditCardOverdueRecord.self, in: modelContext)
        try deleteAll(CreditCardPaymentRecord.self, in: modelContext)
        try deleteAll(CreditCardRepaymentPlan.self, in: modelContext)
        try deleteAll(CreditCardStatementBreakdown.self, in: modelContext)
        try deleteAll(CreditCardStatement.self, in: modelContext)
        try deleteAll(CreditCardCalculationRule.self, in: modelContext)
        try deleteAll(CreditCardDebt.self, in: modelContext)
        try deleteAll(LoanPaymentAllocationDetail.self, in: modelContext)
        try deleteAll(LoanPaymentRecord.self, in: modelContext)
        try deleteAll(LoanOverdueRecord.self, in: modelContext)
        try deleteAll(LoanCalculationRule.self, in: modelContext)
        try deleteAll(LoanRepaymentPlan.self, in: modelContext)
        try deleteAll(LoanDebt.self, in: modelContext)
        try deleteAll(PersonalLendingAllocationDetail.self, in: modelContext)
        try deleteAll(PersonalLendingPaymentRecord.self, in: modelContext)
        try deleteAll(PersonalLendingOverdueRecord.self, in: modelContext)
        try deleteAll(PersonalLendingPlan.self, in: modelContext)
        try deleteAll(PersonalLendingDebt.self, in: modelContext)
        try deleteAll(AppUserSettings.self, in: modelContext)
        try modelContext.save()
    }

    private static func updateSettingsForUITest(in modelContext: ModelContext) throws {
        let settings = try modelContext.fetch(FetchDescriptor<AppUserSettings>())
        if let first = settings.first {
            first.onboardingCompleted = true
            first.monthlyRepaymentBudget = 50_000
            first.currencyCode = "USD"
            first.languagePreference = .english
            first.strategyDataChanged = true
            first.updatedAt = Date()
        } else {
            modelContext.insert(AppUserSettings(onboardingCompleted: true, monthlyRepaymentBudget: 50_000, currencyCode: "USD", languagePreference: .english))
        }
        try modelContext.save()
    }

    private static func deleteAll<T: PersistentModel>(_ modelType: T.Type, in modelContext: ModelContext) throws {
        let items = try modelContext.fetch(FetchDescriptor<T>())
        for item in items {
            modelContext.delete(item)
        }
    }
}
#endif
