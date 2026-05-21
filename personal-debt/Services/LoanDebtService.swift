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

    func createDebt(_ input: LoanDebtInput, today: Date = Date()) throws -> (DebtServiceResult, LoanDebt, [LoanRepaymentPlan]) {
        try perform {
            try validateDebtInput(input)
            let normalized = try normalizedLifecycleInput(from: input, today: today)
            let debt = LoanDebt(
                name: input.name,
                creditorName: input.creditorName,
                note: input.note,
                entryMode: normalized.entryMode,
                repaymentMethod: input.repaymentMethod,
                originalPrincipal: input.originalPrincipal,
                openingPrincipalForManagement: normalized.openingPrincipal,
                annualInterestRate: input.annualInterestRate,
                startDate: input.startDate,
                managementStartDate: normalized.managementStartDate,
                endDate: input.endDate,
                repaymentDay: input.repaymentDay,
                termCount: 1,
                currencyCode: input.currencyCode
            )
            let plans = try scheduleEngine.generatePlans(for: debt)
            if normalized.autoSettleAllPlans {
                autoSettleCompletedPlans(plans)
                debt.outstandingPrincipal = 0
                debt.status = .paidOff
            }
            debt.termCount = plans.count
            insert(debt)
            plans.forEach(insert)
            try markAnalyticsDirty([.debt, .overdue, .cost])
            return (.created, debt, plans)
        }
    }

    func updateDisplayFields(
        debt: LoanDebt,
        name: String,
        creditorName: String,
        note: String
    ) throws -> DebtServiceResult {
        try perform {
            guard name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw DebtServiceError.validationFailed(String(localized: "error.loanNameRequired", defaultValue: "Loan name is required."))
            }
            debt.name = name
            debt.creditorName = creditorName
            debt.note = note
            debt.updatedAt = Date()
            try markAnalyticsDirty(.all)
            return .recalculated
        }
    }

    func updateCoreFields(
        debt: LoanDebt,
        input: LoanDebtInput,
        existingPayments: [LoanPaymentRecord],
        plans: inout [LoanRepaymentPlan],
        today: Date = Date()
    ) throws -> (DebtServiceResult, [LoanRepaymentPlan]) {
        try perform {
            try validateDebtInput(input)
            guard existingPayments.isEmpty else {
                throw DebtServiceError.validationFailed(String(localized: "error.loanCoreLockedAfterPayment", defaultValue: "Core loan fields are locked after payment records exist."))
            }
            for plan in plans {
                modelContext?.delete(plan)
            }
            let normalized = try normalizedLifecycleInput(from: input, today: today)
            debt.name = input.name
            debt.creditorName = input.creditorName
            debt.note = input.note
            debt.entryMode = normalized.entryMode
            debt.repaymentMethod = input.repaymentMethod
            debt.originalPrincipal = input.originalPrincipal
            debt.openingPrincipalForManagement = normalized.openingPrincipal
            debt.outstandingPrincipal = normalized.openingPrincipal
            debt.annualInterestRate = input.annualInterestRate
            debt.startDate = input.startDate
            debt.managementStartDate = normalized.managementStartDate
            debt.endDate = input.endDate
            debt.repaymentDay = input.repaymentDay
            debt.currencyCode = input.currencyCode
            debt.status = .active
            debt.updatedAt = Date()
            let regeneratedPlans = try scheduleEngine.generatePlans(for: debt)
            if normalized.autoSettleAllPlans {
                autoSettleCompletedPlans(regeneratedPlans)
                debt.outstandingPrincipal = 0
                debt.status = .paidOff
            }
            debt.termCount = regeneratedPlans.count
            plans = regeneratedPlans
            regeneratedPlans.forEach(insert)
            try markAnalyticsDirty(.all)
            return (.recalculated, regeneratedPlans)
        }
    }

    func softDeleteDebt(
        _ debt: LoanDebt,
        overdues: [LoanOverdueRecord],
        today: Date = Date()
    ) throws -> DebtServiceResult {
        try perform {
            debt.status = .archived
            debt.updatedAt = today
            for overdue in overdues where overdue.debtID == debt.id {
                overdue.status = .voided
                overdue.overdueEndDate = overdue.overdueEndDate ?? today
                overdue.updatedAt = today
            }
            try markAnalyticsDirty(.all)
            return .recalculated
        }
    }

    func upsertCalculationRule(
        existingRule: LoanCalculationRule? = nil,
        input: LoanCalculationRuleInput,
        today: Date = Date()
    ) throws -> (DebtServiceResult, LoanCalculationRule) {
        try perform {
            try validateCalculationRuleInput(input)

            let ruleToUpdate: LoanCalculationRule?
            if let existingRule {
                ruleToUpdate = existingRule
            } else {
                ruleToUpdate = try findCalculationRule(debtID: input.debtID)
            }

            if let rule = ruleToUpdate {
                apply(input, to: rule, updatedAt: today)
                try deleteDuplicateCalculationRules(debtID: input.debtID, keeping: rule)
                try refreshAfterCalculationRuleChange(targetDebtID: input.debtID, today: today)
                try markAnalyticsDirty(.all)
                return (.recalculated, rule)
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
            try refreshAfterCalculationRuleChange(targetDebtID: input.debtID, today: today)
            try markAnalyticsDirty(.all)
            return (.created, rule)
        }
    }

    func deleteCalculationRule(_ rule: LoanCalculationRule, today: Date = Date()) throws -> DebtServiceResult {
        try perform {
            guard let targetDebtID = rule.debtID else {
                throw DebtServiceError.validationFailed(String(localized: "error.defaultRuleCannotBeDeleted", defaultValue: "Default calculation rules cannot be deleted."))
            }
            modelContext?.delete(rule)
            try refreshAfterCalculationRuleChange(targetDebtID: targetDebtID, today: today)
            try markAnalyticsDirty(.all)
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
                if overdues.contains(where: { $0.planID == plan.id && $0.status == .ignored }) {
                    continue
                }
                let existing = overdues.first { $0.planID == plan.id && $0.status == .active }
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

    func createManualOverdue(
        debt: LoanDebt,
        plan: LoanRepaymentPlan,
        existingOverdues: inout [LoanOverdueRecord],
        input: LoanManualOverdueInput,
        today: Date = Date()
    ) throws -> (DebtServiceResult, LoanOverdueRecord) {
        try perform {
            if existingOverdues.contains(where: { $0.planID == plan.id && $0.status == .active }) {
                throw DebtServiceError.validationFailed(String(localized: "error.overdueAlreadyExists", defaultValue: "An active overdue record already exists for this item."))
            }
            try validateManualOverdueInput(input, dueDate: plan.dueDate, today: today)

            let record = LoanOverdueRecord(
                debtID: debt.id,
                planID: plan.id,
                source: .userCreated,
                status: input.endDate == nil ? .active : .closed,
                isUserManaged: true,
                overdueStartDate: input.startDate,
                overdueEndDate: input.endDate,
                overdueDays: overdueDays(from: input.startDate, to: input.endDate ?? today),
                overdueBaseAmount: plan.remainingPrincipal + plan.remainingInterest,
                overdueFee: input.overdueFee,
                penaltyInterest: input.penaltyInterest,
                note: input.note,
                createdAt: today,
                updatedAt: today
            )
            existingOverdues.append(record)
            insert(record)
            plan.overdueStartDate = input.startDate
            plan.overdueDays = record.overdueDays
            plan.remainingOverdueFee = input.overdueFee
            plan.remainingPenaltyInterest = input.penaltyInterest
            plan.remainingTotalAmount = plan.remainingPrincipal + plan.remainingInterest + input.overdueFee + input.penaltyInterest
            if record.status == .active {
                plan.status = .overdue
                debt.status = .overdue
            }
            try markAnalyticsDirty([.debt, .overdue, .cost])
            return (.created, record)
        }
    }

    func updateManualOverdue(
        _ overdue: LoanOverdueRecord,
        plan: LoanRepaymentPlan,
        debt: LoanDebt,
        plans: [LoanRepaymentPlan],
        overdues: [LoanOverdueRecord],
        input: LoanManualOverdueInput,
        today: Date = Date()
    ) throws -> DebtServiceResult {
        try perform {
            guard overdue.isUserManaged else {
                throw DebtServiceError.validationFailed(String(localized: "error.onlyUserOverdueCanBeEdited", defaultValue: "Only user-managed overdue records can be edited."))
            }
            try validateManualOverdueInput(input, dueDate: plan.dueDate, today: today)
            overdue.source = .userAdjusted
            overdue.status = input.endDate == nil ? .active : .closed
            overdue.overdueStartDate = input.startDate
            overdue.overdueEndDate = input.endDate
            overdue.overdueDays = overdueDays(from: input.startDate, to: input.endDate ?? today)
            overdue.overdueBaseAmount = plan.remainingPrincipal + plan.remainingInterest
            overdue.overdueFee = input.overdueFee
            overdue.penaltyInterest = input.penaltyInterest
            overdue.note = input.note
            overdue.updatedAt = today
            plan.overdueStartDate = input.startDate
            plan.overdueDays = overdue.overdueDays
            plan.remainingOverdueFee = input.endDate == nil ? input.overdueFee : 0
            plan.remainingPenaltyInterest = input.endDate == nil ? input.penaltyInterest : 0
            plan.remainingTotalAmount = plan.remainingPrincipal + plan.remainingInterest + plan.remainingOverdueFee + plan.remainingPenaltyInterest
            if input.endDate == nil {
                plan.status = .overdue
                debt.status = .overdue
            } else {
                recalculateDebtStatus(debt: debt, plans: plans, overdues: overdues, today: today)
            }
            try markAnalyticsDirty([.debt, .overdue, .cost])
            return .recalculated
        }
    }

    func voidOverdue(
        _ overdue: LoanOverdueRecord,
        plan: LoanRepaymentPlan?,
        debt: LoanDebt,
        plans: [LoanRepaymentPlan],
        overdues: [LoanOverdueRecord],
        status: LoanOverdueRecordStatus = .voided,
        today: Date = Date()
    ) throws -> DebtServiceResult {
        try perform {
            overdue.status = status
            overdue.overdueEndDate = overdue.overdueEndDate ?? today
            overdue.updatedAt = today
            if let plan {
                plan.remainingOverdueFee = 0
                plan.remainingPenaltyInterest = 0
                plan.remainingTotalAmount = plan.remainingPrincipal + plan.remainingInterest
                if plan.remainingTotalAmount == 0 {
                    plan.status = .paid
                } else if plan.paidTotalAmount > 0 {
                    plan.status = .partiallyPaid
                } else {
                    plan.status = .pending
                }
            }
            recalculateDebtStatus(debt: debt, plans: plans, overdues: overdues, today: today)
            try markAnalyticsDirty([.debt, .overdue, .cost])
            return .recalculated
        }
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

    private func refreshAfterCalculationRuleChange(targetDebtID: UUID?, today: Date) throws {
        guard let modelContext else { return }

        let debts = try modelContext.fetch(FetchDescriptor<LoanDebt>()).filter { $0.status != .archived }
        let plans = try modelContext.fetch(FetchDescriptor<LoanRepaymentPlan>())
        let payments = try modelContext.fetch(FetchDescriptor<LoanPaymentRecord>())
        let allocationDetails = try modelContext.fetch(FetchDescriptor<LoanPaymentAllocationDetail>())
        var overdues = try modelContext.fetch(FetchDescriptor<LoanOverdueRecord>())
        let rules = try fetchCalculationRules()
        let customDebtIDs = Set(rules.compactMap(\.debtID))
        let affectedDebtIDs: Set<UUID>

        if let targetDebtID {
            affectedDebtIDs = [targetDebtID]
        } else {
            affectedDebtIDs = Set(debts.map(\.id).filter { customDebtIDs.contains($0) == false })
        }

        guard affectedDebtIDs.isEmpty == false else { return }

        let plansByDebtID = Dictionary(grouping: plans, by: \.debtID)
        let paymentsByDebtID = Dictionary(grouping: payments, by: \.debtID)

        for debt in debts where affectedDebtIDs.contains(debt.id) {
            let rule = effectiveCalculationRule(for: debt, rules: rules)
            let debtPlans = (plansByDebtID[debt.id] ?? []).sorted {
                if $0.dueDate == $1.dueDate { return $0.periodIndex < $1.periodIndex }
                return $0.dueDate < $1.dueDate
            }
            var debtOverdues = overdues.filter { $0.debtID == debt.id && $0.status != .voided }

            for plan in debtPlans where plan.status != .paid {
                if debtOverdues.contains(where: { $0.planID == plan.id && $0.status == .ignored }) {
                    continue
                }
                let existing = debtOverdues.first { $0.planID == plan.id && $0.status == .active }
                if let record = overdueEngine.makeOrUpdateOverdueRecord(
                    for: plan,
                    debt: debt,
                    existingRecord: existing,
                    rule: rule,
                    today: today
                ), existing == nil {
                    debtOverdues.append(record)
                    overdues.append(record)
                    insert(record)
                }
            }

            var debtAllocationDetails = allocationDetails.filter { $0.debtID == debt.id }
            try rebuildAllocations(
                debt: debt,
                plans: debtPlans,
                payments: paymentsByDebtID[debt.id] ?? [],
                allocationDetails: &debtAllocationDetails,
                overdues: debtOverdues,
                rule: rule,
                today: today
            )
        }
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
        let overduesClosed = overdues.allSatisfy { [.paid, .waived, .closed, .ignored, .voided].contains($0.status) }

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

    private func fetchCalculationRules() throws -> [LoanCalculationRule] {
        guard let modelContext else { return [] }
        return try modelContext.fetch(FetchDescriptor<LoanCalculationRule>())
    }

    private func findCalculationRule(debtID: UUID?) throws -> LoanCalculationRule? {
        try fetchCalculationRules().sorted(by: calculationRuleSort).first { $0.debtID == debtID }
    }

    private func deleteDuplicateCalculationRules(debtID: UUID?, keeping keptRule: LoanCalculationRule) throws {
        guard let modelContext else { return }
        let duplicates = try fetchCalculationRules().filter {
            $0.debtID == debtID && $0.id != keptRule.id
        }
        duplicates.forEach(modelContext.delete)
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
        if input.autoDetectLifecycleFromDates == false {
            if let openingPrincipalForManagement = input.openingPrincipalForManagement {
                guard openingPrincipalForManagement > 0 else {
                    throw DebtServiceError.validationFailed("Opening principal for management must be greater than 0.")
                }
                guard openingPrincipalForManagement <= input.originalPrincipal else {
                    throw DebtServiceError.validationFailed("Opening principal for management must not exceed original principal.")
                }
            }
        }
        guard input.annualInterestRate >= 0 else {
            throw DebtServiceError.validationFailed("Interest rate must not be negative.")
        }
        guard input.startDate <= input.endDate else {
            throw DebtServiceError.validationFailed("Start date must not be later than end date.")
        }
        if input.autoDetectLifecycleFromDates == false, input.entryMode == .inProgressLoan {
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
    }

    private func validatePaymentInput(_ input: LoanPaymentInput) throws {
        guard input.totalAmount > 0 else {
            throw DebtServiceError.validationFailed("Loan payment amount must be greater than 0.")
        }
    }

    private func validateManualOverdueInput(_ input: LoanManualOverdueInput, dueDate: Date, today: Date) throws {
        try validateNonNegative(input.overdueFee, field: "overdueFee")
        try validateNonNegative(input.penaltyInterest, field: "penaltyInterest")
        guard input.startDate <= today else {
            throw DebtServiceError.validationFailed(String(localized: "error.overdueStartInFuture", defaultValue: "Overdue start date must not be later than today."))
        }
        guard input.startDate >= dueDate else {
            throw DebtServiceError.validationFailed(String(localized: "error.overdueStartBeforeDueDate", defaultValue: "Overdue start date must not be earlier than the due date."))
        }
        if let endDate = input.endDate, endDate < input.startDate {
            throw DebtServiceError.validationFailed(String(localized: "error.overdueStartAfterEnd", defaultValue: "Overdue start date must not be later than end date."))
        }
    }

    private func overdueDays(from startDate: Date, to endDate: Date) -> Int {
        max(Calendar(identifier: .gregorian).dateComponents([.day], from: startDate, to: endDate).day ?? 0, 0)
    }

    private func validateNonNegative(_ amount: Decimal, field: String) throws {
        guard amount >= 0 else {
            throw DebtServiceError.validationFailed("\(field) must not be negative.")
        }
    }

    private struct NormalizedLoanLifecycleInput {
        var entryMode: LoanEntryMode
        var managementStartDate: Date?
        var openingPrincipal: Decimal
        var autoSettleAllPlans: Bool
    }

    private enum LoanLifecycleStage {
        case notStarted
        case inProgress(managementStartDate: Date)
        case completed
    }

    private func normalizedLifecycleInput(from input: LoanDebtInput, today: Date) throws -> NormalizedLoanLifecycleInput {
        guard input.autoDetectLifecycleFromDates else {
            let openingPrincipal = input.entryMode == .newLoan
                ? input.originalPrincipal
                : (input.openingPrincipalForManagement ?? input.originalPrincipal)
            return NormalizedLoanLifecycleInput(
                entryMode: input.entryMode,
                managementStartDate: input.managementStartDate,
                openingPrincipal: openingPrincipal,
                autoSettleAllPlans: false
            )
        }

        switch lifecycleStage(startDate: input.startDate, endDate: input.endDate, today: today) {
        case .notStarted:
            return NormalizedLoanLifecycleInput(
                entryMode: .newLoan,
                managementStartDate: nil,
                openingPrincipal: input.originalPrincipal,
                autoSettleAllPlans: false
            )
        case .inProgress(let managementStartDate):
            let openingPrincipal = try inferredOpeningPrincipalForInProgressLoan(input: input, managementStartDate: managementStartDate)
            return NormalizedLoanLifecycleInput(
                entryMode: .inProgressLoan,
                managementStartDate: managementStartDate,
                openingPrincipal: openingPrincipal,
                autoSettleAllPlans: false
            )
        case .completed:
            return NormalizedLoanLifecycleInput(
                entryMode: .newLoan,
                managementStartDate: nil,
                openingPrincipal: input.originalPrincipal,
                autoSettleAllPlans: true
            )
        }
    }

    private func lifecycleStage(startDate: Date, endDate: Date, today: Date) -> LoanLifecycleStage {
        let policy = scheduleEngine.datePolicy
        let todayDay = policy.startOfDay(today)
        let startDay = policy.startOfDay(startDate)
        let endDay = policy.startOfDay(endDate)
        if todayDay < startDay {
            return .notStarted
        }
        if todayDay > endDay {
            return .completed
        }
        return .inProgress(managementStartDate: max(todayDay, startDay))
    }

    private func inferredOpeningPrincipalForInProgressLoan(input: LoanDebtInput, managementStartDate: Date) throws -> Decimal {
        let projectedDebt = LoanDebt(
            name: input.name,
            creditorName: input.creditorName,
            note: input.note,
            entryMode: .newLoan,
            repaymentMethod: input.repaymentMethod,
            originalPrincipal: input.originalPrincipal,
            openingPrincipalForManagement: input.originalPrincipal,
            annualInterestRate: input.annualInterestRate,
            startDate: input.startDate,
            managementStartDate: nil,
            endDate: input.endDate,
            repaymentDay: input.repaymentDay,
            termCount: 1,
            currencyCode: input.currencyCode
        )
        let fullPlans = try scheduleEngine.generatePlans(for: projectedDebt)
        let policy = scheduleEngine.datePolicy
        let firstDueAfterManagementStart = policy.firstRepaymentDate(after: managementStartDate, dayOfMonth: input.repaymentDay)
        let cutoffDate = policy.startOfDay(firstDueAfterManagementStart) > policy.startOfDay(input.endDate)
            ? policy.startOfDay(input.endDate)
            : policy.startOfDay(firstDueAfterManagementStart)
        let historicalPlans = fullPlans.filter { policy.startOfDay($0.dueDate) < cutoffDate }
        if let lastHistorical = historicalPlans.last {
            return roundingPolicy.round(maxDecimal(lastHistorical.remainingPrincipalAfterScheduledPayment, 0))
        }
        return input.originalPrincipal
    }

    private func autoSettleCompletedPlans(_ plans: [LoanRepaymentPlan]) {
        for plan in plans {
            plan.lockReason = LoanScheduleEngine.autoSettledHistoryLockReason
            plan.status = .paid
            plan.remainingPrincipal = 0
            plan.remainingInterest = 0
            plan.remainingOverdueFee = 0
            plan.remainingPenaltyInterest = 0
            plan.remainingTotalAmount = 0
            plan.paidPrincipal = plan.scheduledPrincipal
            plan.paidInterest = plan.scheduledInterest
            plan.paidOverdueFee = 0
            plan.paidPenaltyInterest = 0
            plan.paidTotalAmount = plan.scheduledTotalAmount
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
