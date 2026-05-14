import SwiftUI
import SwiftData

@main
struct personal_debtApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            CreditCardDebt.self,
            CreditCardBill.self,
            CreditCardTransaction.self,
            CreditCardOverdueRecord.self,
            LoanDebt.self,
            LoanInstallment.self,
            LoanTransaction.self,
            LoanOverdueRecord.self,
            PersonalLendingDebt.self,
            PersonalLendingPlanItem.self,
            PersonalLendingTransaction.self,
            PersonalLendingAllocation.self,
            StrategySimulationSnapshot.self,
            StrategySimulationMonth.self,
            ReminderRule.self
        ])
    }
}
