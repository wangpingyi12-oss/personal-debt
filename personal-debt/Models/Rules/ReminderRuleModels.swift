import Foundation
import SwiftData

@Model
final class ReminderRule {
    @Attribute(.unique) var id: UUID
    var title: String
    var daysBeforeDue: Int
    var triggerAfterStatementDay: Int
    var overdueRiskThreshold: Double
    var isEnabled: Bool
    var isValid: Bool

    init(
        id: UUID = UUID(),
        title: String,
        daysBeforeDue: Int = 1,
        triggerAfterStatementDay: Int = 1,
        overdueRiskThreshold: Double = 0.2,
        isEnabled: Bool = true,
        isValid: Bool = true
    ) {
        self.id = id
        self.title = title
        self.daysBeforeDue = daysBeforeDue
        self.triggerAfterStatementDay = triggerAfterStatementDay
        self.overdueRiskThreshold = overdueRiskThreshold
        self.isEnabled = isEnabled
        self.isValid = isValid
    }
}
