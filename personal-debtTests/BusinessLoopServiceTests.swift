import Foundation
import Testing
@testable import personal_debt

@MainActor
struct BusinessLoopServiceTests {
    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value) ?? 0
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    @Test
    func creditCardRealStatementReplacesFallbackArtifacts() throws {
        let service = CreditCardDebtService()
        let (_, debt, rule) = try service.createDebt(
            CreditCardDebtInput(name: "Card", billingDay: 1, dueDay: 20)
        )
        let installment = CreditCardInstallmentPlan(
            debtID: debt.id,
            nextBillingDate: date(2026, 2, 1),
            principalPerTerm: 100,
            feePerTerm: 10,
            interestPerTerm: 0,
            totalTerms: 3
        )
        let (_, fallback, fallbackPlan, fallbackBreakdown) = try service.generateFallbackStatement(
            debt: debt,
            billingDate: date(2026, 2, 1),
            dueDate: date(2026, 2, 20),
            previousStatement: nil,
            installments: [installment],
            rule: rule
        )

        let (_, realStatement, _) = try service.createUserConfirmedStatement(
            debt: debt,
            input: CreditCardStatementInput(
                billingDate: date(2026, 2, 1),
                dueDate: date(2026, 2, 20),
                statementAmount: 500,
                minimumPaymentAmount: 50
            ),
            rule: rule,
            fallbackStatements: [fallback],
            fallbackPlans: [fallbackPlan],
            fallbackBreakdowns: [fallbackBreakdown]
        )

        #expect(realStatement.source == .userConfirmed)
        #expect(realStatement.statementAmount == 500)
        #expect(fallback.isActive == false)
        #expect(fallback.status == .replaced)
        #expect(fallback.replacedByStatementID == realStatement.id)
        #expect(fallbackPlan.isActive == false)
        #expect(fallbackBreakdown.isActive == false)
    }

    @Test
    func creditCardSystemOverdueUsesRemainingAmountAndPaymentDeletionRecalculates() throws {
        let service = CreditCardDebtService()
        let (_, debt, rule) = try service.createDebt(
            CreditCardDebtInput(name: "Card", billingDay: 1, dueDay: 20)
        )
        let (_, statement, plan) = try service.createUserConfirmedStatement(
            debt: debt,
            input: CreditCardStatementInput(
                billingDate: date(2026, 1, 1),
                dueDate: date(2026, 1, 20),
                statementAmount: 1000,
                minimumPaymentAmount: 200
            ),
            rule: rule,
            fallbackStatements: [],
            fallbackPlans: [],
            fallbackBreakdowns: []
        )
        var payments: [CreditCardPaymentRecord] = []
        var overdues: [CreditCardOverdueRecord] = []

        let (_, payment) = try service.recordPayment(
            debt: debt,
            statement: statement,
            plan: plan,
            payments: &payments,
            overdues: &overdues,
            input: CreditCardPaymentInput(paymentDate: date(2026, 1, 21), amount: 150),
            rule: rule,
            today: date(2026, 1, 21)
        )

        #expect(statement.status == .overdue)
        #expect(overdues.count == 1)
        #expect(overdues[0].overdueAmount == 850)
        #expect(overdues[0].recordSource == .systemGenerated)

        _ = try service.softDeletePayment(
            payment,
            debt: debt,
            statement: statement,
            plan: plan,
            payments: payments,
            overdues: &overdues,
            rule: rule,
            today: date(2026, 1, 21)
        )

        #expect(payment.isActive == false)
        #expect(statement.paidAmount == 0)
        #expect(statement.remainingAmount == 1000)
        #expect(overdues[0].overdueAmount == 1000)
    }

    @Test
    func creditCardSystemOverduePenaltyStartsFromDueDateAndRejectsZeroPayment() throws {
        let service = CreditCardDebtService()
        let (_, debt, _) = try service.createDebt(
            CreditCardDebtInput(name: "Card", billingDay: 1, dueDay: 20)
        )
        let rule = CreditCardCalculationRule(
            debtID: debt.id,
            minimumOverdueFee: 0,
            penaltyDailyRate: decimal("0.01")
        )
        let (_, statement, plan) = try service.createUserConfirmedStatement(
            debt: debt,
            input: CreditCardStatementInput(
                billingDate: date(2026, 1, 1),
                dueDate: date(2026, 1, 20),
                statementAmount: 1000,
                minimumPaymentAmount: 200
            ),
            rule: rule,
            fallbackStatements: [],
            fallbackPlans: [],
            fallbackBreakdowns: []
        )
        var payments: [CreditCardPaymentRecord] = []
        var overdues: [CreditCardOverdueRecord] = []

        do {
            _ = try service.recordPayment(
                debt: debt,
                statement: statement,
                plan: plan,
                payments: &payments,
                overdues: &overdues,
                input: CreditCardPaymentInput(paymentDate: date(2026, 1, 21), amount: 0),
                rule: rule,
                today: date(2026, 1, 21)
            )
            #expect(Bool(false))
        } catch {
            #expect(error is DebtServiceError)
        }

        _ = try service.recordPayment(
            debt: debt,
            statement: statement,
            plan: plan,
            payments: &payments,
            overdues: &overdues,
            input: CreditCardPaymentInput(paymentDate: date(2026, 1, 21), amount: 150),
            rule: rule,
            today: date(2026, 1, 21)
        )

        #expect(overdues.count == 1)
        #expect(overdues[0].overdueAmount == 850)
        #expect(overdues[0].penaltyInterest == decimal("8.50"))
    }

    @Test
    func creditCardManualOverdueRejectsFallbackAndHistoricalStatements() throws {
        let service = CreditCardDebtService()
        let (_, debt, rule) = try service.createDebt(
            CreditCardDebtInput(name: "Card", billingDay: 1, dueDay: 20)
        )
        let (_, oldStatement, oldPlan) = try service.createUserConfirmedStatement(
            debt: debt,
            input: CreditCardStatementInput(
                billingDate: date(2026, 1, 1),
                dueDate: date(2026, 1, 20),
                statementAmount: 1000,
                minimumPaymentAmount: 100
            ),
            rule: rule,
            fallbackStatements: [],
            fallbackPlans: [],
            fallbackBreakdowns: []
        )
        let (_, latestStatement, latestPlan) = try service.createUserConfirmedStatement(
            debt: debt,
            input: CreditCardStatementInput(
                billingDate: date(2026, 2, 1),
                dueDate: date(2026, 2, 20),
                statementAmount: 900,
                minimumPaymentAmount: 90
            ),
            rule: rule,
            fallbackStatements: [],
            fallbackPlans: [],
            fallbackBreakdowns: []
        )
        let fallback = CreditCardStatement(
            debtID: debt.id,
            billingDate: date(2026, 3, 1),
            dueDate: date(2026, 3, 20),
            statementAmount: 100,
            minimumPaymentAmount: 10,
            minimumPaymentSource: "fallbackRule",
            source: .fallback
        )
        var overdues: [CreditCardOverdueRecord] = []
        let input = CreditCardManualOverdueInput(
            overdueAmount: 900,
            overdueFee: 0,
            penaltyInterest: 0,
            startDate: date(2026, 2, 21),
            endDate: nil
        )

        do {
            _ = try service.createManualOverdue(
                debt: debt,
                statement: oldStatement,
                plan: oldPlan,
                allStatements: [oldStatement, latestStatement],
                existingOverdues: &overdues,
                input: input
            )
            #expect(Bool(false))
        } catch {
            #expect(error is DebtServiceError)
        }

        do {
            _ = try service.createManualOverdue(
                debt: debt,
                statement: fallback,
                plan: nil,
                allStatements: [oldStatement, latestStatement, fallback],
                existingOverdues: &overdues,
                input: input
            )
            #expect(Bool(false))
        } catch {
            #expect(error is DebtServiceError)
        }

        let (_, overdue) = try service.createManualOverdue(
            debt: debt,
            statement: latestStatement,
            plan: latestPlan,
            allStatements: [oldStatement, latestStatement],
            existingOverdues: &overdues,
            input: input
        )
        #expect(overdue.recordSource == .userCreated)
        #expect(latestStatement.status == .overdue)
    }

    @Test
    func creditCardManualOverdueRejectsInvalidDateBoundaries() throws {
        let service = CreditCardDebtService()
        let (_, debt, rule) = try service.createDebt(
            CreditCardDebtInput(name: "Card", billingDay: 1, dueDay: 20)
        )
        let (_, statement, plan) = try service.createUserConfirmedStatement(
            debt: debt,
            input: CreditCardStatementInput(
                billingDate: date(2026, 2, 1),
                dueDate: date(2026, 2, 20),
                statementAmount: 900,
                minimumPaymentAmount: 90
            ),
            rule: rule,
            fallbackStatements: [],
            fallbackPlans: [],
            fallbackBreakdowns: []
        )

        for input in [
            CreditCardManualOverdueInput(
                overdueAmount: 900,
                overdueFee: 0,
                penaltyInterest: 0,
                startDate: date(2026, 2, 19),
                endDate: nil
            ),
            CreditCardManualOverdueInput(
                overdueAmount: 900,
                overdueFee: 0,
                penaltyInterest: 0,
                startDate: date(2026, 2, 25),
                endDate: date(2026, 2, 24)
            )
        ] {
            var overdues: [CreditCardOverdueRecord] = []
            do {
                _ = try service.createManualOverdue(
                    debt: debt,
                    statement: statement,
                    plan: plan,
                    allStatements: [statement],
                    existingOverdues: &overdues,
                    input: input
                )
                #expect(Bool(false))
            } catch {
                #expect(error is DebtServiceError)
            }
        }
    }

    @Test
    func creditCardManualOverdueRejectsEndBeforeStart() throws {
        let service = CreditCardDebtService()
        let (_, debt, rule) = try service.createDebt(
            CreditCardDebtInput(name: "Card", billingDay: 1, dueDay: 20)
        )
        let (_, statement, plan) = try service.createUserConfirmedStatement(
            debt: debt,
            input: CreditCardStatementInput(
                billingDate: date(2026, 2, 1),
                dueDate: date(2026, 2, 20),
                statementAmount: 900,
                minimumPaymentAmount: 90
            ),
            rule: rule,
            fallbackStatements: [],
            fallbackPlans: [],
            fallbackBreakdowns: []
        )
        var overdues: [CreditCardOverdueRecord] = []
        let (_, overdue) = try service.createManualOverdue(
            debt: debt,
            statement: statement,
            plan: plan,
            allStatements: [statement],
            existingOverdues: &overdues,
            input: CreditCardManualOverdueInput(
                overdueAmount: 900,
                overdueFee: 0,
                penaltyInterest: 0,
                startDate: date(2026, 2, 22),
                endDate: nil
            )
        )

        do {
            _ = try service.endManualOverdue(
                overdue,
                debt: debt,
                statement: statement,
                plan: plan,
                payments: [],
                endDate: date(2026, 2, 21)
            )
            #expect(Bool(false))
        } catch {
            #expect(error is DebtServiceError)
            #expect(overdue.endDate == nil)
        }
    }

    @Test
    func loanServiceUsesPriorityRuleAndUpdatesOverdueClosure() throws {
        let service = LoanDebtService()
        let input = LoanDebtInput(
            name: "Loan",
            creditorName: "",
            entryMode: .newLoan,
            repaymentMethod: .equalPrincipal,
            originalPrincipal: 200,
            openingPrincipalForManagement: nil,
            annualInterestRate: 0,
            startDate: date(2026, 1, 1),
            managementStartDate: nil,
            endDate: date(2026, 2, 10),
            repaymentDay: 10,
            termCount: 2,
            currencyCode: "USD"
        )
        let (_, debt, plans) = try service.createDebt(input)
        let rule = LoanCalculationRule(
            debtID: debt.id,
            overdueFeeMode: .fixed,
            fixedOverdueFee: 5,
            penaltyInterestMode: .fixedDailyRate,
            fixedPenaltyDailyRate: 0
        )
        var overdues: [LoanOverdueRecord] = []
        _ = try service.refreshOverdues(
            debt: debt,
            plans: plans,
            overdues: &overdues,
            rule: rule,
            today: date(2026, 1, 20)
        )
        #expect(overdues.count == 1)
        overdues[0].penaltyInterest = 10
        overdues[0].generatesPenaltyInterest = true
        plans[0].remainingPenaltyInterest = 10
        plans[0].remainingTotalAmount = plans[0].remainingPrincipal + plans[0].remainingInterest + 5 + 10

        var payments: [LoanPaymentRecord] = []
        var allocations: [LoanPaymentAllocationDetail] = []
        let (result, payment) = try service.recordPayment(
            debt: debt,
            plans: plans,
            payments: &payments,
            allocationDetails: &allocations,
            overdues: overdues,
            input: LoanPaymentInput(paymentDate: date(2026, 1, 20), totalAmount: 50),
            rule: rule,
            today: date(2026, 1, 20)
        )

        #expect(result == .recalculated)
        #expect(payment != nil)
        #expect(allocations.count == 1)
        #expect(allocations[0].allocatedOverdueFee == 5)
        #expect(allocations[0].allocatedPenaltyInterest == 10)
        #expect(allocations[0].allocatedInterest == 0)
        #expect(allocations[0].allocatedPrincipal == 35)
        #expect(overdues[0].paidOverdueFee == 5)
        #expect(overdues[0].paidPenaltyInterest == 10)

        _ = try service.closeOverdue(
            overdues[0],
            plan: plans[0],
            debt: debt,
            plans: plans,
            overdues: overdues,
            today: date(2026, 1, 20)
        )
        #expect(overdues[0].status == .closed)
        #expect(plans[0].status != .paid)
    }

    @Test
    func loanServiceResolvesCalculationRulePriority() throws {
        let service = LoanDebtService()
        let input = LoanDebtInput(
            name: "Loan",
            creditorName: "",
            entryMode: .newLoan,
            repaymentMethod: .equalPrincipal,
            originalPrincipal: 100,
            openingPrincipalForManagement: nil,
            annualInterestRate: 0,
            startDate: date(2026, 1, 1),
            managementStartDate: nil,
            endDate: date(2026, 1, 10),
            repaymentDay: 10,
            termCount: 1,
            currencyCode: "USD"
        )
        let (_, debt, _) = try service.createDebt(input)

        let builtIn = service.effectiveCalculationRule(for: debt, rules: [])
        #expect(builtIn.overdueBaseType == .currentUnpaidPrincipal)
        #expect(builtIn.overdueFeeMode == .zero)
        #expect(builtIn.penaltyInterestMode == .loanDailyRateMultiplier)
        #expect(builtIn.penaltyRateMultiplier == decimal("1.5"))
        #expect(builtIn.paymentAllocationMode == .feeFirst)

        let (_, globalRule) = try service.upsertCalculationRule(
            input: LoanCalculationRuleInput(
                overdueBaseType: .currentRemainingScheduledAmount,
                overdueFeeMode: .percentage,
                overdueFeeRate: decimal("0.10"),
                penaltyInterestMode: .zero,
                paymentAllocationMode: .currentPeriodFirst
            ),
            today: date(2026, 1, 1)
        )
        let globalEffective = service.effectiveCalculationRule(for: debt, rules: [globalRule])
        #expect(globalEffective.id == globalRule.id)
        #expect(globalEffective.paymentAllocationMode == .currentPeriodFirst)

        let (_, debtRule) = try service.upsertCalculationRule(
            input: LoanCalculationRuleInput(
                debtID: debt.id,
                overdueFeeMode: .fixed,
                fixedOverdueFee: 8,
                penaltyInterestMode: .fixedDailyRate,
                fixedPenaltyDailyRate: decimal("0.02")
            ),
            today: date(2026, 1, 2)
        )
        let debtEffective = service.effectiveCalculationRule(for: debt, rules: [globalRule, debtRule])
        #expect(debtEffective.id == debtRule.id)
        #expect(debtEffective.overdueFeeMode == .fixed)
        #expect(debtEffective.fixedOverdueFee == 8)
    }

    @Test
    func loanServiceReturnsUserDecisionForOverpaymentWithoutCreatingPayment() throws {
        let service = LoanDebtService()
        let input = LoanDebtInput(
            name: "Loan",
            creditorName: "",
            entryMode: .newLoan,
            repaymentMethod: .equalPrincipal,
            originalPrincipal: 100,
            openingPrincipalForManagement: nil,
            annualInterestRate: 0,
            startDate: date(2026, 1, 1),
            managementStartDate: nil,
            endDate: date(2026, 1, 10),
            repaymentDay: 10,
            termCount: 1,
            currencyCode: "USD"
        )
        let (_, debt, plans) = try service.createDebt(input)
        var payments: [LoanPaymentRecord] = []
        var allocations: [LoanPaymentAllocationDetail] = []

        let (result, payment) = try service.recordPayment(
            debt: debt,
            plans: plans,
            payments: &payments,
            allocationDetails: &allocations,
            overdues: [],
            input: LoanPaymentInput(paymentDate: date(2026, 1, 10), totalAmount: 150),
            today: date(2026, 1, 10)
        )

        #expect(result == .requiresUserDecision(unappliedAmount: 50))
        #expect(payment == nil)
        #expect(payments.isEmpty)
        #expect(allocations.isEmpty)
    }

    @Test
    func loanServiceRejectsInvalidInProgressBoundaries() throws {
        let service = LoanDebtService()
        let baseInput = LoanDebtInput(
            name: "Loan",
            creditorName: "",
            entryMode: .inProgressLoan,
            repaymentMethod: .equalPrincipal,
            originalPrincipal: 1000,
            openingPrincipalForManagement: 800,
            annualInterestRate: 0,
            startDate: date(2026, 1, 1),
            managementStartDate: date(2026, 2, 1),
            endDate: date(2026, 5, 1),
            repaymentDay: 1,
            termCount: 4,
            currencyCode: "USD"
        )

        var excessiveOpeningPrincipal = baseInput
        excessiveOpeningPrincipal.openingPrincipalForManagement = 1200
        do {
            _ = try service.createDebt(excessiveOpeningPrincipal)
            #expect(Bool(false))
        } catch {
            #expect(error is DebtServiceError)
        }

        var earlyManagementStart = baseInput
        earlyManagementStart.managementStartDate = date(2025, 12, 31)
        do {
            _ = try service.createDebt(earlyManagementStart)
            #expect(Bool(false))
        } catch {
            #expect(error is DebtServiceError)
        }
    }

    @Test
    func loanServiceUpdatesCoreFieldsManualOverduesAndPaymentMutations() throws {
        let service = LoanDebtService()
        let (_, debt, initialPlans) = try service.createDebt(
            LoanDebtInput(
                name: "Loan",
                creditorName: "Bank",
                note: "original",
                entryMode: .newLoan,
                repaymentMethod: .equalPrincipal,
                originalPrincipal: 300,
                openingPrincipalForManagement: nil,
                annualInterestRate: 0,
                startDate: date(2026, 1, 1),
                managementStartDate: nil,
                endDate: date(2026, 3, 10),
                repaymentDay: 10,
                termCount: 3,
                currencyCode: "USD"
            )
        )
        var plans = initialPlans

        let (_, regeneratedPlans) = try service.updateCoreFields(
            debt: debt,
            input: LoanDebtInput(
                name: "Updated Loan",
                creditorName: "New Bank",
                note: "regenerated",
                entryMode: .newLoan,
                repaymentMethod: .equalPayment,
                originalPrincipal: 300,
                openingPrincipalForManagement: nil,
                annualInterestRate: decimal("0.12"),
                startDate: date(2026, 1, 1),
                managementStartDate: nil,
                endDate: date(2026, 3, 10),
                repaymentDay: 10,
                termCount: 3,
                currencyCode: "USD"
            ),
            existingPayments: [],
            plans: &plans
        )
        #expect(debt.name == "Updated Loan")
        #expect(debt.creditorName == "New Bank")
        #expect(regeneratedPlans.count == 3)
        #expect(plans.count == regeneratedPlans.count)

        _ = try service.updateDisplayFields(debt: debt, name: "Display Loan", creditorName: "Display Bank", note: "display")
        #expect(debt.name == "Display Loan")
        #expect(debt.note == "display")

        var overdues: [LoanOverdueRecord] = []
        let (_, overdue) = try service.createManualOverdue(
            debt: debt,
            plan: plans[0],
            existingOverdues: &overdues,
            input: LoanManualOverdueInput(
                overdueFee: 7,
                penaltyInterest: 3,
                startDate: date(2026, 1, 12),
                note: "manual"
            ),
            today: date(2026, 1, 20)
        )
        #expect(overdue.status == .active)
        #expect(plans[0].status == .overdue)

        _ = try service.updateManualOverdue(
            overdue,
            plan: plans[0],
            debt: debt,
            plans: plans,
            overdues: overdues,
            input: LoanManualOverdueInput(
                overdueFee: 8,
                penaltyInterest: 4,
                startDate: date(2026, 1, 12),
                endDate: date(2026, 1, 19),
                note: "closed"
            ),
            today: date(2026, 1, 20)
        )
        #expect(overdue.status == .closed)
        #expect(overdue.source == .userAdjusted)
        #expect(plans[0].remainingOverdueFee == 0)

        _ = try service.voidOverdue(
            overdue,
            plan: plans[0],
            debt: debt,
            plans: plans,
            overdues: overdues,
            status: .ignored,
            today: date(2026, 1, 21)
        )
        #expect(overdue.status == .ignored)

        let (_, rule) = try service.upsertCalculationRule(
            input: LoanCalculationRuleInput(
                debtID: debt.id,
                overdueFeeMode: .fixed,
                fixedOverdueFee: 2,
                penaltyInterestMode: .fixedDailyRate,
                fixedPenaltyDailyRate: decimal("0.001")
            ),
            today: date(2026, 1, 1)
        )
        _ = try service.deleteCalculationRule(rule)

        var payments: [LoanPaymentRecord] = []
        var allocations: [LoanPaymentAllocationDetail] = []
        let (_, payment) = try service.recordPayment(
            debt: debt,
            plans: plans,
            payments: &payments,
            allocationDetails: &allocations,
            overdues: [],
            input: LoanPaymentInput(paymentDate: date(2026, 1, 10), totalAmount: 50, note: "first"),
            today: date(2026, 1, 10)
        )
        let savedPayment = try #require(payment)

        let updateResult = try service.updatePayment(
            savedPayment,
            input: LoanPaymentInput(paymentDate: date(2026, 1, 11), totalAmount: 60, note: "updated"),
            debt: debt,
            plans: plans,
            payments: payments,
            allocationDetails: &allocations,
            overdues: [],
            today: date(2026, 1, 11)
        )
        #expect(updateResult == .recalculated)
        #expect(savedPayment.totalAmount == 60)
        #expect(savedPayment.note == "updated")

        _ = try service.deletePayment(
            savedPayment,
            debt: debt,
            plans: plans,
            payments: &payments,
            allocationDetails: &allocations,
            overdues: [],
            today: date(2026, 1, 12)
        )
        #expect(payments.isEmpty)

        _ = try service.softDeleteDebt(debt, overdues: overdues, today: date(2026, 1, 30))
        #expect(debt.status == .archived)
        #expect(overdue.status == .voided)
    }

    @Test
    func creditCardServiceUpdatesStatementsPaymentsOverduesAndSoftDeletes() throws {
        let service = CreditCardDebtService()
        let (_, debt, rule) = try service.createDebt(
            CreditCardDebtInput(
                name: "Card",
                bankName: "Bank",
                note: "original",
                billingDay: 1,
                dueDay: 20,
                currencyCode: "USD"
            )
        )

        _ = try service.updateDebt(
            debt,
            input: CreditCardDebtInput(
                name: "Updated Card",
                bankName: "New Bank",
                note: "updated",
                billingDay: 2,
                dueDay: 21,
                currencyCode: "USD"
            )
        )
        #expect(debt.name == "Updated Card")
        #expect(debt.billingDay == 2)

        let (_, statement, plan) = try service.createUserConfirmedStatement(
            debt: debt,
            input: CreditCardStatementInput(
                billingDate: date(2026, 1, 2),
                dueDate: date(2026, 1, 21),
                statementAmount: 1000,
                minimumPaymentAmount: 100
            ),
            rule: rule,
            fallbackStatements: [],
            fallbackPlans: [],
            fallbackBreakdowns: []
        )
        var payments: [CreditCardPaymentRecord] = []
        var overdues: [CreditCardOverdueRecord] = []

        _ = try service.updateUserConfirmedStatement(
            statement,
            input: CreditCardStatementInput(
                billingDate: date(2026, 1, 2),
                dueDate: date(2026, 1, 21),
                statementAmount: 900,
                minimumPaymentAmount: nil
            ),
            debt: debt,
            plan: plan,
            payments: payments,
            overdues: &overdues,
            rule: rule,
            today: date(2026, 1, 10)
        )
        #expect(statement.statementAmount == 900)
        #expect(statement.minimumPaymentSource == "fallbackRule")

        let (_, payment) = try service.recordPayment(
            debt: debt,
            statement: statement,
            plan: plan,
            payments: &payments,
            overdues: &overdues,
            input: CreditCardPaymentInput(paymentDate: date(2026, 1, 22), amount: 50, note: "first"),
            rule: rule,
            today: date(2026, 1, 22)
        )

        _ = try service.updatePayment(
            payment,
            input: CreditCardPaymentInput(paymentDate: date(2026, 1, 23), amount: 150, note: "updated"),
            debt: debt,
            statement: statement,
            plan: plan,
            payments: payments,
            overdues: &overdues,
            rule: rule,
            today: date(2026, 1, 23)
        )
        #expect(payment.amount == 150)
        #expect(payment.note == "updated")

        _ = try service.softDeletePayment(
            payment,
            debt: debt,
            statement: statement,
            plan: plan,
            payments: payments,
            overdues: &overdues,
            rule: rule,
            today: date(2026, 1, 24)
        )
        #expect(payment.isActive == false)

        overdues.removeAll()
        let (_, manualOverdue) = try service.createManualOverdue(
            debt: debt,
            statement: statement,
            plan: plan,
            allStatements: [statement],
            existingOverdues: &overdues,
            input: CreditCardManualOverdueInput(
                overdueAmount: 900,
                overdueFee: 9,
                penaltyInterest: 4,
                startDate: date(2026, 1, 22),
                note: "manual"
            )
        )
        _ = try service.updateManualOverdue(
            manualOverdue,
            input: CreditCardManualOverdueInput(
                overdueAmount: 800,
                overdueFee: 8,
                penaltyInterest: 3,
                startDate: date(2026, 1, 22),
                endDate: date(2026, 1, 25),
                note: "ended"
            ),
            debt: debt,
            statement: statement,
            plan: plan,
            today: date(2026, 1, 25)
        )
        #expect(manualOverdue.status == .ended)
        #expect(manualOverdue.recordSource == .userAdjusted)

        _ = try service.voidOverdue(manualOverdue, status: .replaced, today: date(2026, 1, 26))
        #expect(manualOverdue.status == .replaced)
        #expect(manualOverdue.isActive == false)

        _ = try service.softDeleteStatement(
            statement,
            debt: debt,
            plan: plan,
            payments: payments,
            overdues: &overdues,
            today: date(2026, 1, 27)
        )
        #expect(statement.isActive == false)
        #expect(plan.isActive == false)

        let breakdown = CreditCardStatementBreakdown(statementID: statement.id, source: .userProvided)
        let installment = CreditCardInstallmentPlan(
            debtID: debt.id,
            nextBillingDate: date(2026, 2, 2),
            principalPerTerm: 10,
            feePerTerm: 1,
            interestPerTerm: 1,
            totalTerms: 3
        )
        _ = try service.softDeleteDebt(
            debt,
            statements: [statement],
            plans: [plan],
            breakdowns: [breakdown],
            payments: payments,
            overdues: overdues,
            installments: [installment],
            today: date(2026, 1, 28)
        )
        #expect(debt.status == .archived)
        #expect(breakdown.isActive == false)
        #expect(installment.isActive == false)
    }

    @Test
    func personalLendingServiceLocksCoreFieldsAfterPaymentButAllowsDisplayFields() throws {
        let service = PersonalLendingDebtService()
        let input = PersonalLendingDebtInput(
            name: "Friend",
            lenderName: "Alex",
            note: "",
            principalAmount: 1000,
            fixedInterestAmount: 0,
            borrowedDate: date(2026, 1, 1),
            agreedEndDate: date(2026, 2, 1),
            repaymentMethod: .principalAndInterestAtMaturity,
            isInterestBearing: false,
            monthlyRepaymentDay: nil,
            termCount: 0
        )
        let (_, debt, plans) = try service.createDebt(input)
        var payments: [PersonalLendingPaymentRecord] = []
        var allocations: [PersonalLendingAllocationDetail] = []

        let (_, payment) = try service.recordPayment(
            debt: debt,
            plans: plans,
            payments: &payments,
            allocationDetails: &allocations,
            input: PersonalLendingPaymentInput(paymentDate: date(2026, 1, 10), amount: 100),
            today: date(2026, 1, 10)
        )
        #expect(payment.amount == 100)

        var mutablePlans = plans
        do {
            _ = try service.updateCoreFields(
                debt: debt,
                input: PersonalLendingDebtInput(
                    name: "Friend",
                    lenderName: "Alex",
                    note: "",
                    principalAmount: 2000,
                    fixedInterestAmount: 0,
                    borrowedDate: date(2026, 1, 1),
                    agreedEndDate: date(2026, 2, 1),
                    repaymentMethod: .principalAndInterestAtMaturity,
                    isInterestBearing: false,
                    monthlyRepaymentDay: nil,
                    termCount: 0
                ),
                existingPayments: payments,
                plans: &mutablePlans
            )
            #expect(Bool(false))
        } catch {
            #expect(error is DebtServiceError)
        }

        _ = try service.updateDisplayFields(debt: debt, name: "Updated", lenderName: "Alex", note: "ok")
        #expect(debt.name == "Updated")
        #expect(debt.note == "ok")

        do {
            _ = try service.updateDisplayFields(debt: debt, name: "   ", lenderName: "Alex", note: "bad")
            #expect(Bool(false))
        } catch {
            #expect(error is DebtServiceError)
            #expect(debt.name == "Updated")
        }
    }

    @Test
    func personalLendingServiceRejectsInvalidIdentityAndDateBoundaries() throws {
        let service = PersonalLendingDebtService()

        do {
            _ = try service.createDebt(
                PersonalLendingDebtInput(
                    name: " ",
                    lenderName: "Alex",
                    note: "",
                    principalAmount: 500,
                    fixedInterestAmount: 0,
                    borrowedDate: date(2026, 1, 10),
                    agreedEndDate: date(2026, 1, 20),
                    repaymentMethod: .principalAndInterestAtMaturity,
                    isInterestBearing: false,
                    monthlyRepaymentDay: nil,
                    termCount: 0
                )
            )
            #expect(Bool(false))
        } catch {
            #expect(error is DebtServiceError)
        }

        do {
            _ = try service.createDebt(
                PersonalLendingDebtInput(
                    name: "Open",
                    lenderName: "Alex",
                    note: "",
                    principalAmount: 500,
                    fixedInterestAmount: 0,
                    borrowedDate: date(2026, 1, 10),
                    agreedEndDate: date(2026, 1, 9),
                    repaymentMethod: .noFixedPlan,
                    isInterestBearing: false,
                    monthlyRepaymentDay: nil,
                    termCount: 0
                )
            )
            #expect(Bool(false))
        } catch {
            #expect(error is PersonalLendingValidationError)
        }
    }

    @Test
    func personalLendingServiceKeepsPastDueOutOfOverdueState() throws {
        let service = PersonalLendingDebtService()
        let input = PersonalLendingDebtInput(
            name: "Open",
            lenderName: "",
            note: "",
            principalAmount: 500,
            fixedInterestAmount: 0,
            borrowedDate: date(2026, 1, 1),
            agreedEndDate: date(2026, 1, 10),
            repaymentMethod: .noFixedPlan,
            isInterestBearing: false,
            monthlyRepaymentDay: nil,
            termCount: 0
        )
        let (_, debt, plans) = try service.createDebt(input)
        var payments: [PersonalLendingPaymentRecord] = []
        var allocations: [PersonalLendingAllocationDetail] = []

        _ = try service.recordPayment(
            debt: debt,
            plans: plans,
            payments: &payments,
            allocationDetails: &allocations,
            input: PersonalLendingPaymentInput(paymentDate: date(2026, 1, 5), amount: 100),
            today: date(2026, 1, 20)
        )

        #expect(debt.pastDueScheduledAmount == 400)
        #expect(debt.pastDueDebtCount == 1)
        #expect(debt.status == .partiallyPaid)
        #expect(debt.status != .overdue)
    }

    @Test
    func personalLendingOverdueCrudCreatesResolvesAndIgnoresRecords() throws {
        let service = PersonalLendingDebtService()
        let input = PersonalLendingDebtInput(
            name: "Friend",
            lenderName: "Alex",
            note: "",
            principalAmount: 1000,
            fixedInterestAmount: 0,
            borrowedDate: date(2026, 1, 1),
            agreedEndDate: date(2026, 1, 10),
            repaymentMethod: .principalAndInterestAtMaturity,
            isInterestBearing: false,
            monthlyRepaymentDay: nil,
            termCount: 0
        )
        let (_, debt, plans) = try service.createDebt(input)
        var overdues: [PersonalLendingOverdueRecord] = []

        _ = try service.refreshOverdues(
            debt: debt,
            plans: plans,
            overdues: &overdues,
            today: date(2026, 1, 20)
        )

        #expect(overdues.count == 1)
        #expect(overdues[0].status == .active)
        #expect(overdues[0].source == .systemGenerated)
        #expect(plans[0].status == .overdue)
        #expect(debt.status == .overdue)

        _ = try service.resolveOverdue(
            overdues[0],
            debt: debt,
            plan: plans[0],
            plans: plans,
            overdues: overdues,
            endDate: date(2026, 1, 25),
            today: date(2026, 1, 25)
        )

        #expect(overdues[0].status == .resolved)
        #expect(overdues[0].overdueDays == 15)

        _ = try service.createManualOverdue(
            debt: debt,
            plan: plans[0],
            existingOverdues: &overdues,
            input: PersonalLendingManualOverdueInput(
                overdueAmount: 900,
                overdueFee: 10,
                penaltyInterest: 5,
                startDate: date(2026, 1, 15),
                note: "confirmed"
            ),
            today: date(2026, 1, 25)
        )

        #expect(overdues.count == 2)
        #expect(overdues[1].source == .userCreated)
        #expect(overdues[1].note == "confirmed")

        _ = try service.voidOverdue(
            overdues[1],
            debt: debt,
            plan: plans[0],
            plans: plans,
            overdues: overdues,
            status: .ignored,
            today: date(2026, 1, 25)
        )
        #expect(overdues[1].status == .ignored)
    }

    @Test
    func personalLendingUpdatePaymentRollsBackWhenMutationWouldOverpay() throws {
        let service = PersonalLendingDebtService()
        let (_, debt, plans) = try service.createDebt(
            PersonalLendingDebtInput(
                name: "Friend",
                lenderName: "Alex",
                note: "",
                principalAmount: 1000,
                fixedInterestAmount: 0,
                borrowedDate: date(2026, 1, 1),
                agreedEndDate: date(2026, 2, 1),
                repaymentMethod: .principalAndInterestAtMaturity,
                isInterestBearing: false,
                monthlyRepaymentDay: nil,
                termCount: 0
            )
        )
        var payments: [PersonalLendingPaymentRecord] = []
        var allocations: [PersonalLendingAllocationDetail] = []

        let (_, firstPayment) = try service.recordPayment(
            debt: debt,
            plans: plans,
            payments: &payments,
            allocationDetails: &allocations,
            input: PersonalLendingPaymentInput(paymentDate: date(2026, 1, 10), amount: 400, note: "first"),
            today: date(2026, 1, 10)
        )
        _ = try service.recordPayment(
            debt: debt,
            plans: plans,
            payments: &payments,
            allocationDetails: &allocations,
            input: PersonalLendingPaymentInput(paymentDate: date(2026, 1, 20), amount: 300, note: "second"),
            today: date(2026, 1, 20)
        )

        let oldDate = firstPayment.paymentDate
        let oldAmount = firstPayment.amount
        let oldNote = firstPayment.note
        let oldUpdatedAt = firstPayment.updatedAt

        do {
            _ = try service.updatePayment(
                firstPayment,
                input: PersonalLendingPaymentInput(paymentDate: date(2026, 1, 15), amount: 800, note: "edited"),
                debt: debt,
                plans: plans,
                payments: payments,
                allocationDetails: &allocations,
                today: date(2026, 1, 25)
            )
            #expect(Bool(false))
        } catch {
            #expect(error is PersonalLendingPaymentError)
        }

        #expect(firstPayment.paymentDate == oldDate)
        #expect(firstPayment.amount == oldAmount)
        #expect(firstPayment.note == oldNote)
        #expect(firstPayment.updatedAt == oldUpdatedAt)
        #expect(debt.paidAmount == decimal("700"))
        #expect(debt.remainingAmount == decimal("300"))
    }

    @Test
    func personalLendingDeletePaymentRecalculatesDebtAndAllocations() throws {
        let service = PersonalLendingDebtService()
        let (_, debt, plans) = try service.createDebt(
            PersonalLendingDebtInput(
                name: "Friend",
                lenderName: "Alex",
                note: "",
                principalAmount: 600,
                fixedInterestAmount: 0,
                borrowedDate: date(2026, 1, 1),
                agreedEndDate: date(2026, 2, 1),
                repaymentMethod: .principalAndInterestAtMaturity,
                isInterestBearing: false,
                monthlyRepaymentDay: nil,
                termCount: 0
            )
        )
        var payments: [PersonalLendingPaymentRecord] = []
        var allocations: [PersonalLendingAllocationDetail] = []

        _ = try service.recordPayment(
            debt: debt,
            plans: plans,
            payments: &payments,
            allocationDetails: &allocations,
            input: PersonalLendingPaymentInput(paymentDate: date(2026, 1, 10), amount: 200),
            today: date(2026, 1, 10)
        )
        let (_, secondPayment) = try service.recordPayment(
            debt: debt,
            plans: plans,
            payments: &payments,
            allocationDetails: &allocations,
            input: PersonalLendingPaymentInput(paymentDate: date(2026, 1, 20), amount: 150),
            today: date(2026, 1, 20)
        )
        #expect(debt.paidAmount == decimal("350"))
        #expect(allocations.count == 2)

        _ = try service.deletePayment(
            secondPayment,
            debt: debt,
            plans: plans,
            payments: &payments,
            allocationDetails: &allocations,
            today: date(2026, 1, 21)
        )

        #expect(payments.count == 1)
        #expect(payments[0].amount == decimal("200"))
        #expect(debt.paidAmount == decimal("200"))
        #expect(debt.remainingAmount == decimal("400"))
        #expect(allocations.count == 1)
        #expect(allocations[0].allocatedAmount == decimal("200"))
    }

    @Test
    func personalLendingNoPlanIgnoredOverdueDoesNotRegenerateOnRefresh() throws {
        let service = PersonalLendingDebtService()
        let (_, debt, plans) = try service.createDebt(
            PersonalLendingDebtInput(
                name: "Open",
                lenderName: "",
                note: "",
                principalAmount: 500,
                fixedInterestAmount: 0,
                borrowedDate: date(2026, 1, 1),
                agreedEndDate: date(2026, 1, 10),
                repaymentMethod: .noFixedPlan,
                isInterestBearing: false,
                monthlyRepaymentDay: nil,
                termCount: 0
            )
        )
        var overdues: [PersonalLendingOverdueRecord] = []

        #expect(plans.isEmpty)
        _ = try service.refreshOverdues(
            debt: debt,
            plans: plans,
            overdues: &overdues,
            today: date(2026, 1, 20)
        )
        #expect(overdues.count == 1)
        #expect(overdues[0].status == .active)
        #expect(overdues[0].planID == nil)

        _ = try service.voidOverdue(
            overdues[0],
            debt: debt,
            plan: nil,
            plans: plans,
            overdues: overdues,
            status: .ignored,
            today: date(2026, 1, 20)
        )
        _ = try service.refreshOverdues(
            debt: debt,
            plans: plans,
            overdues: &overdues,
            today: date(2026, 1, 25)
        )

        #expect(overdues.count == 1)
        #expect(overdues[0].status == .ignored)
        #expect(debt.status == .active)
    }

    @Test
    func personalLendingRejectsEditingSystemOverdueAndSoftDeleteVoidsRelatedRecords() throws {
        let service = PersonalLendingDebtService()
        let (_, debt, plans) = try service.createDebt(
            PersonalLendingDebtInput(
                name: "Friend",
                lenderName: "Alex",
                note: "",
                principalAmount: 1000,
                fixedInterestAmount: 0,
                borrowedDate: date(2026, 1, 1),
                agreedEndDate: date(2026, 1, 10),
                repaymentMethod: .principalAndInterestAtMaturity,
                isInterestBearing: false,
                monthlyRepaymentDay: nil,
                termCount: 0
            )
        )
        var overdues: [PersonalLendingOverdueRecord] = []

        _ = try service.refreshOverdues(
            debt: debt,
            plans: plans,
            overdues: &overdues,
            today: date(2026, 1, 20)
        )

        do {
            _ = try service.updateManualOverdue(
                overdues[0],
                debt: debt,
                plan: plans[0],
                plans: plans,
                overdues: overdues,
                input: PersonalLendingManualOverdueInput(
                    overdueAmount: 900,
                    overdueFee: 5,
                    penaltyInterest: 1,
                    startDate: date(2026, 1, 12)
                ),
                today: date(2026, 1, 20)
            )
            #expect(Bool(false))
        } catch {
            #expect(error is DebtServiceError)
        }

        _ = try service.createManualOverdue(
            debt: debt,
            plan: nil,
            existingOverdues: &overdues,
            input: PersonalLendingManualOverdueInput(
                overdueAmount: 1000,
                overdueFee: 10,
                penaltyInterest: 2,
                startDate: date(2026, 1, 12),
                note: "manual"
            ),
            today: date(2026, 1, 20)
        )
        #expect(overdues.count == 2)

        _ = try service.softDeleteDebt(debt, overdues: overdues, today: date(2026, 1, 30))

        #expect(debt.isArchived)
        #expect(debt.status == .archived)
        #expect(overdues.allSatisfy { $0.status == .voided })
        #expect(overdues.allSatisfy { $0.overdueEndDate != nil })
    }

    @Test
    func loanOverdueEngineUpdatesExistingRecordsAndPlanStatusBranches() throws {
        let engine = LoanOverdueEngine()
        let debt = LoanDebt(
            name: "Loan",
            creditorName: "Bank",
            repaymentMethod: .equalPrincipal,
            originalPrincipal: 1000,
            annualInterestRate: decimal("0.365"),
            startDate: date(2026, 1, 1),
            endDate: date(2026, 12, 31),
            repaymentDay: 10,
            termCount: 12
        )
        let plan = LoanRepaymentPlan(
            debtID: debt.id,
            periodIndex: 1,
            periodType: .regular,
            periodStartDate: date(2026, 1, 1),
            periodEndDate: date(2026, 1, 31),
            dueDate: date(2026, 1, 10),
            scheduledPrincipal: 100,
            scheduledInterest: 20,
            remainingPrincipalBeforePayment: 1000,
            remainingPrincipalAfterScheduledPayment: 900
        )
        let percentageRule = LoanCalculationRule(
            debtID: debt.id,
            overdueBaseType: .currentRemainingScheduledAmount,
            overdueFeeMode: .percentage,
            overdueFeeRate: decimal("0.10"),
            penaltyInterestMode: .fixedDailyRate,
            fixedPenaltyDailyRate: decimal("0.01")
        )

        let created = try #require(engine.makeOrUpdateOverdueRecord(
            for: plan,
            debt: debt,
            rule: percentageRule,
            today: date(2026, 1, 20)
        ))

        #expect(created.overdueDays == 10)
        #expect(created.overdueBaseAmount == 120)
        #expect(created.overdueFee == 12)
        #expect(created.penaltyInterest == 12)
        #expect(plan.status == .overdue)
        #expect(plan.remainingTotalAmount == 144)

        plan.paidPrincipal = 40
        plan.remainingPrincipal = 60
        plan.paidTotalAmount = 40
        let disabledRule = LoanCalculationRule(
            debtID: debt.id,
            overdueFeeMode: .disabled,
            penaltyInterestMode: .disabled
        )
        let updated = try #require(engine.makeOrUpdateOverdueRecord(
            for: plan,
            debt: debt,
            existingRecord: created,
            rule: disabledRule,
            today: date(2026, 1, 25)
        ))

        #expect(updated === created)
        #expect(updated.generatesOverdueFee == false)
        #expect(updated.generatesPenaltyInterest == false)
        #expect(plan.status == .partiallyPaid)

        let userManaged = LoanOverdueRecord(
            debtID: debt.id,
            planID: plan.id,
            source: .userCreated,
            isUserManaged: true,
            overdueStartDate: date(2026, 1, 10),
            overdueDays: 1,
            overdueBaseAmount: 10
        )
        let unchanged = try #require(engine.makeOrUpdateOverdueRecord(
            for: plan,
            debt: debt,
            existingRecord: userManaged,
            rule: percentageRule,
            today: date(2026, 1, 26)
        ))

        #expect(unchanged.overdueDays == 1)

        updated.status = .closed
        #expect(engine.status(for: plan, overdueRecord: updated) == .closed)
        plan.remainingPrincipal = 0
        plan.remainingInterest = 0
        updated.paidOverdueFee = updated.overdueFee
        updated.paidPenaltyInterest = updated.penaltyInterest
        #expect(engine.status(for: plan, overdueRecord: updated) == .paid)
    }

    @Test
    func personalLendingCoreUpdateAndOverdueRefreshCoverStateTransitions() throws {
        let service = PersonalLendingDebtService()
        let (_, plannedDebt, generatedPlans) = try service.createDebt(
            PersonalLendingDebtInput(
                name: "Planned Friend",
                lenderName: "Alex",
                note: "",
                principalAmount: 900,
                fixedInterestAmount: 90,
                borrowedDate: date(2026, 1, 1),
                agreedEndDate: date(2026, 6, 10),
                repaymentMethod: .equalPrincipalEqualInterest,
                isInterestBearing: true,
                monthlyRepaymentDay: 10,
                termCount: 6
            )
        )
        var plans = generatedPlans

        let (_, regeneratedPlans) = try service.updateCoreFields(
            debt: plannedDebt,
            input: PersonalLendingDebtInput(
                name: "Planned Friend",
                lenderName: "Alex",
                note: "",
                principalAmount: 1200,
                fixedInterestAmount: 120,
                borrowedDate: date(2026, 1, 1),
                agreedEndDate: date(2026, 4, 10),
                repaymentMethod: .equalPrincipalEqualInterest,
                isInterestBearing: true,
                monthlyRepaymentDay: 10,
                termCount: 4
            ),
            existingPayments: [],
            plans: &plans
        )

        #expect(regeneratedPlans.count == 4)
        #expect(plannedDebt.principalAmount == 1200)
        #expect(plans.count == 4)

        let debtLevel = PersonalLendingDebt(
            name: "No Plan Friend",
            lenderName: "Sam",
            principalAmount: 500,
            fixedInterestAmount: 0,
            borrowedDate: date(2026, 1, 1),
            agreedEndDate: date(2026, 1, 10),
            repaymentMethod: .noFixedPlan,
            isInterestBearing: false,
            termCount: 0
        )
        var debtLevelOverdues: [PersonalLendingOverdueRecord] = []
        _ = try service.refreshOverdues(
            debt: debtLevel,
            plans: [],
            overdues: &debtLevelOverdues,
            today: date(2026, 1, 20)
        )

        #expect(debtLevelOverdues.count == 1)
        #expect(debtLevelOverdues[0].overdueDays == 10)
        #expect(debtLevel.status == .overdue)

        _ = try service.refreshOverdues(
            debt: debtLevel,
            plans: [],
            overdues: &debtLevelOverdues,
            today: date(2026, 1, 25)
        )
        #expect(debtLevelOverdues[0].overdueDays == 15)

        _ = try service.voidOverdue(
            debtLevelOverdues[0],
            debt: debtLevel,
            plan: nil,
            plans: [],
            overdues: debtLevelOverdues,
            status: .ignored,
            today: date(2026, 1, 26)
        )
        let ignoredCount = debtLevelOverdues.count
        _ = try service.refreshOverdues(
            debt: debtLevel,
            plans: [],
            overdues: &debtLevelOverdues,
            today: date(2026, 1, 30)
        )
        #expect(debtLevelOverdues.count == ignoredCount)
    }

    @Test
    func personalLendingManualOverdueUpdateResolvesAndReactivatesRecords() throws {
        let service = PersonalLendingDebtService()
        let debt = PersonalLendingDebt(
            name: "Manual Friend",
            lenderName: "Pat",
            principalAmount: 600,
            fixedInterestAmount: 0,
            borrowedDate: date(2026, 1, 1),
            agreedEndDate: date(2026, 1, 10),
            repaymentMethod: .noFixedPlan,
            isInterestBearing: false,
            termCount: 0
        )
        var overdues: [PersonalLendingOverdueRecord] = []

        let (_, record) = try service.createManualOverdue(
            debt: debt,
            plan: nil,
            existingOverdues: &overdues,
            input: PersonalLendingManualOverdueInput(
                overdueAmount: 600,
                overdueFee: 5,
                penaltyInterest: 2,
                startDate: date(2026, 1, 12),
                note: "created"
            ),
            today: date(2026, 1, 20)
        )

        _ = try service.updateManualOverdue(
            record,
            debt: debt,
            plan: nil,
            plans: [],
            overdues: overdues,
            input: PersonalLendingManualOverdueInput(
                overdueAmount: 550,
                overdueFee: 4,
                penaltyInterest: 1,
                startDate: date(2026, 1, 12),
                endDate: date(2026, 1, 18),
                note: "resolved"
            ),
            today: date(2026, 1, 21)
        )

        #expect(record.source == .userAdjusted)
        #expect(record.status == .resolved)
        #expect(record.overdueDays == 6)
        #expect(debt.status == .active)

        _ = try service.updateManualOverdue(
            record,
            debt: debt,
            plan: nil,
            plans: [],
            overdues: overdues,
            input: PersonalLendingManualOverdueInput(
                overdueAmount: 500,
                overdueFee: 3,
                penaltyInterest: 1,
                startDate: date(2026, 1, 13),
                note: "active again"
            ),
            today: date(2026, 1, 22)
        )

        #expect(record.status == .active)
        #expect(record.overdueEndDate == nil)
        #expect(debt.status == .overdue)
    }
}
