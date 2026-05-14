import Foundation

struct PersonalLendingFactSnapshot: Codable {
    let principal: Double
    let annualRate: Double
    let periods: Int
    let startDate: Date
}

enum PersonalLendingCalculator {
    static func snapshotFacts(
        principal: Double,
        annualRate: Double,
        periods: Int,
        startDate: Date
    ) -> String {
        let snapshot = PersonalLendingFactSnapshot(
            principal: principal,
            annualRate: annualRate,
            periods: periods,
            startDate: startDate
        )
        let data = (try? JSONEncoder().encode(snapshot)) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func rebuildPlan(from snapshot: String) -> [PersonalLendingPlanItem] {
        guard let data = snapshot.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(PersonalLendingFactSnapshot.self, from: data),
              decoded.periods > 0 else {
            return []
        }

        let monthlyRate = decoded.annualRate / 12.0
        let principalPerPeriod = decoded.principal / Double(decoded.periods)

        return (1...decoded.periods).map { sequence in
            let remaining = max(0, decoded.principal - principalPerPeriod * Double(sequence - 1))
            let interest = remaining * monthlyRate
            let dueDate = Calendar.current.date(byAdding: .month, value: sequence, to: decoded.startDate) ?? decoded.startDate
            return PersonalLendingPlanItem(
                sequence: sequence,
                dueDate: dueDate,
                principalDue: principalPerPeriod,
                interestDue: interest,
                totalDue: principalPerPeriod + interest
            )
        }
    }

    static func resolveStatus(for debt: PersonalLendingDebt) -> String {
        if debt.overdues.contains(where: { $0.isActive && $0.isValid }) {
            return DebtLifecycleStatus.overdue.rawValue
        }
        if debt.remainingPrincipal <= 0.01 {
            return DebtLifecycleStatus.paidOff.rawValue
        }
        return DebtLifecycleStatus.active.rawValue
    }
}
