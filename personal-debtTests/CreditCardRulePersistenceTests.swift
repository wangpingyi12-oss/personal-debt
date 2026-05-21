import Foundation
import SwiftData
import Testing
@testable import personal_debt

@MainActor
struct CreditCardRulePersistenceTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            CreditCardDebt.self,
            CreditCardCalculationRule.self,
            CreditCardStatement.self,
            CreditCardStatementBreakdown.self,
            CreditCardRepaymentPlan.self,
            CreditCardPaymentRecord.self,
            CreditCardOverdueRecord.self,
            CreditCardInstallmentPlan.self,
            LoanDebt.self,
            LoanRepaymentPlan.self,
            LoanPaymentRecord.self,
            LoanPaymentAllocationDetail.self,
            LoanOverdueRecord.self,
            LoanCalculationRule.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value) ?? 0
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    private func expectValidation(_ work: () throws -> Void) {
        do {
            try work()
            #expect(Bool(false))
        } catch let error as DebtServiceError {
            if case .validationFailed = error {
                #expect(Bool(true))
            } else {
                #expect(Bool(false))
            }
        } catch {
            #expect(Bool(false))
        }
    }

    @Test
    func defaultRuleSeederCreatesGlobalDefaultsForBothDebtTypes() throws {
        let container = try makeContainer()
        let context = container.mainContext

        try DefaultCalculationRuleSeeder.ensureSeeded(in: context)
        try DefaultCalculationRuleSeeder.ensureSeeded(in: context)

        let creditRules = try context.fetch(FetchDescriptor<CreditCardCalculationRule>())
        let loanRules = try context.fetch(FetchDescriptor<LoanCalculationRule>())

        #expect(creditRules.count == 1)
        #expect(creditRules.first?.debtID == nil)
        #expect(loanRules.count == 1)
        #expect(loanRules.first?.debtID == nil)
    }

    @Test
    func creditCardServiceCreatesGlobalDefaultRuleWhenMissing() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let service = CreditCardDebtService(modelContext: context)

        let (_, debt, returnedRule) = try service.createDebt(
            CreditCardDebtInput(name: "Card", billingDay: 1, dueDay: 20)
        )

        let storedRules = try context.fetch(FetchDescriptor<CreditCardCalculationRule>())
        let resolvedRule = service.effectiveCalculationRule(for: debt, rules: storedRules)

        #expect(returnedRule.debtID == nil)
        #expect(storedRules.count == 1)
        #expect(storedRules.first?.debtID == nil)
        #expect(resolvedRule.id == returnedRule.id)
    }

    @Test
    func creditCardRulePriorityDedupesAndRestoresDefault() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let service = CreditCardDebtService(modelContext: context)
        let (_, debt, _) = try service.createDebt(
            CreditCardDebtInput(name: "Card", billingDay: 1, dueDay: 20)
        )

        let (_, globalRule) = try service.upsertCalculationRule(
            input: CreditCardCalculationRuleInput(minimumPaymentRatio: decimal("0.20"))
        )
        #expect(service.effectiveCalculationRule(for: debt, rules: try context.fetch(FetchDescriptor<CreditCardCalculationRule>())).id == globalRule.id)

        let (_, debtRule) = try service.upsertCalculationRule(
            input: CreditCardCalculationRuleInput(debtID: debt.id, minimumPaymentRatio: decimal("0.05"))
        )
        let (_, updatedDebtRule) = try service.upsertCalculationRule(
            input: CreditCardCalculationRuleInput(debtID: debt.id, minimumPaymentRatio: decimal("0.07"))
        )
        let rulesAfterUpsert = try context.fetch(FetchDescriptor<CreditCardCalculationRule>())

        #expect(debtRule.id == updatedDebtRule.id)
        #expect(rulesAfterUpsert.filter { $0.debtID == debt.id }.count == 1)
        #expect(service.effectiveCalculationRule(for: debt, rules: rulesAfterUpsert).minimumPaymentRatio == decimal("0.07"))

        _ = try service.deleteCalculationRule(updatedDebtRule)
        let rulesAfterDelete = try context.fetch(FetchDescriptor<CreditCardCalculationRule>())

        #expect(rulesAfterDelete.contains { $0.debtID == debt.id } == false)
        #expect(service.effectiveCalculationRule(for: debt, rules: rulesAfterDelete).id == globalRule.id)
        #expect(service.effectiveCalculationRule(for: debt, rules: rulesAfterDelete).minimumPaymentRatio == decimal("0.20"))
    }

    @Test
    func creditCardRuleValidationReadModelAndFallbackBranches() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let service = CreditCardDebtService(modelContext: context)
        let (_, debt, _) = try service.createDebt(
            CreditCardDebtInput(name: "Branch Card", billingDay: 1, dueDay: 20)
        )
        let defaultInput = CreditCardCalculationRuleInput()
        let globalRule = try #require(try context.fetch(FetchDescriptor<CreditCardCalculationRule>()).first)

        #expect(defaultInput.minimumPaymentRatio == decimal("0.10"))
        #expect(CreditCardCalculationRule.builtInDefault().isGlobalDefault)
        #expect(service.effectiveCalculationRule(for: debt, rules: []).debtID == debt.id)

        expectValidation {
            _ = try service.deleteCalculationRule(globalRule)
        }

        let (_, debtRule) = try service.upsertCalculationRule(
            input: CreditCardCalculationRuleInput(debtID: debt.id, minimumPaymentRatio: decimal("0.15")),
            today: date(2026, 1, 5)
        )
        let (_, updatedRule) = try service.upsertCalculationRule(
            existingRule: debtRule,
            input: CreditCardCalculationRuleInput(debtID: debt.id, minimumPaymentRatio: decimal("0.16")),
            today: date(2026, 1, 6)
        )
        let detail = DebtReadService().creditCardDetail(
            debt: debt,
            statements: [],
            payments: [],
            overdues: [],
            rules: [updatedRule]
        )

        #expect(detail.rule?.id == updatedRule.id)
        #expect(updatedRule.minimumPaymentRatio == decimal("0.16"))

        expectValidation {
            _ = try service.upsertCalculationRule(input: CreditCardCalculationRuleInput(minimumPaymentRatio: decimal("1.01")))
        }
        expectValidation {
            _ = try service.upsertCalculationRule(input: CreditCardCalculationRuleInput(revolvingDailyRate: decimal("1.01")))
        }
        expectValidation {
            _ = try service.upsertCalculationRule(input: CreditCardCalculationRuleInput(overdueFeeRate: decimal("1.01")))
        }
        expectValidation {
            _ = try service.upsertCalculationRule(input: CreditCardCalculationRuleInput(fixedOverdueFee: -1))
        }
        expectValidation {
            _ = try service.upsertCalculationRule(input: CreditCardCalculationRuleInput(penaltyDailyRate: decimal("1.01")))
        }
    }

    @Test
    func creditCardGlobalRuleRefreshesOnlyInheritedStatements() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let service = CreditCardDebtService(modelContext: context)
        let (_, customDebt, initialRule) = try service.createDebt(
            CreditCardDebtInput(name: "Custom Card", billingDay: 1, dueDay: 20)
        )
        let (_, inheritedDebt, _) = try service.createDebt(
            CreditCardDebtInput(name: "Inherited Card", billingDay: 1, dueDay: 20)
        )
        let (_, customStatement, _) = try service.createUserConfirmedStatement(
            debt: customDebt,
            input: CreditCardStatementInput(
                billingDate: date(2026, 1, 1),
                dueDate: date(2026, 1, 20),
                statementAmount: 1000,
                minimumPaymentAmount: nil
            ),
            rule: initialRule,
            fallbackStatements: [],
            fallbackPlans: [],
            fallbackBreakdowns: []
        )
        let (_, inheritedStatement, _) = try service.createUserConfirmedStatement(
            debt: inheritedDebt,
            input: CreditCardStatementInput(
                billingDate: date(2026, 1, 1),
                dueDate: date(2026, 1, 20),
                statementAmount: 1000,
                minimumPaymentAmount: nil
            ),
            rule: initialRule,
            fallbackStatements: [],
            fallbackPlans: [],
            fallbackBreakdowns: []
        )

        _ = try service.upsertCalculationRule(
            input: CreditCardCalculationRuleInput(debtID: customDebt.id, minimumPaymentRatio: decimal("0.30")),
            today: date(2026, 1, 10)
        )
        _ = try service.upsertCalculationRule(
            input: CreditCardCalculationRuleInput(minimumPaymentRatio: decimal("0.20")),
            today: date(2026, 1, 10)
        )

        #expect(customStatement.minimumPaymentAmount == 300)
        #expect(inheritedStatement.minimumPaymentAmount == 200)
    }

    @Test
    func loanRuleChangeRefreshesOverduesAndRebuildsAllocations() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let service = LoanDebtService(modelContext: context)
        let (_, debt, plans) = try service.createDebt(
            LoanDebtInput(
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
        )
        let (_, feeFirstRule) = try service.upsertCalculationRule(
            input: LoanCalculationRuleInput(
                overdueFeeMode: .fixed,
                fixedOverdueFee: 5,
                penaltyInterestMode: .zero,
                paymentAllocationMode: .feeFirst
            ),
            today: date(2026, 1, 20)
        )
        let overdues = try context.fetch(FetchDescriptor<LoanOverdueRecord>())
        var payments: [LoanPaymentRecord] = []
        var allocations: [LoanPaymentAllocationDetail] = []

        _ = try service.recordPayment(
            debt: debt,
            plans: plans,
            payments: &payments,
            allocationDetails: &allocations,
            overdues: overdues,
            input: LoanPaymentInput(paymentDate: date(2026, 2, 10), totalAmount: 50),
            rule: feeFirstRule,
            today: date(2026, 2, 10)
        )

        let initialAllocations = try context.fetch(FetchDescriptor<LoanPaymentAllocationDetail>())
        let firstAllocation = try #require(initialAllocations.first)
        #expect(firstAllocation.planID == plans[0].id)
        #expect(firstAllocation.allocatedOverdueFee == 5)

        _ = try service.upsertCalculationRule(
            existingRule: feeFirstRule,
            input: LoanCalculationRuleInput(
                overdueFeeMode: .fixed,
                fixedOverdueFee: 5,
                penaltyInterestMode: .zero,
                paymentAllocationMode: .currentPeriodFirst
            ),
            today: date(2026, 2, 10)
        )

        let rebuiltAllocations = try context.fetch(FetchDescriptor<LoanPaymentAllocationDetail>())
        let rebuiltAllocation = try #require(rebuiltAllocations.first)
        #expect(rebuiltAllocation.planID == plans[1].id)
        #expect(rebuiltAllocation.allocatedOverdueFee == 0)
        #expect(rebuiltAllocation.allocatedPrincipal == 50)
    }

    @Test
    func loanRuleRefreshDoesNotOverwriteManualOverdue() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let service = LoanDebtService(modelContext: context)
        let (_, debt, plans) = try service.createDebt(
            LoanDebtInput(
                name: "Manual Loan",
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
        )
        var overdues: [LoanOverdueRecord] = []
        let (_, manual) = try service.createManualOverdue(
            debt: debt,
            plan: plans[0],
            existingOverdues: &overdues,
            input: LoanManualOverdueInput(
                overdueFee: 3,
                penaltyInterest: 2,
                startDate: date(2026, 1, 10)
            ),
            today: date(2026, 1, 20)
        )

        _ = try service.upsertCalculationRule(
            input: LoanCalculationRuleInput(
                overdueFeeMode: .fixed,
                fixedOverdueFee: 99,
                penaltyInterestMode: .fixedDailyRate,
                fixedPenaltyDailyRate: decimal("0.10")
            ),
            today: date(2026, 1, 20)
        )

        #expect(manual.isUserManaged)
        #expect(manual.overdueFee == 3)
        #expect(manual.penaltyInterest == 2)
        #expect(try context.fetch(FetchDescriptor<LoanOverdueRecord>()).count == 1)
    }

    @Test
    func loanRuleDeletionAndIgnoredOverdueBranches() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let service = LoanDebtService(modelContext: context)
        let (_, debt, plans) = try service.createDebt(
            LoanDebtInput(
                name: "Ignored Loan",
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
        )
        let defaultRule = LoanCalculationRule.builtInDefault()
        context.insert(defaultRule)
        let ignoredOverdue = LoanOverdueRecord(
            debtID: debt.id,
            planID: plans[0].id,
            status: .ignored,
            overdueStartDate: date(2026, 1, 10),
            overdueDays: 5
        )
        context.insert(ignoredOverdue)
        try context.save()

        expectValidation {
            _ = try service.deleteCalculationRule(defaultRule)
        }

        let (_, customRule) = try service.upsertCalculationRule(
            input: LoanCalculationRuleInput(
                debtID: debt.id,
                overdueFeeMode: .fixed,
                fixedOverdueFee: 10,
                penaltyInterestMode: .zero
            ),
            today: date(2026, 1, 15)
        )
        let overdues = try context.fetch(FetchDescriptor<LoanOverdueRecord>())

        #expect(customRule.debtID == debt.id)
        #expect(overdues.count == 1)
        #expect(overdues.first?.status == .ignored)
    }
}
