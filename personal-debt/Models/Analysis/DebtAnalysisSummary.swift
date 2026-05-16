import Foundation

struct DebtAnalysisSummary: Equatable {
    var totalRemainingAmount: Decimal
    var totalPaidAmount: Decimal
    var totalInterestAmount: Decimal
    var totalOverdueFeeAmount: Decimal
    var totalPenaltyInterestAmount: Decimal
    var monthlyCashFlowAmount: Decimal
    var progress: Decimal

    static let empty = DebtAnalysisSummary(
        totalRemainingAmount: 0,
        totalPaidAmount: 0,
        totalInterestAmount: 0,
        totalOverdueFeeAmount: 0,
        totalPenaltyInterestAmount: 0,
        monthlyCashFlowAmount: 0,
        progress: 0
    )
}
