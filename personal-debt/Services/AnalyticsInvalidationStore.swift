import Foundation
import SwiftData

struct AnalyticsDirtyScope: OptionSet {
    let rawValue: Int

    static let debt = AnalyticsDirtyScope(rawValue: 1 << 0)
    static let payment = AnalyticsDirtyScope(rawValue: 1 << 1)
    static let overdue = AnalyticsDirtyScope(rawValue: 1 << 2)
    static let cost = AnalyticsDirtyScope(rawValue: 1 << 3)
    static let all: AnalyticsDirtyScope = [.debt, .payment, .overdue, .cost]
}

@MainActor
protocol AnalyticsInvalidating: AnyObject {
    func markAnalyticsDirty(_ scope: AnalyticsDirtyScope) throws
}

@MainActor
final class AnalyticsInvalidationStore: AnalyticsInvalidating {
    private let modelContext: ModelContext
    private let autosaves: Bool

    init(modelContext: ModelContext, autosaves: Bool = true) {
        self.modelContext = modelContext
        self.autosaves = autosaves
    }

    func markAnalyticsDirty(_ scope: AnalyticsDirtyScope) throws {
        let state = try currentState()
        if scope.contains(.debt) {
            state.isDebtAnalyticsDirty = true
        }
        if scope.contains(.payment) {
            state.isPaymentAnalyticsDirty = true
        }
        if scope.contains(.overdue) {
            state.isOverdueAnalyticsDirty = true
        }
        if scope.contains(.cost) {
            state.isCostAnalyticsDirty = true
        }
        state.updatedAt = Date()
        try saveIfNeeded()
    }

    func markAnalyticsGenerated(on date: Date) throws {
        let state = try currentState()
        state.isDebtAnalyticsDirty = false
        state.isPaymentAnalyticsDirty = false
        state.isOverdueAnalyticsDirty = false
        state.isCostAnalyticsDirty = false
        state.lastAnalyticsGeneratedDate = date
        state.updatedAt = Date()
        try saveIfNeeded()
    }

    func needsDailyGeneration(today: Date, calendar: Calendar = Calendar(identifier: .gregorian)) throws -> Bool {
        let state = try currentState()
        guard let lastAnalyticsGeneratedDate = state.lastAnalyticsGeneratedDate else {
            return true
        }
        return calendar.isDate(lastAnalyticsGeneratedDate, inSameDayAs: today) == false
    }

    func currentState() throws -> AnalyticsInvalidationState {
        let descriptor = FetchDescriptor<AnalyticsInvalidationState>()
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }

        let state = AnalyticsInvalidationState()
        modelContext.insert(state)
        try saveIfNeeded()
        return state
    }

    private func saveIfNeeded() throws {
        if autosaves {
            try modelContext.save()
        }
    }
}
