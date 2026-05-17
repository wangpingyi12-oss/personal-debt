import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Query(sort: \AppUserSettings.createdAt) private var settings: [AppUserSettings]

    var body: some View {
        Group {
            if let activeSettings = settings.first {
                DebtUXRootView(settings: activeSettings)
                    .environmentObject(subscriptionStore)
                    .environment(\.locale, activeSettings.preferredLocale)
            } else {
                ProgressView()
                    .task {
                        ensureSettings()
                    }
            }
        }
        .task {
            ensureSettings()
            await subscriptionStore.start()
        }
        .alert(item: $subscriptionStore.message) { message in
            Alert(
                title: Text(message.title),
                message: Text(message.detail),
                dismissButton: .default(Text("common.ok"))
            )
        }
    }

    private func ensureSettings() {
        let shouldSkipOnboarding = ProcessInfo.processInfo.arguments.contains("-UITestSkipOnboarding")
        if let existing = settings.first {
            if shouldSkipOnboarding, existing.onboardingCompleted == false {
                existing.onboardingCompleted = true
                existing.updatedAt = Date()
                try? modelContext.save()
            }
            return
        }
        modelContext.insert(AppUserSettings(onboardingCompleted: shouldSkipOnboarding))
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Could not create app settings: \(error)")
        }
    }
}

#Preview {
    let schema = Schema([
        AppUserSettings.self,
        CreditCardDebt.self,
        CreditCardCalculationRule.self,
        CreditCardStatement.self,
        CreditCardStatementBreakdown.self,
        CreditCardRepaymentPlan.self,
        CreditCardPaymentRecord.self,
        CreditCardOverdueRecord.self,
        CreditCardInstallmentPlan.self,
        LoanDebt.self,
        LoanRepaymentPlan.self,
        LoanPaymentRecord.self,
        LoanPaymentAllocationDetail.self,
        LoanOverdueRecord.self,
        LoanCalculationRule.self,
        PersonalLendingDebt.self,
        PersonalLendingPlan.self,
        PersonalLendingPaymentRecord.self,
        PersonalLendingAllocationDetail.self,
        PersonalLendingOverdueRecord.self,
        StrategyComparisonBatch.self,
        StrategySimulation.self,
        StrategyMonthSnapshot.self,
        StrategyDebtAllocation.self,
        StrategyCostEvent.self,
        StrategyRiskEvent.self,
        DebtAnalyticsSnapshot.self,
        PaymentAnalyticsSnapshot.self,
        OverdueAnalyticsSnapshot.self,
        CostAnalyticsSnapshot.self,
        AnalyticsInvalidationState.self,
    ])
    let container = try! ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
    )
    container.mainContext.insert(AppUserSettings(onboardingCompleted: true, monthlyRepaymentBudget: 1000))

    return ContentView()
        .environmentObject(
            SubscriptionStore.preview(
                accessState: .trialActive(
                    expiresAt: Date().addingTimeInterval(9 * 86_400),
                    daysRemaining: 9
                )
            )
        )
        .modelContainer(container)
}
