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
                billingDay: input.billingDay,
                dueDay: input.dueDay,
                currencyCode: input.currencyCode
            )
            let rule = CreditCardCalculationRule(debtID: debt.id)
            insert(debt)
            insert(rule)
            try markAnalyticsDirty([.debt, .overdue, .cost])
            return (.created, debt, rule)
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
            if existingOverdues.contains(where: { $0.statementID == statement.id && $0.status != .voided }) {
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
