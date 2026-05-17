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
            try validateDebtInput(input)
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

    func refreshOverdues(
        debt: PersonalLendingDebt,
        plans: [PersonalLendingPlan],
        overdues: inout [PersonalLendingOverdueRecord],
        today: Date = Date()
    ) throws -> DebtServiceResult {
        try perform {
            if plans.isEmpty {
                try refreshDebtLevelOverdue(debt: debt, overdues: &overdues, today: today)
            } else {
                for plan in plans {
                    try refreshPlanOverdue(debt: debt, plan: plan, overdues: &overdues, today: today)
                }
            }
            recalculateDebtStatus(debt: debt, plans: plans, overdues: overdues, today: today)
            try markAnalyticsDirty([.debt, .overdue, .cost])
            return .recalculated
        }
    }

    func createManualOverdue(
        debt: PersonalLendingDebt,
        plan: PersonalLendingPlan?,
        existingOverdues: inout [PersonalLendingOverdueRecord],
        input: PersonalLendingManualOverdueInput,
        today: Date = Date()
    ) throws -> (DebtServiceResult, PersonalLendingOverdueRecord) {
        try perform {
            let targetPlanID = plan?.id
            if existingOverdues.contains(where: { $0.debtID == debt.id && $0.planID == targetPlanID && $0.status == .active }) {
                throw DebtServiceError.validationFailed(String(localized: "error.overdueAlreadyExists", defaultValue: "An active overdue record already exists for this item."))
            }
            let dueDate = plan?.dueDate ?? debt.agreedEndDate ?? input.startDate
            try validateManualOverdueInput(input, dueDate: dueDate, today: today)
            let record = PersonalLendingOverdueRecord(
                debtID: debt.id,
                planID: targetPlanID,
                source: .userCreated,
                status: input.endDate == nil ? .active : .resolved,
                isUserManaged: true,
                overdueStartDate: input.startDate,
                overdueEndDate: input.endDate,
                overdueDays: overdueDays(from: input.startDate, to: input.endDate ?? today),
                overdueAmount: input.overdueAmount,
                overdueFee: input.overdueFee,
                penaltyInterest: input.penaltyInterest,
                note: input.note,
                createdAt: today,
                updatedAt: today
            )
            existingOverdues.append(record)
            insert(record)
            if record.status == .active {
                plan?.status = .overdue
                debt.status = .overdue
            }
            try markAnalyticsDirty([.debt, .overdue, .cost])
            return (.created, record)
        }
    }

    func updateManualOverdue(
        _ overdue: PersonalLendingOverdueRecord,
        debt: PersonalLendingDebt,
        plan: PersonalLendingPlan?,
        plans: [PersonalLendingPlan],
        overdues: [PersonalLendingOverdueRecord],
        input: PersonalLendingManualOverdueInput,
        today: Date = Date()
    ) throws -> DebtServiceResult {
        try perform {
            guard overdue.isUserManaged else {
                throw DebtServiceError.validationFailed(String(localized: "error.onlyUserOverdueCanBeEdited", defaultValue: "Only user-managed overdue records can be edited."))
            }
            let dueDate = plan?.dueDate ?? debt.agreedEndDate ?? input.startDate
            try validateManualOverdueInput(input, dueDate: dueDate, today: today)
            overdue.source = .userAdjusted
            overdue.status = input.endDate == nil ? .active : .resolved
            overdue.overdueStartDate = input.startDate
            overdue.overdueEndDate = input.endDate
            overdue.overdueDays = overdueDays(from: input.startDate, to: input.endDate ?? today)
            overdue.overdueAmount = input.overdueAmount
            overdue.overdueFee = input.overdueFee
            overdue.penaltyInterest = input.penaltyInterest
            overdue.note = input.note
            overdue.updatedAt = today
            if overdue.status == .active {
                plan?.status = .overdue
                debt.status = .overdue
            } else {
                recalculateDebtStatus(debt: debt, plans: plans, overdues: overdues, today: today)
            }
            try markAnalyticsDirty([.debt, .overdue, .cost])
            return .recalculated
        }
    }

    func resolveOverdue(
        _ overdue: PersonalLendingOverdueRecord,
        debt: PersonalLendingDebt,
        plan: PersonalLendingPlan?,
        plans: [PersonalLendingPlan],
        overdues: [PersonalLendingOverdueRecord],
        endDate: Date,
        today: Date = Date()
    ) throws -> DebtServiceResult {
        try perform {
            guard endDate >= overdue.overdueStartDate else {
                throw DebtServiceError.validationFailed(String(localized: "error.overdueStartAfterEnd", defaultValue: "Overdue start date must not be later than end date."))
            }
            overdue.status = .resolved
            overdue.overdueEndDate = endDate
            overdue.overdueDays = overdueDays(from: overdue.overdueStartDate, to: endDate)
            overdue.updatedAt = today
            recalculateDebtStatus(debt: debt, plans: plans, overdues: overdues, today: today)
            try markAnalyticsDirty([.debt, .overdue, .cost])
            return .recalculated
        }
    }

    func voidOverdue(
        _ overdue: PersonalLendingOverdueRecord,
        debt: PersonalLendingDebt,
        plan: PersonalLendingPlan?,
        plans: [PersonalLendingPlan],
        overdues: [PersonalLendingOverdueRecord],
        status: PersonalLendingOverdueRecordStatus = .voided,
        today: Date = Date()
    ) throws -> DebtServiceResult {
        try perform {
            overdue.status = status
            overdue.overdueEndDate = overdue.overdueEndDate ?? today
            overdue.updatedAt = today
            recalculateDebtStatus(debt: debt, plans: plans, overdues: overdues, today: today)
            try markAnalyticsDirty([.debt, .overdue, .cost])
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
            try validateDebtInput(input)
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
            try validateName(name)
            debt.name = name
            debt.lenderName = lenderName
            debt.note = note
            debt.updatedAt = Date()
            try markAnalyticsDirty(.all)
            return .recalculated
        }
    }

    func softDeleteDebt(
        _ debt: PersonalLendingDebt,
        overdues: [PersonalLendingOverdueRecord],
        today: Date = Date()
    ) throws -> DebtServiceResult {
        try perform {
            debt.isArchived = true
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

    private func refreshPlanOverdue(
        debt: PersonalLendingDebt,
        plan: PersonalLendingPlan,
        overdues: inout [PersonalLendingOverdueRecord],
        today: Date
    ) throws {
        if overdues.contains(where: { $0.planID == plan.id && $0.status == .ignored }) {
            return
        }
        let isPastDue = today > plan.dueDate && plan.remainingAmount > 0
        let existingIndex = overdues.firstIndex { $0.planID == plan.id && $0.status == .active }

        guard isPastDue else {
            if let existingIndex, overdues[existingIndex].isUserManaged == false {
                overdues[existingIndex].status = .resolved
                overdues[existingIndex].overdueEndDate = today
                overdues[existingIndex].updatedAt = today
            }
            if plan.status == .overdue {
                plan.status = plan.remainingAmount == 0 ? .paid : (plan.paidAmount > 0 ? .partiallyPaid : .pending)
            }
            return
        }

        let days = overdueDays(from: plan.dueDate, to: today)
        if let existingIndex {
            let existing = overdues[existingIndex]
            guard existing.isUserManaged == false else { return }
            existing.overdueDays = days
            existing.overdueAmount = plan.remainingAmount
            existing.status = .active
            existing.updatedAt = today
        } else {
            let record = PersonalLendingOverdueRecord(
                debtID: debt.id,
                planID: plan.id,
                overdueStartDate: plan.dueDate,
                overdueDays: days,
                overdueAmount: plan.remainingAmount,
                updatedAt: today
            )
            overdues.append(record)
            insert(record)
        }
        plan.status = .overdue
    }

    private func refreshDebtLevelOverdue(
        debt: PersonalLendingDebt,
        overdues: inout [PersonalLendingOverdueRecord],
        today: Date
    ) throws {
        guard let agreedEndDate = debt.agreedEndDate else { return }
        if overdues.contains(where: { $0.debtID == debt.id && $0.planID == nil && $0.status == .ignored }) {
            return
        }
        let isPastDue = today > agreedEndDate && debt.remainingAmount > 0
        let existingIndex = overdues.firstIndex { $0.debtID == debt.id && $0.planID == nil && $0.status == .active }

        guard isPastDue else {
            if let existingIndex, overdues[existingIndex].isUserManaged == false {
                overdues[existingIndex].status = .resolved
                overdues[existingIndex].overdueEndDate = today
                overdues[existingIndex].updatedAt = today
            }
            return
        }

        let days = overdueDays(from: agreedEndDate, to: today)
        if let existingIndex {
            let existing = overdues[existingIndex]
            guard existing.isUserManaged == false else { return }
            existing.overdueDays = days
            existing.overdueAmount = debt.remainingAmount
            existing.status = .active
            existing.updatedAt = today
        } else {
            let record = PersonalLendingOverdueRecord(
                debtID: debt.id,
                overdueStartDate: agreedEndDate,
                overdueDays: days,
                overdueAmount: debt.remainingAmount,
                updatedAt: today
            )
            overdues.append(record)
            insert(record)
        }
    }

    private func recalculateDebtStatus(
        debt: PersonalLendingDebt,
        plans: [PersonalLendingPlan],
        overdues: [PersonalLendingOverdueRecord],
        today: Date
    ) {
        if overdues.contains(where: { $0.debtID == debt.id && $0.status == .active }) {
            debt.status = .overdue
        } else if debt.remainingAmount == 0 {
            debt.status = .paidOff
        } else if debt.paidAmount > 0 {
            debt.status = .partiallyPaid
        } else {
            debt.status = .active
        }

        for plan in plans where plan.status == .overdue {
            if plan.remainingAmount == 0 {
                plan.status = .paid
            } else if plan.paidAmount > 0 && !overdues.contains(where: { $0.planID == plan.id && $0.status == .active }) {
                plan.status = .partiallyPaid
            } else if !overdues.contains(where: { $0.planID == plan.id && $0.status == .active }) {
                plan.status = .pending
            }
        }
        paymentEngine.updatePastDueStatistics(debt: debt, plans: plans, today: today)
        debt.updatedAt = today
    }

    private func validateManualOverdueInput(
        _ input: PersonalLendingManualOverdueInput,
        dueDate: Date,
        today: Date
    ) throws {
        try validateNonNegative(input.overdueAmount, field: "overdueAmount")
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

    private func validateNonNegative(_ amount: Decimal, field: String) throws {
        guard amount >= 0 else {
            throw DebtServiceError.validationFailed("\(field) must not be negative.")
        }
    }

    private func overdueDays(from startDate: Date, to endDate: Date) -> Int {
        max(Calendar(identifier: .gregorian).dateComponents([.day], from: startDate, to: endDate).day ?? 0, 0)
    }

    private func validatePaymentInput(_ input: PersonalLendingPaymentInput) throws {
        guard input.amount > 0 else {
            throw DebtServiceError.validationFailed("Personal lending payment amount must be greater than 0.")
        }
    }

    private func validateDebtInput(_ input: PersonalLendingDebtInput) throws {
        try validateName(input.name)
    }

    private func validateName(_ name: String) throws {
        guard name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw DebtServiceError.validationFailed("Personal lending name is required.")
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
