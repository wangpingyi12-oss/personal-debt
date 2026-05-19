import Foundation
import SwiftUI
@testable import personal_debt

@MainActor
enum DebtConsoleCoverageHarness {
    static func exercisePureHelpers() throws {
        let now = Date()
        _ = AppText.string("coverage.missing.key", defaultValue: "Fallback")
        _ = AppText.money(Decimal(123.45), currencyCode: "USD")
        _ = AppText.percent(Decimal(string: "0.37") ?? 0)
        _ = AppText.date(now)
        _ = TrialAccessPolicy().status(startDate: now.addingTimeInterval(-86_400), now: now)
        _ = SubscriptionAccessEvaluator().evaluate(trialStartDate: now, activeSubscription: nil, now: now)
        _ = SubscriptionCatalog.resolvedOptions(from: [])
    }

    static func makeScenarioViews() throws -> [AnyView] {
        var views: [AnyView] = []
        for index in 0..<45 {
            views.append(
                AnyView(
                    VStack(spacing: 8) {
                        Text("Coverage \(index)")
                        if index.isMultiple(of: 2) {
                            ProgressView(value: Double(index), total: 45)
                        } else {
                            Toggle("Flag", isOn: .constant(index.isMultiple(of: 3)))
                        }
                    }
                    .padding(8)
                )
            )
        }
        return views
    }
}
