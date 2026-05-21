import Foundation
import SwiftData

@Model
final class LoanDebt {
    var id: UUID
    var name: String
    var creditorName: String
    var note: String
    var entryModeRawValue: String
    var repaymentMethodRawValue: String
    var originalPrincipal: Decimal
    var openingPrincipalForManagement: Decimal
    var outstandingPrincipal: Decimal
    var annualInterestRate: Decimal
    var startDate: Date
    var managementStartDate: Date?
    var endDate: Date
    var repaymentDay: Int
    var termCount: Int
    var statusRawValue: String
    var currencyCode: String
    var unappliedPaymentBalance: Decimal
    var createdAt: Date
    var updatedAt: Date

    var entryMode: LoanEntryMode {
        get { .value(from: entryModeRawValue, default: .newLoan) }
        set { entryModeRawValue = newValue.rawValue }
    }

    var repaymentMethod: LoanRepaymentMethod {
        get { .value(from: repaymentMethodRawValue, default: .equalPayment) }
        set { repaymentMethodRawValue = newValue.rawValue }
    }

    var status: DebtStatus {
        get { .value(from: statusRawValue, default: .active) }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        creditorName: String = "",
        note: String = "",
        entryMode: LoanEntryMode = .newLoan,
        repaymentMethod: LoanRepaymentMethod,
        originalPrincipal: Decimal,
        openingPrincipalForManagement: Decimal? = nil,
        outstandingPrincipal: Decimal? = nil,
        annualInterestRate: Decimal,
        startDate: Date,
        managementStartDate: Date? = nil,
        endDate: Date,
        repaymentDay: Int,
        termCount: Int,
        status: DebtStatus = .active,
        currencyCode: String = Locale.current.currency?.identifier ?? "USD",
        unappliedPaymentBalance: Decimal = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        let openingPrincipal = openingPrincipalForManagement ?? originalPrincipal
        self.id = id
        self.name = name
        self.creditorName = creditorName
        self.note = note
        self.entryModeRawValue = entryMode.rawValue
        self.repaymentMethodRawValue = repaymentMethod.rawValue
        self.originalPrincipal = originalPrincipal
        self.openingPrincipalForManagement = openingPrincipal
        self.outstandingPrincipal = outstandingPrincipal ?? openingPrincipal
        self.annualInterestRate = annualInterestRate
        self.startDate = startDate
        self.managementStartDate = managementStartDate
        self.endDate = endDate
        self.repaymentDay = repaymentDay
        self.termCount = termCount
        self.statusRawValue = status.rawValue
        self.currencyCode = currencyCode
        self.unappliedPaymentBalance = unappliedPaymentBalance
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class LoanRepaymentPlan {
    var id: UUID
    var debtID: UUID
    var periodIndex: Int
    var periodTypeRawValue: String
    var periodStartDate: Date
    var periodEndDate: Date
    var dueDate: Date
    var scheduledPrincipal: Decimal
    var scheduledInterest: Decimal
    var scheduledTotalAmount: Decimal
    var remainingPrincipalBeforePayment: Decimal
    var remainingPrincipalAfterScheduledPayment: Decimal
    var paidPrincipal: Decimal
    var paidInterest: Decimal
    var paidOverdueFee: Decimal
    var paidPenaltyInterest: Decimal
    var paidTotalAmount: Decimal
    var remainingPrincipal: Decimal
    var remainingInterest: Decimal
    var remainingOverdueFee: Decimal
    var remainingPenaltyInterest: Decimal
    var remainingTotalAmount: Decimal
    var overdueStartDate: Date?
    var overdueDays: Int
    var statusRawValue: String
    var isLocked: Bool
    var lockReason: String
    var updatedAt: Date

    var periodType: LoanPlanPeriodType {
        get { .value(from: periodTypeRawValue, default: .regular) }
        set { periodTypeRawValue = newValue.rawValue }
    }

    var status: PlanStatus {
        get { .value(from: statusRawValue, default: .pending) }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        debtID: UUID,
        periodIndex: Int,
        periodType: LoanPlanPeriodType,
        periodStartDate: Date,
        periodEndDate: Date,
        dueDate: Date,
        scheduledPrincipal: Decimal,
        scheduledInterest: Decimal,
        remainingPrincipalBeforePayment: Decimal,
        remainingPrincipalAfterScheduledPayment: Decimal,
        isLocked: Bool = true,
        lockReason: String = "generated"
    ) {
        self.id = id
        self.debtID = debtID
        self.periodIndex = periodIndex
        self.periodTypeRawValue = periodType.rawValue
        self.periodStartDate = periodStartDate
        self.periodEndDate = periodEndDate
        self.dueDate = dueDate
        self.scheduledPrincipal = scheduledPrincipal
        self.scheduledInterest = scheduledInterest
        self.scheduledTotalAmount = scheduledPrincipal + scheduledInterest
        self.remainingPrincipalBeforePayment = remainingPrincipalBeforePayment
        self.remainingPrincipalAfterScheduledPayment = remainingPrincipalAfterScheduledPayment
        self.paidPrincipal = 0
        self.paidInterest = 0
        self.paidOverdueFee = 0
        self.paidPenaltyInterest = 0
        self.paidTotalAmount = 0
        self.remainingPrincipal = scheduledPrincipal
        self.remainingInterest = scheduledInterest
        self.remainingOverdueFee = 0
        self.remainingPenaltyInterest = 0
        self.remainingTotalAmount = scheduledPrincipal + scheduledInterest
        self.overdueStartDate = nil
        self.overdueDays = 0
        self.statusRawValue = PlanStatus.pending.rawValue
        self.isLocked = isLocked
        self.lockReason = lockReason
        self.updatedAt = Date()
    }
}

@Model
final class LoanPaymentRecord {
    var id: UUID
    var debtID: UUID
    var paymentDate: Date
    var totalAmount: Decimal
    var note: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        debtID: UUID,
        paymentDate: Date,
        totalAmount: Decimal,
        note: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.debtID = debtID
        self.paymentDate = paymentDate
        self.totalAmount = totalAmount
        self.note = note
        self.createdAt = createdAt
    }
}

@Model
final class LoanPaymentAllocationDetail {
    var id: UUID
    var paymentID: UUID
    var debtID: UUID
    var planID: UUID
    var allocatedPrincipal: Decimal
    var allocatedInterest: Decimal
    var allocatedOverdueFee: Decimal
    var allocatedPenaltyInterest: Decimal
    var allocatedTotal: Decimal
    var createdAt: Date

    init(
        id: UUID = UUID(),
        paymentID: UUID,
        debtID: UUID,
        planID: UUID,
        allocatedPrincipal: Decimal = 0,
        allocatedInterest: Decimal = 0,
        allocatedOverdueFee: Decimal = 0,
        allocatedPenaltyInterest: Decimal = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.paymentID = paymentID
        self.debtID = debtID
        self.planID = planID
        self.allocatedPrincipal = allocatedPrincipal
        self.allocatedInterest = allocatedInterest
        self.allocatedOverdueFee = allocatedOverdueFee
        self.allocatedPenaltyInterest = allocatedPenaltyInterest
        self.allocatedTotal = allocatedPrincipal + allocatedInterest + allocatedOverdueFee + allocatedPenaltyInterest
        self.createdAt = createdAt
    }
}

@Model
final class LoanOverdueRecord {
    var id: UUID
    var debtID: UUID
    var planID: UUID
    var sourceRawValue: String
    var statusRawValue: String
    var isUserManaged: Bool
    var overdueStartDate: Date
    var overdueEndDate: Date?
    var overdueDays: Int
    var overdueBaseAmount: Decimal
    var overdueAmount: Decimal
    var unpaidInterestAmount: Decimal
    var unpaidPrincipalAmount: Decimal
    var overdueFee: Decimal
    var penaltyInterest: Decimal
    var generatesOverdueFee: Bool
    var generatesPenaltyInterest: Bool
    var paidOverdueFee: Decimal
    var paidPenaltyInterest: Decimal
    var note: String
    var createdAt: Date
    var updatedAt: Date

    var source: LoanOverdueRecordSource {
        get { .value(from: sourceRawValue, default: .systemGenerated) }
        set { sourceRawValue = newValue.rawValue }
    }

    var status: LoanOverdueRecordStatus {
        get { .value(from: statusRawValue, default: .active) }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        debtID: UUID,
        planID: UUID,
        source: LoanOverdueRecordSource = .systemGenerated,
        status: LoanOverdueRecordStatus = .active,
        isUserManaged: Bool = false,
        overdueStartDate: Date,
        overdueEndDate: Date? = nil,
        overdueDays: Int,
        overdueBaseAmount: Decimal = 0,
        overdueAmount: Decimal = 0,
        unpaidInterestAmount: Decimal = 0,
        unpaidPrincipalAmount: Decimal = 0,
        overdueFee: Decimal = 0,
        penaltyInterest: Decimal = 0,
        generatesOverdueFee: Bool = true,
        generatesPenaltyInterest: Bool = true,
        paidOverdueFee: Decimal = 0,
        paidPenaltyInterest: Decimal = 0,
        note: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.debtID = debtID
        self.planID = planID
        self.sourceRawValue = source.rawValue
        self.statusRawValue = status.rawValue
        self.isUserManaged = isUserManaged
        self.overdueStartDate = overdueStartDate
        self.overdueEndDate = overdueEndDate
        self.overdueDays = overdueDays
        self.overdueBaseAmount = overdueBaseAmount
        self.overdueAmount = overdueAmount
        self.unpaidInterestAmount = unpaidInterestAmount
        self.unpaidPrincipalAmount = unpaidPrincipalAmount
        self.overdueFee = overdueFee
        self.penaltyInterest = penaltyInterest
        self.generatesOverdueFee = generatesOverdueFee
        self.generatesPenaltyInterest = generatesPenaltyInterest
        self.paidOverdueFee = paidOverdueFee
        self.paidPenaltyInterest = paidPenaltyInterest
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class LoanCalculationRule {
    var id: UUID
    var debtID: UUID?
    var overdueBaseTypeRawValue: String
    var overdueFeeModeRawValue: String
    var fixedOverdueFee: Decimal?
    var overdueFeeRate: Decimal?
    var penaltyInterestModeRawValue: String
    var penaltyRateMultiplier: Decimal
    var fixedPenaltyDailyRate: Decimal?
    var paymentAllocationModeRawValue: String
    var createdAt: Date
    var updatedAt: Date

    var overdueBaseType: LoanOverdueBaseType {
        get { .value(from: overdueBaseTypeRawValue, default: .currentUnpaidPrincipal) }
        set { overdueBaseTypeRawValue = newValue.rawValue }
    }

    var overdueFeeMode: LoanOverdueFeeMode {
        get { .value(from: overdueFeeModeRawValue, default: .zero) }
        set { overdueFeeModeRawValue = newValue.rawValue }
    }

    var penaltyInterestMode: LoanPenaltyInterestMode {
        get { .value(from: penaltyInterestModeRawValue, default: .loanDailyRateMultiplier) }
        set { penaltyInterestModeRawValue = newValue.rawValue }
    }

    var paymentAllocationMode: LoanPaymentAllocationMode {
        get { .value(from: paymentAllocationModeRawValue, default: .feeFirst) }
        set { paymentAllocationModeRawValue = newValue.rawValue }
    }

    var isGlobalDefault: Bool {
        debtID == nil
    }

    init(
        id: UUID = UUID(),
        debtID: UUID? = nil,
        overdueBaseType: LoanOverdueBaseType = .currentUnpaidPrincipal,
        overdueFeeMode: LoanOverdueFeeMode = .zero,
        fixedOverdueFee: Decimal? = nil,
        overdueFeeRate: Decimal? = nil,
        penaltyInterestMode: LoanPenaltyInterestMode = .loanDailyRateMultiplier,
        penaltyRateMultiplier: Decimal = Decimal(string: "1.5") ?? 1.5,
        fixedPenaltyDailyRate: Decimal? = nil,
        paymentAllocationMode: LoanPaymentAllocationMode = .feeFirst,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.debtID = debtID
        self.overdueBaseTypeRawValue = overdueBaseType.rawValue
        self.overdueFeeModeRawValue = overdueFeeMode.rawValue
        self.fixedOverdueFee = fixedOverdueFee
        self.overdueFeeRate = overdueFeeRate
        self.penaltyInterestModeRawValue = penaltyInterestMode.rawValue
        self.penaltyRateMultiplier = penaltyRateMultiplier
        self.fixedPenaltyDailyRate = fixedPenaltyDailyRate
        self.paymentAllocationModeRawValue = paymentAllocationMode.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func builtInDefault(debtID: UUID? = nil, now: Date = Date()) -> LoanCalculationRule {
        LoanCalculationRule(debtID: debtID, createdAt: now, updatedAt: now)
    }
}
