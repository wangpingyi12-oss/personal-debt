import Foundation

struct PaymentAnalyticsService {
    var roundingPolicy: MoneyRoundingPolicy

    init(roundingPolicy: MoneyRoundingPolicy = .standard) {
        self.roundingPolicy = roundingPolicy
    }

    func generate(
        creditCardDebts: [CreditCardDebt],
        creditCardPayments: [CreditCardPaymentRecord],
        loanDebts: [LoanDebt],
        loanPayments: [LoanPaymentRecord],
        personalLendingDebts: [PersonalLendingDebt],
        personalLendingPayments: [PersonalLendingPaymentRecord],
        period: AnalyticsPeriod
    ) -> PaymentAnalytics {
        let activeCreditCards = AnalyticsSupport.activeCreditCardDebts(creditCardDebts)
        let activeLoans = AnalyticsSupport.activeLoanDebts(loanDebts)
        let activePersonalLending = AnalyticsSupport.activePersonalLendingDebts(personalLendingDebts)

        let creditCardDebtIDs = Set(activeCreditCards.map(\.id))
        let loanDebtIDs = Set(activeLoans.map(\.id))
        let personalDebtIDs = Set(activePersonalLending.map(\.id))
        let names = AnalyticsSupport.debtNameMaps(
            creditCardDebts: activeCreditCards,
            loanDebts: activeLoans,
            personalLendingDebts: activePersonalLending
        )

        let validCreditCardPayments = creditCardPayments.filter {
            $0.isActive && creditCardDebtIDs.contains($0.debtID)
        }
        let validLoanPayments = loanPayments.filter {
            loanDebtIDs.contains($0.debtID)
        }
        let validPersonalPayments = personalLendingPayments.filter {
            personalDebtIDs.contains($0.debtID)
        }

        let creditCardCurrentMonth = sum(validCreditCardPayments.filter { period.contains($0.paymentDate) }.map(\.amount))
        let loanCurrentMonth = sum(validLoanPayments.filter { period.contains($0.paymentDate) }.map(\.totalAmount))
        let personalCurrentMonth = sum(validPersonalPayments.filter { period.contains($0.paymentDate) }.map(\.amount))

        let creditCardCumulative = sum(validCreditCardPayments.map(\.amount))
        let loanCumulative = sum(validLoanPayments.map(\.totalAmount))
        let personalCumulative = sum(validPersonalPayments.map(\.amount))

        let currentMonthRecordCount = validCreditCardPayments.filter { period.contains($0.paymentDate) }.count
        let loanInputCount = validLoanPayments.filter { period.contains($0.paymentDate) }.count
        let personalInputCount = validPersonalPayments.filter { period.contains($0.paymentDate) }.count

        let latestPayment = latestPayment(
            creditCardPayments: validCreditCardPayments,
            loanPayments: validLoanPayments,
            personalLendingPayments: validPersonalPayments,
            names: names
        )

        return PaymentAnalytics(
            currentMonthPaidAmount: round(creditCardCurrentMonth + loanCurrentMonth + personalCurrentMonth),
            cumulativePaidAmount: round(creditCardCumulative + loanCumulative + personalCumulative),
            creditCardCurrentMonthPaidAmount: creditCardCurrentMonth,
            loanCurrentMonthPaidAmount: loanCurrentMonth,
            personalLendingCurrentMonthPaidAmount: personalCurrentMonth,
            creditCardCumulativePaidAmount: creditCardCumulative,
            loanCumulativePaidAmount: loanCumulative,
            personalLendingCumulativePaidAmount: personalCumulative,
            currentMonthPaymentRecordCount: currentMonthRecordCount,
            currentMonthPaymentInputCount: loanInputCount + personalInputCount,
            creditCardPaymentRecordCount: currentMonthRecordCount,
            loanPaymentInputCount: loanInputCount,
            personalLendingPaymentInputCount: personalInputCount,
            latestPayment: latestPayment
        )
    }

    private func latestPayment(
        creditCardPayments: [CreditCardPaymentRecord],
        loanPayments: [LoanPaymentRecord],
        personalLendingPayments: [PersonalLendingPaymentRecord],
        names: (creditCards: [UUID: String], loans: [UUID: String], personalLending: [UUID: String])
    ) -> AnalyticsPaymentItem? {
        var items: [AnalyticsPaymentItem] = []

        items.append(contentsOf: creditCardPayments.map {
            AnalyticsPaymentItem(
                id: $0.id,
                debtID: $0.debtID,
                debtType: .creditCard,
                debtName: names.creditCards[$0.debtID] ?? "",
                paymentDate: $0.paymentDate,
                amount: round($0.amount)
            )
        })

        items.append(contentsOf: loanPayments.map {
            AnalyticsPaymentItem(
                id: $0.id,
                debtID: $0.debtID,
                debtType: .loan,
                debtName: names.loans[$0.debtID] ?? "",
                paymentDate: $0.paymentDate,
                amount: round($0.totalAmount)
            )
        })

        items.append(contentsOf: personalLendingPayments.map {
            AnalyticsPaymentItem(
                id: $0.id,
                debtID: $0.debtID,
                debtType: .personalLending,
                debtName: names.personalLending[$0.debtID] ?? "",
                paymentDate: $0.paymentDate,
                amount: round($0.amount)
            )
        })

        return items.sorted {
            if $0.paymentDate == $1.paymentDate {
                if $0.amount == $1.amount { return $0.id.uuidString < $1.id.uuidString }
                return $0.amount > $1.amount
            }
            return $0.paymentDate > $1.paymentDate
        }.first
    }

    private func sum(_ values: [Decimal]) -> Decimal {
        round(values.reduce(Decimal(0)) { $0 + AnalyticsSupport.nonNegative($1) })
    }

    private func round(_ value: Decimal) -> Decimal {
        roundingPolicy.round(AnalyticsSupport.nonNegative(value))
    }
}
