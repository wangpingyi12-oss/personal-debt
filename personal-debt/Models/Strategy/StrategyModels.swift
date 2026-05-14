import Foundation
import SwiftData

enum StrategyMode: String, CaseIterable, Codable, Identifiable {
    case avalanche
    case snowball
    case balanced

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .avalanche: return "雪崩策略"
        case .snowball: return "雪球策略"
        case .balanced: return "均衡策略"
        }
    }
}

@Model
final class StrategySimulationSnapshot {
    @Attribute(.unique) var id: UUID
    var name: String
    var mode: String
    var monthlyBudget: Double
    var totalCost: Double
    var monthsToDebtFree: Int
    var riskWarning: String
    var dataDomain: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \StrategySimulationMonth.snapshot) var months: [StrategySimulationMonth]

    init(
        id: UUID = UUID(),
        name: String,
        mode: String,
        monthlyBudget: Double,
        totalCost: Double,
        monthsToDebtFree: Int,
        riskWarning: String,
        dataDomain: String = DataIsolationDomain.simulated.rawValue,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.monthlyBudget = monthlyBudget
        self.totalCost = totalCost
        self.monthsToDebtFree = monthsToDebtFree
        self.riskWarning = riskWarning
        self.dataDomain = dataDomain
        self.createdAt = createdAt
        self.months = []
    }
}

@Model
final class StrategySimulationMonth {
    @Attribute(.unique) var id: UUID
    var sequence: Int
    var principalPaid: Double
    var interestPaid: Double
    var overduePaid: Double
    var remainingBalance: Double
    var pressureIndex: Double
    var snapshot: StrategySimulationSnapshot?

    init(
        id: UUID = UUID(),
        sequence: Int,
        principalPaid: Double,
        interestPaid: Double,
        overduePaid: Double,
        remainingBalance: Double,
        pressureIndex: Double,
        snapshot: StrategySimulationSnapshot? = nil
    ) {
        self.id = id
        self.sequence = sequence
        self.principalPaid = principalPaid
        self.interestPaid = interestPaid
        self.overduePaid = overduePaid
        self.remainingBalance = remainingBalance
        self.pressureIndex = pressureIndex
        self.snapshot = snapshot
    }
}
