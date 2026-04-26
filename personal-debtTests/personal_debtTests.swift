//
//  personal_debtTests.swift
//  personal-debtTests
//
//  Created by Mac on 2026/4/25.

import Foundation
import SwiftData
import Testing
@testable import personal_debt

@MainActor
struct personal_debtTests {
    private func makeInMemoryModelContext() throws -> ModelContext {
        let schema = Schema([CalculationRuleProfile.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    @Test func compareStrategiesDetailedProducesChartReadyTimelineData() async throws {
        let debtA = Debt(
            name: "A债务",
            type: .loan,
            subtype: "信用贷款",
            principal: 10_000,
            nominalAPR: 0.22,
            effectiveAPR: FinanceEngine.effectiveAPR(nominalAPR: 0.22),
            startDate: Date()
        )
        debtA.repaymentPlans = [
            RepaymentPlan(periodIndex: 1, dueDate: Date(), principalDue: 800, interestDue: 120, minimumDue: 400, debt: debtA)
        ]

        let debtB = Debt(
            name: "B债务",
            type: .loan,
            subtype: "信用贷款",
            principal: 6_000,
            nominalAPR: 0.12,
            effectiveAPR: FinanceEngine.effectiveAPR(nominalAPR: 0.12),
            startDate: Date()
        )
        debtB.repaymentPlans = [
            RepaymentPlan(periodIndex: 1, dueDate: Calendar.current.date(byAdding: .day, value: 10, to: Date()) ?? Date(), principalDue: 500, interestDue: 50, minimumDue: 200, debt: debtB)
        ]

        let results = FinanceEngine.compareStrategiesDetailed(
            debts: [debtA, debtB],
            monthlyBudget: 1_600,
            constraints: .init(
                includeMinimumDue: true,
                includeOverduePenalty: true,
                prioritizeOverdueBalances: true,
                requireFullOverdueCoverage: true,
                minimumMonthlyReserve: 0,
                requireFullMinimumCoverage: true,
                maxMonths: 120
            )
        )

        #expect(results.count == StrategyMethod.allCases.count)

        for method in StrategyMethod.allCases {
            let result = try #require(results[method])
            let timeline = try #require(FinanceEngine.decodeStrategyTimeline(from: result.timelineJSON))
            #expect(timeline.method == method.rawValue)
            #expect(timeline.records.isEmpty == false)
            #expect((timeline.records.first?.paymentApplied ?? 0) >= 0)
            #expect((timeline.records.first?.totalPrincipal ?? 0) >= 0)
        }
    }

    @Test func paymentAllocationOrder() async throws {
        let result = FinanceEngine.allocatePayment(
            amount: 1000,
            overdueFee: 100,
            penaltyInterest: 200,
            interest: 300,
            principal: 800
        )

        #expect(result.overdueFee == 100)
        #expect(result.penaltyInterest == 200)
        #expect(result.interest == 300)
        #expect(result.principal == 400)
        #expect(result.totalApplied == 1000)
    }

    @Test func effectiveAPRIsGreaterThanNominalWhenCompounded() async throws {
        let nominal = 0.12
        let effective = FinanceEngine.effectiveAPR(nominalAPR: nominal, periodsPerYear: 12)
        #expect(effective > nominal)
    }

    @Test func loanPlanGenerationHasCorrectPeriods() async throws {
        let rows = FinanceEngine.generateLoanPlan(
            principal: 12000,
            annualRate: 0.12,
            termMonths: 12,
            method: .equalPrincipal,
            startDate: Date()
        )

        #expect(rows.count == 12)
        let principalSum = rows.reduce(0) { $0 + $1.principal }
        #expect(abs(principalSum - 12000) < 1)
    }

    @Test func paymentAllocationOrderPenaltyFirst() async throws {
        let result = FinanceEngine.allocatePayment(
            amount: 120,
            overdueFee: 80,
            penaltyInterest: 100,
            interest: 0,
            principal: 0,
            order: .penaltyFirst
        )

        #expect(result.penaltyInterest == 100)
        #expect(result.overdueFee == 20)
    }

    @Test func overduePenaltyCompoundIsGreaterThanSimple() async throws {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -10, to: now) ?? now

        let simple = FinanceEngine.calculateOverduePenalty(
            baseAmount: 10_000,
            dailyRate: 0.0005,
            startDate: start,
            endDate: now,
            mode: .simple
        )
        let compound = FinanceEngine.calculateOverduePenalty(
            baseAmount: 10_000,
            dailyRate: 0.0005,
            startDate: start,
            endDate: now,
            mode: .compound
        )

        #expect(compound > simple)
    }

    @Test func creditCardPlanContainsMinimumDueAndInstallmentFee() async throws {
        let detail = CreditCardDebtDetail(
            billingDay: 5,
            repaymentDay: 20,
            graceDays: 20,
            statementCycles: 12,
            interestFreeRule: .statementBased,
            minimumRepaymentRate: 0.1,
            minimumRepaymentFloor: 100,
            minimumIncludesFees: true,
            minimumIncludesPenalty: true,
            minimumIncludesInterest: true,
            minimumIncludesInstallmentPrincipal: true,
            minimumIncludesInstallmentFee: true,
            installmentPeriods: 6,
            installmentPrincipal: 6000,
            installmentFeeRatePerPeriod: 0.005,
            installmentFeeMode: .perPeriod,
            penaltyDailyRate: 0.0005,
            overdueFeeFlat: 0
        )

        let rows = FinanceEngine.generateCreditCardPlan(
            principal: 12_000,
            annualRate: 0.15,
            cycles: 12,
            startDate: Date(),
            detail: detail
        )

        #expect(rows.count == 12)
        #expect(rows.first?.minimumDue ?? 0 > 0)
        #expect(rows.first?.installmentFee ?? 0 > 0)
        #expect(rows.allSatisfy { $0.interest == 0 })
    }

    @Test func dataStatisticsSnapshotIncludesPrincipalInterestOverdueAndRateMetrics() async throws {
        let debt = Debt(
            name: "统计口径债务",
            type: .loan,
            subtype: "信用贷款",
            principal: 5_000,
            nominalAPR: 0.18,
            effectiveAPR: FinanceEngine.effectiveAPR(nominalAPR: 0.18),
            startDate: Date()
        )
        let plan = RepaymentPlan(
            periodIndex: 1,
            dueDate: Date(),
            principalDue: 3_500,
            interestDue: 180,
            minimumDue: 400,
            debt: debt
        )
        debt.repaymentPlans = [plan]

        let allocationJSON = "{\"allocation\":{\"overdueFee\":40,\"penaltyInterest\":20,\"interest\":130,\"fee\":10,\"principal\":1500}}"
        let record = RepaymentRecord(amount: 1_700, allocationJSON: allocationJSON, debt: debt, plan: plan)

        let unresolvedOverdue = OverdueEvent(
            startDate: Date(),
            overduePrincipal: 0,
            overdueInterest: 0,
            penaltyInterest: 35,
            overdueFee: 25,
            isResolved: false,
            debt: debt,
            plan: plan
        )

        let snapshot = DataStatisticsDomainService.build(
            debts: [debt],
            records: [record],
            overdueEvents: [unresolvedOverdue],
            now: Date()
        )

        #expect(snapshot.totalOutstanding == 3_500)
        #expect(snapshot.repaidPrincipal == 1_500)
        #expect(snapshot.paidInterest == 130)
        #expect(snapshot.outstandingInterest == 180)
        #expect(snapshot.overdueCost == 60)
        #expect(snapshot.paidOverdueFeeAndPenalty == 60)
        #expect(snapshot.totalOverdueFeeAndPenalty == 120)
        #expect(snapshot.weightedAverageNominalAPR == 0.18)
        #expect(snapshot.highestEffectiveAPR == debt.effectiveAPR)
        #expect(snapshot.lowestEffectiveAPR == debt.effectiveAPR)
        #expect(snapshot.highRateDebtCount == 0)
        #expect(abs((snapshot.debtRateByType[.loan] ?? 0) - debt.effectiveAPR) < 1e-12)
    }

    @Test func creditCardStatementTrackDoesNotGenerateInstallmentPrincipal() async throws {
        let detail = CreditCardDebtDetail(
            statementCycles: 12,
            installmentPeriods: 12,
            installmentPrincipal: 6000,
            installmentFeeRatePerPeriod: 0.005,
            installmentFeeMode: .perPeriod
        )

        let rows = FinanceEngine.generateCreditCardPlan(
            principal: 12_000,
            annualRate: 0.15,
            cycles: 12,
            startDate: Date(),
            detail: detail,
            kind: .statement
        )

        #expect(rows.count == 1)
        #expect(rows.allSatisfy { $0.installmentPrincipal == 0 })
        #expect(rows.first?.principal == 12_000)
    }

    @Test func oneCycleCreditCardPlanUsesMonthlyFullDueAndMinimum() async throws {
        let detail = CreditCardDebtDetail(
            billingDay: 8,
            repaymentDay: 20,
            graceDays: 20,
            statementCycles: 1,
            interestFreeRule: .transactionBased,
            minimumRepaymentRate: 0.1,
            minimumRepaymentFloor: 100,
            minimumIncludesFees: true,
            minimumIncludesPenalty: true,
            minimumIncludesInterest: true,
            minimumIncludesInstallmentPrincipal: true,
            minimumIncludesInstallmentFee: true,
            installmentPeriods: 0,
            installmentPrincipal: 0,
            installmentFeeRatePerPeriod: 0,
            installmentFeeMode: .perPeriod,
            penaltyDailyRate: 0.0005,
            overdueFeeFlat: 0
        )

        let rows = FinanceEngine.generateCreditCardPlan(
            principal: 2_400,
            annualRate: 0.18,
            cycles: 1,
            startDate: Date(),
            detail: detail,
            kind: .statement
        )

        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row.principal == 2_400)
        #expect(row.interest == 0)
        #expect(row.fee == 0)
        #expect(row.principal + row.interest + row.fee == 2_400)
        #expect(row.minimumDue == 240)
        #expect(row.isInterestFree)
    }

    @Test func creditCardStatementRebuildAddsRevolvingInterestAfterPartialRepayment() async throws {
        let debt = Debt(
            name: "未全额还款信用卡",
            type: .creditCard,
            subtype: "一般账单",
            principal: 2_000,
            nominalAPR: 0.18,
            effectiveAPR: FinanceEngine.effectiveAPR(nominalAPR: 0.18),
            startDate: Date()
        )
        debt.creditCardDetail = CreditCardDebtDetail(
            billingDay: 8,
            repaymentDay: 20,
            graceDays: 20,
            statementCycles: 1,
            interestFreeRule: .transactionBased,
            minimumRepaymentRate: 0.1,
            minimumRepaymentFloor: 100,
            minimumIncludesFees: true,
            minimumIncludesPenalty: true,
            minimumIncludesInterest: true,
            minimumIncludesInstallmentPrincipal: true,
            minimumIncludesInstallmentFee: true,
            installmentPeriods: 0,
            installmentPrincipal: 0,
            installmentFeeRatePerPeriod: 0,
            installmentFeeMode: .perPeriod,
            penaltyDailyRate: 0.0005,
            overdueFeeFlat: 0
        )
        debt.repaymentPlans = [
            RepaymentPlan(
                periodIndex: 1,
                dueDate: Calendar.current.date(byAdding: .day, value: -20, to: Date()) ?? Date(),
                statementDate: Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date(),
                principalDue: 2_000,
                interestDue: 0,
                minimumDue: 200,
                debt: debt
            )
        ]

        let result = CreditCardStatementService.applyStatementUpdate(
            debt: debt,
            refreshedAt: Date(),
            statementBalance: 2_350,
            minimumDue: 235,
            installmentFee: 0
        )

        let rebuiltPlan = try #require(debt.repaymentPlans.first)
        #expect(result.rebuiltPlanCount == 1)
        #expect(debt.repaymentPlans.count == 1)
        #expect(rebuiltPlan.principalDue == 2_350)
        #expect(rebuiltPlan.interestDue > 0)
        #expect(rebuiltPlan.totalDue == rebuiltPlan.principalDue + rebuiltPlan.interestDue + rebuiltPlan.feeDue)
        #expect(rebuiltPlan.minimumDue >= 235)
        #expect(result.warnings.contains(where: { $0.contains("循环利息") }))
    }

    @Test func strategyDetailedResultContainsTimelineJSON() async throws {
        let debt = Debt(
            name: "测试债务",
            type: .loan,
            subtype: "信用贷款",
            principal: 12_000,
            nominalAPR: 0.12,
            effectiveAPR: FinanceEngine.effectiveAPR(nominalAPR: 0.12),
            startDate: Date()
        )
        debt.repaymentPlans.append(
            RepaymentPlan(
                periodIndex: 1,
                dueDate: Date(),
                principalDue: 1000,
                interestDue: 80,
                minimumDue: 200,
                debt: debt
            )
        )

        let result = FinanceEngine.compareStrategiesDetailed(
            debts: [debt],
            monthlyBudget: 1500,
            constraints: .init(includeMinimumDue: true, includeOverduePenalty: false, prioritizeOverdueBalances: true, requireFullOverdueCoverage: true, maxMonths: 60)
        )

        let avalanche = result[.avalanche]
        #expect(avalanche != nil)
        #expect(avalanche?.timelineJSON.contains("records") == true)
    }

    @Test func debtKeepsRuleIDWhenRuleNameChanges() async throws {
        let ruleID = UUID()
        let debt = Debt(
            name: "规则绑定测试",
            type: .loan,
            subtype: "信用贷款",
            principal: 1000,
            nominalAPR: 0.1,
            effectiveAPR: 0.105,
            calculationRuleID: ruleID,
            calculationRuleName: "旧规则名",
            startDate: Date()
        )

        debt.calculationRuleName = "新规则名"
        #expect(debt.calculationRuleID == ruleID)
    }

    @Test func legacyRuleMigratesIntoDebtOwnedCustomRule() async throws {
        let profile = CalculationRuleProfile(
            id: UUID(),
            name: "自定义模板",
            overduePenaltyMode: .compound,
            paymentAllocationOrder: .penaltyFirst,
            defaultCreditCardMinimumRate: 0.2,
            defaultCreditCardMinimumFloor: 200,
            defaultCreditCardMinimumIncludesInterest: true,
            defaultCreditCardMinimumIncludesInstallmentPrincipal: true,
            defaultCreditCardMinimumIncludesInstallmentFee: true,
            defaultCreditCardPenaltyDailyRate: 0.001,
            defaultCreditCardOverdueFeeFlat: 30,
            defaultLoanPenaltyDailyRate: 0.0008,
            defaultLoanOverdueInterestBase: .principalAndInterest,
            defaultPrivateLoanPenaltyDailyRate: 0.0006,
            defaultPrivateLoanOverdueInterestBase: .principalAndInterest
        )
        let debt = Debt(
            name: "迁移债务",
            type: .loan,
            subtype: "信用贷款",
            principal: 5_000,
            nominalAPR: 0.1,
            effectiveAPR: 0.105,
            calculationRuleID: profile.id,
            calculationRuleName: profile.name,
            startDate: Date()
        )

        let resolved = RuleProfileResolver.resolve(for: debt, profiles: [profile])

        #expect(resolved != nil)
        #expect(debt.customRule != nil)
        #expect(debt.customRule?.name == "自定义模板")
        #expect(debt.customRule?.overduePenaltyMode == .compound)
        #expect(debt.customRule?.paymentAllocationOrder == .penaltyFirst)
    }

    @Test func builtInRuleTemplatesAreSeededWithoutDuplication() async throws {
        let context = try makeInMemoryModelContext()

        RuleTemplateCatalogService.ensureBuiltInProfiles(modelContext: context)
        RuleTemplateCatalogService.ensureBuiltInProfiles(modelContext: context)

        let profiles = try context.fetch(FetchDescriptor<CalculationRuleProfile>())

        #expect(profiles.count == RuleTemplateCatalogService.builtInTemplates.count)
        #expect(Set(profiles.map(\.name)) == Set(RuleTemplateCatalogService.builtInTemplates.map(\.displayName)))
    }

    @Test func restoringBuiltInRuleTemplatesReappliesCanonicalValues() async throws {
        let context = try makeInMemoryModelContext()
        let drifted = CalculationRuleProfile(name: "个人借贷参考模板")
        drifted.paymentAllocationOrder = .penaltyFirst
        drifted.defaultPrivateLoanOverdueInterestBase = .principalAndInterest
        context.insert(drifted)
        try context.save()

        RuleTemplateCatalogService.restoreReferenceTemplates(modelContext: context)

        let profiles = try context.fetch(FetchDescriptor<CalculationRuleProfile>())
        let restored = profiles.first(where: { $0.name == "个人借贷默认规则" })

        #expect(restored != nil)
        #expect(restored?.paymentAllocationOrder == .overdueFeeFirst)
        #expect(restored?.defaultPrivateLoanOverdueInterestBase == .principalOnly)
        #expect(profiles.count == RuleTemplateCatalogService.builtInTemplates.count)
    }

    @Test func creditCardTemplateDoesNotOverwriteLoanAndPrivateDefaults() async throws {
        let profile = CalculationRuleProfile(
            name: "隔离验证",
            defaultLoanPenaltyDailyRate: 0.0123,
            defaultLoanOverdueFeeFlat: 88,
            defaultLoanGraceDays: 9,
            defaultLoanOverdueInterestBase: .principalAndInterest,
            defaultPrivateLoanPenaltyDailyRate: 0.0456,
            defaultPrivateLoanOverdueFeeFlat: 66,
            defaultPrivateLoanGraceDays: 11,
            defaultPrivateLoanOverdueInterestBase: .principalAndInterest
        )

        RuleTemplateCatalogService.applyTemplate(id: "builtin.default.credit-card", to: profile)

        #expect(profile.defaultLoanPenaltyDailyRate == 0.0123)
        #expect(profile.defaultLoanOverdueFeeFlat == 88)
        #expect(profile.defaultLoanGraceDays == 9)
        #expect(profile.defaultLoanOverdueInterestBase == .principalAndInterest)
        #expect(profile.defaultPrivateLoanPenaltyDailyRate == 0.0456)
        #expect(profile.defaultPrivateLoanOverdueFeeFlat == 66)
        #expect(profile.defaultPrivateLoanGraceDays == 11)
        #expect(profile.defaultPrivateLoanOverdueInterestBase == .principalAndInterest)
    }

    @Test func loanAndPrivateTemplatesDoNotOverwriteCreditCardDefaults() async throws {
        let profile = CalculationRuleProfile(
            name: "隔离验证",
            defaultCreditCardMinimumRate: 0.35,
            defaultCreditCardMinimumFloor: 320,
            defaultCreditCardPenaltyDailyRate: 0.003,
            defaultCreditCardOverdueFeeFlat: 120
        )

        RuleTemplateCatalogService.applyTemplate(id: "builtin.default.loan", to: profile)
        RuleTemplateCatalogService.applyTemplate(id: "builtin.default.private-lending", to: profile)

        #expect(profile.defaultCreditCardMinimumRate == 0.35)
        #expect(profile.defaultCreditCardMinimumFloor == 320)
        #expect(profile.defaultCreditCardPenaltyDailyRate == 0.003)
        #expect(profile.defaultCreditCardOverdueFeeFlat == 120)
    }

    @Test func fullyPaidPlannedDebtHasZeroOutstandingPrincipal() async throws {
        let debt = Debt(
            name: "已结清债务",
            type: .loan,
            subtype: "信用贷款",
            principal: 10_000,
            nominalAPR: 0.1,
            effectiveAPR: 0.105,
            startDate: Date()
        )
        debt.repaymentPlans = [
            RepaymentPlan(periodIndex: 1, dueDate: Date(), principalDue: 0, interestDue: 0, debt: debt),
            RepaymentPlan(periodIndex: 2, dueDate: Date(), principalDue: 0, interestDue: 0, debt: debt)
        ]

        #expect(debt.outstandingPrincipal == 0)
    }

    @Test func repaymentDomainServiceRecordsOnlyAppliedAmount() async throws {
        let debt = Debt(
            name: "还款测试",
            type: .loan,
            subtype: "信用贷款",
            principal: 1_000,
            nominalAPR: 0.1,
            effectiveAPR: 0.105,
            startDate: Date()
        )
        debt.repaymentPlans = [
            RepaymentPlan(periodIndex: 1, dueDate: Date(), principalDue: 100, interestDue: 10, debt: debt)
        ]

        let result = RepaymentDomainService.applyRepayment(
            debt: debt,
            amount: 200,
            note: "超额还款",
            paidAt: Date(),
            allocationOrder: .overdueFeeFirst
        )

        #expect(result.record.amount == 110)
        #expect(result.remainingAmount == 90)
        #expect(debt.outstandingPrincipal == 0)
        #expect(debt.status == .settled)
    }

    @Test func debtMutationServiceUsesDebtOwnedCustomRuleDefaults() async throws {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? Date()
        let end = Calendar.current.date(from: DateComponents(year: 2027, month: 1, day: 1)) ?? Date()
        let debt = Debt(
            name: "专属规则贷款",
            type: .loan,
            subtype: "信用贷款",
            principal: 8_000,
            nominalAPR: 0.12,
            effectiveAPR: FinanceEngine.effectiveAPR(nominalAPR: 0.12),
            startDate: start
        )
        debt.customRule = DebtCustomRule(
            name: "债务专属规则",
            overduePenaltyMode: .compound,
            paymentAllocationOrder: .penaltyFirst,
            defaultCreditCardMinimumRate: 0.15,
            defaultCreditCardMinimumFloor: 150,
            defaultCreditCardPenaltyDailyRate: 0.001,
            defaultCreditCardOverdueFeeFlat: 20,
            defaultLoanPenaltyDailyRate: 0.0012,
            defaultPrivateLoanPenaltyDailyRate: 0.0009,
            debt: debt
        )

        try DebtMutationService.rebuildDebt(
            debt: debt,
            draft: .init(
                name: "专属规则贷款",
                type: .loan,
                subtype: "信用贷款",
                principal: 8_000,
                nominalAPR: 0.12,
                startDate: start,
                endDate: end,
                loanMethod: .equalInstallment,
                termMonths: 12,
                billingDay: 1,
                repaymentDay: 20,
                statementCycles: 12,
                minimumRepaymentRate: 0.1,
                minimumRepaymentFloor: 100,
                minimumIncludesFees: true,
                minimumIncludesPenalty: true,
                minimumIncludesInterest: true,
                minimumIncludesInstallmentPrincipal: true,
                minimumIncludesInstallmentFee: true,
                installmentPeriods: 0,
                installmentPrincipal: 0,
                installmentFeeRatePerPeriod: 0.005,
                installmentFeeMode: .perPeriod,
                penaltyDailyRate: 0.0005,
                overdueFeeFlat: 0,
                creditCardOverdueInterestBase: .principalOnly,
                creditCardOverduePenaltyMode: .simple,
                loanOverdueInterestBase: .principalOnly,
                privateOverdueInterestBase: .principalOnly
            ),
            ruleProfile: nil
        )

        #expect(debt.loanDetail?.penaltyDailyRate == 0.12 / 365 * 1.5)
        #expect(debt.customRule?.paymentAllocationOrder == .penaltyFirst)
        #expect(debt.loanDetail?.maturityDate == end)
    }

    @Test func loanValidationRequiresEndDateAndValidRange() async throws {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 1)) ?? Date()
        let invalidEnd = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 31)) ?? Date()

        #expect(throws: FinanceEngine.ValidationError.missingLoanEndDate) {
            try FinanceEngine.validateDebtInput(
                name: "贷款A",
                type: .loan,
                principal: 10_000,
                nominalAPR: 0.12,
                startDate: start,
                endDate: nil,
                loanTermMonths: 12
            )
        }

        #expect(throws: FinanceEngine.ValidationError.invalidLoanDateRange) {
            try FinanceEngine.validateDebtInput(
                name: "贷款B",
                type: .loan,
                principal: 10_000,
                nominalAPR: 0.12,
                startDate: start,
                endDate: invalidEnd,
                loanTermMonths: 12
            )
        }
    }

    @Test func overdueRegistrationIsIdempotentAndRepaymentResolvesIt() async throws {
        let debt = Debt(
            name: "逾期测试",
            type: .loan,
            subtype: "信用贷款",
            principal: 1_000,
            nominalAPR: 0.1,
            effectiveAPR: 0.105,
            startDate: Date()
        )
        let plan = RepaymentPlan(periodIndex: 1, dueDate: Date(), principalDue: 100, interestDue: 20, debt: debt)
        debt.repaymentPlans = [plan]

        let first = OverdueDomainService.registerOverdue(
            debt: debt,
            startDate: Calendar.current.date(byAdding: .day, value: -5, to: Date()) ?? Date(),
            penaltyMode: .simple,
            dailyRate: 0.001,
            fixedFee: 10
        )
        let second = OverdueDomainService.registerOverdue(
            debt: debt,
            startDate: Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date(),
            penaltyMode: .simple,
            dailyRate: 0.001,
            fixedFee: 10
        )

        #expect(first.isNew)
        #expect(second.isNew == false)
        #expect(first.event.id == second.event.id)

        let totalDue = second.event.overdueFee + second.event.penaltyInterest + plan.interestDue + plan.principalDue
        _ = RepaymentDomainService.applyRepayment(
            debt: debt,
            amount: totalDue,
            note: "结清逾期",
            paidAt: Date(),
            allocationOrder: .overdueFeeFirst
        )

        #expect(second.event.isResolved)
        #expect(second.event.endDate != nil)
        #expect(plan.status == .paid)
    }

    @Test func debtMutationServiceRebuildsInstallmentDebtUsingRealPeriods() async throws {
        let debt = Debt(
            name: "分期卡",
            type: .creditCard,
            subtype: "信用卡分期",
            principal: 6_000,
            nominalAPR: 0.12,
            effectiveAPR: FinanceEngine.effectiveAPR(nominalAPR: 0.12),
            startDate: Date()
        )

        try DebtMutationService.rebuildDebt(
            debt: debt,
            draft: .init(
                name: "分期卡",
                type: .creditCard,
                subtype: "信用卡分期",
                principal: 6_000,
                nominalAPR: 0.12,
                startDate: Date(),
                loanMethod: .equalInstallment,
                termMonths: 12,
                billingDay: 5,
                repaymentDay: 20,
                statementCycles: 12,
                minimumRepaymentRate: 0.1,
                minimumRepaymentFloor: 100,
                minimumIncludesFees: true,
                minimumIncludesPenalty: true,
                minimumIncludesInterest: true,
                minimumIncludesInstallmentPrincipal: true,
                minimumIncludesInstallmentFee: true,
                installmentPeriods: 6,
                installmentPrincipal: 6_000,
                installmentFeeRatePerPeriod: 0.005,
                installmentFeeMode: .perPeriod,
                penaltyDailyRate: 0.0005,
                overdueFeeFlat: 0,
                creditCardOverdueInterestBase: .principalOnly,
                creditCardOverduePenaltyMode: .simple,
                loanOverdueInterestBase: .principalOnly,
                privateOverdueInterestBase: .principalOnly
            ),
            ruleProfile: nil
        )

        #expect(debt.repaymentPlans.count == 6)
        #expect(debt.repaymentPlans.last?.installmentFeeDue ?? 0 > 0)
    }

    @Test func strategyTimelineCanBeDecodedForDetailView() async throws {
        let debt = Debt(
            name: "策略详情债务",
            type: .loan,
            subtype: "信用贷款",
            principal: 10_000,
            nominalAPR: 0.12,
            effectiveAPR: FinanceEngine.effectiveAPR(nominalAPR: 0.12),
            startDate: Date()
        )
        debt.repaymentPlans = [
            RepaymentPlan(periodIndex: 1, dueDate: Date(), principalDue: 1000, interestDue: 100, minimumDue: 200, debt: debt)
        ]

        let result = FinanceEngine.generateStrategyDetailed(
            debts: [debt],
            monthlyBudget: 1500,
            method: .snowball,
            constraints: .init(includeMinimumDue: true, includeOverduePenalty: false, maxMonths: 60)
        )

        let timeline = result.flatMap { FinanceEngine.decodeStrategyTimeline(from: $0.timelineJSON) }
        #expect(timeline != nil)
        #expect(timeline?.method == StrategyMethod.snowball.rawValue)
        #expect((timeline?.records.count ?? 0) > 0)
    }

    @Test func reminderDomainServiceBuildsRepaymentAndStatementRefreshReminders() async throws {
        let debt = Debt(
            name: "信用卡提醒",
            type: .creditCard,
            subtype: "一般账单",
            principal: 5_000,
            nominalAPR: 0.12,
            effectiveAPR: FinanceEngine.effectiveAPR(nominalAPR: 0.12),
            startDate: Date()
        )
        debt.customRule = DebtCustomRule(
            name: "信用卡提醒规则",
            repaymentReminderLeadDays: 4,
            creditCardStatementReminderOffsetDays: 2,
            debt: debt
        )
        debt.creditCardDetail = CreditCardDebtDetail(
            billingDay: 8,
            repaymentDay: 20,
            graceDays: 20,
            statementCycles: 12,
            interestFreeRule: .statementBased,
            minimumRepaymentRate: 0.1,
            minimumRepaymentFloor: 100,
            minimumIncludesFees: true,
            minimumIncludesPenalty: true,
            minimumIncludesInterest: true,
            minimumIncludesInstallmentPrincipal: true,
            minimumIncludesInstallmentFee: true,
            installmentPeriods: 0,
            installmentPrincipal: 0,
            installmentFeeRatePerPeriod: 0,
            installmentFeeMode: .perPeriod,
            penaltyDailyRate: 0.0005,
            overdueFeeFlat: 0
        )
        let statementDate = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 8)) ?? Date()
        let dueDate = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 20)) ?? Date()
        let plan = RepaymentPlan(
            periodIndex: 1,
            dueDate: dueDate,
            statementDate: statementDate,
            principalDue: 800,
            interestDue: 20,
            minimumDue: 120,
            debt: debt
        )
        debt.repaymentPlans = [plan]

        ReminderDomainService.rebuildReminders(for: debt, now: statementDate)

        #expect(debt.reminderTasks.count == 2)
        let categories = Set(debt.reminderTasks.map(\.category))
        #expect(categories.contains(.repaymentDue))
        #expect(categories.contains(.creditCardStatementRefresh))
        let statementReminder = debt.reminderTasks.first(where: { $0.category == .creditCardStatementRefresh })
        let repaymentReminder = debt.reminderTasks.first(where: { $0.category == .repaymentDue })
        #expect(statementReminder?.remindAt == Calendar.current.date(byAdding: .day, value: 2, to: statementDate))
        #expect(repaymentReminder?.remindAt == Calendar.current.date(byAdding: .day, value: -4, to: dueDate))
    }

    @Test func automaticOverdueEventIsCreatedForPastDueCreditCardPlan() async throws {
        let debt = Debt(
            name: "自动逾期信用卡",
            type: .creditCard,
            subtype: "一般账单",
            principal: 3_000,
            nominalAPR: 0.18,
            effectiveAPR: FinanceEngine.effectiveAPR(nominalAPR: 0.18),
            startDate: Date()
        )
        debt.creditCardDetail = CreditCardDebtDetail(
            billingDay: 8,
            repaymentDay: 20,
            graceDays: 20,
            statementCycles: 1,
            interestFreeRule: .statementBased,
            minimumRepaymentRate: 0.1,
            minimumRepaymentFloor: 100,
            minimumIncludesFees: true,
            minimumIncludesPenalty: true,
            minimumIncludesInterest: true,
            minimumIncludesInstallmentPrincipal: true,
            minimumIncludesInstallmentFee: true,
            installmentPeriods: 0,
            installmentPrincipal: 0,
            installmentFeeRatePerPeriod: 0,
            installmentFeeMode: .perPeriod,
            penaltyDailyRate: 0.001,
            overdueFeeFlat: 50
        )
        debt.repaymentPlans = [
            RepaymentPlan(
                periodIndex: 1,
                dueDate: Calendar.current.date(byAdding: .day, value: -10, to: Date()) ?? Date(),
                statementDate: Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date(),
                principalDue: 3_000,
                interestDue: 0,
                minimumDue: 300,
                debt: debt
            )
        ]

        DebtLifecycleService.refreshStatus(debt: debt, now: Date())

        let overdue = try #require(debt.overdueEvents.first(where: { !$0.isResolved }))
        #expect(debt.status == .overdue)
        #expect(debt.repaymentPlans.first?.status == .overdue)
        #expect(overdue.overdueFee >= 50)
        #expect(overdue.penaltyInterest > 0)
        #expect(overdue.startDate == debt.repaymentPlans.first?.dueDate)
    }

    @Test func infeasibleStrategyCapturesReasonWhenMinimumsCannotBeCovered() async throws {
        let debt = Debt(
            name: "预算不足债务",
            type: .loan,
            subtype: "信用贷款",
            principal: 9_000,
            nominalAPR: 0.12,
            effectiveAPR: FinanceEngine.effectiveAPR(nominalAPR: 0.12),
            startDate: Date()
        )
        debt.repaymentPlans = [
            RepaymentPlan(periodIndex: 1, dueDate: Date(), principalDue: 1000, interestDue: 60, minimumDue: 800, debt: debt)
        ]

        let result = FinanceEngine.generateStrategyDetailed(
            debts: [debt],
            monthlyBudget: 700,
            method: .avalanche,
            constraints: .init(
                includeMinimumDue: true,
                includeOverduePenalty: false,
                prioritizeOverdueBalances: true,
                requireFullOverdueCoverage: true,
                minimumMonthlyReserve: 50,
                requireFullMinimumCoverage: true,
                maxMonths: 60
            )
        )

        let timeline = result.flatMap { FinanceEngine.decodeStrategyTimeline(from: $0.timelineJSON) }
        #expect(timeline != nil)
        #expect(timeline?.completed == false)
        #expect(timeline?.infeasibleReason?.contains("预算不足") == true)
        #expect(timeline?.records.first?.isBudgetShortfall == true)
    }

    @Test func debtGuidanceSuggestsProfessionalHelpWhenBudgetBelowMinimumDue() async throws {
        let debt = Debt(
            name: "最低还款压力债务",
            type: .loan,
            subtype: "信用贷款",
            principal: 12_000,
            nominalAPR: 0.16,
            effectiveAPR: FinanceEngine.effectiveAPR(nominalAPR: 0.16),
            startDate: Date()
        )
        debt.repaymentPlans = [
            RepaymentPlan(periodIndex: 1, dueDate: Date(), principalDue: 1_000, interestDue: 120, minimumDue: 900, debt: debt)
        ]

        let recommendation = DebtGuidanceService.build(
            debts: [debt],
            monthlyBudget: 500,
            constraints: .init(
                includeMinimumDue: true,
                includeOverduePenalty: true,
                prioritizeOverdueBalances: true,
                requireFullOverdueCoverage: true,
                minimumMonthlyReserve: 0,
                requireFullMinimumCoverage: true,
                maxMonths: 60
            )
        )

        #expect(recommendation.isFeasible == false)
        #expect(recommendation.minimumFeasibleBudget >= 900)
        #expect(recommendation.actions.contains(where: { $0.detail.contains("寻求专业帮助") }))
        #expect(recommendation.risks.contains(where: { $0.contains("寻求专业帮助") }))
    }

    @Test func creditCardMinimumDueCanExcludeInstallmentComponents() async throws {
        let minimum = FinanceEngine.calculateCreditCardMinimumDue(
            statementPrincipal: 800,
            installmentPrincipal: 500,
            statementInterest: 30,
            statementFees: 0,
            installmentFee: 25,
            penaltyInterest: 10,
            minimumRate: 0.1,
            minimumFloor: 100,
            includesFees: true,
            includesPenalty: true,
            includesInterest: true,
            includesInstallmentPrincipal: false,
            includesInstallmentFee: false
        )

        #expect(minimum == 100)
    }

    @Test func statementRefreshReminderDisappearsAfterStatementUpdate() async throws {
        let debt = Debt(
            name: "账单更新测试",
            type: .creditCard,
            subtype: "一般账单",
            principal: 4_000,
            nominalAPR: 0.12,
            effectiveAPR: FinanceEngine.effectiveAPR(nominalAPR: 0.12),
            startDate: Date()
        )
        debt.customRule = DebtCustomRule(
            name: "提醒规则",
            creditCardStatementReminderOffsetDays: 1,
            requireCreditCardStatementRefresh: true,
            debt: debt
        )
        let statementDate = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 8)) ?? Date()
        let dueDate = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 20)) ?? Date()
        debt.creditCardDetail = CreditCardDebtDetail(
            billingDay: 8,
            repaymentDay: 20,
            graceDays: 20,
            statementCycles: 12,
            interestFreeRule: .statementBased,
            minimumRepaymentRate: 0.1,
            minimumRepaymentFloor: 100,
            minimumIncludesFees: true,
            minimumIncludesPenalty: true,
            minimumIncludesInterest: true,
            minimumIncludesInstallmentPrincipal: true,
            minimumIncludesInstallmentFee: true,
            installmentPeriods: 0,
            installmentPrincipal: 0,
            installmentFeeRatePerPeriod: 0,
            installmentFeeMode: .perPeriod,
            penaltyDailyRate: 0.0005,
            overdueFeeFlat: 0
        )
        debt.repaymentPlans = [
            RepaymentPlan(
                periodIndex: 1,
                dueDate: dueDate,
                statementDate: statementDate,
                principalDue: 1200,
                interestDue: 0,
                minimumDue: 120,
                debt: debt
            )
        ]

        ReminderDomainService.rebuildReminders(for: debt, now: statementDate)
        #expect(debt.reminderTasks.contains(where: { $0.category == .creditCardStatementRefresh }))

        _ = ReminderDomainService.markCreditCardStatementUpdated(
            debt: debt,
            refreshedAt: Calendar.current.date(byAdding: .day, value: 2, to: statementDate) ?? statementDate,
            statementBalance: 1300,
            minimumDue: 130,
            installmentFee: 0
        )

        #expect(debt.creditCardDetail?.lastStatementBalance == 1300)
        #expect(debt.reminderTasks.contains(where: { $0.category == .creditCardStatementRefresh }) == false)
    }

    @Test func overdueConstraintProducesDedicatedShortfallReason() async throws {
        let debt = Debt(
            name: "逾期约束债务",
            type: .loan,
            subtype: "信用贷款",
            principal: 5_000,
            nominalAPR: 0.12,
            effectiveAPR: FinanceEngine.effectiveAPR(nominalAPR: 0.12),
            startDate: Date()
        )
        debt.repaymentPlans = [
            RepaymentPlan(periodIndex: 1, dueDate: Date(), principalDue: 1000, interestDue: 50, minimumDue: 200, debt: debt)
        ]
        debt.overdueEvents = [
            OverdueEvent(
                startDate: Calendar.current.date(byAdding: .day, value: -8, to: Date()) ?? Date(),
                overduePrincipal: 0,
                overdueInterest: 40,
                penaltyInterest: 30,
                overdueFee: 80,
                isResolved: false,
                debt: debt,
                plan: debt.repaymentPlans.first
            )
        ]

        let result = FinanceEngine.generateStrategyDetailed(
            debts: [debt],
            monthlyBudget: 100,
            method: .avalanche,
            constraints: .init(
                includeMinimumDue: false,
                includeOverduePenalty: true,
                prioritizeOverdueBalances: true,
                requireFullOverdueCoverage: true,
                minimumMonthlyReserve: 0,
                requireFullMinimumCoverage: false,
                maxMonths: 12
            )
        )

        let timeline = result.flatMap { FinanceEngine.decodeStrategyTimeline(from: $0.timelineJSON) }
        #expect(timeline?.completed == false)
        #expect(timeline?.infeasibleReason?.contains("逾期费用") == true)
        #expect((timeline?.records.first?.overdueRequired ?? 0) > 0)
        #expect(timeline?.records.first?.isBudgetShortfall == true)
    }

    @Test func creditCardStatementUpdateRebuildsPendingPlans() async throws {
        let debt = Debt(
            name: "账单重建卡",
            type: .creditCard,
            subtype: "一般账单",
            principal: 6_000,
            nominalAPR: 0.12,
            effectiveAPR: FinanceEngine.effectiveAPR(nominalAPR: 0.12),
            startDate: Date()
        )
        debt.creditCardDetail = CreditCardDebtDetail(
            billingDay: 8,
            repaymentDay: 20,
            graceDays: 20,
            statementCycles: 3,
            interestFreeRule: .statementBased,
            minimumRepaymentRate: 0.1,
            minimumRepaymentFloor: 100,
            minimumIncludesFees: true,
            minimumIncludesPenalty: true,
            minimumIncludesInterest: true,
            minimumIncludesInstallmentPrincipal: true,
            minimumIncludesInstallmentFee: true,
            installmentPeriods: 0,
            installmentPrincipal: 0,
            installmentFeeRatePerPeriod: 0,
            installmentFeeMode: .perPeriod,
            penaltyDailyRate: 0.0005,
            overdueFeeFlat: 0
        )
        debt.repaymentPlans = [
            RepaymentPlan(periodIndex: 1, dueDate: Date(), statementDate: Date(), principalDue: 1000, interestDue: 0, minimumDue: 100, debt: debt),
            RepaymentPlan(periodIndex: 2, dueDate: Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date(), statementDate: Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date(), principalDue: 1000, interestDue: 0, minimumDue: 100, debt: debt),
            RepaymentPlan(periodIndex: 3, dueDate: Calendar.current.date(byAdding: .month, value: 2, to: Date()) ?? Date(), statementDate: Calendar.current.date(byAdding: .month, value: 2, to: Date()) ?? Date(), principalDue: 1000, interestDue: 0, minimumDue: 100, debt: debt)
        ]

        let result = CreditCardStatementService.applyStatementUpdate(
            debt: debt,
            refreshedAt: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date(),
            statementBalance: 3_600,
            minimumDue: 480,
            installmentFee: 0
        )

        #expect(result.rebuiltPlanCount == 1)
        #expect(debt.repaymentPlans.count == 1)
        #expect(debt.repaymentPlans.sorted(by: { $0.periodIndex < $1.periodIndex }).first?.minimumDue == 480)
        #expect(abs(debt.outstandingPrincipal - 3600) < 1)
    }

    @Test func debtGuidanceReturnsFeasibleRecommendationAndActions() async throws {
        let highRateDebt = Debt(
            name: "高利率贷款",
            type: .loan,
            subtype: "信用贷款",
            principal: 8_000,
            nominalAPR: 0.24,
            effectiveAPR: FinanceEngine.effectiveAPR(nominalAPR: 0.24),
            startDate: Date()
        )
        highRateDebt.repaymentPlans = [
            RepaymentPlan(periodIndex: 1, dueDate: Date(), principalDue: 600, interestDue: 80, minimumDue: 300, debt: highRateDebt)
        ]

        let lowRateDebt = Debt(
            name: "低利率贷款",
            type: .loan,
            subtype: "信用贷款",
            principal: 5_000,
            nominalAPR: 0.1,
            effectiveAPR: FinanceEngine.effectiveAPR(nominalAPR: 0.1),
            startDate: Date()
        )
        lowRateDebt.repaymentPlans = [
            RepaymentPlan(periodIndex: 1, dueDate: Calendar.current.date(byAdding: .day, value: 10, to: Date()) ?? Date(), principalDue: 400, interestDue: 30, minimumDue: 150, debt: lowRateDebt)
        ]

        let recommendation = DebtGuidanceService.build(
            debts: [highRateDebt, lowRateDebt],
            monthlyBudget: 1500,
            constraints: .init(
                includeMinimumDue: true,
                includeOverduePenalty: true,
                prioritizeOverdueBalances: true,
                requireFullOverdueCoverage: true,
                minimumMonthlyReserve: 0,
                requireFullMinimumCoverage: true,
                maxMonths: 120
            )
        )

        #expect(recommendation.isFeasible)
        #expect(recommendation.recommendedMethod != nil)
        #expect(recommendation.actions.isEmpty == false)
        #expect(recommendation.minimumFeasibleBudget >= 450)
        #expect(recommendation.alternatives.count == StrategyMethod.allCases.count)
    }

    @Test func subscriptionLifecycleResolutionCoversKeyStates() async throws {
        let now = Date()
        let future = Calendar.current.date(byAdding: .day, value: 10, to: now) ?? now
        let past = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now

        let trial = SubscriptionLifecycleAuditService.resolveStatus(
            renewalPhase: .active,
            expirationDate: future,
            gracePeriodExpirationDate: nil,
            revokedDate: nil,
            willAutoRenew: true,
            isVerified: true,
            isTrialPeriod: true,
            now: now
        )
        let grace = SubscriptionLifecycleAuditService.resolveStatus(
            renewalPhase: .inGracePeriod,
            expirationDate: future,
            gracePeriodExpirationDate: Calendar.current.date(byAdding: .day, value: 3, to: now),
            revokedDate: nil,
            willAutoRenew: true,
            isVerified: true,
            isTrialPeriod: false,
            now: now
        )
        let retry = SubscriptionLifecycleAuditService.resolveStatus(
            renewalPhase: .inBillingRetry,
            expirationDate: future,
            gracePeriodExpirationDate: nil,
            revokedDate: nil,
            willAutoRenew: true,
            isVerified: true,
            isTrialPeriod: false,
            now: now
        )
        let expired = SubscriptionLifecycleAuditService.resolveStatus(
            renewalPhase: .expired,
            expirationDate: past,
            gracePeriodExpirationDate: nil,
            revokedDate: nil,
            willAutoRenew: false,
            isVerified: true,
            isTrialPeriod: false,
            now: now
        )

        #expect(trial == .trial)
        #expect(grace == .gracePeriod)
        #expect(retry == .billingRetry)
        #expect(expired == .expired)
    }

    @Test func subscriptionAuditFlagsStaleAndExpiredSnapshots() async throws {
        let now = Date()
        let staleVerification = Calendar.current.date(byAdding: .day, value: -2, to: now) ?? now
        let expiredAt = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now

        let entitlement = SubscriptionEntitlement(
            productId: "com.personaldebt.pro.monthly",
            productName: "连续包月",
            status: .active,
            renewalPhase: .active,
            verificationState: .verified,
            verificationMessage: "",
            isActive: true,
            willAutoRenew: false,
            renewalProductId: "com.personaldebt.pro.monthly",
            ownershipType: "purchased",
            environment: "sandbox",
            purchaseDate: Calendar.current.date(byAdding: .day, value: -20, to: now),
            expireAt: expiredAt,
            gracePeriodExpireAt: nil,
            revokedAt: nil,
            originalTransactionId: "1000001",
            latestTransactionId: "1000002",
            trialUsed: false,
            lastVerifiedAt: staleVerification,
            lastSyncedAt: now
        )

        let audit = SubscriptionLifecycleAuditService.audit(entitlements: [entitlement], now: now)

        #expect(audit.currentEntitlement?.productId == entitlement.productId)
        #expect(audit.staleCount == 1)
        #expect(audit.invalidCount == 1)
        #expect(audit.issues.isEmpty == false)
    }

    @Test func subscriptionAuditPrefersEntitledSnapshotAsCurrent() async throws {
        let now = Date()
        let active = SubscriptionEntitlement(
            productId: "com.personaldebt.pro.yearly",
            productName: "连续包年",
            status: .active,
            renewalPhase: .active,
            verificationState: .verified,
            verificationMessage: "",
            isActive: true,
            willAutoRenew: true,
            renewalProductId: "com.personaldebt.pro.yearly",
            ownershipType: "purchased",
            environment: "sandbox",
            purchaseDate: now,
            expireAt: Calendar.current.date(byAdding: .day, value: 365, to: now),
            gracePeriodExpireAt: nil,
            revokedAt: nil,
            originalTransactionId: "2000001",
            latestTransactionId: "2000001",
            trialUsed: false,
            lastVerifiedAt: now,
            lastSyncedAt: now
        )
        let expired = SubscriptionEntitlement(
            productId: "com.personaldebt.pro.monthly",
            productName: "连续包月",
            status: .expired,
            renewalPhase: .expired,
            verificationState: .verified,
            verificationMessage: "",
            isActive: false,
            willAutoRenew: false,
            renewalProductId: "com.personaldebt.pro.monthly",
            ownershipType: "purchased",
            environment: "sandbox",
            purchaseDate: Calendar.current.date(byAdding: .month, value: -2, to: now),
            expireAt: Calendar.current.date(byAdding: .day, value: -3, to: now),
            gracePeriodExpireAt: nil,
            revokedAt: nil,
            originalTransactionId: "3000001",
            latestTransactionId: "3000002",
            trialUsed: true,
            lastVerifiedAt: now,
            lastSyncedAt: now
        )

        let audit = SubscriptionLifecycleAuditService.audit(entitlements: [expired, active], now: now)

        #expect(audit.currentEntitlement?.productId == active.productId)
        #expect(audit.headline == SubscriptionLifecycleStatus.active.rawValue)
    }

    @Test func repaymentDetailViewModelParsesStructuredAllocationPayload() async throws {
        let debt = Debt(
            name: "解析流水债务",
            type: .loan,
            subtype: "信用贷款",
            principal: 5_000,
            nominalAPR: 0.12,
            effectiveAPR: FinanceEngine.effectiveAPR(nominalAPR: 0.12),
            startDate: Date()
        )
        debt.repaymentPlans = [
            RepaymentPlan(periodIndex: 1, dueDate: Date(), principalDue: 2_500, interestDue: 80, minimumDue: 300, debt: debt)
        ]

        let payload = """
        {"allocation":{"overdueFee":30,"penaltyInterest":20,"interest":50,"fee":10,"principal":390},"inputAmount":600,"appliedAmount":500,"remainingAmount":100,"calculatedAt":"2026-04-28T10:00:00Z"}
        """
        let record = RepaymentRecord(amount: 500, allocationJSON: payload, debt: debt)

        let viewModel = RepaymentDetailViewModel(record: record)

        #expect(viewModel.allocation.inputAmount == 600)
        #expect(viewModel.allocation.appliedAmount == 500)
        #expect(viewModel.allocation.remainingAmount == 100)
        #expect(viewModel.allocation.principal == 390)
        #expect(viewModel.allocation.fee == 10)
        #expect(viewModel.statusSummary.footnote?.contains("100.00") == true)
    }

    @Test func debtDetailViewModelHighlightsOverduePressure() async throws {
        let debt = Debt(
            name: "逾期展示债务",
            type: .loan,
            subtype: "信用贷款",
            principal: 8_000,
            nominalAPR: 0.16,
            effectiveAPR: FinanceEngine.effectiveAPR(nominalAPR: 0.16),
            startDate: Date()
        )
        let pastDue = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let plan = RepaymentPlan(periodIndex: 1, dueDate: pastDue, principalDue: 1_200, interestDue: 90, minimumDue: 400, status: .overdue, debt: debt)
        let overdue = OverdueEvent(
            startDate: pastDue,
            overduePrincipal: 1_200,
            overdueInterest: 90,
            penaltyInterest: 35,
            overdueFee: 60,
            isResolved: false,
            debt: debt,
            plan: plan
        )
        debt.repaymentPlans = [plan]
        debt.overdueEvents = [overdue]
        debt.status = .overdue

        let viewModel = DebtDetailViewModel(debt: debt)

        #expect(viewModel.badgeText == DebtStatus.overdue.rawValue)
        #expect(viewModel.statusSummary.tone == .danger)
        #expect(viewModel.statusSummary.message.contains("未结清逾期"))
        #expect(viewModel.metrics.contains(where: { $0.title == "未结清逾期" && $0.value == currencyText(1_385) }))
    }

    @Test func overdueDetailViewModelDescribesResolvedEvent() async throws {
        let debt = Debt(
            name: "已处理逾期债务",
            type: .privateLending,
            subtype: "有息借贷",
            principal: 3_000,
            nominalAPR: 0.1,
            effectiveAPR: FinanceEngine.effectiveAPR(nominalAPR: 0.1),
            startDate: Date()
        )
        debt.privateLoanDetail = PrivateLoanDebtDetail(isInterestFree: false, agreedAPR: 0.1, penaltyDailyRate: 0.0003, overdueFeeFlat: 20)
        debt.status = .normal

        let start = Calendar.current.date(byAdding: .day, value: -12, to: Date()) ?? Date()
        let end = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        let event = OverdueEvent(
            startDate: start,
            endDate: end,
            overduePrincipal: 300,
            overdueInterest: 20,
            penaltyInterest: 15,
            overdueFee: 20,
            isResolved: true,
            debt: debt,
            plan: nil
        )

        let viewModel = OverdueDetailViewModel(event: event)

        #expect(viewModel.badgeText == "已处理")
        #expect(viewModel.statusSummary.tone == .success)
        #expect(viewModel.statusSummary.message.contains("处理完成"))
        #expect(viewModel.relatedFields.contains(where: { $0.title == "债务类型" && $0.value == DebtType.privateLending.rawValue }))
    }
}
