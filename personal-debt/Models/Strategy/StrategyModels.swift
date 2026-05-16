import Foundation
import SwiftData

enum StrategyRiskLevel: String, Codable, CaseIterable, Identifiable {
    case low
    case medium
    case high
    case critical

    var id: String { rawValue }

    var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .critical: return 3
        }
    }
}

enum StrategyCostEventType: String, Codable, CaseIterable, Identifiable {
    case creditCardMinimumPaymentProtection
    case creditCardRevolvingInterestProtection
    case creditCardExistingOverduePenalty
    case loanCurrentPlanProtection
    case loanExistingOverduePenalty
    case personalLendingDuePlan
    case personalLendingMaturity

    var id: String { rawValue }
}

enum StrategyRiskEventType: String, Codable, CaseIterable, Identifiable {
    case budgetCannotCoverProtection
    case fallbackDataUsed
    case overdueMayContinue
    case informalPersonalLending
    case missingRepaymentPlan
    case cannotPayoffWithinSimulation
    case zeroBudgetCannotProgress
    case noDebtToSimulate
    case internalSimulationDisclaimer

    var id: String { rawValue }
}

enum StrategySimulationStatus: String, Codable, CaseIterable, Identifiable {
    case completed
    case notPaidOffWithinLimit
    case cannotProgress
    case invalidInput

    var id: String { rawValue }
}

@Model
final class StrategyComparisonBatch {
    var id: UUID
    var strategyDate: Date
    var generatedAt: Date
    var monthlyBudget: Decimal
    var maxMonths: Int
    var recommendedStrategyRawValue: String?
    var recommendationReason: String
    var disclaimer: String
    var globalRiskNotesText: String

    var recommendedStrategy: StrategyType? {
        get {
            guard let recommendedStrategyRawValue else { return nil }
            return StrategyType(rawValue: recommendedStrategyRawValue)
        }
        set { recommendedStrategyRawValue = newValue?.rawValue }
    }

    var globalRiskNotes: [String] {
        get { globalRiskNotesText.lines }
        set { globalRiskNotesText = newValue.joined(separator: "\n") }
    }

    init(
        id: UUID = UUID(),
        strategyDate: Date,
        generatedAt: Date = Date(),
        monthlyBudget: Decimal,
        maxMonths: Int,
        recommendedStrategy: StrategyType? = nil,
        recommendationReason: String = "",
        disclaimer: String = StrategyComparisonBatch.defaultDisclaimer,
        globalRiskNotes: [String] = []
    ) {
        self.id = id
        self.strategyDate = strategyDate
        self.generatedAt = generatedAt
        self.monthlyBudget = monthlyBudget
        self.maxMonths = maxMonths
        self.recommendedStrategyRawValue = recommendedStrategy?.rawValue
        self.recommendationReason = recommendationReason
        self.disclaimer = disclaimer
        self.globalRiskNotesText = globalRiskNotes.joined(separator: "\n")
    }

    static let defaultDisclaimer = "This is an internal cash-flow simulation for the app. It is not a commitment from a bank, lender, or creditor, and it is not investment, legal, or debt restructuring advice."
}

@Model
final class StrategySimulation {
    var id: UUID
    var comparisonBatchID: UUID?
    var name: String
    var strategyTypeRawValue: String
    var strategyDate: Date?
    var monthlyBudget: Decimal
    var maxMonths: Int
    var isHighRisk: Bool
    var totalAllocatedAmount: Decimal
    var totalEstimatedCost: Decimal
    var estimatedInterestAmount: Decimal
    var estimatedOverdueFee: Decimal
    var estimatedPenaltyInterest: Decimal
    var endingRemainingAmount: Decimal
    var highestMonthlyPayment: Decimal
    var averageMonthlyPayment: Decimal
    var overdueMonthCount: Int
    var highestOverdueDebtCount: Int
    var estimatedPayoffMonth: Int?
    var estimatedPayoffDate: Date?
    var riskLevelRawValue: String
    var statusRawValue: String
    var featureDescription: String
    var recommendationReason: String
    var createdAt: Date

    var strategyType: StrategyType {
        get { .value(from: strategyTypeRawValue, default: .balanced) }
        set { strategyTypeRawValue = newValue.rawValue }
    }

    var riskLevel: StrategyRiskLevel {
        get { .value(from: riskLevelRawValue, default: .low) }
        set { riskLevelRawValue = newValue.rawValue }
    }

    var status: StrategySimulationStatus {
        get { .value(from: statusRawValue, default: .notPaidOffWithinLimit) }
        set { statusRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        comparisonBatchID: UUID? = nil,
        name: String,
        strategyType: StrategyType,
        strategyDate: Date? = nil,
        monthlyBudget: Decimal,
        maxMonths: Int,
        isHighRisk: Bool = false,
        totalAllocatedAmount: Decimal = 0,
        totalEstimatedCost: Decimal = 0,
        estimatedInterestAmount: Decimal = 0,
        estimatedOverdueFee: Decimal = 0,
        estimatedPenaltyInterest: Decimal = 0,
        endingRemainingAmount: Decimal = 0,
        highestMonthlyPayment: Decimal = 0,
        averageMonthlyPayment: Decimal = 0,
        overdueMonthCount: Int = 0,
        highestOverdueDebtCount: Int = 0,
        estimatedPayoffMonth: Int? = nil,
        estimatedPayoffDate: Date? = nil,
        riskLevel: StrategyRiskLevel = .low,
        status: StrategySimulationStatus = .notPaidOffWithinLimit,
        featureDescription: String = "",
        recommendationReason: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.comparisonBatchID = comparisonBatchID
        self.name = name
        self.strategyTypeRawValue = strategyType.rawValue
        self.strategyDate = strategyDate
        self.monthlyBudget = monthlyBudget
        self.maxMonths = maxMonths
        self.isHighRisk = isHighRisk
        self.totalAllocatedAmount = totalAllocatedAmount
        self.totalEstimatedCost = totalEstimatedCost
        self.estimatedInterestAmount = estimatedInterestAmount
        self.estimatedOverdueFee = estimatedOverdueFee
        self.estimatedPenaltyInterest = estimatedPenaltyInterest
        self.endingRemainingAmount = endingRemainingAmount
        self.highestMonthlyPayment = highestMonthlyPayment
        self.averageMonthlyPayment = averageMonthlyPayment
        self.overdueMonthCount = overdueMonthCount
        self.highestOverdueDebtCount = highestOverdueDebtCount
        self.estimatedPayoffMonth = estimatedPayoffMonth
        self.estimatedPayoffDate = estimatedPayoffDate
        self.riskLevelRawValue = riskLevel.rawValue
        self.statusRawValue = status.rawValue
        self.featureDescription = featureDescription
        self.recommendationReason = recommendationReason
        self.createdAt = createdAt
    }
}

@Model
final class StrategyMonthSnapshot {
    var id: UUID
    var simulationID: UUID
    var monthIndex: Int
    var monthStartDate: Date?
    var monthEndDate: Date?
    var availableBudget: Decimal
    var remainingAmountBeforePayment: Decimal
    var allocatedAmount: Decimal
    var unusedBudget: Decimal
    var addedInterestAmount: Decimal
    var addedOverdueFee: Decimal
    var addedPenaltyInterest: Decimal
    var addedInstallmentAmount: Decimal
    var remainingAmountAfterPayment: Decimal
    var overdueDebtCount: Int
    var isHighRisk: Bool
    var riskNotesText: String

    var riskNotes: [String] {
        get { riskNotesText.lines }
        set { riskNotesText = newValue.joined(separator: "\n") }
    }

    init(
        id: UUID = UUID(),
        simulationID: UUID,
        monthIndex: Int,
        monthStartDate: Date? = nil,
        monthEndDate: Date? = nil,
        availableBudget: Decimal = 0,
        remainingAmountBeforePayment: Decimal,
        allocatedAmount: Decimal,
        unusedBudget: Decimal = 0,
        addedInterestAmount: Decimal = 0,
        addedOverdueFee: Decimal = 0,
        addedPenaltyInterest: Decimal = 0,
        addedInstallmentAmount: Decimal = 0,
        remainingAmountAfterPayment: Decimal,
        overdueDebtCount: Int = 0,
        isHighRisk: Bool = false,
        riskNotes: [String] = []
    ) {
        self.id = id
        self.simulationID = simulationID
        self.monthIndex = monthIndex
        self.monthStartDate = monthStartDate
        self.monthEndDate = monthEndDate
        self.availableBudget = availableBudget
        self.remainingAmountBeforePayment = remainingAmountBeforePayment
        self.allocatedAmount = allocatedAmount
        self.unusedBudget = unusedBudget
        self.addedInterestAmount = addedInterestAmount
        self.addedOverdueFee = addedOverdueFee
        self.addedPenaltyInterest = addedPenaltyInterest
        self.addedInstallmentAmount = addedInstallmentAmount
        self.remainingAmountAfterPayment = remainingAmountAfterPayment
        self.overdueDebtCount = overdueDebtCount
        self.isHighRisk = isHighRisk
        self.riskNotesText = riskNotes.joined(separator: "\n")
    }
}

@Model
final class StrategyDebtAllocation {
    var id: UUID
    var simulationID: UUID
    var monthSnapshotID: UUID
    var monthIndex: Int
    var sourceDebtID: UUID
    var debtTypeRawValue: String
    var debtName: String
    var dataSource: String
    var remainingAmountBeforePayment: Decimal
    var minimumPaymentAmount: Decimal
    var extraPaymentAmount: Decimal
    var allocatedAmount: Decimal
    var addedInterestAmount: Decimal
    var addedOverdueFee: Decimal
    var addedPenaltyInterest: Decimal
    var addedInstallmentAmount: Decimal
    var remainingAmountAfterPayment: Decimal
    var priorityRank: Int
    var costEventsText: String
    var riskEventsText: String
    var isOverdueAtMonthEnd: Bool
    var overdueDaysAtMonthEnd: Int

    var debtType: DebtType {
        get { .value(from: debtTypeRawValue, default: .loan) }
        set { debtTypeRawValue = newValue.rawValue }
    }

    var costEvents: [String] {
        get { costEventsText.lines }
        set { costEventsText = newValue.joined(separator: "\n") }
    }

    var riskEvents: [String] {
        get { riskEventsText.lines }
        set { riskEventsText = newValue.joined(separator: "\n") }
    }

    init(
        id: UUID = UUID(),
        simulationID: UUID,
        monthSnapshotID: UUID,
        monthIndex: Int = 0,
        sourceDebtID: UUID,
        debtType: DebtType,
        debtName: String,
        dataSource: String = "",
        remainingAmountBeforePayment: Decimal = 0,
        minimumPaymentAmount: Decimal,
        extraPaymentAmount: Decimal,
        allocatedAmount: Decimal,
        addedInterestAmount: Decimal = 0,
        addedOverdueFee: Decimal = 0,
        addedPenaltyInterest: Decimal = 0,
        addedInstallmentAmount: Decimal = 0,
        remainingAmountAfterPayment: Decimal,
        priorityRank: Int,
        costEvents: [String] = [],
        riskEvents: [String] = [],
        isOverdueAtMonthEnd: Bool = false,
        overdueDaysAtMonthEnd: Int = 0
    ) {
        self.id = id
        self.simulationID = simulationID
        self.monthSnapshotID = monthSnapshotID
        self.monthIndex = monthIndex
        self.sourceDebtID = sourceDebtID
        self.debtTypeRawValue = debtType.rawValue
        self.debtName = debtName
        self.dataSource = dataSource
        self.remainingAmountBeforePayment = remainingAmountBeforePayment
        self.minimumPaymentAmount = minimumPaymentAmount
        self.extraPaymentAmount = extraPaymentAmount
        self.allocatedAmount = allocatedAmount
        self.addedInterestAmount = addedInterestAmount
        self.addedOverdueFee = addedOverdueFee
        self.addedPenaltyInterest = addedPenaltyInterest
        self.addedInstallmentAmount = addedInstallmentAmount
        self.remainingAmountAfterPayment = remainingAmountAfterPayment
        self.priorityRank = priorityRank
        self.costEventsText = costEvents.joined(separator: "\n")
        self.riskEventsText = riskEvents.joined(separator: "\n")
        self.isOverdueAtMonthEnd = isOverdueAtMonthEnd
        self.overdueDaysAtMonthEnd = overdueDaysAtMonthEnd
    }
}

@Model
final class StrategyCostEvent {
    var id: UUID
    var simulationID: UUID
    var monthSnapshotID: UUID?
    var monthIndex: Int
    var debtID: UUID
    var debtTypeRawValue: String
    var debtName: String
    var eventTypeRawValue: String
    var protectionAmount: Decimal
    var uncoveredAmount: Decimal
    var estimatedCostIfUncovered: Decimal
    var realizedCost: Decimal
    var estimatedInterestAmount: Decimal
    var estimatedOverdueFee: Decimal
    var estimatedPenaltyInterest: Decimal
    var marginalCostRate: Decimal
    var dueDate: Date?
    var isRiskFlagged: Bool
    var isCovered: Bool
    var note: String

    var debtType: DebtType {
        get { .value(from: debtTypeRawValue, default: .loan) }
        set { debtTypeRawValue = newValue.rawValue }
    }

    var eventType: StrategyCostEventType {
        get { .value(from: eventTypeRawValue, default: .loanCurrentPlanProtection) }
        set { eventTypeRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        simulationID: UUID,
        monthSnapshotID: UUID? = nil,
        monthIndex: Int,
        debtID: UUID,
        debtType: DebtType,
        debtName: String,
        eventType: StrategyCostEventType,
        protectionAmount: Decimal,
        uncoveredAmount: Decimal = 0,
        estimatedCostIfUncovered: Decimal,
        realizedCost: Decimal = 0,
        estimatedInterestAmount: Decimal = 0,
        estimatedOverdueFee: Decimal = 0,
        estimatedPenaltyInterest: Decimal = 0,
        marginalCostRate: Decimal,
        dueDate: Date? = nil,
        isRiskFlagged: Bool = false,
        isCovered: Bool = false,
        note: String = ""
    ) {
        self.id = id
        self.simulationID = simulationID
        self.monthSnapshotID = monthSnapshotID
        self.monthIndex = monthIndex
        self.debtID = debtID
        self.debtTypeRawValue = debtType.rawValue
        self.debtName = debtName
        self.eventTypeRawValue = eventType.rawValue
        self.protectionAmount = protectionAmount
        self.uncoveredAmount = uncoveredAmount
        self.estimatedCostIfUncovered = estimatedCostIfUncovered
        self.realizedCost = realizedCost
        self.estimatedInterestAmount = estimatedInterestAmount
        self.estimatedOverdueFee = estimatedOverdueFee
        self.estimatedPenaltyInterest = estimatedPenaltyInterest
        self.marginalCostRate = marginalCostRate
        self.dueDate = dueDate
        self.isRiskFlagged = isRiskFlagged
        self.isCovered = isCovered
        self.note = note
    }
}

@Model
final class StrategyRiskEvent {
    var id: UUID
    var comparisonBatchID: UUID?
    var simulationID: UUID?
    var monthSnapshotID: UUID?
    var monthIndex: Int
    var debtID: UUID?
    var debtTypeRawValue: String?
    var debtName: String
    var eventTypeRawValue: String
    var riskLevelRawValue: String
    var message: String
    var dataSource: String

    var debtType: DebtType? {
        get {
            guard let debtTypeRawValue else { return nil }
            return DebtType(rawValue: debtTypeRawValue)
        }
        set { debtTypeRawValue = newValue?.rawValue }
    }

    var eventType: StrategyRiskEventType {
        get { .value(from: eventTypeRawValue, default: .internalSimulationDisclaimer) }
        set { eventTypeRawValue = newValue.rawValue }
    }

    var riskLevel: StrategyRiskLevel {
        get { .value(from: riskLevelRawValue, default: .low) }
        set { riskLevelRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        comparisonBatchID: UUID? = nil,
        simulationID: UUID? = nil,
        monthSnapshotID: UUID? = nil,
        monthIndex: Int = 0,
        debtID: UUID? = nil,
        debtType: DebtType? = nil,
        debtName: String = "",
        eventType: StrategyRiskEventType,
        riskLevel: StrategyRiskLevel,
        message: String,
        dataSource: String = ""
    ) {
        self.id = id
        self.comparisonBatchID = comparisonBatchID
        self.simulationID = simulationID
        self.monthSnapshotID = monthSnapshotID
        self.monthIndex = monthIndex
        self.debtID = debtID
        self.debtTypeRawValue = debtType?.rawValue
        self.debtName = debtName
        self.eventTypeRawValue = eventType.rawValue
        self.riskLevelRawValue = riskLevel.rawValue
        self.message = message
        self.dataSource = dataSource
    }
}

private extension String {
    var lines: [String] {
        split(separator: "\n").map(String.init).filter { $0.isEmpty == false }
    }
}
