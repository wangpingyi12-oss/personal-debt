import Foundation

enum StrategySimulationError: Error, Equatable {
    case invalidMonthlyBudget
    case invalidMaxMonths
    case noDebtToSimulate
}

struct StrategySimulationRequest: Equatable {
    var strategyDate: Date
    var monthlyBudget: Decimal
    var maxMonths: Int
    var generatedAt: Date

    init(
        strategyDate: Date = Date(),
        monthlyBudget: Decimal,
        maxMonths: Int = 360,
        generatedAt: Date = Date()
    ) {
        self.strategyDate = strategyDate
        self.monthlyBudget = monthlyBudget
        self.maxMonths = maxMonths
        self.generatedAt = generatedAt
    }
}

struct StrategyPlanSnapshot: Equatable, Identifiable {
    var id: UUID
    var periodIndex: Int
    var dueDate: Date
    var remainingAmount: Decimal
    var remainingPrincipal: Decimal
    var remainingInterest: Decimal
    var dataSource: String
    var isOverdue: Bool
    var overdueDays: Int

    init(
        id: UUID = UUID(),
        periodIndex: Int,
        dueDate: Date,
        remainingAmount: Decimal,
        remainingPrincipal: Decimal = 0,
        remainingInterest: Decimal = 0,
        dataSource: String = "",
        isOverdue: Bool = false,
        overdueDays: Int = 0
    ) {
        self.id = id
        self.periodIndex = periodIndex
        self.dueDate = dueDate
        self.remainingAmount = remainingAmount
        self.remainingPrincipal = remainingPrincipal
        self.remainingInterest = remainingInterest
        self.dataSource = dataSource
        self.isOverdue = isOverdue
        self.overdueDays = overdueDays
    }
}

struct StrategyDebtSnapshot: Equatable, Identifiable {
    var id: UUID
    var debtType: DebtType
    var name: String
    var remainingAmount: Decimal
    var minimumPaymentAmount: Decimal
    var costRate: Decimal
    var riskWeight: Decimal
    var dueDate: Date?
    var dataSource: String
    var isFallbackData: Bool
    var isOverdue: Bool
    var overdueDays: Int
    var plans: [StrategyPlanSnapshot]
    var userRiskNotes: [String]
    var revolvingInterestEnabled: Bool
    var revolvingDailyRate: Decimal
    var overdueFeeRate: Decimal
    var minimumOverdueFee: Decimal
    var fixedOverdueFee: Decimal?
    var penaltyDailyRate: Decimal
    var penaltyBaseUsesStatementAmount: Bool
    var annualInterestRate: Decimal
    var loanPenaltyRateMultiplier: Decimal
    var fixedPenaltyDailyRate: Decimal?
    var loanOverdueFeeMode: LoanOverdueFeeMode
    var loanFixedOverdueFee: Decimal?
    var loanOverdueFeeRate: Decimal?
    var loanOverdueBaseType: LoanOverdueBaseType

    init(
        id: UUID = UUID(),
        debtType: DebtType,
        name: String,
        remainingAmount: Decimal,
        minimumPaymentAmount: Decimal,
        costRate: Decimal = 0,
        riskWeight: Decimal = 1,
        dueDate: Date? = nil,
        dataSource: String = "",
        isFallbackData: Bool = false,
        isOverdue: Bool = false,
        overdueDays: Int = 0,
        plans: [StrategyPlanSnapshot] = [],
        userRiskNotes: [String] = [],
        revolvingInterestEnabled: Bool = true,
        revolvingDailyRate: Decimal = Decimal(string: "0.0005") ?? 0,
        overdueFeeRate: Decimal = Decimal(string: "0.005") ?? 0,
        minimumOverdueFee: Decimal = 25,
        fixedOverdueFee: Decimal? = nil,
        penaltyDailyRate: Decimal = Decimal(string: "0.0005") ?? 0,
        penaltyBaseUsesStatementAmount: Bool = false,
        annualInterestRate: Decimal = 0,
        loanPenaltyRateMultiplier: Decimal = Decimal(string: "1.5") ?? 1.5,
        fixedPenaltyDailyRate: Decimal? = nil,
        loanOverdueFeeMode: LoanOverdueFeeMode = .zero,
        loanFixedOverdueFee: Decimal? = nil,
        loanOverdueFeeRate: Decimal? = nil,
        loanOverdueBaseType: LoanOverdueBaseType = .currentUnpaidPrincipal
    ) {
        self.id = id
        self.debtType = debtType
        self.name = name
        self.remainingAmount = remainingAmount
        self.minimumPaymentAmount = minimumPaymentAmount
        self.costRate = costRate
        self.riskWeight = riskWeight
        self.dueDate = dueDate
        self.dataSource = dataSource
        self.isFallbackData = isFallbackData
        self.isOverdue = isOverdue
        self.overdueDays = overdueDays
        self.plans = plans
        self.userRiskNotes = userRiskNotes
        self.revolvingInterestEnabled = revolvingInterestEnabled
        self.revolvingDailyRate = revolvingDailyRate
        self.overdueFeeRate = overdueFeeRate
        self.minimumOverdueFee = minimumOverdueFee
        self.fixedOverdueFee = fixedOverdueFee
        self.penaltyDailyRate = penaltyDailyRate
        self.penaltyBaseUsesStatementAmount = penaltyBaseUsesStatementAmount
        self.annualInterestRate = annualInterestRate
        self.loanPenaltyRateMultiplier = loanPenaltyRateMultiplier
        self.fixedPenaltyDailyRate = fixedPenaltyDailyRate
        self.loanOverdueFeeMode = loanOverdueFeeMode
        self.loanFixedOverdueFee = loanFixedOverdueFee
        self.loanOverdueFeeRate = loanOverdueFeeRate
        self.loanOverdueBaseType = loanOverdueBaseType
    }
}

struct StrategySummary: Equatable {
    var strategyType: StrategyType
    var payoffMonth: Int?
    var payoffDate: Date?
    var totalPayment: Decimal
    var totalEstimatedCost: Decimal
    var estimatedInterest: Decimal
    var estimatedOverdueFee: Decimal
    var estimatedPenaltyInterest: Decimal
    var endingRemainingAmount: Decimal
    var highestMonthlyPayment: Decimal
    var averageMonthlyPayment: Decimal
    var overdueMonthCount: Int
    var highestOverdueDebtCount: Int
    var riskLevel: StrategyRiskLevel
    var featureDescription: String
}

struct StrategySimulationOutput {
    var simulation: StrategySimulation
    var monthSnapshots: [StrategyMonthSnapshot]
    var allocations: [StrategyDebtAllocation]
    var costEvents: [StrategyCostEvent]
    var riskEvents: [StrategyRiskEvent]

    var summary: StrategySummary {
        StrategySummary(
            strategyType: simulation.strategyType,
            payoffMonth: simulation.estimatedPayoffMonth,
            payoffDate: simulation.estimatedPayoffDate,
            totalPayment: simulation.totalAllocatedAmount,
            totalEstimatedCost: simulation.totalEstimatedCost,
            estimatedInterest: simulation.estimatedInterestAmount,
            estimatedOverdueFee: simulation.estimatedOverdueFee,
            estimatedPenaltyInterest: simulation.estimatedPenaltyInterest,
            endingRemainingAmount: simulation.endingRemainingAmount,
            highestMonthlyPayment: simulation.highestMonthlyPayment,
            averageMonthlyPayment: simulation.averageMonthlyPayment,
            overdueMonthCount: simulation.overdueMonthCount,
            highestOverdueDebtCount: simulation.highestOverdueDebtCount,
            riskLevel: simulation.riskLevel,
            featureDescription: simulation.featureDescription
        )
    }
}

struct StrategyComparisonResult {
    var comparisonBatch: StrategyComparisonBatch
    var simulations: [StrategySimulationOutput]
    var riskEvents: [StrategyRiskEvent]

    var summaries: [StrategySummary] {
        simulations.map(\.summary)
    }

    var recommendedSimulation: StrategySimulationOutput? {
        guard let strategyType = comparisonBatch.recommendedStrategy else { return nil }
        return simulations.first { $0.simulation.strategyType == strategyType }
    }
}

struct StrategySimulationEngine {
    var roundingPolicy: MoneyRoundingPolicy
    var datePolicy: DateCalculationPolicy

    init(
        roundingPolicy: MoneyRoundingPolicy = .standard,
        datePolicy: DateCalculationPolicy = .standard
    ) {
        self.roundingPolicy = roundingPolicy
        self.datePolicy = datePolicy
    }

    func generateComparison(
        request: StrategySimulationRequest,
        debts: [StrategyDebtSnapshot]
    ) throws -> StrategyComparisonResult {
        try validate(request: request)
        let activeDebts = normalizedDebts(debts)
        guard activeDebts.isEmpty == false else {
            throw StrategySimulationError.noDebtToSimulate
        }

        let comparisonBatch = StrategyComparisonBatch(
            strategyDate: datePolicy.startOfDay(request.strategyDate),
            generatedAt: request.generatedAt,
            monthlyBudget: roundingPolicy.round(request.monthlyBudget),
            maxMonths: request.maxMonths
        )

        let simulations = StrategyType.allCases.map {
            simulate(
                name: displayName(for: $0),
                strategyType: $0,
                request: request,
                debts: activeDebts,
                comparisonBatchID: comparisonBatch.id
            )
        }

        let recommendation = recommendation(for: simulations)
        comparisonBatch.recommendedStrategy = recommendation.strategyType
        comparisonBatch.recommendationReason = recommendation.reason
        comparisonBatch.globalRiskNotes = globalRiskNotes(
            for: simulations,
            debts: activeDebts,
            recommendationReason: recommendation.reason
        )

        let globalRiskEvents = comparisonBatch.globalRiskNotes.map {
            StrategyRiskEvent(
                comparisonBatchID: comparisonBatch.id,
                eventType: .internalSimulationDisclaimer,
                riskLevel: .medium,
                message: $0
            )
        }

        for output in simulations {
            output.simulation.recommendationReason = output.simulation.strategyType == recommendation.strategyType
                ? recommendation.reason
                : ""
        }

        return StrategyComparisonResult(
            comparisonBatch: comparisonBatch,
            simulations: simulations,
            riskEvents: globalRiskEvents
        )
    }

    func generateSimulation(
        name: String,
        strategyType: StrategyType,
        monthlyBudget: Decimal,
        debts: [StrategyDebtSnapshot],
        maxMonths: Int = 360,
        createdAt: Date = Date()
    ) -> StrategySimulationOutput {
        let safeBudget = maxDecimal(monthlyBudget, 0)
        let safeMonths = min(max(maxMonths, 1), 360)
        let request = StrategySimulationRequest(
            strategyDate: createdAt,
            monthlyBudget: safeBudget,
            maxMonths: safeMonths,
            generatedAt: createdAt
        )
        return simulate(
            name: name,
            strategyType: strategyType,
            request: request,
            debts: normalizedDebts(debts),
            comparisonBatchID: nil
        )
    }

    private func validate(request: StrategySimulationRequest) throws {
        guard request.monthlyBudget >= 0 else {
            throw StrategySimulationError.invalidMonthlyBudget
        }
        guard (1...360).contains(request.maxMonths) else {
            throw StrategySimulationError.invalidMaxMonths
        }
    }

    private func normalizedDebts(_ debts: [StrategyDebtSnapshot]) -> [StrategyDebtSnapshot] {
        debts.compactMap { debt in
            let remaining = roundingPolicy.round(maxDecimal(debt.remainingAmount, 0))
            guard remaining > 0 else { return nil }
            var normalized = debt
            normalized.remainingAmount = remaining
            normalized.minimumPaymentAmount = roundingPolicy.round(maxDecimal(debt.minimumPaymentAmount, 0))
            normalized.costRate = maxDecimal(debt.costRate, 0)
            normalized.riskWeight = maxDecimal(debt.riskWeight, 0)
            normalized.plans = debt.plans
                .filter { $0.remainingAmount > 0 }
                .map {
                    StrategyPlanSnapshot(
                        id: $0.id,
                        periodIndex: $0.periodIndex,
                        dueDate: $0.dueDate,
                        remainingAmount: roundingPolicy.round(maxDecimal($0.remainingAmount, 0)),
                        remainingPrincipal: roundingPolicy.round(maxDecimal($0.remainingPrincipal, 0)),
                        remainingInterest: roundingPolicy.round(maxDecimal($0.remainingInterest, 0)),
                        dataSource: $0.dataSource,
                        isOverdue: $0.isOverdue,
                        overdueDays: max($0.overdueDays, 0)
                    )
                }
            return normalized
        }
    }

    private func simulate(
        name: String,
        strategyType: StrategyType,
        request: StrategySimulationRequest,
        debts: [StrategyDebtSnapshot],
        comparisonBatchID: UUID?
    ) -> StrategySimulationOutput {
        let simulation = StrategySimulation(
            comparisonBatchID: comparisonBatchID,
            name: name,
            strategyType: strategyType,
            strategyDate: request.strategyDate,
            monthlyBudget: roundingPolicy.round(maxDecimal(request.monthlyBudget, 0)),
            maxMonths: request.maxMonths,
            featureDescription: featureDescription(for: strategyType),
            createdAt: request.generatedAt
        )

        var states = debts.map { DebtState(snapshot: $0, roundingPolicy: roundingPolicy) }
        var monthSnapshots: [StrategyMonthSnapshot] = []
        var allocations: [StrategyDebtAllocation] = []
        var allCostEvents: [StrategyCostEvent] = []
        var allRiskEvents = staticRiskEvents(
            comparisonBatchID: comparisonBatchID,
            simulationID: simulation.id,
            strategyType: strategyType,
            debts: debts
        )

        var monthIndex = 1
        var completedPayoffDate: Date?

        while totalBalance(states) > 0 && monthIndex <= request.maxMonths {
            let period = monthPeriod(monthIndex: monthIndex, strategyDate: request.strategyDate)
            let beginningBalances = Dictionary(uniqueKeysWithValues: states.map { ($0.id, $0.balance) })
            let remainingBefore = totalBalance(states)
            let eventDrafts = makeCostEvents(
                for: states,
                monthIndex: monthIndex,
                period: period
            )
            let orderedDebtIDs = debtOrder(
                strategyType: strategyType,
                states: states,
                events: eventDrafts
            )

            let allocationResult = allocate(
                strategyType: strategyType,
                budget: roundingPolicy.round(maxDecimal(request.monthlyBudget, 0)),
                states: &states,
                events: eventDrafts,
                orderedDebtIDs: orderedDebtIDs
            )

            let evaluatedEvents = evaluate(
                eventDrafts: eventDrafts,
                allocationByDebt: allocationResult.allocatedByDebt
            )
            let realizedCostsByDebt = applyCosts(evaluatedEvents, to: &states)
            advanceOverdueState(for: &states, monthEndDate: period.endDate)

            let monthRiskEvents = makeMonthRiskEvents(
                comparisonBatchID: comparisonBatchID,
                simulationID: simulation.id,
                monthIndex: monthIndex,
                eventResults: evaluatedEvents,
                states: states,
                monthlyBudget: request.monthlyBudget
            )
            let riskNotes = monthRiskEvents.map(\.message)
            let remainingAfter = totalBalance(states)
            let overdueDebtCount = states.filter { $0.balance > 0 && $0.isOverdue(at: period.endDate) }.count

            let monthSnapshot = StrategyMonthSnapshot(
                simulationID: simulation.id,
                monthIndex: monthIndex,
                monthStartDate: period.startDate,
                monthEndDate: period.endDate,
                availableBudget: roundingPolicy.round(maxDecimal(request.monthlyBudget, 0)),
                remainingAmountBeforePayment: remainingBefore,
                allocatedAmount: allocationResult.totalAllocated,
                unusedBudget: allocationResult.unusedBudget,
                addedInterestAmount: evaluatedEvents.totalInterest,
                addedOverdueFee: evaluatedEvents.totalOverdueFee,
                addedPenaltyInterest: evaluatedEvents.totalPenaltyInterest,
                addedInstallmentAmount: 0,
                remainingAmountAfterPayment: remainingAfter,
                overdueDebtCount: overdueDebtCount,
                isHighRisk: riskNotes.isEmpty == false,
                riskNotes: riskNotes
            )

            let persistedCostEvents = evaluatedEvents.events.map {
                $0.makeModel(simulationID: simulation.id, monthSnapshotID: monthSnapshot.id)
            }
            let persistedMonthRiskEvents = monthRiskEvents.map {
                $0.with(monthSnapshotID: monthSnapshot.id).makeModel()
            }

            monthSnapshots.append(monthSnapshot)
            allCostEvents.append(contentsOf: persistedCostEvents)
            allRiskEvents.append(contentsOf: persistedMonthRiskEvents)

            allocations.append(
                contentsOf: makeAllocations(
                    simulationID: simulation.id,
                    monthSnapshotID: monthSnapshot.id,
                    monthIndex: monthIndex,
                    states: states,
                    beginningBalances: beginningBalances,
                    allocationResult: allocationResult,
                    eventResults: evaluatedEvents,
                    costByDebt: realizedCostsByDebt,
                    riskEvents: persistedMonthRiskEvents,
                    orderedDebtIDs: orderedDebtIDs
                )
            )

            if remainingAfter == 0 {
                completedPayoffDate = period.endDate
                break
            }
            monthIndex += 1
        }

        let totalAllocated = roundingPolicy.round(monthSnapshots.reduce(Decimal(0)) { $0 + $1.allocatedAmount })
        let endingRemaining = roundingPolicy.round(totalBalance(states))
        let completed = endingRemaining == 0
        let status: StrategySimulationStatus
        if request.monthlyBudget == 0 && completed == false {
            status = .cannotProgress
        } else if completed {
            status = .completed
        } else {
            status = .notPaidOffWithinLimit
        }

        simulation.totalAllocatedAmount = totalAllocated
        simulation.totalEstimatedCost = roundingPolicy.round(allCostEvents.reduce(Decimal(0)) { $0 + $1.realizedCost })
        simulation.estimatedInterestAmount = roundingPolicy.round(allCostEvents.reduce(Decimal(0)) { $0 + $1.estimatedInterestAmount })
        simulation.estimatedOverdueFee = roundingPolicy.round(allCostEvents.reduce(Decimal(0)) { $0 + $1.estimatedOverdueFee })
        simulation.estimatedPenaltyInterest = roundingPolicy.round(allCostEvents.reduce(Decimal(0)) { $0 + $1.estimatedPenaltyInterest })
        simulation.endingRemainingAmount = endingRemaining
        simulation.highestMonthlyPayment = roundingPolicy.round(monthSnapshots.map(\.allocatedAmount).max() ?? 0)
        simulation.averageMonthlyPayment = monthSnapshots.isEmpty
            ? 0
            : roundingPolicy.round(totalAllocated / Decimal(monthSnapshots.count))
        simulation.overdueMonthCount = monthSnapshots.filter { $0.overdueDebtCount > 0 }.count
        simulation.highestOverdueDebtCount = monthSnapshots.map(\.overdueDebtCount).max() ?? 0
        simulation.estimatedPayoffMonth = completed ? monthSnapshots.count : nil
        simulation.estimatedPayoffDate = completedPayoffDate
        simulation.status = status
        simulation.riskLevel = riskLevel(
            status: status,
            endingRemaining: endingRemaining,
            overdueMonthCount: simulation.overdueMonthCount,
            highestOverdueDebtCount: simulation.highestOverdueDebtCount,
            debts: debts
        )
        simulation.isHighRisk = simulation.riskLevel.rank >= StrategyRiskLevel.high.rank

        if completed == false {
            let riskEvent = RiskEventDraft(
                comparisonBatchID: comparisonBatchID,
                simulationID: simulation.id,
                monthIndex: request.maxMonths,
                debtID: nil,
                debtType: nil,
                debtName: "",
                eventType: status == .cannotProgress ? .zeroBudgetCannotProgress : .cannotPayoffWithinSimulation,
                riskLevel: status == .cannotProgress ? .critical : .high,
                message: status == .cannotProgress
                    ? "Monthly budget is zero, so the simulation cannot produce an effective repayment allocation."
                    : "This strategy does not fully pay off all simulated debts within the maximum simulation window.",
                dataSource: ""
            ).makeModel()
            allRiskEvents.append(riskEvent)
        }

        return StrategySimulationOutput(
            simulation: simulation,
            monthSnapshots: monthSnapshots,
            allocations: allocations,
            costEvents: allCostEvents,
            riskEvents: allRiskEvents
        )
    }

    private func allocate(
        strategyType: StrategyType,
        budget: Decimal,
        states: inout [DebtState],
        events: [CostEventDraft],
        orderedDebtIDs: [UUID]
    ) -> AllocationResult {
        guard budget > 0 else {
            return AllocationResult(totalAllocated: 0, unusedBudget: 0, allocatedByDebt: [:], protectionAllocatedByDebt: [:], allocationOrder: [])
        }

        var budgetLeft = budget
        var allocatedByDebt: [UUID: Decimal] = [:]
        var protectionAllocatedByDebt: [UUID: Decimal] = [:]
        var allocationOrder: [UUID] = []

        func pay(_ amount: Decimal, debtID: UUID, isProtection: Bool) {
            guard amount > 0, let index = states.firstIndex(where: { $0.id == debtID }) else { return }
            let paid = states[index].applyPayment(amount, roundingPolicy: roundingPolicy)
            guard paid > 0 else { return }
            budgetLeft = roundingPolicy.round(maxDecimal(budgetLeft - paid, 0))
            allocatedByDebt[debtID, default: 0] = roundingPolicy.round((allocatedByDebt[debtID] ?? 0) + paid)
            if isProtection {
                protectionAllocatedByDebt[debtID, default: 0] = roundingPolicy.round((protectionAllocatedByDebt[debtID] ?? 0) + paid)
            }
            if allocationOrder.contains(debtID) == false {
                allocationOrder.append(debtID)
            }
        }

        switch strategyType {
        case .avalanche:
            var projectedProtectionByDebt: [UUID: Decimal] = [:]
            for event in events.sorted(by: costEventSort) where budgetLeft > 0 {
                let existing = projectedProtectionByDebt[event.debtID] ?? 0
                let uncoveredProtection = roundingPolicy.round(maxDecimal(event.protectionAmount - existing, 0))
                let allocation = minDecimal(budgetLeft, uncoveredProtection)
                pay(allocation, debtID: event.debtID, isProtection: true)
                projectedProtectionByDebt[event.debtID, default: 0] = roundingPolicy.round(existing + allocation)
            }
            for debtID in orderedDebtIDs where budgetLeft > 0 {
                pay(budgetLeft, debtID: debtID, isProtection: false)
            }
        case .snowball:
            for debtID in orderedDebtIDs where budgetLeft > 0 {
                pay(budgetLeft, debtID: debtID, isProtection: false)
            }
        case .balanced:
            distributeProportionally(budgetLeft: &budgetLeft, states: &states, allocatedByDebt: &allocatedByDebt, allocationOrder: &allocationOrder)
        }

        let totalAllocated = roundingPolicy.round(allocatedByDebt.values.reduce(Decimal(0), +))
        return AllocationResult(
            totalAllocated: totalAllocated,
            unusedBudget: roundingPolicy.round(maxDecimal(budget - totalAllocated, 0)),
            allocatedByDebt: allocatedByDebt,
            protectionAllocatedByDebt: protectionAllocatedByDebt,
            allocationOrder: allocationOrder
        )
    }

    private func distributeProportionally(
        budgetLeft: inout Decimal,
        states: inout [DebtState],
        allocatedByDebt: inout [UUID: Decimal],
        allocationOrder: inout [UUID]
    ) {
        while budgetLeft > 0 {
            let activeIndices = states.indices.filter { states[$0].balance > 0 }
            let totalRemaining = activeIndices.reduce(Decimal(0)) { $0 + states[$1].balance }
            guard totalRemaining > 0 else { return }

            let budgetAtStart = budgetLeft
            var distributedThisPass = Decimal(0)

            for (position, index) in activeIndices.enumerated() where budgetLeft > 0 {
                let balance = states[index].balance
                let proportional = position == activeIndices.count - 1
                    ? budgetLeft
                    : roundingPolicy.round(budgetAtStart * balance / totalRemaining)
                let payment = minDecimal(minDecimal(proportional, balance), budgetLeft)
                let paid = states[index].applyPayment(payment, roundingPolicy: roundingPolicy)
                guard paid > 0 else { continue }
                budgetLeft = roundingPolicy.round(maxDecimal(budgetLeft - paid, 0))
                distributedThisPass = roundingPolicy.round(distributedThisPass + paid)
                let debtID = states[index].id
                allocatedByDebt[debtID, default: 0] = roundingPolicy.round((allocatedByDebt[debtID] ?? 0) + paid)
                if allocationOrder.contains(debtID) == false {
                    allocationOrder.append(debtID)
                }
            }

            if distributedThisPass == 0 {
                return
            }
        }
    }

    private func makeCostEvents(
        for states: [DebtState],
        monthIndex: Int,
        period: MonthPeriod
    ) -> [CostEventDraft] {
        states.flatMap { state in
            guard state.balance > 0 else { return [CostEventDraft]() }
            switch state.debtType {
            case .creditCard:
                return creditCardCostEvents(for: state, monthIndex: monthIndex, period: period)
            case .loan:
                return loanCostEvents(for: state, monthIndex: monthIndex, period: period)
            case .personalLending:
                return personalLendingCostEvents(for: state, monthIndex: monthIndex, period: period)
            }
        }
    }

    private func creditCardCostEvents(
        for state: DebtState,
        monthIndex: Int,
        period: MonthPeriod
    ) -> [CostEventDraft] {
        let balance = state.balance
        let snapshot = state.snapshot
        let days = Decimal(max(period.dayCount, 1))
        let overdueFee = snapshot.fixedOverdueFee ?? roundingPolicy.round(maxDecimal(balance * snapshot.overdueFeeRate, snapshot.minimumOverdueFee))
        let penaltyBase = snapshot.penaltyBaseUsesStatementAmount ? snapshot.remainingAmount : balance
        let penaltyInterest = roundingPolicy.round(maxDecimal(penaltyBase, 0) * snapshot.penaltyDailyRate * days)
        let revolvingInterest = snapshot.revolvingInterestEnabled
            ? roundingPolicy.round(balance * snapshot.revolvingDailyRate * days)
            : 0

        var events: [CostEventDraft] = []
        let minimumProtection = minDecimal(balance, snapshot.minimumPaymentAmount)
        if minimumProtection > 0 {
            events.append(
                CostEventDraft(
                    monthIndex: monthIndex,
                    debtID: state.id,
                    debtType: state.debtType,
                    debtName: state.name,
                    eventType: .creditCardMinimumPaymentProtection,
                    protectionAmount: minimumProtection,
                    estimatedOverdueFee: overdueFee,
                    estimatedPenaltyInterest: penaltyInterest,
                    dueDate: snapshot.dueDate,
                    note: "Protects the credit card minimum payment path."
                )
            )
        }

        if revolvingInterest > 0 {
            events.append(
                CostEventDraft(
                    monthIndex: monthIndex,
                    debtID: state.id,
                    debtType: state.debtType,
                    debtName: state.name,
                    eventType: .creditCardRevolvingInterestProtection,
                    protectionAmount: balance,
                    estimatedInterestAmount: revolvingInterest,
                    dueDate: snapshot.dueDate,
                    note: "Protects against estimated revolving interest if the statement is not fully paid."
                )
            )
        }

        if state.isOverdue(at: period.startDate), overdueFee + penaltyInterest > 0 {
            events.append(
                CostEventDraft(
                    monthIndex: monthIndex,
                    debtID: state.id,
                    debtType: state.debtType,
                    debtName: state.name,
                    eventType: .creditCardExistingOverduePenalty,
                    protectionAmount: balance,
                    estimatedOverdueFee: overdueFee,
                    estimatedPenaltyInterest: penaltyInterest,
                    dueDate: snapshot.dueDate,
                    note: "Existing overdue credit card balance may continue to accrue fees or penalty interest."
                )
            )
        }

        return events
    }

    private func loanCostEvents(
        for state: DebtState,
        monthIndex: Int,
        period: MonthPeriod
    ) -> [CostEventDraft] {
        var events: [CostEventDraft] = []
        for plan in state.plans where plan.remainingAmount > 0 {
            let isCurrentMonthDue = plan.dueDate >= period.startDate && plan.dueDate <= period.endDate
            let isAlreadyOverdue = plan.dueDate < period.startDate || plan.isOverdue
            guard isCurrentMonthDue || isAlreadyOverdue else { continue }

            let days: Int
            if isAlreadyOverdue {
                days = max(period.dayCount, 1)
            } else {
                days = max(datePolicy.daysBetween(plan.dueDate, period.endDate) + 1, 1)
            }
            let components = loanCostComponents(for: state, plan: plan, days: days)
            let eventType: StrategyCostEventType = isAlreadyOverdue ? .loanExistingOverduePenalty : .loanCurrentPlanProtection
            events.append(
                CostEventDraft(
                    monthIndex: monthIndex,
                    debtID: state.id,
                    debtType: state.debtType,
                    debtName: state.name,
                    eventType: eventType,
                    protectionAmount: minDecimal(plan.remainingAmount, state.balance),
                    estimatedOverdueFee: components.overdueFee,
                    estimatedPenaltyInterest: components.penaltyInterest,
                    dueDate: plan.dueDate,
                    note: isAlreadyOverdue
                        ? "Existing overdue loan plan may continue to accrue penalty interest."
                        : "Current loan plan due this month may become overdue if not covered."
                )
            )
        }
        return events
    }

    private func loanCostComponents(for state: DebtState, plan: PlanState, days: Int) -> (overdueFee: Decimal, penaltyInterest: Decimal) {
        let snapshot = state.snapshot
        let principalBase = plan.remainingPrincipal > 0 ? plan.remainingPrincipal : plan.remainingAmount
        let base = snapshot.loanOverdueBaseType == .currentUnpaidPrincipal ? principalBase : plan.remainingAmount
        let overdueFee: Decimal
        switch snapshot.loanOverdueFeeMode {
        case .zero, .disabled:
            overdueFee = 0
        case .fixed:
            overdueFee = roundingPolicy.round(maxDecimal(snapshot.loanFixedOverdueFee ?? 0, 0))
        case .percentage:
            overdueFee = roundingPolicy.round(base * maxDecimal(snapshot.loanOverdueFeeRate ?? 0, 0))
        }

        let dailyRate = snapshot.fixedPenaltyDailyRate ?? (snapshot.annualInterestRate / Decimal(365) * snapshot.loanPenaltyRateMultiplier)
        let penaltyInterest = roundingPolicy.round(maxDecimal(base, 0) * maxDecimal(dailyRate, 0) * Decimal(max(days, 0)))
        return (overdueFee, penaltyInterest)
    }

    private func personalLendingCostEvents(
        for state: DebtState,
        monthIndex: Int,
        period: MonthPeriod
    ) -> [CostEventDraft] {
        if state.plans.isEmpty {
            guard let dueDate = state.snapshot.dueDate, dueDate <= period.endDate else { return [] }
            return [
                CostEventDraft(
                    monthIndex: monthIndex,
                    debtID: state.id,
                    debtType: state.debtType,
                    debtName: state.name,
                    eventType: .personalLendingMaturity,
                    protectionAmount: state.balance,
                    dueDate: dueDate,
                    note: "Personal lending has no default financial penalty in the first version, but maturity risk is shown."
                )
            ]
        }

        return state.plans
            .filter { $0.remainingAmount > 0 && $0.dueDate <= period.endDate }
            .map {
                CostEventDraft(
                    monthIndex: monthIndex,
                    debtID: state.id,
                    debtType: state.debtType,
                    debtName: state.name,
                    eventType: .personalLendingDuePlan,
                    protectionAmount: minDecimal($0.remainingAmount, state.balance),
                    dueDate: $0.dueDate,
                    note: "Personal lending plan due this month has no default financial penalty, but it is surfaced as risk."
                )
            }
    }

    private func evaluate(
        eventDrafts: [CostEventDraft],
        allocationByDebt: [UUID: Decimal]
    ) -> EventEvaluation {
        var results: [CostEventResult] = []
        var appliedProtectionByDebt: [UUID: Decimal] = [:]

        for event in eventDrafts {
            let allocatedToDebt = allocationByDebt[event.debtID] ?? 0
            let alreadyApplied = appliedProtectionByDebt[event.debtID] ?? 0
            let coverageForEvent = maxDecimal(allocatedToDebt - alreadyApplied, 0)
            let coveredAmount = minDecimal(event.protectionAmount, coverageForEvent)
            let uncoveredAmount = roundingPolicy.round(maxDecimal(event.protectionAmount - coveredAmount, 0))
            let uncoveredRatio = event.protectionAmount > 0 ? uncoveredAmount / event.protectionAmount : 0
            let realizedInterest = roundingPolicy.round(event.estimatedInterestAmount * uncoveredRatio)
            let realizedOverdueFee = roundingPolicy.round(event.estimatedOverdueFee * uncoveredRatio)
            let realizedPenalty = roundingPolicy.round(event.estimatedPenaltyInterest * uncoveredRatio)

            appliedProtectionByDebt[event.debtID, default: 0] = roundingPolicy.round(alreadyApplied + coveredAmount)
            results.append(
                CostEventResult(
                    draft: event,
                    uncoveredAmount: uncoveredAmount,
                    realizedInterestAmount: realizedInterest,
                    realizedOverdueFee: realizedOverdueFee,
                    realizedPenaltyInterest: realizedPenalty
                )
            )
        }

        return EventEvaluation(events: results, roundingPolicy: roundingPolicy)
    }

    private func applyCosts(_ evaluation: EventEvaluation, to states: inout [DebtState]) -> [UUID: CostComponents] {
        var costsByDebt: [UUID: CostComponents] = [:]
        for event in evaluation.events {
            let totalCost = event.realizedCost
            guard totalCost > 0, let index = states.firstIndex(where: { $0.id == event.debtID }) else { continue }
            states[index].balance = roundingPolicy.round(states[index].balance + totalCost)
            states[index].extraCostBalance = roundingPolicy.round(states[index].extraCostBalance + totalCost)
            costsByDebt[event.debtID, default: .zero].add(event, roundingPolicy: roundingPolicy)
        }
        return costsByDebt
    }

    private func makeAllocations(
        simulationID: UUID,
        monthSnapshotID: UUID,
        monthIndex: Int,
        states: [DebtState],
        beginningBalances: [UUID: Decimal],
        allocationResult: AllocationResult,
        eventResults: EventEvaluation,
        costByDebt: [UUID: CostComponents],
        riskEvents: [StrategyRiskEvent],
        orderedDebtIDs: [UUID]
    ) -> [StrategyDebtAllocation] {
        let eventMessagesByDebt = Dictionary(grouping: eventResults.events, by: \.debtID)
        let riskMessagesByDebt = Dictionary(grouping: riskEvents.filter { $0.debtID != nil }, by: { $0.debtID ?? UUID() })
        let allocationIDs = allocationResult.allocationOrder
        let debtIDsWithCosts = costByDebt.keys.filter { allocationIDs.contains($0) == false }
        let debtIDs = allocationIDs + debtIDsWithCosts

        return debtIDs.compactMap { debtID in
            guard let state = states.first(where: { $0.id == debtID }) else { return nil }
            let allocated = allocationResult.allocatedByDebt[debtID] ?? 0
            let components = costByDebt[debtID] ?? .zero
            let protectionAllocated = allocationResult.protectionAllocatedByDebt[debtID] ?? 0
            let extraAllocated = roundingPolicy.round(maxDecimal(allocated - protectionAllocated, 0))
            let costEvents = (eventMessagesByDebt[debtID] ?? []).map { event in
                "\(event.draft.eventType.rawValue): uncovered \(event.uncoveredAmount), realized cost \(event.realizedCost)"
            }
            let riskMessages = (riskMessagesByDebt[debtID] ?? []).map(\.message)

            return StrategyDebtAllocation(
                simulationID: simulationID,
                monthSnapshotID: monthSnapshotID,
                monthIndex: monthIndex,
                sourceDebtID: debtID,
                debtType: state.debtType,
                debtName: state.name,
                dataSource: state.snapshot.dataSource,
                remainingAmountBeforePayment: beginningBalances[debtID] ?? 0,
                minimumPaymentAmount: protectionAllocated,
                extraPaymentAmount: extraAllocated,
                allocatedAmount: allocated,
                addedInterestAmount: components.interest,
                addedOverdueFee: components.overdueFee,
                addedPenaltyInterest: components.penaltyInterest,
                addedInstallmentAmount: 0,
                remainingAmountAfterPayment: state.balance,
                priorityRank: (orderedDebtIDs.firstIndex(of: debtID) ?? 0) + 1,
                costEvents: costEvents,
                riskEvents: riskMessages,
                isOverdueAtMonthEnd: state.currentOverdue,
                overdueDaysAtMonthEnd: state.currentOverdueDays
            )
        }
    }

    private func makeMonthRiskEvents(
        comparisonBatchID: UUID?,
        simulationID: UUID,
        monthIndex: Int,
        eventResults: EventEvaluation,
        states: [DebtState],
        monthlyBudget: Decimal
    ) -> [RiskEventDraft] {
        var riskEvents: [RiskEventDraft] = []

        if monthlyBudget == 0 {
            riskEvents.append(
                RiskEventDraft(
                    comparisonBatchID: comparisonBatchID,
                    simulationID: simulationID,
                    monthIndex: monthIndex,
                    debtID: nil,
                    debtType: nil,
                    debtName: "",
                    eventType: .zeroBudgetCannotProgress,
                    riskLevel: .critical,
                    message: "Monthly budget is zero, so no effective repayment allocation can be generated.",
                    dataSource: ""
                )
            )
        }

        for event in eventResults.events where event.uncoveredAmount > 0 {
            let riskLevel: StrategyRiskLevel = event.realizedCost > 0 ? .high : .medium
            riskEvents.append(
                RiskEventDraft(
                    comparisonBatchID: comparisonBatchID,
                    simulationID: simulationID,
                    monthIndex: monthIndex,
                    debtID: event.debtID,
                    debtType: event.debtType,
                    debtName: event.debtName,
                    eventType: .budgetCannotCoverProtection,
                    riskLevel: riskLevel,
                    message: "\(event.debtName) has an uncovered protection amount of \(event.uncoveredAmount). Extra cost or overdue risk may increase.",
                    dataSource: states.first { $0.id == event.debtID }?.snapshot.dataSource ?? ""
                )
            )
        }

        for state in states where state.balance > 0 && state.currentOverdue {
            riskEvents.append(
                RiskEventDraft(
                    comparisonBatchID: comparisonBatchID,
                    simulationID: simulationID,
                    monthIndex: monthIndex,
                    debtID: state.id,
                    debtType: state.debtType,
                    debtName: state.name,
                    eventType: .overdueMayContinue,
                    riskLevel: .high,
                    message: "\(state.name) remains overdue at the end of this simulated month.",
                    dataSource: state.snapshot.dataSource
                )
            )
        }

        return riskEvents
    }

    private func staticRiskEvents(
        comparisonBatchID: UUID?,
        simulationID: UUID,
        strategyType: StrategyType,
        debts: [StrategyDebtSnapshot]
    ) -> [StrategyRiskEvent] {
        var drafts: [RiskEventDraft] = [
            RiskEventDraft(
                comparisonBatchID: comparisonBatchID,
                simulationID: simulationID,
                debtID: nil,
                debtType: nil,
                debtName: "",
                eventType: .internalSimulationDisclaimer,
                riskLevel: .low,
                message: StrategyComparisonBatch.defaultDisclaimer,
                dataSource: ""
            )
        ]

        if strategyType == .snowball {
            drafts.append(
                RiskEventDraft(
                    comparisonBatchID: comparisonBatchID,
                    simulationID: simulationID,
                    debtID: nil,
                    debtType: nil,
                    debtName: "",
                    eventType: .internalSimulationDisclaimer,
                    riskLevel: .medium,
                    message: "Snowball prioritizes reducing debt count and may not prioritize the highest-cost debt first.",
                    dataSource: ""
                )
            )
        }

        if strategyType == .balanced {
            drafts.append(
                RiskEventDraft(
                    comparisonBatchID: comparisonBatchID,
                    simulationID: simulationID,
                    debtID: nil,
                    debtType: nil,
                    debtName: "",
                    eventType: .internalSimulationDisclaimer,
                    riskLevel: .medium,
                    message: "Balanced repayment lowers multiple debts together and may not prioritize the highest-cost debt first.",
                    dataSource: ""
                )
            )
        }

        for debt in debts {
            if debt.isFallbackData {
                drafts.append(
                    RiskEventDraft(
                        comparisonBatchID: comparisonBatchID,
                        simulationID: simulationID,
                        debtID: debt.id,
                        debtType: debt.debtType,
                        debtName: debt.name,
                        eventType: .fallbackDataUsed,
                        riskLevel: .medium,
                        message: "\(debt.name) uses fallback or system-estimated data. Confirmed creditor amounts should take precedence.",
                        dataSource: debt.dataSource
                    )
                )
            }

            if debt.debtType == .personalLending {
                drafts.append(
                    RiskEventDraft(
                        comparisonBatchID: comparisonBatchID,
                        simulationID: simulationID,
                        debtID: debt.id,
                        debtType: debt.debtType,
                        debtName: debt.name,
                        eventType: .informalPersonalLending,
                        riskLevel: .medium,
                        message: "\(debt.name) may involve informal agreement or relationship pressure. The strategy only simulates amounts.",
                        dataSource: debt.dataSource
                    )
                )
            }

            for note in debt.userRiskNotes {
                drafts.append(
                    RiskEventDraft(
                        comparisonBatchID: comparisonBatchID,
                        simulationID: simulationID,
                        debtID: debt.id,
                        debtType: debt.debtType,
                        debtName: debt.name,
                        eventType: .missingRepaymentPlan,
                        riskLevel: .medium,
                        message: note,
                        dataSource: debt.dataSource
                    )
                )
            }
        }

        return drafts.map { $0.makeModel() }
    }

    private func debtOrder(
        strategyType: StrategyType,
        states: [DebtState],
        events: [CostEventDraft]
    ) -> [UUID] {
        let activeStates = states.filter { $0.balance > 0 }
        switch strategyType {
        case .snowball:
            return activeStates.sorted {
                if $0.balance == $1.balance {
                    let lhsCost = highestMarginalCostRate(for: $0.id, events: events, fallback: $0.snapshot.costRate)
                    let rhsCost = highestMarginalCostRate(for: $1.id, events: events, fallback: $1.snapshot.costRate)
                    if lhsCost == rhsCost {
                        return earlierDueDate($0.snapshot.dueDate, $1.snapshot.dueDate)
                    }
                    return lhsCost > rhsCost
                }
                return $0.balance < $1.balance
            }.map(\.id)
        case .avalanche:
            return activeStates.sorted {
                let lhsCost = highestMarginalCostRate(for: $0.id, events: events, fallback: $0.snapshot.costRate)
                let rhsCost = highestMarginalCostRate(for: $1.id, events: events, fallback: $1.snapshot.costRate)
                if lhsCost == rhsCost {
                    let lhsTotalCost = totalCost(for: $0.id, events: events)
                    let rhsTotalCost = totalCost(for: $1.id, events: events)
                    if lhsTotalCost == rhsTotalCost {
                        return earlierDueDate($0.snapshot.dueDate, $1.snapshot.dueDate)
                    }
                    return lhsTotalCost > rhsTotalCost
                }
                return lhsCost > rhsCost
            }.map(\.id)
        case .balanced:
            return activeStates.sorted {
                if $0.riskWeight == $1.riskWeight {
                    return $0.balance > $1.balance
                }
                return $0.riskWeight > $1.riskWeight
            }.map(\.id)
        }
    }

    private func highestMarginalCostRate(for debtID: UUID, events: [CostEventDraft], fallback: Decimal) -> Decimal {
        events
            .filter { $0.debtID == debtID }
            .map(\.marginalCostRate)
            .max()
            .map { maxDecimal($0, fallback) }
            ?? fallback
    }

    private func totalCost(for debtID: UUID, events: [CostEventDraft]) -> Decimal {
        events.filter { $0.debtID == debtID }.reduce(Decimal(0)) { $0 + $1.estimatedCostIfUncovered }
    }

    private func costEventSort(_ lhs: CostEventDraft, _ rhs: CostEventDraft) -> Bool {
        if lhs.marginalCostRate == rhs.marginalCostRate {
            if lhs.estimatedCostIfUncovered == rhs.estimatedCostIfUncovered {
                if lhs.protectionAmount == rhs.protectionAmount {
                    return earlierDueDate(lhs.dueDate, rhs.dueDate)
                }
                return lhs.protectionAmount < rhs.protectionAmount
            }
            return lhs.estimatedCostIfUncovered > rhs.estimatedCostIfUncovered
        }
        return lhs.marginalCostRate > rhs.marginalCostRate
    }

    private func earlierDueDate(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return lhs < rhs
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return false
        }
    }

    private func totalBalance(_ states: [DebtState]) -> Decimal {
        roundingPolicy.round(states.reduce(Decimal(0)) { $0 + maxDecimal($1.balance, 0) })
    }

    private func advanceOverdueState(for states: inout [DebtState], monthEndDate: Date) {
        for index in states.indices {
            states[index].refreshOverdueStatus(monthEndDate: monthEndDate, datePolicy: datePolicy)
        }
    }

    private func riskLevel(
        status: StrategySimulationStatus,
        endingRemaining: Decimal,
        overdueMonthCount: Int,
        highestOverdueDebtCount: Int,
        debts: [StrategyDebtSnapshot]
    ) -> StrategyRiskLevel {
        if status == .cannotProgress {
            return .critical
        }
        if endingRemaining > 0 {
            return .high
        }
        if overdueMonthCount > 0 || highestOverdueDebtCount > 0 {
            return .high
        }
        if debts.contains(where: { $0.isFallbackData || $0.userRiskNotes.isEmpty == false }) {
            return .medium
        }
        return .low
    }

    private func recommendation(for simulations: [StrategySimulationOutput]) -> (strategyType: StrategyType?, reason: String) {
        guard simulations.isEmpty == false else {
            return (nil, "No strategy was generated.")
        }

        let minCost = simulations.map { $0.simulation.totalEstimatedCost }.min() ?? 0
        let maxCost = simulations.map { $0.simulation.totalEstimatedCost }.max() ?? 0
        let costSpreadTolerance = Decimal(3) / Decimal(100)
        let minimumCloseThreshold = Decimal(1) / Decimal(100)
        let closeThreshold = maxDecimal(
            roundingPolicy.round(maxDecimal(minCost, 1) * costSpreadTolerance),
            minimumCloseThreshold
        )
        let costSpreadIsClose = roundingPolicy.round(maxCost - minCost) <= closeThreshold

        let ordered: [StrategySimulationOutput]
        if costSpreadIsClose {
            ordered = simulations.sorted {
                let lhsPayoff = $0.simulation.estimatedPayoffMonth ?? Int.max
                let rhsPayoff = $1.simulation.estimatedPayoffMonth ?? Int.max
                if lhsPayoff == rhsPayoff {
                    if $0.simulation.overdueMonthCount == $1.simulation.overdueMonthCount {
                        return $0.simulation.riskLevel.rank < $1.simulation.riskLevel.rank
                    }
                    return $0.simulation.overdueMonthCount < $1.simulation.overdueMonthCount
                }
                return lhsPayoff < rhsPayoff
            }
        } else {
            ordered = simulations.sorted {
                if $0.simulation.totalEstimatedCost == $1.simulation.totalEstimatedCost {
                    return ($0.simulation.estimatedPayoffMonth ?? Int.max) < ($1.simulation.estimatedPayoffMonth ?? Int.max)
                }
                return $0.simulation.totalEstimatedCost < $1.simulation.totalEstimatedCost
            }
        }

        guard let selected = ordered.first else {
            return (nil, "No strategy was generated.")
        }

        let reason = costSpreadIsClose
            ? "\(displayName(for: selected.simulation.strategyType)) is recommended because estimated extra costs are close and it has the shorter payoff path, fewer overdue months, or lower risk."
            : "\(displayName(for: selected.simulation.strategyType)) is recommended because it has the lowest estimated extra cost in the internal simulation."
        return (selected.simulation.strategyType, reason)
    }

    private func globalRiskNotes(
        for simulations: [StrategySimulationOutput],
        debts: [StrategyDebtSnapshot],
        recommendationReason: String
    ) -> [String] {
        var notes = [StrategyComparisonBatch.defaultDisclaimer, recommendationReason]
        if debts.contains(where: \.isFallbackData) {
            notes.append("Some debts use fallback or system-estimated data. Confirm actual creditor balances before acting.")
        }
        if simulations.contains(where: { $0.simulation.status != .completed }) {
            notes.append("At least one strategy does not fully pay off all debts within the simulation window.")
        }
        if debts.contains(where: { $0.debtType == .personalLending }) {
            notes.append("Personal lending can involve non-financial risk; this simulation only models amounts and simple timing.")
        }
        return Array(NSOrderedSet(array: notes)) as? [String] ?? notes
    }

    private func featureDescription(for strategyType: StrategyType) -> String {
        switch strategyType {
        case .snowball:
            return "Prioritizes the smallest simulated balance first to reduce debt count faster."
        case .avalanche:
            return "Prioritizes the highest marginal cost event first to reduce estimated extra cost."
        case .balanced:
            return "Allocates repayment proportionally so multiple debts decline together."
        }
    }

    private func displayName(for strategyType: StrategyType) -> String {
        switch strategyType {
        case .snowball: return "Snowball"
        case .avalanche: return "Avalanche"
        case .balanced: return "Balanced"
        }
    }

    private func monthPeriod(monthIndex: Int, strategyDate: Date) -> MonthPeriod {
        let startDate: Date
        if monthIndex == 1 {
            startDate = datePolicy.startOfDay(strategyDate)
        } else {
            let firstMonth = firstDayOfMonth(containing: strategyDate)
            startDate = datePolicy.calendar.date(byAdding: .month, value: monthIndex - 1, to: firstMonth) ?? firstMonth
        }
        let monthStart = firstDayOfMonth(containing: startDate)
        let nextMonthStart = datePolicy.calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let endDate = datePolicy.calendar.date(byAdding: .day, value: -1, to: nextMonthStart) ?? startDate
        let dayCount = max(datePolicy.daysBetween(startDate, endDate) + 1, 1)
        return MonthPeriod(startDate: startDate, endDate: endDate, dayCount: dayCount)
    }

    private func firstDayOfMonth(containing date: Date) -> Date {
        let components = datePolicy.calendar.dateComponents([.year, .month], from: date)
        return datePolicy.calendar.date(from: DateComponents(year: components.year, month: components.month, day: 1)) ?? datePolicy.startOfDay(date)
    }
}

private struct MonthPeriod {
    var startDate: Date
    var endDate: Date
    var dayCount: Int
}

private struct PlanState {
    var id: UUID
    var periodIndex: Int
    var dueDate: Date
    var remainingAmount: Decimal
    var remainingPrincipal: Decimal
    var remainingInterest: Decimal
    var isOverdue: Bool
    var overdueDays: Int

    nonisolated init(snapshot: StrategyPlanSnapshot) {
        id = snapshot.id
        periodIndex = snapshot.periodIndex
        dueDate = snapshot.dueDate
        remainingAmount = maxDecimal(snapshot.remainingAmount, 0)
        remainingPrincipal = maxDecimal(snapshot.remainingPrincipal, 0)
        remainingInterest = maxDecimal(snapshot.remainingInterest, 0)
        isOverdue = snapshot.isOverdue
        overdueDays = max(snapshot.overdueDays, 0)
    }

    mutating func applyPayment(_ payment: Decimal, roundingPolicy: MoneyRoundingPolicy) -> Decimal {
        let paid = minDecimal(maxDecimal(payment, 0), remainingAmount)
        guard paid > 0 else { return 0 }
        let before = remainingAmount
        let ratio = before > 0 ? paid / before : 0
        remainingAmount = roundingPolicy.round(maxDecimal(remainingAmount - paid, 0))
        remainingPrincipal = roundingPolicy.round(maxDecimal(remainingPrincipal - remainingPrincipal * ratio, 0))
        remainingInterest = roundingPolicy.round(maxDecimal(remainingInterest - remainingInterest * ratio, 0))
        if remainingAmount == 0 {
            isOverdue = false
            overdueDays = 0
        }
        return paid
    }
}

private struct DebtState {
    var snapshot: StrategyDebtSnapshot
    var balance: Decimal
    var plans: [PlanState]
    var extraCostBalance: Decimal
    var currentOverdue: Bool
    var currentOverdueDays: Int

    var id: UUID { snapshot.id }
    var debtType: DebtType { snapshot.debtType }
    var name: String { snapshot.name }
    var riskWeight: Decimal { snapshot.riskWeight }

    init(snapshot: StrategyDebtSnapshot, roundingPolicy: MoneyRoundingPolicy) {
        self.snapshot = snapshot
        self.balance = roundingPolicy.round(maxDecimal(snapshot.remainingAmount, 0))
        self.plans = snapshot.plans.map(PlanState.init).sorted {
            if $0.dueDate == $1.dueDate { return $0.periodIndex < $1.periodIndex }
            return $0.dueDate < $1.dueDate
        }
        self.extraCostBalance = 0
        self.currentOverdue = snapshot.isOverdue
        self.currentOverdueDays = snapshot.overdueDays
    }

    mutating func applyPayment(_ payment: Decimal, roundingPolicy: MoneyRoundingPolicy) -> Decimal {
        var amountLeft = minDecimal(maxDecimal(payment, 0), balance)
        guard amountLeft > 0 else { return 0 }
        let requested = amountLeft

        if plans.isEmpty {
            balance = roundingPolicy.round(maxDecimal(balance - amountLeft, 0))
            if balance == 0 {
                currentOverdue = false
                currentOverdueDays = 0
            }
            return roundingPolicy.round(requested)
        }

        for index in plans.indices where amountLeft > 0 {
            let paid = plans[index].applyPayment(amountLeft, roundingPolicy: roundingPolicy)
            amountLeft = roundingPolicy.round(maxDecimal(amountLeft - paid, 0))
        }

        if amountLeft > 0 && extraCostBalance > 0 {
            let paid = minDecimal(amountLeft, extraCostBalance)
            extraCostBalance = roundingPolicy.round(maxDecimal(extraCostBalance - paid, 0))
            amountLeft = roundingPolicy.round(maxDecimal(amountLeft - paid, 0))
        }

        let paidTotal = roundingPolicy.round(maxDecimal(requested - amountLeft, 0))
        balance = roundingPolicy.round(maxDecimal(balance - paidTotal, 0))
        if balance == 0 {
            currentOverdue = false
            currentOverdueDays = 0
        }
        return paidTotal
    }

    func isOverdue(at date: Date) -> Bool {
        guard balance > 0 else { return false }
        if currentOverdue { return true }
        if plans.contains(where: { $0.remainingAmount > 0 && $0.dueDate < date }) { return true }
        if let dueDate = snapshot.dueDate, dueDate < date { return true }
        return false
    }

    mutating func refreshOverdueStatus(monthEndDate: Date, datePolicy: DateCalculationPolicy) {
        guard balance > 0 else {
            currentOverdue = false
            currentOverdueDays = 0
            return
        }

        let overduePlanDates = plans
            .filter { $0.remainingAmount > 0 && $0.dueDate < monthEndDate }
            .map(\.dueDate)
        var earliestDueDate = overduePlanDates.min()
        if let debtDueDate = snapshot.dueDate, debtDueDate < monthEndDate {
            earliestDueDate = min(earliestDueDate ?? debtDueDate, debtDueDate)
        }

        guard let earliestDueDate else {
            currentOverdue = false
            currentOverdueDays = 0
            return
        }

        currentOverdue = true
        currentOverdueDays = datePolicy.daysBetween(earliestDueDate, monthEndDate)
    }
}

private struct AllocationResult {
    var totalAllocated: Decimal
    var unusedBudget: Decimal
    var allocatedByDebt: [UUID: Decimal]
    var protectionAllocatedByDebt: [UUID: Decimal]
    var allocationOrder: [UUID]
}

private struct CostComponents {
    var interest: Decimal
    var overdueFee: Decimal
    var penaltyInterest: Decimal

    static let zero = CostComponents(interest: 0, overdueFee: 0, penaltyInterest: 0)

    mutating func add(_ event: CostEventResult, roundingPolicy: MoneyRoundingPolicy) {
        interest = roundingPolicy.round(interest + event.realizedInterestAmount)
        overdueFee = roundingPolicy.round(overdueFee + event.realizedOverdueFee)
        penaltyInterest = roundingPolicy.round(penaltyInterest + event.realizedPenaltyInterest)
    }
}

private struct CostEventDraft {
    var monthIndex: Int
    var debtID: UUID
    var debtType: DebtType
    var debtName: String
    var eventType: StrategyCostEventType
    var protectionAmount: Decimal
    var estimatedInterestAmount: Decimal
    var estimatedOverdueFee: Decimal
    var estimatedPenaltyInterest: Decimal
    var dueDate: Date?
    var note: String

    var estimatedCostIfUncovered: Decimal {
        estimatedInterestAmount + estimatedOverdueFee + estimatedPenaltyInterest
    }

    var marginalCostRate: Decimal {
        guard protectionAmount > 0 else { return 0 }
        return estimatedCostIfUncovered / protectionAmount
    }

    init(
        monthIndex: Int,
        debtID: UUID,
        debtType: DebtType,
        debtName: String,
        eventType: StrategyCostEventType,
        protectionAmount: Decimal,
        estimatedInterestAmount: Decimal = 0,
        estimatedOverdueFee: Decimal = 0,
        estimatedPenaltyInterest: Decimal = 0,
        dueDate: Date? = nil,
        note: String
    ) {
        self.monthIndex = monthIndex
        self.debtID = debtID
        self.debtType = debtType
        self.debtName = debtName
        self.eventType = eventType
        self.protectionAmount = maxDecimal(protectionAmount, 0)
        self.estimatedInterestAmount = maxDecimal(estimatedInterestAmount, 0)
        self.estimatedOverdueFee = maxDecimal(estimatedOverdueFee, 0)
        self.estimatedPenaltyInterest = maxDecimal(estimatedPenaltyInterest, 0)
        self.dueDate = dueDate
        self.note = note
    }
}

private struct CostEventResult {
    var draft: CostEventDraft
    var uncoveredAmount: Decimal
    var realizedInterestAmount: Decimal
    var realizedOverdueFee: Decimal
    var realizedPenaltyInterest: Decimal

    var debtID: UUID { draft.debtID }
    var debtType: DebtType { draft.debtType }
    var debtName: String { draft.debtName }
    var realizedCost: Decimal { realizedInterestAmount + realizedOverdueFee + realizedPenaltyInterest }

    func makeModel(simulationID: UUID, monthSnapshotID: UUID) -> StrategyCostEvent {
        StrategyCostEvent(
            simulationID: simulationID,
            monthSnapshotID: monthSnapshotID,
            monthIndex: draft.monthIndex,
            debtID: draft.debtID,
            debtType: draft.debtType,
            debtName: draft.debtName,
            eventType: draft.eventType,
            protectionAmount: draft.protectionAmount,
            uncoveredAmount: uncoveredAmount,
            estimatedCostIfUncovered: draft.estimatedCostIfUncovered,
            realizedCost: realizedCost,
            estimatedInterestAmount: realizedInterestAmount,
            estimatedOverdueFee: realizedOverdueFee,
            estimatedPenaltyInterest: realizedPenaltyInterest,
            marginalCostRate: draft.marginalCostRate,
            dueDate: draft.dueDate,
            isRiskFlagged: uncoveredAmount > 0,
            isCovered: uncoveredAmount == 0,
            note: draft.note
        )
    }
}

private struct EventEvaluation {
    var events: [CostEventResult]
    var roundingPolicy: MoneyRoundingPolicy

    var totalInterest: Decimal {
        roundingPolicy.round(events.reduce(Decimal(0)) { $0 + $1.realizedInterestAmount })
    }

    var totalOverdueFee: Decimal {
        roundingPolicy.round(events.reduce(Decimal(0)) { $0 + $1.realizedOverdueFee })
    }

    var totalPenaltyInterest: Decimal {
        roundingPolicy.round(events.reduce(Decimal(0)) { $0 + $1.realizedPenaltyInterest })
    }
}

private struct RiskEventDraft {
    var comparisonBatchID: UUID?
    var simulationID: UUID?
    var monthSnapshotID: UUID?
    var monthIndex: Int
    var debtID: UUID?
    var debtType: DebtType?
    var debtName: String
    var eventType: StrategyRiskEventType
    var riskLevel: StrategyRiskLevel
    var message: String
    var dataSource: String

    init(
        comparisonBatchID: UUID?,
        simulationID: UUID?,
        monthSnapshotID: UUID? = nil,
        monthIndex: Int = 0,
        debtID: UUID?,
        debtType: DebtType?,
        debtName: String,
        eventType: StrategyRiskEventType,
        riskLevel: StrategyRiskLevel,
        message: String,
        dataSource: String
    ) {
        self.comparisonBatchID = comparisonBatchID
        self.simulationID = simulationID
        self.monthSnapshotID = monthSnapshotID
        self.monthIndex = monthIndex
        self.debtID = debtID
        self.debtType = debtType
        self.debtName = debtName
        self.eventType = eventType
        self.riskLevel = riskLevel
        self.message = message
        self.dataSource = dataSource
    }

    func with(monthSnapshotID: UUID) -> RiskEventDraft {
        var copy = self
        copy.monthSnapshotID = monthSnapshotID
        return copy
    }

    func makeModel() -> StrategyRiskEvent {
        StrategyRiskEvent(
            comparisonBatchID: comparisonBatchID,
            simulationID: simulationID,
            monthSnapshotID: monthSnapshotID,
            monthIndex: monthIndex,
            debtID: debtID,
            debtType: debtType,
            debtName: debtName,
            eventType: eventType,
            riskLevel: riskLevel,
            message: message,
            dataSource: dataSource
        )
    }
}
