import Foundation
import SwiftData

@MainActor
final class CreditCardDebtService {
    private let modelContext: ModelContext?
    private let billingEngine: CreditCardBillingEngine
    private let roundingPolicy: MoneyRoundingPolicy
    private let datePolicy: DateCalculationPolicy
    private let analyticsInvalidator: AnalyticsInvalidating?
    private let writeAccessAuthorizer: WriteAccessAuthorizing

    init(
        modelContext: ModelContext? = nil,
        billingEngine: CreditCardBillingEngine? = nil,
        roundingPolicy: MoneyRoundingPolicy? = nil,
        datePolicy: DateCalculationPolicy? = nil,
        analyticsInvalidator: AnalyticsInvalidating? = nil,
        writeAccessAuthorizer: WriteAccessAuthorizing? = nil
    ) {
        self.modelContext = modelContext
        self.billingEngine = billingEngine ?? CreditCardBillingEngine()
        self.roundingPolicy = roundingPolicy ?? .standard
        self.datePolicy = datePolicy ?? .standard
        self.analyticsInvalidator = analyticsInvalidator
        self.writeAccessAuthorizer = writeAccessAuthorizer ?? UnrestrictedWriteAccessAuthorizer.shared
    }

    func createDebt(_ input: CreditCardDebtInput) throws -> (DebtServiceResult, CreditCardDebt, CreditCardCalculationRule) {
        try perform {
            try validateDay(input.billingDay, field: "billingDay")
            try validateDay(input.dueDay, field: "dueDay")
            guard input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw DebtServiceError.validationFailed("Credit card name is required.")
            }

            let debt = CreditCardDebt(
                name: input.name,
                bankName: input.bankName,
                note: input.note,
                billingDay: input.billingDay,
                dueDay: input.dueDay,
                currencyCode: input.currencyCode
            )
            let rule = try globalDefaultCalculationRule()
            insert(debt)
            try markAnalyticsDirty([.debt, .overdue, .cost])
            return (.created, debt, rule)
        }
    }

    func updateDebt(_ debt: CreditCardDebt, input: CreditCardDebtInput) throws -> DebtServiceResult {
        try perform {
            try validateDay(input.billingDay, field: "billingDay")
            try validateDay(input.dueDay, field: "dueDay")
            guard input.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw DebtServiceError.validationFailed(String(localized: "error.creditCardNameRequired", defaultValue: "Credit card name is required."))
            }

            debt.name = input.name
            debt.bankName = input.bankName
            debt.note = input.note
            debt.billingDay = input.billingDay
            debt.dueDay = input.dueDay
            debt.currencyCode = input.currencyCode
            debt.updatedAt = Date()
            try markAnalyticsDirty([.debt, .overdue, .cost])
            return .recalculated
        }
    }

    func upsertCalculationRule(
        existingRule: CreditCardCalculationRule? = nil,
        input: CreditCardCalculationRuleInput,
        today: Date = Date()
    ) throws -> (DebtServiceResult, CreditCardCalculationRule) {
        try perform {
            try validateCalculationRuleInput(input)

            let ruleToUpdate: CreditCardCalculationRule?
            if let existingRule {
                ruleToUpdate = existingRule
            } else {
                ruleToUpdate = try findCalculationRule(debtID: input.debtID)
            }

            if let rule = ruleToUpdate {
                apply(input, to: rule)
                try deleteDuplicateCalculationRules(debtID: input.debtID, keeping: rule)
                try refreshAfterCalculationRuleChange(targetDebtID: input.debtID, today: today)
                try markAnalyticsDirty(.all)
                return (.recalculated, rule)
            }

            let rule = CreditCardCalculationRule(
                debtID: input.debtID,
                minimumPaymentRatio: input.minimumPaymentRatio,
                minimumPaymentFloor: input.minimumPaymentFloor,
                revolvingInterestEnabled: input.revolvingInterestEnabled,
                revolvingDailyRate: input.revolvingDailyRate,
                overdueFeeRate: input.overdueFeeRate,
                minimumOverdueFee: input.minimumOverdueFee,
                fixedOverdueFee: input.fixedOverdueFee,
                penaltyBaseType: input.penaltyBaseType,
                penaltyDailyRate: input.penaltyDailyRate,
                currentPurchaseFallbackMode: input.currentPurchaseFallbackMode
            )
            insert(rule)
            try refreshAfterCalculationRuleChange(targetDebtID: input.debtID, today: today)
            try markAnalyticsDirty(.all)
            return (.created, rule)
        }
    }

    func deleteCalculationRule(
        _ rule: CreditCardCalculationRule,
        today: Date = Date()
    ) throws -> DebtServiceResult {
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

    func softDeleteDebt(
        _ debt: CreditCardDebt,
        statements: [CreditCardStatement],
        plans: [CreditCardRepaymentPlan],
        breakdowns: [CreditCardStatementBreakdown],
        payments: [CreditCardPaymentRecord],
        overdues: [CreditCardOverdueRecord],
        installments: [CreditCardInstallmentPlan],
        today: Date = Date()
    ) throws -> DebtServiceResult {
        try perform {
            debt.isActive = false
            debt.status = .archived
            debt.updatedAt = today

            for statement in statements where statement.debtID == debt.id {
                statement.isActive = false
                statement.status = .replaced
                statement.updatedAt = today
            }
            for plan in plans where plan.debtID == debt.id {
                plan.isActive = false
            }
            let statementIDs = Set(statements.filter { $0.debtID == debt.id }.map(\.id))
            for breakdown in breakdowns where statementIDs.contains(breakdown.statementID) {
                breakdown.isActive = false
            }
            for payment in payments where payment.debtID == debt.id {
                payment.isActive = false
                payment.updatedAt = today
            }
            for overdue in overdues where overdue.debtID == debt.id {
                overdue.status = .voided
                overdue.isActive = false
                overdue.endDate = overdue.endDate ?? today
                overdue.updatedAt = today
            }
            for installment in installments where installment.debtID == debt.id {
                installment.isActive = false
            }
            try markAnalyticsDirty(.all)
            return .recalculated
        }
    }

    func generateFallbackStatement(
        debt: CreditCardDebt,
        billingDate: Date,
        dueDate: Date,
        previousStatement: CreditCardStatement?,
        installments: [CreditCardInstallmentPlan],
        rule: CreditCardCalculationRule
    ) throws -> (DebtServiceResult, CreditCardStatement, CreditCardRepaymentPlan, CreditCardStatementBreakdown) {
        try perform {
            try validateDateOrder(billingDate, dueDate, message: "Billing date must not be later than due date.")

            let statement = billingEngine.makeFallbackStatement(
                debtID: debt.id,
                billingDate: billingDate,
                dueDate: dueDate,
                previousStatement: previousStatement,
                installments: installments,
                rule: rule
            )
            let plan = billingEngine.makeRepaymentPlan(for: statement)
            let breakdown = makeFallbackBreakdown(
                statement: statement,
                previousStatement: previousStatement,
                installments: installments,
                billingDate: billingDate
            )
            insert(statement)
            insert(plan)
            insert(breakdown)
            try markAnalyticsDirty([.debt, .overdue, .cost])
            return (.created, statement, plan, breakdown)
        }
    }

    func createUserConfirmedStatement(
        debt: CreditCardDebt,
        input: CreditCardStatementInput,
        rule: CreditCardCalculationRule,
        fallbackStatements: [CreditCardStatement],
        fallbackPlans: [CreditCardRepaymentPlan],
        fallbackBreakdowns: [CreditCardStatementBreakdown]
    ) throws -> (DebtServiceResult, CreditCardStatement, CreditCardRepaymentPlan) {
        try perform {
            try validateNonNegative(input.statementAmount, field: "statementAmount")
            if let minimumPaymentAmount = input.minimumPaymentAmount {
                try validateNonNegative(minimumPaymentAmount, field: "minimumPaymentAmount")
                if minimumPaymentAmount > input.statementAmount {
                    throw DebtServiceError.validationFailed("Minimum payment must not exceed statement amount.")
                }
            }
            try validateDateOrder(input.billingDate, input.dueDate, message: "Billing date must not be later than due date.")

            let statement = billingEngine.makeUserConfirmedStatement(
                debtID: debt.id,
                billingDate: input.billingDate,
                dueDate: input.dueDate,
                statementAmount: input.statementAmount,
                userMinimumPaymentAmount: input.minimumPaymentAmount,
                rule: rule
            )
            let plan = billingEngine.makeRepaymentPlan(for: statement)
            invalidateMatchingFallbacks(
                replacementStatementID: statement.id,
                debtID: debt.id,
                billingDate: input.billingDate,
                statements: fallbackStatements,
                plans: fallbackPlans,
                breakdowns: fallbackBreakdowns
            )

            insert(statement)
            insert(plan)
            debt.status = .active
            debt.updatedAt = Date()
            try markAnalyticsDirty([.debt, .overdue, .cost])
            return (.created, statement, plan)
        }
    }

    func updateUserConfirmedStatement(
        _ statement: CreditCardStatement,
        input: CreditCardStatementInput,
        debt: CreditCardDebt,
        plan: CreditCardRepaymentPlan?,
        payments: [CreditCardPaymentRecord],
        overdues: inout [CreditCardOverdueRecord],
        rule: CreditCardCalculationRule,
        today: Date = Date()
    ) throws -> DebtServiceResult {
        try perform {
            guard statement.source == .userConfirmed, statement.isActive else {
                throw DebtServiceError.validationFailed(String(localized: "error.onlyRealStatementCanBeEdited", defaultValue: "Only active real statements can be edited."))
            }
            try validateNonNegative(input.statementAmount, field: "statementAmount")
            if let minimumPaymentAmount = input.minimumPaymentAmount {
                try validateNonNegative(minimumPaymentAmount, field: "minimumPaymentAmount")
                if minimumPaymentAmount > input.statementAmount {
                    throw DebtServiceError.validationFailed(String(localized: "error.minimumPaymentExceedsStatement", defaultValue: "Minimum payment must not exceed statement amount."))
                }
            }
            try validateDateOrder(input.billingDate, input.dueDate, message: String(localized: "error.billingDateAfterDueDate", defaultValue: "Billing date must not be later than due date."))

            statement.billingDate = input.billingDate
            statement.dueDate = input.dueDate
            statement.statementAmount = roundingPolicy.round(input.statementAmount)
            statement.minimumPaymentAmount = billingEngine.minimumPaymentAmount(
                statementAmount: input.statementAmount,
                userInput: input.minimumPaymentAmount,
                rule: rule
            )
            statement.minimumPaymentSource = input.minimumPaymentAmount == nil ? "fallbackRule" : "userProvided"
            recalculateStatementAndOverdue(
                debt: debt,
                statement: statement,
                plan: plan,
                payments: payments,
                overdues: &overdues,
                rule: rule,
                today: today
            )
            try markAnalyticsDirty(.all)
            return .recalculated
        }
    }

    func softDeleteStatement(
        _ statement: CreditCardStatement,
        debt: CreditCardDebt,
        plan: CreditCardRepaymentPlan?,
        payments: [CreditCardPaymentRecord],
        overdues: inout [CreditCardOverdueRecord],
        today: Date = Date()
    ) throws -> DebtServiceResult {
        try perform {
            statement.isActive = false
            statement.status = .replaced
            statement.updatedAt = today
            plan?.isActive = false

            for payment in payments where payment.statementID == statement.id {
                payment.isActive = false
                payment.updatedAt = today
            }
            for overdue in overdues where overdue.statementID == statement.id {
                overdue.status = .voided
                overdue.isActive = false
                overdue.endDate = overdue.endDate ?? today
                overdue.updatedAt = today
            }
            debt.status = .active
            debt.updatedAt = today
            try markAnalyticsDirty(.all)
            return .recalculated
        }
    }

    func recordPayment(
        debt: CreditCardDebt,
        statement: CreditCardStatement,
        plan: CreditCardRepaymentPlan?,
        payments: inout [CreditCardPaymentRecord],
        overdues: inout [CreditCardOverdueRecord],
        input: CreditCardPaymentInput,
        rule: CreditCardCalculationRule,
        today: Date = Date()
    ) throws -> (DebtServiceResult, CreditCardPaymentRecord) {
        try perform {
            try validatePositive(input.amount, field: "paymentAmount")
            let payment = CreditCardPaymentRecord(
                debtID: debt.id,
                statementID: statement.id,
                paymentDate: input.paymentDate,
                amount: input.amount,
                note: input.note
            )
            payments.append(payment)
            insert(payment)
            recalculateStatementAndOverdue(
                debt: debt,
                statement: statement,
                plan: plan,
                payments: payments,
                overdues: &overdues,
                rule: rule,
                today: today
            )
            try markAnalyticsDirty([.debt, .payment, .overdue])
            return (.recalculated, payment)
        }
    }

    func refreshStatementOverdue(
        debt: CreditCardDebt,
        statement: CreditCardStatement,
        plan: CreditCardRepaymentPlan?,
        payments: [CreditCardPaymentRecord],
        overdues: inout [CreditCardOverdueRecord],
        rule: CreditCardCalculationRule,
        today: Date = Date()
    ) throws -> DebtServiceResult {
        try perform {
            recalculateStatementAndOverdue(
                debt: debt,
                statement: statement,
                plan: plan,
                payments: payments,
                overdues: &overdues,
                rule: rule,
                today: today
            )
            try markAnalyticsDirty([.debt, .overdue])
            return .recalculated
        }
    }

    func updatePayment(
        _ payment: CreditCardPaymentRecord,
        input: CreditCardPaymentInput,
        debt: CreditCardDebt,
        statement: CreditCardStatement,
        plan: CreditCardRepaymentPlan?,
        payments: [CreditCardPaymentRecord],
        overdues: inout [CreditCardOverdueRecord],
        rule: CreditCardCalculationRule,
        today: Date = Date()
    ) throws -> DebtServiceResult {
        try perform {
            try validatePositive(input.amount, field: "paymentAmount")
            payment.paymentDate = input.paymentDate
            payment.amount = input.amount
            payment.note = input.note
            payment.updatedAt = today
            recalculateStatementAndOverdue(
                debt: debt,
                statement: statement,
                plan: plan,
                payments: payments,
                overdues: &overdues,
                rule: rule,
                today: today
            )
            try markAnalyticsDirty([.debt, .payment, .overdue])
            return .recalculated
        }
    }

    func softDeletePayment(
        _ payment: CreditCardPaymentRecord,
        debt: CreditCardDebt,
        statement: CreditCardStatement,
        plan: CreditCardRepaymentPlan?,
        payments: [CreditCardPaymentRecord],
        overdues: inout [CreditCardOverdueRecord],
        rule: CreditCardCalculationRule,
        today: Date = Date()
    ) throws -> DebtServiceResult {
        try perform {
            payment.isActive = false
            payment.updatedAt = today
            recalculateStatementAndOverdue(
                debt: debt,
                statement: statement,
                plan: plan,
                payments: payments,
                overdues: &overdues,
                rule: rule,
                today: today
            )
            try markAnalyticsDirty([.debt, .payment, .overdue])
            return .recalculated
        }
    }

    func createManualOverdue(
        debt: CreditCardDebt,
        statement: CreditCardStatement,
        plan: CreditCardRepaymentPlan?,
        allStatements: [CreditCardStatement],
        existingOverdues: inout [CreditCardOverdueRecord],
        input: CreditCardManualOverdueInput
    ) throws -> (DebtServiceResult, CreditCardOverdueRecord) {
        try perform {
            guard statement.source == .userConfirmed, statement.isActive, statement.status != .replaced else {
                throw DebtServiceError.validationFailed("Manual credit card overdue records must be based on the latest real statement.")
            }
            guard latestRealStatementID(for: debt.id, in: allStatements) == statement.id else {
                throw DebtServiceError.validationFailed("Manual credit card overdue records can only target the latest real statement.")
            }
            if existingOverdues.contains(where: { $0.statementID == statement.id && $0.status == .active }) {
                throw DebtServiceError.validationFailed("A non-voided overdue record already exists for this statement.")
            }
            try validateNonNegative(input.overdueAmount, field: "overdueAmount")
            try validateNonNegative(input.overdueFee, field: "overdueFee")
            try validateNonNegative(input.penaltyInterest, field: "penaltyInterest")
            try validateDateOrder(input.startDate, input.endDate ?? input.startDate, message: "Manual overdue start date must not be later than end date.")
            guard input.startDate >= statement.dueDate else {
                throw DebtServiceError.validationFailed("Manual overdue start date must not be earlier than the statement due date.")
            }

            let record = CreditCardOverdueRecord(
                debtID: debt.id,
                statementID: statement.id,
                overdueAmount: input.overdueAmount,
                overdueFee: input.overdueFee,
                penaltyInterest: input.penaltyInterest,
                startDate: input.startDate,
                endDate: input.endDate,
                source: .userCreated,
                isUserManaged: true,
                note: input.note,
                systemCalculatedOverdueAmount: statement.remainingAmount
            )
            existingOverdues.append(record)
            insert(record)
            statement.status = .overdue
            plan?.status = .overdue
            debt.status = .overdue
            try markAnalyticsDirty([.debt, .overdue, .cost])
            return (.created, record)
        }
    }

    func updateManualOverdue(
        _ overdue: CreditCardOverdueRecord,
        input: CreditCardManualOverdueInput,
        debt: CreditCardDebt,
        statement: CreditCardStatement,
        plan: CreditCardRepaymentPlan?,
        today: Date = Date()
    ) throws -> DebtServiceResult {
        try perform {
            guard overdue.isUserManaged else {
                throw DebtServiceError.validationFailed(String(localized: "error.onlyUserOverdueCanBeEdited", defaultValue: "Only user-managed overdue records can be edited."))
            }
            try validateNonNegative(input.overdueAmount, field: "overdueAmount")
            try validateNonNegative(input.overdueFee, field: "overdueFee")
            try validateNonNegative(input.penaltyInterest, field: "penaltyInterest")
            try validateDateOrder(input.startDate, input.endDate ?? input.startDate, message: String(localized: "error.overdueStartAfterEnd", defaultValue: "Overdue start date must not be later than end date."))
            guard input.startDate >= statement.dueDate else {
                throw DebtServiceError.validationFailed(String(localized: "error.manualOverdueBeforeDueDate", defaultValue: "Manual overdue start date must not be earlier than the statement due date."))
            }

            overdue.overdueAmount = input.overdueAmount
            overdue.overdueFee = input.overdueFee
            overdue.penaltyInterest = input.penaltyInterest
            overdue.startDate = input.startDate
            overdue.endDate = input.endDate
            overdue.note = input.note
            overdue.recordSource = .userAdjusted
            overdue.status = input.endDate == nil ? .active : .ended
            overdue.isActive = overdue.status == .active
            overdue.updatedAt = today
            if overdue.status == .active {
                statement.status = .overdue
                plan?.status = .overdue
                debt.status = .overdue
            }
            try markAnalyticsDirty([.debt, .overdue, .cost])
            return .recalculated
        }
    }

    func voidOverdue(
        _ overdue: CreditCardOverdueRecord,
        status: CreditCardOverdueRecordStatus = .voided,
        today: Date = Date()
    ) throws -> DebtServiceResult {
        try perform {
            overdue.status = status
            overdue.isActive = false
            overdue.endDate = overdue.endDate ?? today
            overdue.updatedAt = today
            try markAnalyticsDirty([.debt, .overdue, .cost])
            return .recalculated
        }
    }

    func endManualOverdue(
        _ overdue: CreditCardOverdueRecord,
        debt: CreditCardDebt,
        statement: CreditCardStatement,
        plan: CreditCardRepaymentPlan?,
        payments: [CreditCardPaymentRecord],
        endDate: Date,
        today: Date = Date()
    ) throws -> DebtServiceResult {
        try perform {
            guard overdue.isUserManaged else {
                throw DebtServiceError.validationFailed("Only user-managed credit card overdue records can be ended manually.")
            }
            try validateDateOrder(overdue.startDate, endDate, message: "Manual overdue end date must not be earlier than the start date.")
            overdue.endDate = endDate
            overdue.status = .ended
            overdue.isActive = false
            overdue.updatedAt = today
            billingEngine.recalculate(statement: statement, plan: plan, payments: payments, debt: debt, today: today)
            if statement.status == .overdue {
                throw DebtServiceError.validationFailed("The statement is still below minimum payment after ending overdue.")
            }
            try markAnalyticsDirty([.debt, .overdue, .cost])
            return .recalculated
        }
    }

    private func recalculateStatementAndOverdue(
        debt: CreditCardDebt,
        statement: CreditCardStatement,
        plan: CreditCardRepaymentPlan?,
        payments: [CreditCardPaymentRecord],
        overdues: inout [CreditCardOverdueRecord],
        rule: CreditCardCalculationRule,
        today: Date
    ) {
        billingEngine.recalculate(statement: statement, plan: plan, payments: payments, debt: debt, today: today)
        refreshSystemOverdue(debt: debt, statement: statement, plan: plan, overdues: &overdues, rule: rule, today: today)
    }

    private func refreshSystemOverdue(
        debt: CreditCardDebt,
        statement: CreditCardStatement,
        plan: CreditCardRepaymentPlan?,
        overdues: inout [CreditCardOverdueRecord],
        rule: CreditCardCalculationRule,
        today: Date
    ) {
        let existingIndex = overdues.firstIndex {
            $0.statementID == statement.id && $0.status != .voided && $0.status != .replaced
        }

        guard statement.status == .overdue else {
            if let existingIndex, overdues[existingIndex].recordSource == .systemGenerated {
                overdues[existingIndex].status = .ended
                overdues[existingIndex].isActive = false
                overdues[existingIndex].endDate = today
                overdues[existingIndex].updatedAt = today
            }
            return
        }

        let overdueAmount = roundingPolicy.round(statement.remainingAmount)
        let overdueFee = rule.fixedOverdueFee ?? roundingPolicy.round(maxDecimal(overdueAmount * rule.overdueFeeRate, rule.minimumOverdueFee))
        let penaltyBase = rule.penaltyBaseType == .unpaidAmount ? overdueAmount : statement.statementAmount
        let overdueDays = max(datePolicy.daysBetween(statement.dueDate, today), 0)
        let penaltyInterest = roundingPolicy.round(penaltyBase * rule.penaltyDailyRate * Decimal(overdueDays))

        if let existingIndex {
            let existing = overdues[existingIndex]
            guard existing.isUserManaged == false else { return }
            existing.overdueAmount = overdueAmount
            existing.overdueFee = overdueFee
            existing.penaltyInterest = penaltyInterest
            existing.systemCalculatedOverdueAmount = overdueAmount
            existing.systemCalculatedOverdueFee = overdueFee
            existing.systemCalculatedPenaltyInterest = penaltyInterest
            existing.status = .active
            existing.isActive = true
            existing.updatedAt = today
            plan?.status = .overdue
            debt.status = .overdue
            return
        }

        let record = CreditCardOverdueRecord(
            debtID: debt.id,
            statementID: statement.id,
            overdueAmount: overdueAmount,
            overdueFee: overdueFee,
            penaltyInterest: penaltyInterest,
            startDate: statement.dueDate,
            source: .systemGenerated,
            isUserManaged: false,
            systemCalculatedOverdueAmount: overdueAmount,
            systemCalculatedOverdueFee: overdueFee,
            systemCalculatedPenaltyInterest: penaltyInterest
        )
        overdues.append(record)
        insert(record)
        plan?.status = .overdue
        debt.status = .overdue
    }

    private func makeFallbackBreakdown(
        statement: CreditCardStatement,
        previousStatement: CreditCardStatement?,
        installments: [CreditCardInstallmentPlan],
        billingDate: Date
    ) -> CreditCardStatementBreakdown {
        let activeInstallments = installments.filter {
            $0.isActive && $0.paidTerms < $0.totalTerms && datePolicy.startOfDay($0.nextBillingDate) <= datePolicy.startOfDay(billingDate)
        }
        let breakdown = CreditCardStatementBreakdown(
            statementID: statement.id,
            source: .fallback,
            previousCycleRemainingAmount: billingEngine.previousCycleRemainingAmount(from: previousStatement),
            installmentPrincipal: activeInstallments.reduce(Decimal(0)) { $0 + $1.principalPerTerm },
            installmentFee: activeInstallments.reduce(Decimal(0)) { $0 + $1.feePerTerm },
            installmentInterest: activeInstallments.reduce(Decimal(0)) { $0 + $1.interestPerTerm }
        )
        billingEngine.updateBreakdown(breakdown, for: statement)
        return breakdown
    }

    private func invalidateMatchingFallbacks(
        replacementStatementID: UUID,
        debtID: UUID,
        billingDate: Date,
        statements: [CreditCardStatement],
        plans: [CreditCardRepaymentPlan],
        breakdowns: [CreditCardStatementBreakdown]
    ) {
        let replacedStatementIDs = statements
            .filter {
                $0.debtID == debtID
                    && $0.source == .fallback
                    && $0.isActive
                    && datePolicy.isSameDay($0.billingDate, billingDate)
            }
            .map(\.id)

        for statement in statements where replacedStatementIDs.contains(statement.id) {
            statement.isActive = false
            statement.status = .replaced
            statement.replacedByStatementID = replacementStatementID
        }
        for plan in plans where replacedStatementIDs.contains(plan.statementID) {
            plan.isActive = false
        }
        for breakdown in breakdowns where replacedStatementIDs.contains(breakdown.statementID) {
            breakdown.isActive = false
        }
    }

    private func latestRealStatementID(for debtID: UUID, in statements: [CreditCardStatement]) -> UUID? {
        statements
            .filter { $0.debtID == debtID && $0.source == .userConfirmed && $0.isActive && $0.status != .replaced }
            .sorted { $0.billingDate > $1.billingDate }
            .first?
            .id
    }

    func effectiveCalculationRule(for debt: CreditCardDebt, rules: [CreditCardCalculationRule]) -> CreditCardCalculationRule {
        if let debtRule = rules.first(where: { $0.debtID == debt.id }) {
            return debtRule
        }
        if let globalDefault = rules.first(where: { $0.debtID == nil }) {
            return globalDefault
        }
        return CreditCardCalculationRule.builtInDefault(debtID: debt.id)
    }

    private func refreshAfterCalculationRuleChange(targetDebtID: UUID?, today: Date) throws {
        guard let modelContext else { return }

        let debts = try modelContext.fetch(FetchDescriptor<CreditCardDebt>()).filter(\.isActive)
        let statements = try modelContext.fetch(FetchDescriptor<CreditCardStatement>())
        let plans = try modelContext.fetch(FetchDescriptor<CreditCardRepaymentPlan>())
        let payments = try modelContext.fetch(FetchDescriptor<CreditCardPaymentRecord>())
        var overdues = try modelContext.fetch(FetchDescriptor<CreditCardOverdueRecord>())
        let rules = try fetchCalculationRules()
        let customDebtIDs = Set(rules.compactMap(\.debtID))
        let affectedDebtIDs: Set<UUID>

        if let targetDebtID {
            affectedDebtIDs = [targetDebtID]
        } else {
            affectedDebtIDs = Set(debts.map(\.id).filter { customDebtIDs.contains($0) == false })
        }

        guard affectedDebtIDs.isEmpty == false else { return }

        let plansByStatementID = Dictionary(grouping: plans.filter(\.isActive), by: \.statementID)
        let statementsByDebtID = Dictionary(grouping: statements, by: \.debtID)
        let paymentsByStatementID = Dictionary(grouping: payments.filter(\.isActive), by: \.statementID)

        for debt in debts where affectedDebtIDs.contains(debt.id) {
            let rule = effectiveCalculationRule(for: debt, rules: rules)
            let debtStatements = (statementsByDebtID[debt.id] ?? [])
                .filter { $0.isActive && $0.status != .replaced }
                .sorted { $0.billingDate < $1.billingDate }

            for statement in debtStatements {
                if statement.minimumPaymentSource != "userProvided" {
                    statement.minimumPaymentAmount = billingEngine.minimumPaymentAmount(
                        statementAmount: statement.statementAmount,
                        userInput: nil,
                        rule: rule
                    )
                    statement.minimumPaymentSource = "fallbackRule"
                }

                let plan = plansByStatementID[statement.id]?.first
                plan?.dueDate = statement.dueDate
                plan?.scheduledAmount = statement.statementAmount

                recalculateStatementAndOverdue(
                    debt: debt,
                    statement: statement,
                    plan: plan,
                    payments: paymentsByStatementID[statement.id] ?? [],
                    overdues: &overdues,
                    rule: rule,
                    today: today
                )
            }
        }
    }

    private func globalDefaultCalculationRule(now: Date = Date()) throws -> CreditCardCalculationRule {
        let rules = try fetchCalculationRules()
        if let globalDefault = rules.first(where: { $0.debtID == nil }) {
            return globalDefault
        }
        let rule = CreditCardCalculationRule.builtInDefault(now: now)
        insert(rule)
        return rule
    }

    private func fetchCalculationRules() throws -> [CreditCardCalculationRule] {
        guard let modelContext else { return [] }
        return try modelContext.fetch(FetchDescriptor<CreditCardCalculationRule>())
    }

    private func findCalculationRule(debtID: UUID?) throws -> CreditCardCalculationRule? {
        try fetchCalculationRules().first { $0.debtID == debtID }
    }

    private func deleteDuplicateCalculationRules(debtID: UUID?, keeping keptRule: CreditCardCalculationRule) throws {
        guard let modelContext else { return }
        let duplicates = try fetchCalculationRules().filter {
            $0.debtID == debtID && $0.id != keptRule.id
        }
        duplicates.forEach(modelContext.delete)
    }

    private func apply(_ input: CreditCardCalculationRuleInput, to rule: CreditCardCalculationRule) {
        rule.debtID = input.debtID
        rule.minimumPaymentRatio = input.minimumPaymentRatio
        rule.minimumPaymentFloor = input.minimumPaymentFloor
        rule.revolvingInterestEnabled = input.revolvingInterestEnabled
        rule.revolvingDailyRate = input.revolvingDailyRate
        rule.overdueFeeRate = input.overdueFeeRate
        rule.minimumOverdueFee = input.minimumOverdueFee
        rule.fixedOverdueFee = input.fixedOverdueFee
        rule.penaltyBaseType = input.penaltyBaseType
        rule.penaltyDailyRate = input.penaltyDailyRate
        rule.currentPurchaseFallbackMode = input.currentPurchaseFallbackMode
    }

    private func validateCalculationRuleInput(_ input: CreditCardCalculationRuleInput) throws {
        guard (Decimal(0)...Decimal(1)).contains(input.minimumPaymentRatio) else {
            throw DebtServiceError.validationFailed("Minimum payment ratio must be between 0 and 100%.")
        }
        try validateNonNegative(input.minimumPaymentFloor, field: "minimumPaymentFloor")
        guard (Decimal(0)...Decimal(1)).contains(input.revolvingDailyRate) else {
            throw DebtServiceError.validationFailed("Revolving daily rate must be between 0 and 100%.")
        }
        guard (Decimal(0)...Decimal(1)).contains(input.overdueFeeRate) else {
            throw DebtServiceError.validationFailed("Overdue fee rate must be between 0 and 100%.")
        }
        try validateNonNegative(input.minimumOverdueFee, field: "minimumOverdueFee")
        if let fixedOverdueFee = input.fixedOverdueFee {
            try validateNonNegative(fixedOverdueFee, field: "fixedOverdueFee")
        }
        guard (Decimal(0)...Decimal(1)).contains(input.penaltyDailyRate) else {
            throw DebtServiceError.validationFailed("Penalty daily rate must be between 0 and 100%.")
        }
    }

    private func validateDay(_ value: Int, field: String) throws {
        guard (1...31).contains(value) else {
            throw DebtServiceError.validationFailed("\(field) must be between 1 and 31.")
        }
    }

    private func validateNonNegative(_ value: Decimal, field: String) throws {
        guard value >= 0 else {
            throw DebtServiceError.validationFailed("\(field) must not be negative.")
        }
    }

    private func validatePositive(_ value: Decimal, field: String) throws {
        guard value > 0 else {
            throw DebtServiceError.validationFailed("\(field) must be greater than 0.")
        }
    }

    private func validateDateOrder(_ startDate: Date, _ endDate: Date, message: String) throws {
        guard startDate <= endDate else {
            throw DebtServiceError.validationFailed(message)
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
