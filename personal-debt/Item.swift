//
//  Item.swift
//  personal-debt
//
//  Created by Mac on 2026/4/25.
//

import Foundation
import SwiftData

enum DebtType: String, Codable, CaseIterable, Identifiable {
    case creditCard = "信用卡类"
    case loan = "贷款类"
    case privateLending = "个人借贷"

    var id: String { rawValue }
}

enum DebtStatus: String, Codable, CaseIterable, Identifiable {
    case normal = "正常"
    case overdue = "逾期"
    case settled = "结清"

    var id: String { rawValue }
}

enum LoanRepaymentMethod: String, Codable, CaseIterable, Identifiable {
    case equalInstallment = "等额本息"
    case equalPrincipal = "等额本金"
    case interestOnly = "先息后本"
    case bullet = "到期还本付息"

    var id: String { rawValue }
}

enum PlanStatus: String, Codable, CaseIterable, Identifiable {
    case pending = "待还款"
    case paid = "已还款"
    case overdue = "逾期"

    var id: String { rawValue }
}

enum StrategyMethod: String, Codable, CaseIterable, Identifiable {
    case avalanche = "雪崩法"
    case snowball = "雪球法"
    case balanced = "均衡法"

    var id: String { rawValue }
}

enum CreditCardInterestFreeRule: String, Codable, CaseIterable, Identifiable {
    case statementBased = "按账单日免息"
    case transactionBased = "按消费日免息"

    var id: String { rawValue }
}

enum CreditCardInstallmentFeeMode: String, Codable, CaseIterable, Identifiable {
    case perPeriod = "按期收取"
    case upfront = "一次性收取"

    var id: String { rawValue }
}

enum CreditCardPlanKind: String, Codable, CaseIterable, Identifiable {
    case statement = "一般账单"
    case installment = "信用卡分期"

    var id: String { rawValue }
}

enum OverduePenaltyMode: String, Codable, CaseIterable, Identifiable {
    case simple = "单利"
    case compound = "复利"

    var id: String { rawValue }
}

enum PaymentAllocationOrder: String, Codable, CaseIterable, Identifiable {
    enum Component: String, CaseIterable {
        case overdueFee
        case penaltyInterest
        case interest
        case principal
    }

    case overdueFeeFirst = "逾期费用优先"
    case penaltyFirst = "罚息优先"

    var id: String { rawValue }

    var displayText: String { rawValue }

    var components: [Component] {
        switch self {
        case .overdueFeeFirst:
            return [.overdueFee, .penaltyInterest, .interest, .principal]
        case .penaltyFirst:
            return [.penaltyInterest, .overdueFee, .interest, .principal]
        }
    }
}

enum OverdueInterestBase: String, Codable, CaseIterable, Identifiable {
    case principalOnly = "仅本金"
    case principalAndInterest = "本金+利息"

    var id: String { rawValue }
}

enum ReminderCategory: String, Codable, CaseIterable, Identifiable {
    case repaymentDue = "还款提醒"
    case creditCardStatementRefresh = "账单更新提醒"

    var id: String { rawValue }
}

enum SubscriptionLifecycleStatus: String, Codable, CaseIterable, Identifiable {
    case inactive = "未开通"
    case trial = "试用中"
    case active = "订阅中"
    case expiringSoon = "即将到期"
    case gracePeriod = "宽限期"
    case billingRetry = "扣费重试"
    case expired = "已过期"
    case revoked = "已撤销"
    case verificationFailed = "验证失败"

    var id: String { rawValue }

    var isEntitled: Bool {
        switch self {
        case .trial, .active, .expiringSoon, .gracePeriod:
            return true
        case .inactive, .billingRetry, .expired, .revoked, .verificationFailed:
            return false
        }
    }
}

enum SubscriptionVerificationState: String, Codable, CaseIterable, Identifiable {
    case notChecked = "未校验"
    case verified = "已验证"
    case stale = "待刷新"
    case failed = "验证失败"
    case notConfigured = "未配置"

    var id: String { rawValue }
}

enum SubscriptionRenewalPhase: String, Codable, CaseIterable, Identifiable {
    case active = "生效中"
    case inGracePeriod = "宽限期"
    case inBillingRetry = "扣费重试"
    case expired = "已过期"
    case revoked = "已撤销"
    case unknown = "未知"

    var id: String { rawValue }
}

@Model
final class Debt {
    @Attribute(.unique) var id: UUID
    var name: String
    var type: DebtType
    var subtype: String
    var status: DebtStatus
    var principal: Double
    var nominalAPR: Double
    var effectiveAPR: Double
    var calculationRuleID: UUID?
    var calculationRuleName: String
    var startDate: Date
    var endDate: Date?
    var createdAt: Date

    @Relationship(deleteRule: .cascade) var repaymentPlans: [RepaymentPlan]
    @Relationship(deleteRule: .cascade) var repaymentRecords: [RepaymentRecord]
    @Relationship(deleteRule: .cascade) var overdueEvents: [OverdueEvent]
    @Relationship(deleteRule: .cascade) var reminderTasks: [ReminderTask]
    @Relationship(deleteRule: .cascade) var customRule: DebtCustomRule?

    @Relationship(deleteRule: .cascade) var creditCardDetail: CreditCardDebtDetail?
    @Relationship(deleteRule: .cascade) var loanDetail: LoanDebtDetail?
    @Relationship(deleteRule: .cascade) var privateLoanDetail: PrivateLoanDebtDetail?

    init(
        id: UUID = UUID(),
        name: String,
        type: DebtType,
        subtype: String,
        status: DebtStatus = .normal,
        principal: Double,
        nominalAPR: Double,
        effectiveAPR: Double,
        calculationRuleID: UUID? = nil,
        calculationRuleName: String = "默认规则",
        startDate: Date,
        endDate: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.subtype = subtype
        self.status = status
        self.principal = principal
        self.nominalAPR = nominalAPR
        self.effectiveAPR = effectiveAPR
        self.calculationRuleID = calculationRuleID
        self.calculationRuleName = calculationRuleName
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
        self.repaymentPlans = []
        self.repaymentRecords = []
        self.overdueEvents = []
        self.reminderTasks = []
        self.customRule = nil
    }

    var outstandingPrincipal: Double {
        if !repaymentPlans.isEmpty {
            return repaymentPlans.reduce(0) { $0 + max($1.principalDue, 0) }
        }
        return max(principal, 0)
    }
}

@Model
final class DebtCustomRule {
    @Attribute(.unique) var id: UUID
    var name: String
    var overduePenaltyMode: OverduePenaltyMode
    var paymentAllocationOrder: PaymentAllocationOrder

    var defaultCreditCardMinimumRate: Double
    var defaultCreditCardMinimumFloor: Double
    var defaultCreditCardMinimumIncludesFees: Bool
    var defaultCreditCardMinimumIncludesPenalty: Bool
    var defaultCreditCardMinimumIncludesInterest: Bool
    var defaultCreditCardMinimumIncludesInstallmentPrincipal: Bool
    var defaultCreditCardMinimumIncludesInstallmentFee: Bool
    var defaultCreditCardGraceDays: Int
    var defaultCreditCardStatementCycles: Int
    var defaultCreditCardPenaltyDailyRate: Double
    var defaultCreditCardOverdueFeeFlat: Double
    var defaultCreditCardOverdueGraceDays: Int
    var defaultCreditCardOverdueInterestBase: OverdueInterestBase
    var repaymentReminderLeadDays: Int
    var creditCardStatementReminderOffsetDays: Int
    var requireCreditCardStatementRefresh: Bool

    var defaultLoanPenaltyDailyRate: Double
    var defaultLoanOverdueFeeFlat: Double
    var defaultLoanGraceDays: Int
    var defaultLoanOverdueInterestBase: OverdueInterestBase
    var defaultPrivateLoanPenaltyDailyRate: Double
    var defaultPrivateLoanOverdueFeeFlat: Double
    var defaultPrivateLoanGraceDays: Int
    var defaultPrivateLoanOverdueInterestBase: OverdueInterestBase

    var debt: Debt?

    init(
        id: UUID = UUID(),
        name: String = "默认规则",
        overduePenaltyMode: OverduePenaltyMode = .simple,
        paymentAllocationOrder: PaymentAllocationOrder = .overdueFeeFirst,
        defaultCreditCardMinimumRate: Double = 0.1,
        defaultCreditCardMinimumFloor: Double = 100,
        defaultCreditCardMinimumIncludesFees: Bool = true,
        defaultCreditCardMinimumIncludesPenalty: Bool = true,
        defaultCreditCardMinimumIncludesInterest: Bool = true,
        defaultCreditCardMinimumIncludesInstallmentPrincipal: Bool = true,
        defaultCreditCardMinimumIncludesInstallmentFee: Bool = true,
        defaultCreditCardGraceDays: Int = 0,
        defaultCreditCardStatementCycles: Int = 1,
        defaultCreditCardPenaltyDailyRate: Double = 0.0005,
        defaultCreditCardOverdueFeeFlat: Double = 0,
        defaultCreditCardOverdueGraceDays: Int = 0,
        defaultCreditCardOverdueInterestBase: OverdueInterestBase = .principalOnly,
        repaymentReminderLeadDays: Int = 3,
        creditCardStatementReminderOffsetDays: Int = 1,
        requireCreditCardStatementRefresh: Bool = true,
        defaultLoanPenaltyDailyRate: Double = 0.0005,
        defaultLoanOverdueFeeFlat: Double = 0,
        defaultLoanGraceDays: Int = 0,
        defaultLoanOverdueInterestBase: OverdueInterestBase = .principalOnly,
        defaultPrivateLoanPenaltyDailyRate: Double = 0,
        defaultPrivateLoanOverdueFeeFlat: Double = 0,
        defaultPrivateLoanGraceDays: Int = 0,
        defaultPrivateLoanOverdueInterestBase: OverdueInterestBase = .principalOnly,
        debt: Debt? = nil
    ) {
        self.id = id
        self.name = name
        self.overduePenaltyMode = overduePenaltyMode
        self.paymentAllocationOrder = paymentAllocationOrder
        self.defaultCreditCardMinimumRate = defaultCreditCardMinimumRate
        self.defaultCreditCardMinimumFloor = defaultCreditCardMinimumFloor
        self.defaultCreditCardMinimumIncludesFees = defaultCreditCardMinimumIncludesFees
        self.defaultCreditCardMinimumIncludesPenalty = defaultCreditCardMinimumIncludesPenalty
        self.defaultCreditCardMinimumIncludesInterest = defaultCreditCardMinimumIncludesInterest
        self.defaultCreditCardMinimumIncludesInstallmentPrincipal = defaultCreditCardMinimumIncludesInstallmentPrincipal
        self.defaultCreditCardMinimumIncludesInstallmentFee = defaultCreditCardMinimumIncludesInstallmentFee
        self.defaultCreditCardGraceDays = defaultCreditCardGraceDays
        self.defaultCreditCardStatementCycles = 1
        self.defaultCreditCardPenaltyDailyRate = defaultCreditCardPenaltyDailyRate
        self.defaultCreditCardOverdueFeeFlat = defaultCreditCardOverdueFeeFlat
        self.defaultCreditCardOverdueGraceDays = defaultCreditCardOverdueGraceDays
        self.defaultCreditCardOverdueInterestBase = defaultCreditCardOverdueInterestBase
        self.repaymentReminderLeadDays = repaymentReminderLeadDays
        self.creditCardStatementReminderOffsetDays = creditCardStatementReminderOffsetDays
        self.requireCreditCardStatementRefresh = requireCreditCardStatementRefresh
        self.defaultLoanPenaltyDailyRate = defaultLoanPenaltyDailyRate
        self.defaultLoanOverdueFeeFlat = defaultLoanOverdueFeeFlat
        self.defaultLoanGraceDays = defaultLoanGraceDays
        self.defaultLoanOverdueInterestBase = defaultLoanOverdueInterestBase
        self.defaultPrivateLoanPenaltyDailyRate = defaultPrivateLoanPenaltyDailyRate
        self.defaultPrivateLoanOverdueFeeFlat = defaultPrivateLoanOverdueFeeFlat
        self.defaultPrivateLoanGraceDays = defaultPrivateLoanGraceDays
        self.defaultPrivateLoanOverdueInterestBase = defaultPrivateLoanOverdueInterestBase
        self.debt = debt
    }
}

@Model
final class CalculationRuleProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var overduePenaltyMode: OverduePenaltyMode
    var paymentAllocationOrder: PaymentAllocationOrder

    var defaultCreditCardMinimumRate: Double
    var defaultCreditCardMinimumFloor: Double
    var defaultCreditCardMinimumIncludesFees: Bool
    var defaultCreditCardMinimumIncludesPenalty: Bool
    var defaultCreditCardMinimumIncludesInterest: Bool
    var defaultCreditCardMinimumIncludesInstallmentPrincipal: Bool
    var defaultCreditCardMinimumIncludesInstallmentFee: Bool
    var defaultCreditCardGraceDays: Int
    var defaultCreditCardStatementCycles: Int
    var defaultCreditCardPenaltyDailyRate: Double
    var defaultCreditCardOverdueFeeFlat: Double
    var defaultCreditCardOverdueGraceDays: Int
    var defaultCreditCardOverdueInterestBase: OverdueInterestBase
    var repaymentReminderLeadDays: Int
    var creditCardStatementReminderOffsetDays: Int
    var requireCreditCardStatementRefresh: Bool

    var defaultLoanPenaltyDailyRate: Double
    var defaultLoanOverdueFeeFlat: Double
    var defaultLoanGraceDays: Int
    var defaultLoanOverdueInterestBase: OverdueInterestBase
    var defaultPrivateLoanPenaltyDailyRate: Double
    var defaultPrivateLoanOverdueFeeFlat: Double
    var defaultPrivateLoanGraceDays: Int
    var defaultPrivateLoanOverdueInterestBase: OverdueInterestBase

    init(
        id: UUID = UUID(),
        name: String,
        overduePenaltyMode: OverduePenaltyMode = .simple,
        paymentAllocationOrder: PaymentAllocationOrder = .overdueFeeFirst,
        defaultCreditCardMinimumRate: Double = 0.1,
        defaultCreditCardMinimumFloor: Double = 100,
        defaultCreditCardMinimumIncludesFees: Bool = true,
        defaultCreditCardMinimumIncludesPenalty: Bool = true,
        defaultCreditCardMinimumIncludesInterest: Bool = true,
        defaultCreditCardMinimumIncludesInstallmentPrincipal: Bool = true,
        defaultCreditCardMinimumIncludesInstallmentFee: Bool = true,
        defaultCreditCardGraceDays: Int = 0,
        defaultCreditCardStatementCycles: Int = 1,
        defaultCreditCardPenaltyDailyRate: Double = 0.0005,
        defaultCreditCardOverdueFeeFlat: Double = 0,
        defaultCreditCardOverdueGraceDays: Int = 0,
        defaultCreditCardOverdueInterestBase: OverdueInterestBase = .principalOnly,
        repaymentReminderLeadDays: Int = 3,
        creditCardStatementReminderOffsetDays: Int = 1,
        requireCreditCardStatementRefresh: Bool = true,
        defaultLoanPenaltyDailyRate: Double = 0.0005,
        defaultLoanOverdueFeeFlat: Double = 0,
        defaultLoanGraceDays: Int = 0,
        defaultLoanOverdueInterestBase: OverdueInterestBase = .principalOnly,
        defaultPrivateLoanPenaltyDailyRate: Double = 0,
        defaultPrivateLoanOverdueFeeFlat: Double = 0,
        defaultPrivateLoanGraceDays: Int = 0,
        defaultPrivateLoanOverdueInterestBase: OverdueInterestBase = .principalOnly
    ) {
        self.id = id
        self.name = name
        self.overduePenaltyMode = overduePenaltyMode
        self.paymentAllocationOrder = paymentAllocationOrder
        self.defaultCreditCardMinimumRate = defaultCreditCardMinimumRate
        self.defaultCreditCardMinimumFloor = defaultCreditCardMinimumFloor
        self.defaultCreditCardMinimumIncludesFees = defaultCreditCardMinimumIncludesFees
        self.defaultCreditCardMinimumIncludesPenalty = defaultCreditCardMinimumIncludesPenalty
        self.defaultCreditCardMinimumIncludesInterest = defaultCreditCardMinimumIncludesInterest
        self.defaultCreditCardMinimumIncludesInstallmentPrincipal = defaultCreditCardMinimumIncludesInstallmentPrincipal
        self.defaultCreditCardMinimumIncludesInstallmentFee = defaultCreditCardMinimumIncludesInstallmentFee
        self.defaultCreditCardGraceDays = defaultCreditCardGraceDays
        self.defaultCreditCardStatementCycles = 1
        self.defaultCreditCardPenaltyDailyRate = defaultCreditCardPenaltyDailyRate
        self.defaultCreditCardOverdueFeeFlat = defaultCreditCardOverdueFeeFlat
        self.defaultCreditCardOverdueGraceDays = defaultCreditCardOverdueGraceDays
        self.defaultCreditCardOverdueInterestBase = defaultCreditCardOverdueInterestBase
        self.repaymentReminderLeadDays = repaymentReminderLeadDays
        self.creditCardStatementReminderOffsetDays = creditCardStatementReminderOffsetDays
        self.requireCreditCardStatementRefresh = requireCreditCardStatementRefresh
        self.defaultLoanPenaltyDailyRate = defaultLoanPenaltyDailyRate
        self.defaultLoanOverdueFeeFlat = defaultLoanOverdueFeeFlat
        self.defaultLoanGraceDays = defaultLoanGraceDays
        self.defaultLoanOverdueInterestBase = defaultLoanOverdueInterestBase
        self.defaultPrivateLoanPenaltyDailyRate = defaultPrivateLoanPenaltyDailyRate
        self.defaultPrivateLoanOverdueFeeFlat = defaultPrivateLoanOverdueFeeFlat
        self.defaultPrivateLoanGraceDays = defaultPrivateLoanGraceDays
        self.defaultPrivateLoanOverdueInterestBase = defaultPrivateLoanOverdueInterestBase
    }
}

@Model
final class CreditCardDebtDetail {
    var billingDay: Int
    var repaymentDay: Int
    var graceDays: Int
    var statementCycles: Int
    var interestFreeRule: CreditCardInterestFreeRule
    var minimumRepaymentRate: Double
    var minimumRepaymentFloor: Double
    var minimumIncludesFees: Bool
    var minimumIncludesPenalty: Bool
    var minimumIncludesInterest: Bool
    var minimumIncludesInstallmentPrincipal: Bool
    var minimumIncludesInstallmentFee: Bool

    var installmentPeriods: Int
    var installmentPrincipal: Double
    var installmentFeeRatePerPeriod: Double
    var installmentFeeMode: CreditCardInstallmentFeeMode

    var penaltyDailyRate: Double
    var overdueFeeFlat: Double
    var overdueGraceDays: Int
    var overdueInterestBase: OverdueInterestBase
    var lastStatementRefreshedAt: Date?
    var lastStatementBalance: Double
    var lastStatementMinimumDue: Double
    var lastStatementInstallmentFee: Double

    init(
        billingDay: Int = 1,
        repaymentDay: Int = 20,
        graceDays: Int = 0,
        statementCycles: Int = 1,
        interestFreeRule: CreditCardInterestFreeRule = .statementBased,
        minimumRepaymentRate: Double = 0.1,
        minimumRepaymentFloor: Double = 100,
        minimumIncludesFees: Bool = true,
        minimumIncludesPenalty: Bool = true,
        minimumIncludesInterest: Bool = true,
        minimumIncludesInstallmentPrincipal: Bool = true,
        minimumIncludesInstallmentFee: Bool = true,
        installmentPeriods: Int = 0,
        installmentPrincipal: Double = 0,
        installmentFeeRatePerPeriod: Double = 0.005,
        installmentFeeMode: CreditCardInstallmentFeeMode = .perPeriod,
        penaltyDailyRate: Double = 0.0005,
        overdueFeeFlat: Double = 0,
        overdueGraceDays: Int = 0,
        overdueInterestBase: OverdueInterestBase = .principalOnly,
        lastStatementRefreshedAt: Date? = nil,
        lastStatementBalance: Double = 0,
        lastStatementMinimumDue: Double = 0,
        lastStatementInstallmentFee: Double = 0
    ) {
        self.billingDay = billingDay
        self.repaymentDay = repaymentDay
        self.graceDays = graceDays
        self.statementCycles = 1
        self.interestFreeRule = interestFreeRule
        self.minimumRepaymentRate = minimumRepaymentRate
        self.minimumRepaymentFloor = minimumRepaymentFloor
        self.minimumIncludesFees = minimumIncludesFees
        self.minimumIncludesPenalty = minimumIncludesPenalty
        self.minimumIncludesInterest = minimumIncludesInterest
        self.minimumIncludesInstallmentPrincipal = minimumIncludesInstallmentPrincipal
        self.minimumIncludesInstallmentFee = minimumIncludesInstallmentFee
        self.installmentPeriods = installmentPeriods
        self.installmentPrincipal = installmentPrincipal
        self.installmentFeeRatePerPeriod = installmentFeeRatePerPeriod
        self.installmentFeeMode = installmentFeeMode
        self.penaltyDailyRate = penaltyDailyRate
        self.overdueFeeFlat = overdueFeeFlat
        self.overdueGraceDays = overdueGraceDays
        self.overdueInterestBase = overdueInterestBase
        self.lastStatementRefreshedAt = lastStatementRefreshedAt
        self.lastStatementBalance = lastStatementBalance
        self.lastStatementMinimumDue = lastStatementMinimumDue
        self.lastStatementInstallmentFee = lastStatementInstallmentFee
    }
}

@Model
final class LoanDebtDetail {
    var repaymentMethod: LoanRepaymentMethod
    var termMonths: Int
    var maturityDate: Date?
    var isMortgage: Bool
    var penaltyDailyRate: Double
    var overdueFeeFlat: Double
    var overdueGraceDays: Int
    var overdueInterestBase: OverdueInterestBase

    init(
        repaymentMethod: LoanRepaymentMethod = .equalInstallment,
        termMonths: Int = 12,
        maturityDate: Date? = nil,
        isMortgage: Bool = false,
        penaltyDailyRate: Double = 0.0005,
        overdueFeeFlat: Double = 0,
        overdueGraceDays: Int = 0,
        overdueInterestBase: OverdueInterestBase = .principalOnly
    ) {
        self.repaymentMethod = repaymentMethod
        self.termMonths = termMonths
        self.maturityDate = maturityDate
        self.isMortgage = isMortgage
        self.penaltyDailyRate = penaltyDailyRate
        self.overdueFeeFlat = overdueFeeFlat
        self.overdueGraceDays = overdueGraceDays
        self.overdueInterestBase = overdueInterestBase
    }
}

@Model
final class PrivateLoanDebtDetail {
    var isInterestFree: Bool
    var agreedAPR: Double
    var penaltyDailyRate: Double
    var overdueFeeFlat: Double
    var overdueGraceDays: Int
    var overdueInterestBase: OverdueInterestBase

    init(
        isInterestFree: Bool = true,
        agreedAPR: Double = 0,
        penaltyDailyRate: Double = 0,
        overdueFeeFlat: Double = 0,
        overdueGraceDays: Int = 0,
        overdueInterestBase: OverdueInterestBase = .principalOnly
    ) {
        self.isInterestFree = isInterestFree
        self.agreedAPR = agreedAPR
        self.penaltyDailyRate = penaltyDailyRate
        self.overdueFeeFlat = overdueFeeFlat
        self.overdueGraceDays = overdueGraceDays
        self.overdueInterestBase = overdueInterestBase
    }
}

@Model
final class RepaymentPlan {
    @Attribute(.unique) var id: UUID
    var periodIndex: Int
    var dueDate: Date
    var statementDate: Date?
    var principalDue: Double
    var statementPrincipalDue: Double
    var installmentPrincipalDue: Double
    var interestDue: Double
    var feeDue: Double
    var minimumDue: Double
    var installmentFeeDue: Double
    var isInterestFree: Bool
    var status: PlanStatus

    var debt: Debt?
    @Relationship(deleteRule: .nullify) var repaymentRecords: [RepaymentRecord]
    @Relationship(deleteRule: .nullify) var overdueEvents: [OverdueEvent]
    @Relationship(deleteRule: .nullify) var reminderTasks: [ReminderTask]

    init(
        id: UUID = UUID(),
        periodIndex: Int,
        dueDate: Date,
        statementDate: Date? = nil,
        principalDue: Double,
        statementPrincipalDue: Double = 0,
        installmentPrincipalDue: Double = 0,
        interestDue: Double,
        feeDue: Double = 0,
        minimumDue: Double = 0,
        installmentFeeDue: Double = 0,
        isInterestFree: Bool = false,
        status: PlanStatus = .pending,
        debt: Debt? = nil
    ) {
        self.id = id
        self.periodIndex = periodIndex
        self.dueDate = dueDate
        self.statementDate = statementDate
        self.principalDue = principalDue
        self.statementPrincipalDue = statementPrincipalDue
        self.installmentPrincipalDue = installmentPrincipalDue
        self.interestDue = interestDue
        self.feeDue = feeDue
        self.minimumDue = minimumDue
        self.installmentFeeDue = installmentFeeDue
        self.isInterestFree = isInterestFree
        self.status = status
        self.debt = debt
        self.repaymentRecords = []
        self.overdueEvents = []
        self.reminderTasks = []
    }

    var totalDue: Double {
        principalDue + interestDue + feeDue
    }
}

@Model
final class RepaymentRecord {
    @Attribute(.unique) var id: UUID
    var paidAt: Date
    var amount: Double
    var allocationJSON: String
    var note: String

    var debt: Debt?
    var plan: RepaymentPlan?

    init(
        id: UUID = UUID(),
        paidAt: Date = Date(),
        amount: Double,
        allocationJSON: String,
        note: String = "",
        debt: Debt? = nil,
        plan: RepaymentPlan? = nil
    ) {
        self.id = id
        self.paidAt = paidAt
        self.amount = amount
        self.allocationJSON = allocationJSON
        self.note = note
        self.debt = debt
        self.plan = plan
    }
}

@Model
final class OverdueEvent {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    var endDate: Date?
    var overduePrincipal: Double
    var overdueInterest: Double
    var penaltyInterest: Double
    var overdueFee: Double
    var isResolved: Bool

    var debt: Debt?
    var plan: RepaymentPlan?

    init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date? = nil,
        overduePrincipal: Double,
        overdueInterest: Double,
        penaltyInterest: Double,
        overdueFee: Double,
        isResolved: Bool = false,
        debt: Debt? = nil,
        plan: RepaymentPlan? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.overduePrincipal = overduePrincipal
        self.overdueInterest = overdueInterest
        self.penaltyInterest = penaltyInterest
        self.overdueFee = overdueFee
        self.isResolved = isResolved
        self.debt = debt
        self.plan = plan
    }
}

@Model
final class StrategyScenario {
    @Attribute(.unique) var id: UUID
    var name: String
    var method: StrategyMethod
    var monthlyBudget: Double
    var generatedAt: Date
    var totalInterest: Double
    var payoffDate: Date
    var timelineJSON: String

    init(
        id: UUID = UUID(),
        name: String = "",
        method: StrategyMethod,
        monthlyBudget: Double,
        generatedAt: Date = Date(),
        totalInterest: Double,
        payoffDate: Date,
        timelineJSON: String
    ) {
        self.id = id
        self.name = name.isEmpty
            ? "\(method.rawValue)-\(generatedAt.formatted(date: .abbreviated, time: .shortened))"
            : name
        self.method = method
        self.monthlyBudget = monthlyBudget
        self.generatedAt = generatedAt
        self.totalInterest = totalInterest
        self.payoffDate = payoffDate
        self.timelineJSON = timelineJSON
    }
}

@Model
final class ReminderTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var message: String
    var remindAt: Date
    var category: ReminderCategory
    var deduplicationKey: String
    var notificationIdentifier: String
    var referenceDate: Date?
    var isCompleted: Bool
    var isNotificationScheduled: Bool
    var createdAt: Date
    var completedAt: Date?
    var lastNotificationSyncAt: Date?
    var notificationErrorMessage: String

    var debt: Debt?
    var plan: RepaymentPlan?

    init(
        id: UUID = UUID(),
        title: String,
        message: String,
        remindAt: Date,
        category: ReminderCategory,
        deduplicationKey: String,
        notificationIdentifier: String? = nil,
        referenceDate: Date? = nil,
        isCompleted: Bool = false,
        isNotificationScheduled: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        lastNotificationSyncAt: Date? = nil,
        notificationErrorMessage: String = "",
        debt: Debt? = nil,
        plan: RepaymentPlan? = nil
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.remindAt = remindAt
        self.category = category
        self.deduplicationKey = deduplicationKey
        self.notificationIdentifier = notificationIdentifier ?? deduplicationKey
        self.referenceDate = referenceDate
        self.isCompleted = isCompleted
        self.isNotificationScheduled = isNotificationScheduled
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.lastNotificationSyncAt = lastNotificationSyncAt
        self.notificationErrorMessage = notificationErrorMessage
        self.debt = debt
        self.plan = plan
    }
}

@Model
final class SubscriptionEntitlement {
    @Attribute(.unique) var id: UUID
    var productId: String
    var productName: String
    var status: SubscriptionLifecycleStatus
    var renewalPhase: SubscriptionRenewalPhase
    var verificationState: SubscriptionVerificationState
    var verificationMessage: String
    var isActive: Bool
    var willAutoRenew: Bool
    var renewalProductId: String
    var ownershipType: String
    var environment: String
    var purchaseDate: Date?
    var expireAt: Date?
    var gracePeriodExpireAt: Date?
    var revokedAt: Date?
    var originalTransactionId: String
    var latestTransactionId: String
    var trialUsed: Bool
    var lastVerifiedAt: Date?
    var lastSyncedAt: Date

    init(
        id: UUID = UUID(),
        productId: String,
        productName: String = "",
        status: SubscriptionLifecycleStatus = .inactive,
        renewalPhase: SubscriptionRenewalPhase = .unknown,
        verificationState: SubscriptionVerificationState = .notChecked,
        verificationMessage: String = "",
        isActive: Bool,
        willAutoRenew: Bool = false,
        renewalProductId: String = "",
        ownershipType: String = "direct",
        environment: String = "",
        purchaseDate: Date? = nil,
        expireAt: Date? = nil,
        gracePeriodExpireAt: Date? = nil,
        revokedAt: Date? = nil,
        originalTransactionId: String = "",
        latestTransactionId: String = "",
        trialUsed: Bool = false,
        lastVerifiedAt: Date? = nil,
        lastSyncedAt: Date = Date()
    ) {
        self.id = id
        self.productId = productId
        self.productName = productName
        self.status = status
        self.renewalPhase = renewalPhase
        self.verificationState = verificationState
        self.verificationMessage = verificationMessage
        self.isActive = isActive
        self.willAutoRenew = willAutoRenew
        self.renewalProductId = renewalProductId
        self.ownershipType = ownershipType
        self.environment = environment
        self.purchaseDate = purchaseDate
        self.expireAt = expireAt
        self.gracePeriodExpireAt = gracePeriodExpireAt
        self.revokedAt = revokedAt
        self.originalTransactionId = originalTransactionId
        self.latestTransactionId = latestTransactionId
        self.trialUsed = trialUsed
        self.lastVerifiedAt = lastVerifiedAt
        self.lastSyncedAt = lastSyncedAt
    }
}

@Model
final class SubscriptionTransactionRecord {
    @Attribute(.unique) var id: String
    var productId: String
    var productName: String
    var lifecycleStatus: SubscriptionLifecycleStatus
    var verificationState: SubscriptionVerificationState
    var purchaseDate: Date
    var expirationDate: Date?
    var revocationDate: Date?
    var originalTransactionId: String
    var environment: String
    var ownershipType: String
    var isTrialPeriod: Bool
    var note: String

    init(
        id: String,
        productId: String,
        productName: String = "",
        lifecycleStatus: SubscriptionLifecycleStatus = .inactive,
        verificationState: SubscriptionVerificationState = .notChecked,
        purchaseDate: Date,
        expirationDate: Date? = nil,
        revocationDate: Date? = nil,
        originalTransactionId: String = "",
        environment: String = "",
        ownershipType: String = "direct",
        isTrialPeriod: Bool = false,
        note: String = ""
    ) {
        self.id = id
        self.productId = productId
        self.productName = productName
        self.lifecycleStatus = lifecycleStatus
        self.verificationState = verificationState
        self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate
        self.revocationDate = revocationDate
        self.originalTransactionId = originalTransactionId
        self.environment = environment
        self.ownershipType = ownershipType
        self.isTrialPeriod = isTrialPeriod
        self.note = note
    }
}

struct PaymentAllocation: Codable {
    var overdueFee: Double
    var penaltyInterest: Double
    var interest: Double
    var principal: Double

    var totalApplied: Double {
        overdueFee + penaltyInterest + interest + principal
    }
}
