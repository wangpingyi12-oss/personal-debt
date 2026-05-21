import Foundation
import SwiftData

@MainActor
enum DefaultCalculationRuleSeeder {
    static func ensureSeeded(in modelContext: ModelContext) throws {
        let creditCardRules = try modelContext.fetch(FetchDescriptor<CreditCardCalculationRule>())
        if creditCardRules.contains(where: { $0.debtID == nil }) == false {
            modelContext.insert(CreditCardCalculationRule.builtInDefault())
        }

        let loanRules = try modelContext.fetch(FetchDescriptor<LoanCalculationRule>())
        if loanRules.contains(where: { $0.debtID == nil }) == false {
            modelContext.insert(LoanCalculationRule.builtInDefault())
        }

        try modelContext.save()
    }
}
