import Foundation
import SwiftData

@MainActor
final class DebtRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func addCreditCard(_ debt: CreditCardDebt) throws {
        context.insert(debt)
        try context.save()
    }

    func addLoan(_ debt: LoanDebt) throws {
        context.insert(debt)
        try context.save()
    }

    func addPersonalLending(_ debt: PersonalLendingDebt) throws {
        context.insert(debt)
        try context.save()
    }

    func markAnalyticsInvalidation() {
        // Placeholder for future analytics cache invalidation marker.
    }
}
