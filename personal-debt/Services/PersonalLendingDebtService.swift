import Foundation
import SwiftData

@MainActor
final class PersonalLendingDebtService {
    private let modelContext: ModelContext?
    private let scheduleEngine: PersonalLendingScheduleEngine
    private let paymentEngine: PersonalLendingPaymentEngine
    private let analyticsInvalidator: AnalyticsInvalidating?
    private let writeAccessAuthorizer: WriteAccessAuthorizing

    init(
        modelContext: ModelContext? = nil,
        scheduleEngine: PersonalLendingScheduleEngine? = nil,
        paymentEngine: PersonalLendingPaymentEngine? = nil,
        analyticsInvalidator: AnalyticsInvalidating? = nil,
        writeAccessAuthorizer: WriteAccessAuthorizing? = nil
    ) {
        self.modelContext = modelContext
        self.scheduleEngine = scheduleEngine ?? PersonalLendingScheduleEngine()
        self.paymentEngine = paymentEngine ?? PersonalLendingPaymentEngine()
        self.analyticsInvalidator = analyticsInvalidator
        self.writeAccessAuthorizer = writeAccessAuthorizer ?? UnrestrictedWriteAccessAuthorizer.shared
    }

    func createDebt(_ input: PersonalLendingDebtInput) throws -> (DebtServiceResult, PersonalLendingDebt, [PersonalLendingPlan]) {
        try perform {
            let debt = PersonalLendingDebt(
                name: input.name,
                lenderName: input.lenderName,
                note: input.note,
                principalAmount: input.principalAmount,
                fixedInterestAmount: input.fixedInterestAmount,
                borrowedDate: input.borrowedDate,
                agreedEndDate: input.agreedEndDate,
                repaymentMethod: input.repaymentMethod,
                isInterestBearing: input.isInterestBearing,
                monthlyRepaymentDay: input.monthlyRepaymentDay,
                termCount: input.termCount
            )
            let plans = try scheduleEngine.generatePlans(for: debt)
            insert(debt)
            plans.forEach(insert)
            try markAnalyticsDirty([.debt, .overdue, .cost])
            return (.created, debt, plans)
        }
    }

    func recordPayment(
        debt: PersonalLendingDebt,
        plans: [PersonalLendingPlan],
        payments: inout [PersonalLendingPaymentRecord],
        allocationDetails: inout [PersonalLendingAllocationDetail],
        input: PersonalLendingPaymentInput,
        today: Date = Date()
    ) throws -> (DebtServiceResult, PersonalLendingPaymentRecord) {
        try perform {
            try validatePaymentInput(input)
            guard input.amount <= debt.remainingAmount else {
                throw PersonalLendingPaymentError.overpaymentNotAllowed
            }
            let payment = PersonalLendingPaymentRecord(
                debtID: debt.id,
                paymentDate: input.paymentDate,
                amount: input.amount,
                note: input.note
            )
            payments.append(payment)
            insert(payment)
            try rebuildPayments(
                debt: debt,
                plans: plans,
                payments: payments,
                allocationDetails: &allocationDetails,
                today: today
            )
            try markAnalyticsDirty(.all)
            return (.recalculated, payment)
        }
    }

    func updatePayment(
        _ payment: PersonalLendingPaymentRecord,
        input: PersonalLendingPaymentInput,
        debt: PersonalLendingDebt,
        plans: [PersonalLendingPlan],
        payments: [PersonalLendingPaymentRecord],
        allocationDetails: inout [PersonalLendingAllocationDetail],
        today: Date = Date()
    ) throws -> DebtServiceResult {
        try perform {
            try validatePaymentInput(input)
            let oldDate = payment.paymentDate
            let oldAmount = payment.amount
            let oldNote = payment.note
            let oldUpdatedAt = payment.updatedAt

            payment.paymentDate = input.paymentDate
            payment.amount = input.amount
            payment.note = input.note
            payment.updatedAt = today

            do {
                try rebuildPayments(
                    debt: debt,
                    plans: plans,
                    payments: payments,
                    allocationDetails: &allocationDetails,
                    today: today
                )
            } catch {
                payment.paymentDate = oldDate
                payment.amount = oldAmount
                payment.note = oldNote
                payment.updatedAt = oldUpdatedAt
                throw error
            }
            try markAnalyticsDirty(.all)
            return .recalculated
        }
    }

    func deletePayment(
        _ payment: PersonalLendingPaymentRecord,
        debt: PersonalLendingDebt,
        plans: [PersonalLendingPlan],
        payments: inout [PersonalLendingPaymentRecord],
        allocationDetails: inout [PersonalLendingAllocationDetail],
        today: Date = Date()
    ) throws -> DebtServiceResult {
        try perform {
            payments.removeAll { $0.id == payment.id }
            modelContext?.delete(payment)
            try rebuildPayments(
                debt: debt,
                plans: plans,
                payments: payments,
                allocationDetails: &allocationDetails,
                today: today
            )
            try markAnalyticsDirty(.all)
            return .recalculated
        }
    }

    func updateCoreFields(
        debt: PersonalLendingDebt,
        input: PersonalLendingDebtInput,
        existingPayments: [PersonalLendingPaymentRecord],
        plans: inout [PersonalLendingPlan]
    ) throws -> (DebtServiceResult, [PersonalLendingPlan]) {
        try perform {
            guard existingPayments.isEmpty else {
                throw DebtServiceError.validationFailed("Core personal lending fields are locked after payment records exist.")
            }
            for plan in plans {
                modelContext?.delete(plan)
            }
            debt.principalAmount = input.principalAmount
            debt.fixedInterestAmount = input.fixedInterestAmount
            debt.borrowedDate = input.borrowedDate
            debt.agreedEndDate = input.agreedEndDate
            debt.repaymentMethod = input.repaymentMethod
            debt.isInterestBearing = input.isInterestBearing
            debt.monthlyRepaymentDay = input.monthlyRepaymentDay
            debt.termCount = input.termCount
            debt.updatedAt = Date()
            let regeneratedPlans = try scheduleEngine.generatePlans(for: debt)
            plans = regeneratedPlans
            regeneratedPlans.forEach(insert)
            try markAnalyticsDirty(.all)
            return (.recalculated, regeneratedPlans)
        }
    }

    func updateDisplayFields(
        debt: PersonalLendingDebt,
        name: String,
        lenderName: String,
        note: String
    ) throws -> DebtServiceResult {
        try perform {
            debt.name = name
            debt.lenderName = lenderName
            debt.note = note
            debt.updatedAt = Date()
            try markAnalyticsDirty(.all)
            return .recalculated
        }
    }

    private func rebuildPayments(
        debt: PersonalLendingDebt,
        plans: [PersonalLendingPlan],
        payments: [PersonalLendingPaymentRecord],
        allocationDetails: inout [PersonalLendingAllocationDetail],
        today: Date
    ) throws {
        for detail in allocationDetails {
            modelContext?.delete(detail)
        }
        let newDetails = try paymentEngine.rebuildPayments(debt: debt, plans: plans, payments: payments, today: today)
        allocationDetails = newDetails
        newDetails.forEach(insert)
    }

    private func validatePaymentInput(_ input: PersonalLendingPaymentInput) throws {
        guard input.amount > 0 else {
            throw DebtServiceError.validationFailed("Personal lending payment amount must be greater than 0.")
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
