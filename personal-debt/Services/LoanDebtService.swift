import Foundation
import SwiftData

@MainActor
final class LoanDebtService {
    private let modelContext: ModelContext?
    private let scheduleEngine: LoanScheduleEngine
    private let overdueEngine: LoanOverdueEngine
    private let allocationEngine: LoanPaymentAllocationEngine
    private let roundingPolicy: MoneyRoundingPolicy
    private let analyticsInvalidator: AnalyticsInvalidating?
    private let writeAccessAuthorizer: WriteAccessAuthorizing

    init(
        modelContext: ModelContext? = nil,
        scheduleEngine: LoanScheduleEngine? = nil,
        overdueEngine: LoanOverdueEngine? = nil,
        allocationEngine: LoanPaymentAllocationEngine? = nil,
        roundingPolicy: MoneyRoundingPolicy? = nil,
        analyticsInvalidator: AnalyticsInvalidating? = nil,
        writeAccessAuthorizer: WriteAccessAuthorizing? = nil
    ) {
        self.modelContext = modelContext
        self.scheduleEngine = scheduleEngine ?? LoanScheduleEngine()
        self.overdueEngine = overdueEngine ?? LoanOverdueEngine()
        self.allocationEngine = allocationEngine ?? LoanPaymentAllocationEngine()
        self.roundingPolicy = roundingPolicy ?? .standard
        self.analyticsInvalidator = analyticsInvalidator
        self.writeAccessAuthorizer = writeAccessAuthorizer ?? UnrestrictedWriteAccessAuthorizer.shared
    }

    func createDebt(_ input: LoanDebtInput) throws -> (DebtServiceResult, LoanDebt, [LoanRepaymentPlan]) {
        try perform {
            try validateDebtInput(input)
            let openingPrincipal = input.entryMode == .newLoan
                ? input.originalPrincipal
                : (input.openingPrincipalForManagement ?? input.originalPrincipal)
            let debt = LoanDebt(
                name: input.name,
                creditorName: input.creditorName,
                entryMode: input.entryMode,
                repaymentMethod: input.repaymentMethod,
                originalPrincipal: input.originalPrincipal,
                openingPrincipalForManagement: openingPrincipal,
                annualInterestRate: input.annualInterestRate,
                startDate: input.startDate,
                managementStartDate: input.managementStartDate,
                endDate: input.endDate,
                repaymentDay: input.repaymentDay,
                termCount: input.termCount,
                currencyCode: input.currencyCode
            )
            let plans = try scheduleEngine.generatePlans(for: debt)
            insert(debt)
            plans.forEach(insert)
            try markAnalyticsDirty([.debt, .overdue, .cost])
            return (.created, debt, plans)
        }
    }

    func upsertCalculationRule(
        existingRule: LoanCalculationRule? = nil,
        input: LoanCalculationRuleInput,
        today: Date = Date()
    ) throws -> (DebtServiceResult, LoanCalculationRule) {
        try perform {
            try validateCalculationRuleInput(input)

            if let existingRule {
                apply(input, to: existingRule, updatedAt: today)
                try markAnalyticsDirty([.overdue, .cost])
                return (.recalculated, existingRule)
            }

            let rule = LoanCalculationRule(
                debtID: input.debtID,
                overdueBaseType: input.overdueBaseType,
                overdueFeeMode: input.overdueFeeMode,
                fixedOverdueFee: input.fixedOverdueFee,
                overdueFeeRate: input.overdueFeeRate,
                penaltyInterestMode: input.penaltyInterestMode,
                penaltyRateMultiplier: input.penaltyRateMultiplier,
                fixedPenaltyDailyRate: input.fixedPenaltyDailyRate,
                paymentAllocationMode: input.paymentAllocationMode,
                createdAt: today,
                updatedAt: today
            )
            insert(rule)
            try markAnalyticsDirty([.overdue, .cost])
            return (.created, rule)
        }
    }

    func deleteCalculationRule(_ rule: LoanCalculationRule) throws -> DebtServiceResult {
        try perform {
            modelContext?.delete(rule)
            try markAnalyticsDirty([.overdue, .cost])
            return .recalculated
        }
    }

    func effectiveCalculationRule(for debt: LoanDebt, rules: [LoanCalculationRule]) -> LoanCalculationRule {
        let orderedRules = rules.sorted(by: calculationRuleSort)
        if let debtRule = orderedRules.first(where: { $0.debtID == debt.id }) {
            return debtRule
        }
        if let globalDefault = orderedRules.first(where: { $0.debtID == nil }) {
            return globalDefault
        }
        return LoanCalculationRule.builtInDefault()
    }

    func refreshOverdues(
        debt: LoanDebt,
        plans: [LoanRepaymentPlan],
        overdues: inout [LoanOverdueRecord],
        rule: LoanCalculationRule? = nil,
        today: Date = Date()
    ) throws -> DebtServiceResult {
        try perform {
            let effectiveRule = rule ?? LoanCalculationRule.builtInDefault()
            for plan in plans where plan.status != .paid {
                let existing = overdues.first {
                    $0.planID == plan.id
                        && $0.status != .paid
                        && $0.status != .waived
                        && $0.status != .closed
                }
                if let record = overdueEngine.makeOrUpdateOverdueRecord(
                    for: plan,
                    debt: debt,
                    existingRecord: existing,
                    rule: effectiveRule,
                    today: today
                ), existing == nil {
                    overdues.append(record)
                    insert(record)
                }
            }
            recalculateDebtStatus(debt: debt, plans: plans, overdues: overdues, today: today)
            try markAnalyticsDirty([.debt, .overdue, .cost])
            return .recalculated
        }
    }

    func refreshOverdues(
        debt: LoanDebt,
        plans: [LoanRepaymentPlan],
        overdues: inout [LoanOverdueRecord],
        calculationRules: [LoanCalculationRule],
        today: Date = Date()
    ) throws -> DebtServiceResult {
        let rule = effectiveCalculationRule(for: debt, rules: calculationRules)
        return try refreshOverdues(debt: debt, plans: plans, overdues: &overdues, rule: rule, today: today)
    }

    func recordPayment(
        debt: LoanDebt,
        plans: [LoanRepaymentPlan],
        payments: inout [LoanPaymentRecord],
        allocationDetails: inout [LoanPaymentAllocationDetail],
        overdues: [LoanOverdueRecord],
        input: LoanPaymentInput,
        rule: LoanCalculationRule? = nil,
        today: Date = Date()
    ) throws -> (DebtServiceResult, LoanPaymentRecord?) {
        try perform {
            try validatePaymentInput(input)
            let dueAmount = allocationEngine.currentDuePayableAmount(plans: plans, overdues: overdues, paymentDate: input.paymentDate)
            if input.totalAmount > dueAmount {
                return (.requiresUserDecision(unappliedAmount: roundingPolicy.round(input.totalAmount - dueAmount)), nil)
            }

            let payment = LoanPaymentRecord(
                debtID: debt.id,
                paymentDate: input.paymentDate,
                totalAmount: input.totalAmount,
                note: input.note
            )
            payments.append(payment)
            insert(payment)
            try rebuildAllocations(
                debt: debt,
                plans: plans,
                payments: payments,
                allocationDetails: &allocationDetails,
                overdues: overdues,
                rule: rule,
                today: today
            )
            try markAnalyticsDirty(.all)
            return (.recalculated, payment)
        }
    }

    func updatePayment(
        _ payment: LoanPaymentRecord,
        input: LoanPaymentInput,
        debt: LoanDebt,
        plans: [LoanRepaymentPlan],
        payments: [LoanPaymentRecord],
        allocationDetails: inout [LoanPaymentAllocationDetail],
        overdues: [LoanOverdueRecord],
        rule: LoanCalculationRule? = nil,
        today: Date = Date()
    ) throws -> DebtServiceResult {
        try perform {
            try validatePaymentInput(input)
            let oldDate = payment.paymentDate
            let oldAmount = payment.totalAmount
            let oldNote = payment.note

            payment.paymentDate = input.paymentDate
            payment.totalAmount = input.totalAmount
            payment.note = input.note

            let allocationMode = (rule ?? LoanCalculationRule.builtInDefault()).paymentAllocationMode
            let result = allocationEngine.rebuildAllocations(
                payments: payments,
                plans: plans,
                overdues: overdues,
                allocationMode: allocationMode
            )
            if case let .requiresUserDecision(unappliedAmount) = result.result {
                payment.paymentDate = oldDate
                payment.totalAmount = oldAmount
                payment.note = oldNote
                _ = allocationEngine.rebuildAllocations(
                    payments: payments,
                    plans: plans,
                    overdues: overdues,
                    allocationMode: allocationMode
                )
                return .requiresUserDecision(unappliedAmount: unappliedAmount)
            }
            replaceAllocationDetails(&allocationDetails, with: result.details)
            recalculateDebtStatus(debt: debt, plans: plans, overdues: overdues, today: today)
            try markAnalyticsDirty(.all)
            return .recalculated
        }
    }

    func deletePayment(
        _ payment: LoanPaymentRecord,
        debt: LoanDebt,
        plans: [LoanRepaymentPlan],
        payments: inout [LoanPaymentRecord],
        allocationDetails: inout [LoanPaymentAllocationDetail],
        overdues: [LoanOverdueRecord],
        rule: LoanCalculationRule? = nil,
        today: Date = Date()
    ) throws -> DebtServiceResult {
        try perform {
            payments.removeAll { $0.id == payment.id }
            modelContext?.delete(payment)
            try rebuildAllocations(
                debt: debt,
                plans: plans,
                payments: payments,
                allocationDetails: &allocationDetails,
                overdues: overdues,
                rule: rule,
                today: today
            )
            try markAnalyticsDirty(.all)
            return .recalculated
        }
    }

    func closeOverdue(
        _ overdue: LoanOverdueRecord,
        plan: LoanRepaymentPlan,
        debt: LoanDebt,
        plans: [LoanRepaymentPlan],
        overdues: [LoanOverdueRecord],
        today: Date = Date()
    ) throws -> DebtServiceResult {
        try perform {
            overdue.status = .closed
            overdue.updatedAt = today
            if plan.remainingPrincipal > 0 || plan.remainingInterest > 0 {
                plan.status = plan.paidTotalAmount > 0 ? .partiallyPaid : .pending
            }
            recalculateDebtStatus(debt: debt, plans: plans, overdues: overdues, today: today)
            try markAnalyticsDirty([.debt, .overdue, .cost])
            return .recalculated
        }
    }

    private func rebuildAllocations(
        debt: LoanDebt,
        plans: [LoanRepaymentPlan],
        payments: [LoanPaymentRecord],
        allocationDetails: inout [LoanPaymentAllocationDetail],
        overdues: [LoanOverdueRecord],
        rule: LoanCalculationRule?,
        today: Date
    ) throws {
        let allocationMode = (rule ?? LoanCalculationRule.builtInDefault()).paymentAllocationMode
        let result = allocationEngine.rebuildAllocations(
            payments: payments,
            plans: plans,
            overdues: overdues,
            allocationMode: allocationMode
        )
        if case let .requiresUserDecision(unappliedAmount) = result.result {
            throw DebtServiceError.validationFailed("Payment exceeds current due amount by \(unappliedAmount).")
        }
        replaceAllocationDetails(&allocationDetails, with: result.details)
        recalculateDebtStatus(debt: debt, plans: plans, overdues: overdues, today: today)
    }

    private func replaceAllocationDetails(
        _ allocationDetails: inout [LoanPaymentAllocationDetail],
        with newDetails: [LoanPaymentAllocationDetail]
    ) {
        for detail in allocationDetails {
            modelContext?.delete(detail)
        }
        allocationDetails = newDetails
        newDetails.forEach(insert)
    }

    private func recalculateDebtStatus(
        debt: LoanDebt,
        plans: [LoanRepaymentPlan],
        overdues: [LoanOverdueRecord],
        today: Date
    ) {
        let paidPrincipal = plans.reduce(Decimal(0)) { $0 + $1.paidPrincipal }
        debt.outstandingPrincipal = roundingPolicy.round(maxDecimal(debt.openingPrincipalForManagement - paidPrincipal, 0))
        let plansPaid = plans.allSatisfy { $0.status == .paid }
        let overduesClosed = overdues.allSatisfy { [.paid, .waived, .closed].contains($0.status) }

        if debt.outstandingPrincipal == 0 && plansPaid && overduesClosed {
            debt.status = .paidOff
        } else if overdues.contains(where: { $0.status == .active }) || plans.contains(where: { $0.status == .overdue }) {
            debt.status = .overdue
        } else if plans.contains(where: { $0.paidTotalAmount > 0 }) {
            debt.status = .partiallyPaid
        } else {
            debt.status = .active
        }
        debt.updatedAt = today
    }

    private func apply(_ input: LoanCalculationRuleInput, to rule: LoanCalculationRule, updatedAt: Date) {
        rule.debtID = input.debtID
        rule.overdueBaseType = input.overdueBaseType
        rule.overdueFeeMode = input.overdueFeeMode
        rule.fixedOverdueFee = input.fixedOverdueFee
        rule.overdueFeeRate = input.overdueFeeRate
        rule.penaltyInterestMode = input.penaltyInterestMode
        rule.penaltyRateMultiplier = input.penaltyRateMultiplier
        rule.fixedPenaltyDailyRate = input.fixedPenaltyDailyRate
        rule.paymentAllocationMode = input.paymentAllocationMode
        rule.updatedAt = updatedAt
    }

    private func calculationRuleSort(_ lhs: LoanCalculationRule, _ rhs: LoanCalculationRule) -> Bool {
        if lhs.updatedAt == rhs.updatedAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private func validateCalculationRuleInput(_ input: LoanCalculationRuleInput) throws {
        if let fixedOverdueFee = input.fixedOverdueFee {
            try validateNonNegative(fixedOverdueFee, field: "fixedOverdueFee")
        }
        if let overdueFeeRate = input.overdueFeeRate {
            guard (Decimal(0)...Decimal(1)).contains(overdueFeeRate) else {
                throw DebtServiceError.validationFailed("Overdue fee rate must be between 0 and 100%.")
            }
        }
        if input.penaltyRateMultiplier < 0 {
            throw DebtServiceError.validationFailed("Penalty rate multiplier must not be negative.")
        }
        if let fixedPenaltyDailyRate = input.fixedPenaltyDailyRate {
            try validateNonNegative(fixedPenaltyDailyRate, field: "fixedPenaltyDailyRate")
        }
    }

    private func validateDebtInput(_ input: LoanDebtInput) throws {
        guard input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw DebtServiceError.validationFailed("Loan name is required.")
        }
        guard input.originalPrincipal > 0 else {
            throw DebtServiceError.validationFailed("Original principal must be greater than 0.")
        }
        if let openingPrincipalForManagement = input.openingPrincipalForManagement {
            guard openingPrincipalForManagement > 0 else {
                throw DebtServiceError.validationFailed("Opening principal for management must be greater than 0.")
            }
            guard openingPrincipalForManagement <= input.originalPrincipal else {
                throw DebtServiceError.validationFailed("Opening principal for management must not exceed original principal.")
            }
        }
        guard input.annualInterestRate >= 0 else {
            throw DebtServiceError.validationFailed("Interest rate must not be negative.")
        }
        guard input.startDate <= input.endDate else {
            throw DebtServiceError.validationFailed("Start date must not be later than end date.")
        }
        if input.entryMode == .inProgressLoan {
            guard let managementStartDate = input.managementStartDate else {
                throw DebtServiceError.validationFailed("Management start date is required for in-progress loans.")
            }
            guard managementStartDate <= input.endDate else {
                throw DebtServiceError.validationFailed("Management start date must not be later than end date.")
            }
            guard managementStartDate >= input.startDate else {
                throw DebtServiceError.validationFailed("Management start date must not be earlier than loan start date.")
            }
        }
        guard (1...31).contains(input.repaymentDay) else {
            throw DebtServiceError.validationFailed("Repayment day must be between 1 and 31.")
        }
        guard input.termCount > 0 else {
            throw DebtServiceError.validationFailed("Term count must be greater than 0.")
        }
    }

    private func validatePaymentInput(_ input: LoanPaymentInput) throws {
        guard input.totalAmount > 0 else {
            throw DebtServiceError.validationFailed("Loan payment amount must be greater than 0.")
        }
    }

    private func validateNonNegative(_ amount: Decimal, field: String) throws {
        guard amount >= 0 else {
            throw DebtServiceError.validationFailed("\(field) must not be negative.")
        }
    }

    private func insert<T: PersistentModel>(_ model: T) {
        modelContext?.insert(model)
    }

    private func markAnalyticsDirty(_ scope: AnalyticsDirtyScope) throws {
        try analyticsInvalidator?.markAnalyticsDirty(scope)
    }

    private func perform<T>(_ block: () throws -> T) throws -> T {
        do {
            try writeAccessAuthorizer.requireWriteAccess()
            let result = try block()
            try modelContext?.save()
            return result
        } catch {
            modelContext?.rollback()
            throw error
        }
    }
}
