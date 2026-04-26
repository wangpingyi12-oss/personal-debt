//
//  FinanceEngine.swift
//  personal-debt
//
//  Created by Mac on 2026/4/25.
//

import Foundation

enum FinanceEngine {
    enum ValidationError: Error, LocalizedError {
        case emptyName
        case invalidPrincipal
        case invalidNominalAPR
        case invalidLoanTerm
        case invalidBillingDay
        case invalidRepaymentDay
        case invalidInstallmentConfig
        case invalidMinimumRepaymentRate
        case invalidPenaltyRate
        case invalidStatementCycles
        case missingLoanEndDate
        case invalidLoanDateRange

        var errorDescription: String? {
            switch self {
            case .emptyName:
                return "债务名称不能为空"
            case .invalidPrincipal:
                return "本金必须大于0"
            case .invalidNominalAPR:
                return "名义年化必须在0到100%之间"
            case .invalidLoanTerm:
                return "贷款期数必须在1到360之间"
            case .invalidBillingDay:
                return "账单日必须在1到31之间"
            case .invalidRepaymentDay:
                return "还款日必须在1到31之间"
            case .invalidInstallmentConfig:
                return "分期配置不合法，请检查分期本金与期数"
            case .invalidMinimumRepaymentRate:
                return "最低还款比例必须在0到100%之间，保底金额不能为负数"
            case .invalidPenaltyRate:
                return "罚息或手续费率不能为负数"
            case .invalidStatementCycles:
                return "信用卡账单周期固定为1个月"
            case .missingLoanEndDate:
                return "贷款类债务必须填写结束日期"
            case .invalidLoanDateRange:
                return "贷款结束日期不能早于开始日期"
            }
        }
    }

    struct StrategyNode {
        var debtName: String
        var principal: Double
        var overdueBalance: Double
        var monthlyRate: Double
        var minimumDue: Double
    }

    struct CreditCardPlanRow {
        var period: Int
        var statementDate: Date
        var dueDate: Date
        var principal: Double
        var statementPrincipal: Double
        var installmentPrincipal: Double
        var interest: Double
        var fee: Double
        var minimumDue: Double
        var installmentFee: Double
        var isInterestFree: Bool
    }

    struct StrategyConstraints {
        var includeMinimumDue: Bool = true
        var includeOverduePenalty: Bool = true
        var prioritizeOverdueBalances: Bool = true
        var requireFullOverdueCoverage: Bool = true
        var minimumMonthlyReserve: Double = 0
        var requireFullMinimumCoverage: Bool = true
        var maxMonths: Int = 600
    }

    struct StrategyResult {
        var totalInterest: Double
        var payoffDate: Date
        var timelineJSON: String
    }

    struct StrategyTimelinePayload: Codable {
        struct DebtAction: Codable {
            var debtName: String
            var openingBalance: Double
            var openingOverdueBalance: Double
            var interestAccrued: Double
            var overdueRequired: Double
            var overduePaid: Double
            var minimumDue: Double
            var minimumPaid: Double
            var extraPaid: Double
            var closingBalance: Double
            var closingOverdueBalance: Double
            var isTarget: Bool
        }

        struct MonthRecord: Codable {
            var monthIndex: Int
            var totalPrincipal: Double
            var paymentApplied: Double
            var interestAccrued: Double
            var overdueRequired: Double
            var overduePaid: Double
            var minimumRequired: Double
            var minimumPaid: Double
            var remainingBudget: Double
            var targetedDebtName: String?
            var isBudgetShortfall: Bool
            var notes: [String]
            var debtActions: [DebtAction]
        }

        var method: String
        var constraints: ConstraintRecord
        var completed: Bool
        var infeasibleReason: String?
        var records: [MonthRecord]
    }

    struct ConstraintRecord: Codable {
        var includeMinimumDue: Bool
        var includeOverduePenalty: Bool
        var prioritizeOverdueBalances: Bool
        var requireFullOverdueCoverage: Bool
        var minimumMonthlyReserve: Double
        var requireFullMinimumCoverage: Bool
        var maxMonths: Int
    }

    static func effectiveAPR(nominalAPR: Double, periodsPerYear: Int = 12) -> Double {
        guard nominalAPR > 0, periodsPerYear > 0 else { return 0 }
        let base = 1 + nominalAPR / Double(periodsPerYear)
        return pow(base, Double(periodsPerYear)) - 1
    }

    static func validateDebtInput(
        name: String,
        type: DebtType,
        principal: Double,
        nominalAPR: Double,
        startDate: Date? = nil,
        endDate: Date? = nil,
        loanTermMonths: Int? = nil,
        creditCardDetail: CreditCardDebtDetail? = nil
    ) throws {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.emptyName
        }
        if principal <= 0 {
            throw ValidationError.invalidPrincipal
        }
        if nominalAPR < 0 || nominalAPR > 1 {
            throw ValidationError.invalidNominalAPR
        }

        if type == .loan {
            let term = loanTermMonths ?? 0
            if term < 1 || term > 360 {
                throw ValidationError.invalidLoanTerm
            }
            guard let loanEndDate = endDate else {
                throw ValidationError.missingLoanEndDate
            }
            if let loanStartDate = startDate, loanEndDate < loanStartDate {
                throw ValidationError.invalidLoanDateRange
            }
        }

        if type == .creditCard, let detail = creditCardDetail {
            if detail.billingDay < 1 || detail.billingDay > 31 {
                throw ValidationError.invalidBillingDay
            }
            if detail.repaymentDay < 1 || detail.repaymentDay > 31 {
                throw ValidationError.invalidRepaymentDay
            }
            let hasInstallmentAmount = detail.installmentPrincipal > 0
            let hasInstallmentPeriods = detail.installmentPeriods > 0
            if hasInstallmentAmount != hasInstallmentPeriods {
                throw ValidationError.invalidInstallmentConfig
            }
            if detail.installmentPrincipal > principal || detail.installmentPeriods > 60 {
                throw ValidationError.invalidInstallmentConfig
            }
            if detail.minimumRepaymentRate < 0 || detail.minimumRepaymentRate > 1 || detail.minimumRepaymentFloor < 0 {
                throw ValidationError.invalidMinimumRepaymentRate
            }
            if detail.penaltyDailyRate < 0 || detail.installmentFeeRatePerPeriod < 0 || detail.overdueFeeFlat < 0 {
                throw ValidationError.invalidPenaltyRate
            }
            if detail.statementCycles != 1 {
                throw ValidationError.invalidStatementCycles
            }
        }
    }

    static func allocatePayment(
        amount: Double,
        overdueFee: Double,
        penaltyInterest: Double,
        interest: Double,
        principal: Double
    ) -> PaymentAllocation {
        allocatePayment(
            amount: amount,
            overdueFee: overdueFee,
            penaltyInterest: penaltyInterest,
            interest: interest,
            principal: principal,
            order: .overdueFeeFirst
        )
    }

    static func allocatePayment(
        amount: Double,
        overdueFee: Double,
        penaltyInterest: Double,
        interest: Double,
        principal: Double,
        order: PaymentAllocationOrder
    ) -> PaymentAllocation {
        var remaining = max(amount, 0)
        var appliedOverdueFee = 0.0
        var appliedPenaltyInterest = 0.0
        var appliedInterest = 0.0
        var appliedPrincipal = 0.0

        for component in order.components {
            switch component {
            case .overdueFee:
                let applied = min(remaining, max(overdueFee, 0) - appliedOverdueFee)
                appliedOverdueFee += applied
                remaining -= applied
            case .penaltyInterest:
                let applied = min(remaining, max(penaltyInterest, 0) - appliedPenaltyInterest)
                appliedPenaltyInterest += applied
                remaining -= applied
            case .interest:
                let applied = min(remaining, max(interest, 0) - appliedInterest)
                appliedInterest += applied
                remaining -= applied
            case .principal:
                let applied = min(remaining, max(principal, 0) - appliedPrincipal)
                appliedPrincipal += applied
                remaining -= applied
            }

            if remaining <= 0 { break }
        }

        if remaining > 0 {
            let extraInterest = min(remaining, max(interest, 0) - appliedInterest)
            appliedInterest += extraInterest
            remaining -= extraInterest

            let extraPrincipal = min(remaining, max(principal, 0) - appliedPrincipal)
            appliedPrincipal += extraPrincipal
        }

        return PaymentAllocation(
            overdueFee: appliedOverdueFee,
            penaltyInterest: appliedPenaltyInterest,
            interest: appliedInterest,
            principal: appliedPrincipal
        )
    }

    static func calculateCreditCardMinimumDue(
        statementPrincipal: Double,
        installmentPrincipal: Double,
        statementInterest: Double,
        statementFees: Double,
        installmentFee: Double,
        penaltyInterest: Double,
        minimumRate: Double,
        minimumFloor: Double,
        includesFees: Bool,
        includesPenalty: Bool,
        includesInterest: Bool,
        includesInstallmentPrincipal: Bool,
        includesInstallmentFee: Bool
    ) -> Double {
        let principal = max(statementPrincipal, 0)
        let installment = includesInstallmentPrincipal ? max(installmentPrincipal, 0) : 0
        let interest = includesInterest ? max(statementInterest, 0) : 0
        let fees = includesFees ? max(statementFees, 0) : 0
        let installmentFees = includesInstallmentFee ? max(installmentFee, 0) : 0
        let penalty = includesPenalty ? max(penaltyInterest, 0) : 0

        let base = principal + installment + interest + fees + installmentFees + penalty
        guard base > 0 else { return 0 }

        let ratioDue = base * max(minimumRate, 0)
        return roundCurrency(min(base, max(ratioDue, max(minimumFloor, 0))))
    }

    static func calculateCreditCardInstallmentFee(
        installmentPrincipal: Double,
        feeRatePerPeriod: Double,
        periods: Int,
        periodIndex: Int,
        mode: CreditCardInstallmentFeeMode
    ) -> Double {
        let principal = max(installmentPrincipal, 0)
        let rate = max(feeRatePerPeriod, 0)
        let periodCount = max(periods, 0)
        guard principal > 0, rate > 0, periodCount > 0 else { return 0 }

        switch mode {
        case .perPeriod:
            return periodIndex <= periodCount ? roundCurrency(principal * rate) : 0
        case .upfront:
            return periodIndex == 1 ? roundCurrency(principal * rate * Double(periodCount)) : 0
        }
    }

    static func calculateCreditCardRevolvingInterest(
        principal: Double,
        annualRate: Double,
        from startDate: Date,
        to endDate: Date
    ) -> Double {
        let balance = max(principal, 0)
        let rate = max(annualRate, 0)
        guard balance > 0, rate > 0, endDate > startDate else { return 0 }

        let days = max(Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0, 0)
        guard days > 0 else { return 0 }
        return roundCurrency(balance * rate / 365 * Double(days))
    }

    static func generateCreditCardPlan(
        principal: Double,
        annualRate: Double,
        cycles: Int,
        startDate: Date,
        detail: CreditCardDebtDetail,
        kind: CreditCardPlanKind? = nil
    ) -> [CreditCardPlanRow] {
        let resolvedKind: CreditCardPlanKind = {
            if let kind { return kind }
            return detail.installmentPeriods > 0 && detail.installmentPrincipal > 0 ? .installment : .statement
        }()
        let effectiveCycles = resolvedCycles(for: detail, requestedCycles: cycles, kind: resolvedKind)
        guard principal > 0, effectiveCycles > 0 else { return [] }

        switch resolvedKind {
        case .statement:
            let context = statementContext(referenceDate: startDate, billingDay: detail.billingDay, repaymentDay: detail.repaymentDay)
            let statementPrincipal = roundCurrency(max(principal, 0))
            let minimumDue = calculateCreditCardMinimumDue(
                statementPrincipal: statementPrincipal,
                installmentPrincipal: 0,
                statementInterest: 0,
                statementFees: 0,
                installmentFee: 0,
                penaltyInterest: 0,
                minimumRate: detail.minimumRepaymentRate,
                minimumFloor: detail.minimumRepaymentFloor,
                includesFees: detail.minimumIncludesFees,
                includesPenalty: detail.minimumIncludesPenalty,
                includesInterest: detail.minimumIncludesInterest,
                includesInstallmentPrincipal: detail.minimumIncludesInstallmentPrincipal,
                includesInstallmentFee: detail.minimumIncludesInstallmentFee
            )
            return [
                CreditCardPlanRow(
                    period: 1,
                    statementDate: context.statementDate,
                    dueDate: context.dueDate,
                    principal: statementPrincipal,
                    statementPrincipal: statementPrincipal,
                    installmentPrincipal: 0,
                    interest: 0,
                    fee: 0,
                    minimumDue: minimumDue,
                    installmentFee: 0,
                    isInterestFree: true
                )
            ]

        case .installment:
            let installmentPeriods = max(detail.installmentPeriods, effectiveCycles, 1)
            let totalInstallmentPrincipal = min(max(detail.installmentPrincipal, 0) > 0 ? detail.installmentPrincipal : principal, principal)
            let revolvingPrincipal = max(principal - totalInstallmentPrincipal, 0)
            var remainingInstallmentPrincipal = roundCurrency(totalInstallmentPrincipal)
            var remainingRevolvingPrincipal = roundCurrency(revolvingPrincipal)
            var rows: [CreditCardPlanRow] = []

            for period in 1...installmentPeriods {
                let monthAnchor = Calendar.current.date(byAdding: .month, value: period - 1, to: startDate) ?? startDate
                let context = statementContext(referenceDate: monthAnchor, billingDay: detail.billingDay, repaymentDay: detail.repaymentDay)
                let periodsRemaining = installmentPeriods - period + 1
                let installmentPrincipalDue = roundCurrency(
                    period == installmentPeriods
                        ? remainingInstallmentPrincipal
                        : min(remainingInstallmentPrincipal, roundCurrency(remainingInstallmentPrincipal / Double(periodsRemaining)))
                )
                let statementPrincipalDue = period == 1 ? remainingRevolvingPrincipal : 0
                let installmentFee = calculateCreditCardInstallmentFee(
                    installmentPrincipal: totalInstallmentPrincipal,
                    feeRatePerPeriod: detail.installmentFeeRatePerPeriod,
                    periods: installmentPeriods,
                    periodIndex: period,
                    mode: detail.installmentFeeMode
                )
                let principalDue = roundCurrency(installmentPrincipalDue + statementPrincipalDue)
                let fullDue = roundCurrency(principalDue + installmentFee)

                rows.append(
                    CreditCardPlanRow(
                        period: period,
                        statementDate: context.statementDate,
                        dueDate: context.dueDate,
                        principal: principalDue,
                        statementPrincipal: statementPrincipalDue,
                        installmentPrincipal: installmentPrincipalDue,
                        interest: 0,
                        fee: installmentFee,
                        minimumDue: fullDue,
                        installmentFee: installmentFee,
                        isInterestFree: true
                    )
                )

                remainingInstallmentPrincipal = max(roundCurrency(remainingInstallmentPrincipal - installmentPrincipalDue), 0)
                remainingRevolvingPrincipal = 0
            }

            return rows
        }
    }

    static func generateLoanPlan(
        principal: Double,
        annualRate: Double,
        termMonths: Int,
        method: LoanRepaymentMethod,
        startDate: Date
    ) -> [(period: Int, dueDate: Date, principal: Double, interest: Double)] {
        guard principal > 0, termMonths > 0 else { return [] }

        let calendar = Calendar.current
        let monthlyRate = annualRate / 12
        var plan: [(Int, Date, Double, Double)] = []

        switch method {
        case .equalInstallment:
            let payment: Double
            if monthlyRate == 0 {
                payment = principal / Double(termMonths)
            } else {
                let factor = pow(1 + monthlyRate, Double(termMonths))
                payment = principal * monthlyRate * factor / (factor - 1)
            }

            var remaining = principal
            for i in 1...termMonths {
                let interest = remaining * monthlyRate
                let principalPart = min(remaining, payment - interest)
                remaining -= principalPart
                let dueDate = calendar.date(byAdding: .month, value: i, to: startDate) ?? startDate
                plan.append((i, dueDate, max(principalPart, 0), max(interest, 0)))
            }

        case .equalPrincipal:
            let monthlyPrincipal = principal / Double(termMonths)
            var remaining = principal
            for i in 1...termMonths {
                let interest = remaining * monthlyRate
                let principalPart = min(remaining, monthlyPrincipal)
                remaining -= principalPart
                let dueDate = calendar.date(byAdding: .month, value: i, to: startDate) ?? startDate
                plan.append((i, dueDate, max(principalPart, 0), max(interest, 0)))
            }

        case .interestOnly:
            for i in 1...termMonths {
                let interest = principal * monthlyRate
                let principalPart = i == termMonths ? principal : 0
                let dueDate = calendar.date(byAdding: .month, value: i, to: startDate) ?? startDate
                plan.append((i, dueDate, max(principalPart, 0), max(interest, 0)))
            }

        case .bullet:
            let totalInterest = principal * annualRate * Double(termMonths) / 12
            let dueDate = calendar.date(byAdding: .month, value: termMonths, to: startDate) ?? startDate
            plan.append((1, dueDate, principal, totalInterest))
        }

        return plan
    }

    static func calculateOverduePenalty(
        baseAmount: Double,
        dailyRate: Double,
        startDate: Date,
        endDate: Date = Date(),
        mode: OverduePenaltyMode = .simple
    ) -> Double {
        let days = max(Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0, 0)
        let principal = max(baseAmount, 0)
        let rate = max(dailyRate, 0)
        guard principal > 0, rate > 0, days > 0 else { return 0 }

        switch mode {
        case .simple:
            return roundCurrency(principal * rate * Double(days))
        case .compound:
            let factor = pow(1 + rate, Double(days)) - 1
            return roundCurrency(principal * factor)
        }
    }

    static func compareStrategies(debts: [Debt], monthlyBudget: Double, startDate: Date = Date()) -> [StrategyMethod: (totalInterest: Double, payoffDate: Date)] {
        let detailed = compareStrategiesDetailed(debts: debts, monthlyBudget: monthlyBudget, startDate: startDate)
        return detailed.reduce(into: [:]) { partial, entry in
            partial[entry.key] = (entry.value.totalInterest, entry.value.payoffDate)
        }
    }

    static func compareStrategiesDetailed(
        debts: [Debt],
        monthlyBudget: Double,
        startDate: Date = Date(),
        constraints: StrategyConstraints = StrategyConstraints()
    ) -> [StrategyMethod: StrategyResult] {
        guard monthlyBudget > 0 else { return [:] }

        var snapshots: [StrategyMethod: StrategyResult] = [:]
        for method in StrategyMethod.allCases {
            snapshots[method] = runStrategy(
                debts: debts,
                monthlyBudget: monthlyBudget,
                method: method,
                startDate: startDate,
                constraints: constraints
            )
        }
        return snapshots
    }

    static func generateStrategyDetailed(
        debts: [Debt],
        monthlyBudget: Double,
        method: StrategyMethod,
        startDate: Date = Date(),
        constraints: StrategyConstraints = StrategyConstraints()
    ) -> StrategyResult? {
        guard monthlyBudget > 0 else { return nil }
        return runStrategy(
            debts: debts,
            monthlyBudget: monthlyBudget,
            method: method,
            startDate: startDate,
            constraints: constraints
        )
    }

    static func decodeStrategyTimeline(from json: String) -> StrategyTimelinePayload? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(StrategyTimelinePayload.self, from: data)
    }

    private static func runStrategy(
        debts: [Debt],
        monthlyBudget: Double,
        method: StrategyMethod,
        startDate: Date,
        constraints: StrategyConstraints
    ) -> StrategyResult {
        var nodes: [StrategyNode] = debts
            .filter { $0.status != .settled }
            .map {
                let rate = max($0.effectiveAPR > 0 ? $0.effectiveAPR : $0.nominalAPR, 0)
                let unresolvedOverdue = constraints.includeOverduePenalty
                    ? $0.overdueEvents
                        .filter { !$0.isResolved }
                        .reduce(0) { $0 + $1.penaltyInterest + $1.overdueFee + $1.overdueInterest }
                    : 0
                let minDue = constraints.includeMinimumDue
                    ? max(
                        $0.repaymentPlans
                            .filter { $0.status != .paid }
                            .sorted(by: { $0.dueDate < $1.dueDate })
                            .first?.minimumDue ?? 0,
                        0
                    )
                    : 0

                return StrategyNode(
                    debtName: $0.name,
                    principal: max($0.outstandingPrincipal, 0),
                    overdueBalance: max(unresolvedOverdue, 0),
                    monthlyRate: rate / 12,
                    minimumDue: minDue
                )
            }
            .filter { $0.principal > 0 || $0.overdueBalance > 0 }

        guard !nodes.isEmpty else {
            return StrategyResult(totalInterest: 0, payoffDate: startDate, timelineJSON: "{}")
        }

        var totalInterest = 0.0
        var month = 0
        var timelineRows: [StrategyTimelinePayload.MonthRecord] = []
        let reserveBudget = max(constraints.minimumMonthlyReserve, 0)
        var completionReason: String?
        var completed = true

        if monthlyBudget <= reserveBudget {
            completed = false
            completionReason = "月预算不足以覆盖预留金额，无法生成可执行策略。"
        }

        while completed && nodes.contains(where: { $0.principal > 0.01 || $0.overdueBalance > 0.01 }) && month < max(constraints.maxMonths, 1) {
            month += 1
            var monthInterest = 0.0
            var monthPayment = 0.0
            var monthOverdueRequired = 0.0
            var monthOverduePaid = 0.0
            var monthMinimumRequired = 0.0
            var monthMinimumPaid = 0.0
            var monthNotes: [String] = []
            let openingBalances: [Double] = nodes.map(\.principal)
            let openingOverdues: [Double] = nodes.map(\.overdueBalance)
            var interestByNode = Array(repeating: 0.0, count: nodes.count)
            var overdueRequiredByNode = Array(repeating: 0.0, count: nodes.count)
            var overduePaidByNode = Array(repeating: 0.0, count: nodes.count)
            var minimumDueByNode = Array(repeating: 0.0, count: nodes.count)
            var minimumPaidByNode = Array(repeating: 0.0, count: nodes.count)
            var extraPaidByNode = Array(repeating: 0.0, count: nodes.count)
            var targetedDebtName: String?
            var isBudgetShortfall = false

            for i in nodes.indices where nodes[i].principal > 0 {
                let interest = nodes[i].principal * nodes[i].monthlyRate
                nodes[i].principal += interest
                totalInterest += interest
                monthInterest += interest
                interestByNode[i] = interest
            }

            var remainingBudget = max(monthlyBudget - reserveBudget, 0)

            if constraints.includeOverduePenalty && constraints.prioritizeOverdueBalances {
                monthOverdueRequired = nodes.reduce(0) { partial, node in
                    partial + max(node.overdueBalance, 0)
                }
                if constraints.requireFullOverdueCoverage && remainingBudget + 0.0001 < monthOverdueRequired {
                    isBudgetShortfall = true
                    completed = false
                    completionReason = "第\(month)个月预算不足，无法覆盖逾期费用与罚息。"
                    monthNotes.append("预算不足：逾期成本要求为 ¥\(roundCurrency(monthOverdueRequired))，可用预算仅为 ¥\(roundCurrency(remainingBudget))。")
                }

                for i in nodes.indices where nodes[i].overdueBalance > 0.01 && remainingBudget > 0 {
                    let requiredOverdue = nodes[i].overdueBalance
                    overdueRequiredByNode[i] = requiredOverdue
                    let cappedOverdue = constraints.requireFullOverdueCoverage ? requiredOverdue : min(requiredOverdue, remainingBudget)
                    let appliedOverdue = min(cappedOverdue, remainingBudget)
                    nodes[i].overdueBalance = max(nodes[i].overdueBalance - appliedOverdue, 0)
                    remainingBudget -= appliedOverdue
                    monthPayment += appliedOverdue
                    monthOverduePaid += appliedOverdue
                    overduePaidByNode[i] = appliedOverdue
                }
            }

            if constraints.includeMinimumDue {
                monthMinimumRequired = nodes.reduce(0) { partial, node in
                    partial + (node.principal > 0.01 ? min(node.principal, node.minimumDue) : 0)
                }
                if constraints.requireFullMinimumCoverage && remainingBudget + 0.0001 < monthMinimumRequired {
                    isBudgetShortfall = true
                    completed = false
                    completionReason = "第\(month)个月预算不足，无法覆盖最低还款要求。"
                    monthNotes.append("预算不足：最低还款要求为 ¥\(roundCurrency(monthMinimumRequired))，可用预算仅为 ¥\(roundCurrency(remainingBudget))。")
                }
                for i in nodes.indices where nodes[i].principal > 0.01 && remainingBudget > 0 {
                    let requiredMinimum = min(nodes[i].principal, nodes[i].minimumDue)
                    minimumDueByNode[i] = requiredMinimum
                    let cappedMinimum = constraints.requireFullMinimumCoverage ? requiredMinimum : min(requiredMinimum, remainingBudget)
                    let appliedMinimum = min(cappedMinimum, remainingBudget)
                    nodes[i].principal -= appliedMinimum
                    remainingBudget -= appliedMinimum
                    monthPayment += appliedMinimum
                    monthMinimumPaid += appliedMinimum
                    minimumPaidByNode[i] = appliedMinimum
                }
            }

            if completed {
                if let targetIndex = pickTarget(nodes: nodes, method: method) {
                    targetedDebtName = nodes[targetIndex].debtName
                    let payment = min(nodes[targetIndex].principal, max(remainingBudget, 0))
                    nodes[targetIndex].principal -= payment
                    monthPayment += payment
                    extraPaidByNode[targetIndex] = payment
                    if let targetedDebtName {
                        monthNotes.append("额外预算优先分配给 \(targetedDebtName)。")
                    }
                    remainingBudget = max(remainingBudget - payment, 0)
                } else if monthOverduePaid > 0 {
                    monthNotes.append("本月预算全部用于清理逾期成本。")
                }
            }

            let debtActions = nodes.indices.map { index in
                StrategyTimelinePayload.DebtAction(
                    debtName: nodes[index].debtName,
                    openingBalance: roundCurrency(openingBalances[index]),
                    openingOverdueBalance: roundCurrency(openingOverdues[index]),
                    interestAccrued: roundCurrency(interestByNode[index]),
                    overdueRequired: roundCurrency(overdueRequiredByNode[index]),
                    overduePaid: roundCurrency(overduePaidByNode[index]),
                    minimumDue: roundCurrency(minimumDueByNode[index]),
                    minimumPaid: roundCurrency(minimumPaidByNode[index]),
                    extraPaid: roundCurrency(extraPaidByNode[index]),
                    closingBalance: roundCurrency(max(nodes[index].principal, 0)),
                    closingOverdueBalance: roundCurrency(max(nodes[index].overdueBalance, 0)),
                    isTarget: nodes[index].debtName == targetedDebtName
                )
            }

            timelineRows.append(
                StrategyTimelinePayload.MonthRecord(
                    monthIndex: month,
                    totalPrincipal: roundCurrency(nodes.reduce(0) { $0 + max($1.principal, 0) + max($1.overdueBalance, 0) }),
                    paymentApplied: roundCurrency(monthPayment),
                    interestAccrued: roundCurrency(monthInterest),
                    overdueRequired: roundCurrency(monthOverdueRequired),
                    overduePaid: roundCurrency(monthOverduePaid),
                    minimumRequired: roundCurrency(monthMinimumRequired),
                    minimumPaid: roundCurrency(monthMinimumPaid),
                    remainingBudget: roundCurrency(remainingBudget),
                    targetedDebtName: targetedDebtName,
                    isBudgetShortfall: isBudgetShortfall,
                    notes: monthNotes,
                    debtActions: debtActions
                )
            )
        }

        if completed && nodes.contains(where: { $0.principal > 0.01 || $0.overdueBalance > 0.01 }) {
            completed = false
            completionReason = "达到最大测算月数后仍未结清全部债务。"
        }

        let payoffDate = Calendar.current.date(byAdding: .month, value: month, to: startDate) ?? startDate
        let timeline = StrategyTimelinePayload(
            method: method.rawValue,
            constraints: ConstraintRecord(
                includeMinimumDue: constraints.includeMinimumDue,
                includeOverduePenalty: constraints.includeOverduePenalty,
                prioritizeOverdueBalances: constraints.prioritizeOverdueBalances,
                requireFullOverdueCoverage: constraints.requireFullOverdueCoverage,
                minimumMonthlyReserve: reserveBudget,
                requireFullMinimumCoverage: constraints.requireFullMinimumCoverage,
                maxMonths: constraints.maxMonths
            ),
            completed: completed,
            infeasibleReason: completionReason,
            records: timelineRows
        )
        let timelineData = (try? JSONEncoder().encode(timeline)) ?? Data("{}".utf8)
        let timelineJSON = String(data: timelineData, encoding: .utf8) ?? "{}"

        return StrategyResult(
            totalInterest: max(totalInterest, 0),
            payoffDate: payoffDate,
            timelineJSON: timelineJSON
        )
    }

    private static func pickTarget(nodes: [StrategyNode], method: StrategyMethod) -> Int? {
        switch method {
        case .avalanche:
            return nodes.enumerated()
                .filter { $0.element.principal > 0.01 }
                .max(by: { $0.element.monthlyRate < $1.element.monthlyRate })?
                .offset

        case .snowball:
            return nodes.enumerated()
                .filter { $0.element.principal > 0.01 }
                .min(by: { $0.element.principal < $1.element.principal })?
                .offset

        case .balanced:
            let maxPrincipal = max(nodes.map(\.principal).max() ?? 0, 0.0001)
            let maxRate = max(nodes.map(\.monthlyRate).max() ?? 0, 0.0001)
            return nodes.enumerated()
                .filter { $0.element.principal > 0.01 }
                .max(by: {
                    let left = 0.5 * ($0.element.monthlyRate / maxRate) + 0.5 * ($0.element.principal / maxPrincipal)
                    let right = 0.5 * ($1.element.monthlyRate / maxRate) + 0.5 * ($1.element.principal / maxPrincipal)
                    return left < right
                })?
                .offset
        }
    }

    private static func resolvedCycles(for detail: CreditCardDebtDetail, requestedCycles: Int, kind: CreditCardPlanKind) -> Int {
        switch kind {
        case .statement:
            return 1
        case .installment:
            return max(requestedCycles, detail.installmentPeriods, 1)
        }
    }

    private static func statementContext(referenceDate: Date, billingDay: Int, repaymentDay: Int) -> (statementDate: Date, dueDate: Date) {
        let statementDate = mostRecentMonthlyDate(anchor: referenceDate, day: billingDay)
        let dueDate = nextMonthlyDate(after: statementDate, day: repaymentDay)
        return (statementDate, dueDate)
    }

    private static func mostRecentMonthlyDate(anchor: Date, day: Int) -> Date {
        let currentMonthDate = dateInMonth(anchor: anchor, day: day)
        if currentMonthDate <= anchor {
            return currentMonthDate
        }

        let previousMonthAnchor = Calendar.current.date(byAdding: .month, value: -1, to: anchor) ?? anchor
        return dateInMonth(anchor: previousMonthAnchor, day: day)
    }

    private static func nextMonthlyDate(after date: Date, day: Int) -> Date {
        let currentMonthDate = dateInMonth(anchor: date, day: day)
        if currentMonthDate > date {
            return currentMonthDate
        }

        let nextMonthAnchor = Calendar.current.date(byAdding: .month, value: 1, to: date) ?? date
        return dateInMonth(anchor: nextMonthAnchor, day: day)
    }

    private static func dateInMonth(anchor: Date, day: Int) -> Date {
        let calendar = Calendar.current
        let normalizedDay = max(day, 1)
        var components = calendar.dateComponents([.year, .month], from: anchor)
        let maxDay = calendar.range(of: .day, in: .month, for: anchor)?.count ?? 28
        components.day = min(normalizedDay, maxDay)
        return calendar.date(from: components) ?? anchor
    }

    private static func roundCurrency(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
