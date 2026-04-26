import Foundation
import SwiftData
import UserNotifications

@MainActor
enum RuleProfileResolver {
    static func resolve(for debt: Debt, profiles: [CalculationRuleProfile]) -> DebtCustomRule? {
        if let customRule = debt.customRule {
            return customRule
        }

        let fallback = resolveLegacyProfile(for: debt, profiles: profiles)
            ?? RuleTemplateCatalogService.defaultProfile(for: debt.type, in: profiles)
            ?? profiles.first(where: { $0.name == "默认规则" })
            ?? profiles.first
        assign(fallback, to: debt)
        return debt.customRule
    }

    static func assign(_ profile: CalculationRuleProfile?, to debt: Debt) {
        let rule = debt.customRule ?? DebtCustomRule(debt: debt)
        if debt.customRule == nil {
            debt.customRule = rule
        }

        apply(profile, to: rule)
        debt.calculationRuleID = profile?.id
        debt.calculationRuleName = profile?.name ?? rule.name
    }

    static func ensureCustomRule(for debt: Debt, preferredProfile: CalculationRuleProfile? = nil) -> DebtCustomRule {
        if let customRule = debt.customRule {
            return customRule
        }

        let rule = DebtCustomRule(debt: debt)
        debt.customRule = rule
        if let preferredProfile {
            apply(preferredProfile, to: rule)
            debt.calculationRuleID = preferredProfile.id
            debt.calculationRuleName = preferredProfile.name
        } else {
            debt.calculationRuleID = debt.calculationRuleID
            debt.calculationRuleName = debt.calculationRuleName.isEmpty ? rule.name : debt.calculationRuleName
        }
        return rule
    }

    static func updateCustomRule(on debt: Debt, using mutate: (DebtCustomRule) -> Void) {
        let rule = ensureCustomRule(for: debt)
        mutate(rule)
    }

    static func rebindDebtsReferencingDeletedProfile(
        debts: [Debt],
        deletedProfile: CalculationRuleProfile,
        fallbackProfile: CalculationRuleProfile?
    ) {
        for debt in debts where debt.customRule == nil && (debt.calculationRuleID == deletedProfile.id || debt.calculationRuleName == deletedProfile.name) {
            assign(fallbackProfile, to: debt)
        }
    }

    private static func resolveLegacyProfile(for debt: Debt, profiles: [CalculationRuleProfile]) -> CalculationRuleProfile? {
        if let ruleID = debt.calculationRuleID,
           let matched = profiles.first(where: { $0.id == ruleID }) {
            if debt.calculationRuleName != matched.name {
                debt.calculationRuleName = matched.name
            }
            return matched
        }

        if let legacy = profiles.first(where: { $0.name == debt.calculationRuleName }) {
            debt.calculationRuleID = legacy.id
            debt.calculationRuleName = legacy.name
            return legacy
        }

        return nil
    }

    private static func apply(_ profile: CalculationRuleProfile?, to rule: DebtCustomRule) {
        guard let profile else {
            rule.name = rule.name.isEmpty ? "默认规则" : rule.name
            return
        }

        rule.name = profile.name
        rule.overduePenaltyMode = profile.overduePenaltyMode
        rule.paymentAllocationOrder = profile.paymentAllocationOrder
        rule.defaultCreditCardMinimumRate = profile.defaultCreditCardMinimumRate
        rule.defaultCreditCardMinimumFloor = profile.defaultCreditCardMinimumFloor
        rule.defaultCreditCardMinimumIncludesFees = profile.defaultCreditCardMinimumIncludesFees
        rule.defaultCreditCardMinimumIncludesPenalty = profile.defaultCreditCardMinimumIncludesPenalty
        rule.defaultCreditCardMinimumIncludesInterest = profile.defaultCreditCardMinimumIncludesInterest
        rule.defaultCreditCardMinimumIncludesInstallmentPrincipal = profile.defaultCreditCardMinimumIncludesInstallmentPrincipal
        rule.defaultCreditCardMinimumIncludesInstallmentFee = profile.defaultCreditCardMinimumIncludesInstallmentFee
        rule.defaultCreditCardGraceDays = profile.defaultCreditCardGraceDays
        rule.defaultCreditCardStatementCycles = profile.defaultCreditCardStatementCycles
        rule.defaultCreditCardPenaltyDailyRate = profile.defaultCreditCardPenaltyDailyRate
        rule.defaultCreditCardOverdueFeeFlat = profile.defaultCreditCardOverdueFeeFlat
        rule.defaultCreditCardOverdueGraceDays = profile.defaultCreditCardOverdueGraceDays
        rule.defaultCreditCardOverdueInterestBase = profile.defaultCreditCardOverdueInterestBase
        rule.defaultLoanPenaltyDailyRate = profile.defaultLoanPenaltyDailyRate
        rule.defaultLoanOverdueFeeFlat = profile.defaultLoanOverdueFeeFlat
        rule.defaultLoanGraceDays = profile.defaultLoanGraceDays
        rule.defaultLoanOverdueInterestBase = profile.defaultLoanOverdueInterestBase
        rule.defaultPrivateLoanPenaltyDailyRate = profile.defaultPrivateLoanPenaltyDailyRate
        rule.defaultPrivateLoanOverdueFeeFlat = profile.defaultPrivateLoanOverdueFeeFlat
        rule.defaultPrivateLoanGraceDays = profile.defaultPrivateLoanGraceDays
        rule.defaultPrivateLoanOverdueInterestBase = profile.defaultPrivateLoanOverdueInterestBase
    }
}

@MainActor
enum RuleTemplateCatalogService {
    private static let defaultLoanPenaltyDailyRate = 0.18 / 365 * 1.5

    struct TemplateValues {
        var overduePenaltyMode: OverduePenaltyMode = .simple
        var paymentAllocationOrder: PaymentAllocationOrder = .overdueFeeFirst

        var defaultCreditCardMinimumRate: Double = 0.1
        var defaultCreditCardMinimumFloor: Double = 100
        var defaultCreditCardMinimumIncludesFees: Bool = true
        var defaultCreditCardMinimumIncludesPenalty: Bool = true
        var defaultCreditCardMinimumIncludesInterest: Bool = true
        var defaultCreditCardMinimumIncludesInstallmentPrincipal: Bool = true
        var defaultCreditCardMinimumIncludesInstallmentFee: Bool = true
        var defaultCreditCardGraceDays: Int = 0
        var defaultCreditCardStatementCycles: Int = 1
        var defaultCreditCardPenaltyDailyRate: Double = 0.0005
        var defaultCreditCardOverdueFeeFlat: Double = 0
        var defaultCreditCardOverdueGraceDays: Int = 0
        var defaultCreditCardOverdueInterestBase: OverdueInterestBase = .principalOnly
        var repaymentReminderLeadDays: Int = 3
        var creditCardStatementReminderOffsetDays: Int = 1
        var requireCreditCardStatementRefresh: Bool = true

        var defaultLoanPenaltyDailyRate: Double = 0.0005
        var defaultLoanOverdueFeeFlat: Double = 0
        var defaultLoanGraceDays: Int = 0
        var defaultLoanOverdueInterestBase: OverdueInterestBase = .principalOnly
        var defaultPrivateLoanPenaltyDailyRate: Double = 0
        var defaultPrivateLoanOverdueFeeFlat: Double = 0
        var defaultPrivateLoanGraceDays: Int = 0
        var defaultPrivateLoanOverdueInterestBase: OverdueInterestBase = .principalOnly
    }

    struct TemplateDefinition: Identifiable {
        let id: String
        let displayName: String
        let debtType: DebtType?
        let summary: String
        let usageHint: String
        let values: TemplateValues
    }

    static let creditCardDefaultTemplate = TemplateDefinition(
            id: "builtin.default.credit-card",
            displayName: "信用卡默认规则",
            debtType: .creditCard,
            summary: "按信用卡账单口径预设最低还款、分期与逾期测算参数。",
            usageHint: "用于信用卡债务的默认计算规则。",
            values: TemplateValues(
                overduePenaltyMode: .simple,
                paymentAllocationOrder: .overdueFeeFirst,
                defaultCreditCardMinimumRate: 0.1,
                defaultCreditCardMinimumFloor: 100,
                defaultCreditCardMinimumIncludesFees: true,
                defaultCreditCardMinimumIncludesPenalty: true,
                defaultCreditCardMinimumIncludesInterest: true,
                defaultCreditCardMinimumIncludesInstallmentPrincipal: true,
                defaultCreditCardMinimumIncludesInstallmentFee: true,
                defaultCreditCardGraceDays: 20,
                defaultCreditCardStatementCycles: 1,
                defaultCreditCardPenaltyDailyRate: 0.0005,
                defaultCreditCardOverdueFeeFlat: 0,
                defaultCreditCardOverdueGraceDays: 0,
                defaultCreditCardOverdueInterestBase: .principalOnly,
                repaymentReminderLeadDays: 5,
                creditCardStatementReminderOffsetDays: 1,
                requireCreditCardStatementRefresh: true
            )
        )

    static let loanDefaultTemplate = TemplateDefinition(
            id: "builtin.default.loan",
            displayName: "贷款默认规则",
            debtType: .loan,
            summary: "按贷款场景预设违约与还款测算参数。",
            usageHint: "用于贷款债务的默认计算规则。",
            values: TemplateValues(
                overduePenaltyMode: .simple,
                paymentAllocationOrder: .overdueFeeFirst,
                repaymentReminderLeadDays: 3,
                creditCardStatementReminderOffsetDays: 1,
                requireCreditCardStatementRefresh: true,
                defaultLoanPenaltyDailyRate: RuleTemplateCatalogService.defaultLoanPenaltyDailyRate,
                defaultLoanOverdueFeeFlat: 0,
                defaultLoanGraceDays: 0,
                defaultLoanOverdueInterestBase: .principalOnly
            )
        )

    static let privateLendingDefaultTemplate = TemplateDefinition(
            id: "builtin.default.private-lending",
            displayName: "个人借贷默认规则",
            debtType: .privateLending,
            summary: "按个人借贷场景预设审慎的逾期测算口径。",
            usageHint: "用于个人借贷债务的默认计算规则。",
            values: TemplateValues(
                overduePenaltyMode: .simple,
                paymentAllocationOrder: .overdueFeeFirst,
                repaymentReminderLeadDays: 3,
                creditCardStatementReminderOffsetDays: 1,
                requireCreditCardStatementRefresh: true,
                defaultPrivateLoanPenaltyDailyRate: 0,
                defaultPrivateLoanOverdueFeeFlat: 0,
                defaultPrivateLoanGraceDays: 0,
                defaultPrivateLoanOverdueInterestBase: .principalOnly
            )
        )

    static let builtInTemplates: [TemplateDefinition] = [
        creditCardDefaultTemplate,
        loanDefaultTemplate,
        privateLendingDefaultTemplate
    ]

    private static let legacyTemplateNamesByDebtType: [DebtType: [String]] = [
        .creditCard: ["默认规则", "信用卡参考模板"],
        .loan: ["默认规则", "贷款参考模板"],
        .privateLending: ["默认规则", "个人借贷参考模板"]
    ]

    static func defaultTemplate(for debtType: DebtType) -> TemplateDefinition {
        builtInTemplates.first(where: { $0.debtType == debtType }) ?? creditCardDefaultTemplate
    }

    static func defaultTemplateDisplayName(for debtType: DebtType) -> String {
        defaultTemplate(for: debtType).displayName
    }

    static func legacyTemplateNames(for debtType: DebtType) -> [String] {
        legacyTemplateNamesByDebtType[debtType] ?? []
    }

    static func defaultProfile(for debtType: DebtType, in profiles: [CalculationRuleProfile]) -> CalculationRuleProfile? {
        let canonicalName = defaultTemplateDisplayName(for: debtType)
        if let profile = profiles.first(where: { $0.name == canonicalName }) {
            return profile
        }

        let legacyNames = Set(legacyTemplateNames(for: debtType))
        return profiles.first(where: { legacyNames.contains($0.name) })
    }

    static func template(id: String) -> TemplateDefinition? {
        builtInTemplates.first(where: { $0.id == id })
    }

    static func template(for profileName: String) -> TemplateDefinition? {
        if let matched = builtInTemplates.first(where: { $0.displayName == profileName }) {
            return matched
        }

        if let debtType = legacyTemplateNamesByDebtType.first(where: { $0.value.contains(profileName) })?.key {
            return defaultTemplate(for: debtType)
        }

        return nil
    }

    static func ensureBuiltInProfiles(modelContext: ModelContext) {
        let existingProfiles = (try? modelContext.fetch(FetchDescriptor<CalculationRuleProfile>())) ?? []
        var existingByName = Dictionary(uniqueKeysWithValues: existingProfiles.map { ($0.name, $0) })

        for template in builtInTemplates {
            if let existing = existingByName[template.displayName] {
                populate(existing, from: template)
                continue
            }

            if let debtType = template.debtType,
               let legacyName = legacyTemplateNames(for: debtType).first(where: { existingByName[$0] != nil }),
               let legacyProfile = existingByName[legacyName] {
                legacyProfile.name = template.displayName
                populate(legacyProfile, from: template)
                existingByName.removeValue(forKey: legacyName)
                existingByName[template.displayName] = legacyProfile
                continue
            }

            let created = makeProfile(from: template)
            modelContext.insert(created)
            existingByName[template.displayName] = created
        }

        try? modelContext.save()
    }

    static func restoreReferenceTemplates(modelContext: ModelContext) {
        // Keep the old API name for backward compatibility.
        let existingProfiles = (try? modelContext.fetch(FetchDescriptor<CalculationRuleProfile>())) ?? []
        var existingByName = Dictionary(uniqueKeysWithValues: existingProfiles.map { ($0.name, $0) })

        for template in builtInTemplates {
            if let existing = existingByName[template.displayName] {
                populate(existing, from: template)
            } else if let debtType = template.debtType,
                      let legacyName = legacyTemplateNames(for: debtType).first(where: { existingByName[$0] != nil }),
                      let legacy = existingByName[legacyName] {
                legacy.name = template.displayName
                populate(legacy, from: template)
                existingByName.removeValue(forKey: legacyName)
                existingByName[template.displayName] = legacy
            } else {
                let created = makeProfile(from: template)
                modelContext.insert(created)
                existingByName[template.displayName] = created
            }
        }

        try? modelContext.save()
    }

    static func applyTemplate(id: String, to profile: CalculationRuleProfile) {
        guard let template = template(id: id) else { return }
        populate(profile, from: template)
    }

    static func applyTemplate(id: String, to rule: DebtCustomRule) {
        guard let template = template(id: id) else { return }
        populate(rule, from: template)
    }

    private static func makeProfile(from template: TemplateDefinition) -> CalculationRuleProfile {
        let profile = CalculationRuleProfile(name: template.displayName)
        populate(profile, from: template)
        return profile
    }

    private static func populate(_ profile: CalculationRuleProfile, from template: TemplateDefinition) {
        let values = template.values
        profile.name = template.displayName
        applyCommonValues(values, to: profile)

        switch template.debtType {
        case .creditCard:
            applyCreditCardValues(values, to: profile)
        case .loan:
            applyLoanValues(values, to: profile)
        case .privateLending:
            applyPrivateLendingValues(values, to: profile)
        case nil:
            applyCreditCardValues(values, to: profile)
            applyLoanValues(values, to: profile)
            applyPrivateLendingValues(values, to: profile)
        }
    }

    private static func populate(_ rule: DebtCustomRule, from template: TemplateDefinition) {
        let values = template.values
        rule.name = template.displayName
        applyCommonValues(values, to: rule)

        switch template.debtType {
        case .creditCard:
            applyCreditCardValues(values, to: rule)
        case .loan:
            applyLoanValues(values, to: rule)
        case .privateLending:
            applyPrivateLendingValues(values, to: rule)
        case nil:
            applyCreditCardValues(values, to: rule)
            applyLoanValues(values, to: rule)
            applyPrivateLendingValues(values, to: rule)
        }
    }

    private static func applyCommonValues(_ values: TemplateValues, to profile: CalculationRuleProfile) {
        profile.overduePenaltyMode = values.overduePenaltyMode
        profile.paymentAllocationOrder = values.paymentAllocationOrder
        profile.repaymentReminderLeadDays = values.repaymentReminderLeadDays
        profile.creditCardStatementReminderOffsetDays = values.creditCardStatementReminderOffsetDays
        profile.requireCreditCardStatementRefresh = values.requireCreditCardStatementRefresh
    }

    private static func applyCreditCardValues(_ values: TemplateValues, to profile: CalculationRuleProfile) {
        profile.defaultCreditCardMinimumRate = values.defaultCreditCardMinimumRate
        profile.defaultCreditCardMinimumFloor = values.defaultCreditCardMinimumFloor
        profile.defaultCreditCardMinimumIncludesFees = values.defaultCreditCardMinimumIncludesFees
        profile.defaultCreditCardMinimumIncludesPenalty = values.defaultCreditCardMinimumIncludesPenalty
        profile.defaultCreditCardMinimumIncludesInterest = values.defaultCreditCardMinimumIncludesInterest
        profile.defaultCreditCardMinimumIncludesInstallmentPrincipal = values.defaultCreditCardMinimumIncludesInstallmentPrincipal
        profile.defaultCreditCardMinimumIncludesInstallmentFee = values.defaultCreditCardMinimumIncludesInstallmentFee
        profile.defaultCreditCardGraceDays = values.defaultCreditCardGraceDays
        profile.defaultCreditCardStatementCycles = values.defaultCreditCardStatementCycles
        profile.defaultCreditCardPenaltyDailyRate = values.defaultCreditCardPenaltyDailyRate
        profile.defaultCreditCardOverdueFeeFlat = values.defaultCreditCardOverdueFeeFlat
        profile.defaultCreditCardOverdueGraceDays = values.defaultCreditCardOverdueGraceDays
        profile.defaultCreditCardOverdueInterestBase = values.defaultCreditCardOverdueInterestBase
    }

    private static func applyLoanValues(_ values: TemplateValues, to profile: CalculationRuleProfile) {
        profile.defaultLoanPenaltyDailyRate = values.defaultLoanPenaltyDailyRate
        profile.defaultLoanOverdueFeeFlat = values.defaultLoanOverdueFeeFlat
        profile.defaultLoanGraceDays = values.defaultLoanGraceDays
        profile.defaultLoanOverdueInterestBase = values.defaultLoanOverdueInterestBase
    }

    private static func applyPrivateLendingValues(_ values: TemplateValues, to profile: CalculationRuleProfile) {
        profile.defaultPrivateLoanPenaltyDailyRate = values.defaultPrivateLoanPenaltyDailyRate
        profile.defaultPrivateLoanOverdueFeeFlat = values.defaultPrivateLoanOverdueFeeFlat
        profile.defaultPrivateLoanGraceDays = values.defaultPrivateLoanGraceDays
        profile.defaultPrivateLoanOverdueInterestBase = values.defaultPrivateLoanOverdueInterestBase
    }

    private static func applyCommonValues(_ values: TemplateValues, to rule: DebtCustomRule) {
        rule.overduePenaltyMode = values.overduePenaltyMode
        rule.paymentAllocationOrder = values.paymentAllocationOrder
        rule.repaymentReminderLeadDays = values.repaymentReminderLeadDays
        rule.creditCardStatementReminderOffsetDays = values.creditCardStatementReminderOffsetDays
        rule.requireCreditCardStatementRefresh = values.requireCreditCardStatementRefresh
    }

    private static func applyCreditCardValues(_ values: TemplateValues, to rule: DebtCustomRule) {
        rule.defaultCreditCardMinimumRate = values.defaultCreditCardMinimumRate
        rule.defaultCreditCardMinimumFloor = values.defaultCreditCardMinimumFloor
        rule.defaultCreditCardMinimumIncludesFees = values.defaultCreditCardMinimumIncludesFees
        rule.defaultCreditCardMinimumIncludesPenalty = values.defaultCreditCardMinimumIncludesPenalty
        rule.defaultCreditCardMinimumIncludesInterest = values.defaultCreditCardMinimumIncludesInterest
        rule.defaultCreditCardMinimumIncludesInstallmentPrincipal = values.defaultCreditCardMinimumIncludesInstallmentPrincipal
        rule.defaultCreditCardMinimumIncludesInstallmentFee = values.defaultCreditCardMinimumIncludesInstallmentFee
        rule.defaultCreditCardGraceDays = values.defaultCreditCardGraceDays
        rule.defaultCreditCardStatementCycles = values.defaultCreditCardStatementCycles
        rule.defaultCreditCardPenaltyDailyRate = values.defaultCreditCardPenaltyDailyRate
        rule.defaultCreditCardOverdueFeeFlat = values.defaultCreditCardOverdueFeeFlat
        rule.defaultCreditCardOverdueGraceDays = values.defaultCreditCardOverdueGraceDays
        rule.defaultCreditCardOverdueInterestBase = values.defaultCreditCardOverdueInterestBase
    }

    private static func applyLoanValues(_ values: TemplateValues, to rule: DebtCustomRule) {
        rule.defaultLoanPenaltyDailyRate = values.defaultLoanPenaltyDailyRate
        rule.defaultLoanOverdueFeeFlat = values.defaultLoanOverdueFeeFlat
        rule.defaultLoanGraceDays = values.defaultLoanGraceDays
        rule.defaultLoanOverdueInterestBase = values.defaultLoanOverdueInterestBase
    }

    private static func applyPrivateLendingValues(_ values: TemplateValues, to rule: DebtCustomRule) {
        rule.defaultPrivateLoanPenaltyDailyRate = values.defaultPrivateLoanPenaltyDailyRate
        rule.defaultPrivateLoanOverdueFeeFlat = values.defaultPrivateLoanOverdueFeeFlat
        rule.defaultPrivateLoanGraceDays = values.defaultPrivateLoanGraceDays
        rule.defaultPrivateLoanOverdueInterestBase = values.defaultPrivateLoanOverdueInterestBase
    }
}

@MainActor
enum DataStatisticsDomainService {
    struct Snapshot {
        var totalOutstanding: Double
        var totalRepaid: Double
        var overdueCost: Double
        var repaidPrincipal: Double
        var outstandingInterest: Double
        var paidInterest: Double
        var paidOverdueFeeAndPenalty: Double
        var debtCount: Int
        var settledCount: Int
        var weightedAverageAPR: Double
        var weightedAverageNominalAPR: Double
        var highestEffectiveAPR: Double
        var lowestEffectiveAPR: Double
        var highRateDebtCount: Int
        var last30DaysRepayment: Double
        var debtByType: [DebtType: Double]
        var debtRateByType: [DebtType: Double]

        var settlementRate: Double {
            guard debtCount > 0 else { return 0 }
            return Double(settledCount) / Double(debtCount)
        }

        var repaymentCoverageRate: Double {
            let base = totalOutstanding + totalRepaid
            guard base > 0 else { return 0 }
            return totalRepaid / base
        }

        var totalOverdueFeeAndPenalty: Double {
            overdueCost + paidOverdueFeeAndPenalty
        }
    }

    private struct RepaymentAllocationBreakdown {
        var overdueFee: Double
        var penaltyInterest: Double
        var interest: Double
        var fee: Double
        var principal: Double

        var total: Double {
            overdueFee + penaltyInterest + interest + fee + principal
        }
    }

    private static func allocationBreakdown(from record: RepaymentRecord) -> RepaymentAllocationBreakdown {
        guard
            let data = record.allocationJSON.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let allocation = object["allocation"] as? [String: Any]
        else {
            return RepaymentAllocationBreakdown(
                overdueFee: 0,
                penaltyInterest: 0,
                interest: 0,
                fee: 0,
                principal: record.amount
            )
        }

        return RepaymentAllocationBreakdown(
            overdueFee: allocation["overdueFee"] as? Double ?? 0,
            penaltyInterest: allocation["penaltyInterest"] as? Double ?? 0,
            interest: allocation["interest"] as? Double ?? 0,
            fee: allocation["fee"] as? Double ?? 0,
            principal: allocation["principal"] as? Double ?? 0
        )
    }

    private static func appliedAmount(from record: RepaymentRecord) -> Double {
        let breakdown = allocationBreakdown(from: record)
        return breakdown.total > 0 ? breakdown.total : record.amount
    }

    static func build(
        debts: [Debt],
        records: [RepaymentRecord],
        overdueEvents: [OverdueEvent],
        now: Date = Date()
    ) -> Snapshot {
        let totalOutstanding = debts.reduce(0) { $0 + $1.outstandingPrincipal }
        let totalRepaid = records.reduce(0) { $0 + appliedAmount(from: $1) }
        let repaidPrincipal = records.reduce(0) { partial, record in
            partial + allocationBreakdown(from: record).principal
        }
        let paidInterest = records.reduce(0) { partial, record in
            partial + allocationBreakdown(from: record).interest
        }
        let paidOverdueFeeAndPenalty = records.reduce(0) { partial, record in
            let allocation = allocationBreakdown(from: record)
            return partial + allocation.overdueFee + allocation.penaltyInterest
        }
        let outstandingInterest = debts.reduce(0) { partial, debt in
            let debtPendingInterest = debt.repaymentPlans
                .filter { $0.status != .paid }
                .reduce(0) { $0 + max($1.interestDue, 0) }
            return partial + debtPendingInterest
        }
        let overdueCost = overdueEvents
            .filter { !$0.isResolved }
            .reduce(0) { $0 + $1.overdueFee + $1.penaltyInterest }
        let debtCount = debts.count
        let settledCount = debts.filter { $0.status == .settled }.count

        let weightedAverageAPR: Double = {
            let weightedPrincipal = debts.reduce(0) { $0 + max($1.outstandingPrincipal, 0) }
            guard weightedPrincipal > 0 else { return 0 }
            let weightedAPR = debts.reduce(0) { partial, debt in
                partial + max(debt.outstandingPrincipal, 0) * max(debt.effectiveAPR, 0)
            }
            return weightedAPR / weightedPrincipal
        }()

        let weightedAverageNominalAPR: Double = {
            let weightedPrincipal = debts.reduce(0) { $0 + max($1.outstandingPrincipal, 0) }
            guard weightedPrincipal > 0 else { return 0 }
            let weightedAPR = debts.reduce(0) { partial, debt in
                partial + max(debt.outstandingPrincipal, 0) * max(debt.nominalAPR, 0)
            }
            return weightedAPR / weightedPrincipal
        }()

        let activeDebts = debts.filter { $0.outstandingPrincipal > 0.01 }
        let highestEffectiveAPR = activeDebts.map { max($0.effectiveAPR, 0) }.max() ?? 0
        let lowestEffectiveAPR = activeDebts.map { max($0.effectiveAPR, 0) }.min() ?? 0
        let highRateDebtCount = activeDebts.filter { $0.effectiveAPR >= 0.24 }.count

        let start = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let last30DaysRepayment = records
            .filter { $0.paidAt >= start }
            .reduce(0) { $0 + appliedAmount(from: $1) }

        let debtByType = Dictionary(grouping: debts, by: \.type)
            .mapValues { list in
                list.reduce(0) { $0 + $1.outstandingPrincipal }
            }

        let debtRateByType = Dictionary(grouping: activeDebts, by: \.type)
            .mapValues { list in
                let outstanding = list.reduce(0.0) { $0 + max($1.outstandingPrincipal, 0) }
                guard outstanding > 0 else { return 0.0 }
                let weightedAPR = list.reduce(0.0) { partial, debt in
                    partial + max(debt.outstandingPrincipal, 0) * max(debt.effectiveAPR, 0)
                }
                return weightedAPR / outstanding
            }

        return Snapshot(
            totalOutstanding: totalOutstanding,
            totalRepaid: totalRepaid,
            overdueCost: overdueCost,
            repaidPrincipal: repaidPrincipal,
            outstandingInterest: outstandingInterest,
            paidInterest: paidInterest,
            paidOverdueFeeAndPenalty: paidOverdueFeeAndPenalty,
            debtCount: debtCount,
            settledCount: settledCount,
            weightedAverageAPR: weightedAverageAPR,
            weightedAverageNominalAPR: weightedAverageNominalAPR,
            highestEffectiveAPR: highestEffectiveAPR,
            lowestEffectiveAPR: lowestEffectiveAPR,
            highRateDebtCount: highRateDebtCount,
            last30DaysRepayment: last30DaysRepayment,
            debtByType: debtByType,
            debtRateByType: debtRateByType
        )
    }
}

@MainActor
enum DebtLifecycleService {
    private static let tolerance = 0.01

    static func refreshStatus(debt: Debt, now: Date = Date()) {
        synchronizeAutomaticOverdues(for: debt, now: now)
        let unresolvedOverdues = debt.overdueEvents.filter { !$0.isResolved }

        for plan in debt.repaymentPlans {
            let hasOutstanding = plan.principalDue > tolerance || plan.interestDue > tolerance || plan.feeDue > tolerance
            if !hasOutstanding {
                plan.status = .paid
            } else if unresolvedOverdues.contains(where: { $0.plan?.id == plan.id }) {
                plan.status = .overdue
            } else {
                plan.status = .pending
            }
        }

        for event in debt.overdueEvents where !event.isResolved {
            let hasOutstanding = event.overdueFee > tolerance
                || event.penaltyInterest > tolerance
                || event.overduePrincipal > tolerance
                || event.overdueInterest > tolerance
            if !hasOutstanding {
                event.isResolved = true
                event.endDate = event.endDate ?? now
            }
        }

        let hasOpenPlan = debt.repaymentPlans.contains {
            $0.principalDue > tolerance || $0.interestDue > tolerance || $0.feeDue > tolerance
        }
        let hasOpenOverdue = debt.overdueEvents.contains { !$0.isResolved }

        if !hasOpenPlan && !hasOpenOverdue && debt.outstandingPrincipal <= tolerance {
            debt.status = .settled
            debt.endDate = debt.endDate ?? now
            return
        }

        debt.endDate = nil
        debt.status = hasOpenOverdue ? .overdue : .normal
    }

    private static func synchronizeAutomaticOverdues(for debt: Debt, now: Date) {
        for plan in debt.repaymentPlans {
            let hasOutstanding = plan.principalDue > tolerance || plan.interestDue > tolerance || plan.feeDue > tolerance
            let existingEvent = debt.overdueEvents.first(where: { $0.plan?.id == plan.id && !$0.isResolved })

            guard hasOutstanding, let effectiveStartDate = overdueStartDate(for: debt, plan: plan), effectiveStartDate <= now else {
                if let existingEvent, !hasOutstanding {
                    existingEvent.overduePrincipal = 0
                    existingEvent.overdueInterest = 0
                    existingEvent.penaltyInterest = 0
                    existingEvent.overdueFee = 0
                    existingEvent.isResolved = true
                    existingEvent.endDate = now
                }
                continue
            }

            let overduePrincipal = max(plan.principalDue, 0)
            let overdueInterest = max(plan.interestDue, 0)
            let overdueBase = resolvedOverdueBase(principal: overduePrincipal, interest: overdueInterest, debt: debt)
            let penaltyInterest = FinanceEngine.calculateOverduePenalty(
                baseAmount: overdueBase,
                dailyRate: penaltyDailyRate(for: debt),
                startDate: effectiveStartDate,
                endDate: now,
                mode: debt.customRule?.overduePenaltyMode ?? .simple
            )
            let fixedFee = fixedOverdueFee(
                for: debt,
                overduePrincipal: overduePrincipal,
                overdueInterest: overdueInterest
            )

            if let existingEvent {
                existingEvent.startDate = effectiveStartDate
                existingEvent.endDate = nil
                existingEvent.overduePrincipal = overduePrincipal
                existingEvent.overdueInterest = overdueInterest
                existingEvent.penaltyInterest = penaltyInterest
                existingEvent.overdueFee = max(existingEvent.overdueFee, fixedFee)
                existingEvent.isResolved = false
            } else {
                debt.overdueEvents.append(
                    OverdueEvent(
                        startDate: effectiveStartDate,
                        overduePrincipal: overduePrincipal,
                        overdueInterest: overdueInterest,
                        penaltyInterest: penaltyInterest,
                        overdueFee: fixedFee,
                        isResolved: false,
                        debt: debt,
                        plan: plan
                    )
                )
            }
        }
    }

    private static func overdueStartDate(for debt: Debt, plan: RepaymentPlan) -> Date? {
        _ = debt
        return plan.dueDate
    }

    private static func penaltyDailyRate(for debt: Debt) -> Double {
        switch debt.type {
        case .creditCard:
            return max(debt.creditCardDetail?.penaltyDailyRate ?? debt.customRule?.defaultCreditCardPenaltyDailyRate ?? 0, 0)
        case .loan:
            return max(debt.loanDetail?.penaltyDailyRate ?? debt.customRule?.defaultLoanPenaltyDailyRate ?? 0, 0)
        case .privateLending:
            return max(debt.privateLoanDetail?.penaltyDailyRate ?? debt.customRule?.defaultPrivateLoanPenaltyDailyRate ?? 0, 0)
        }
    }

    private static func fixedOverdueFee(for debt: Debt, overduePrincipal _: Double, overdueInterest _: Double) -> Double {
        switch debt.type {
        case .creditCard:
            return max(debt.creditCardDetail?.overdueFeeFlat ?? debt.customRule?.defaultCreditCardOverdueFeeFlat ?? 0, 0)
        case .loan:
            return max(debt.loanDetail?.overdueFeeFlat ?? debt.customRule?.defaultLoanOverdueFeeFlat ?? 0, 0)
        case .privateLending:
            return max(debt.privateLoanDetail?.overdueFeeFlat ?? debt.customRule?.defaultPrivateLoanOverdueFeeFlat ?? 0, 0)
        }
    }

    private static func resolvedOverdueBase(principal: Double, interest: Double, debt: Debt) -> Double {
        switch debt.type {
        case .creditCard:
            switch debt.creditCardDetail?.overdueInterestBase ?? debt.customRule?.defaultCreditCardOverdueInterestBase ?? .principalOnly {
            case .principalOnly:
                return principal
            case .principalAndInterest:
                return principal + interest
            }
        case .loan:
            switch debt.loanDetail?.overdueInterestBase ?? .principalOnly {
            case .principalOnly:
                return principal
            case .principalAndInterest:
                return principal + interest
            }
        case .privateLending:
            switch debt.privateLoanDetail?.overdueInterestBase ?? .principalOnly {
            case .principalOnly:
                return principal
            case .principalAndInterest:
                return principal + interest
            }
        }
    }
}

@MainActor
enum DebtMutationService {
    struct Draft {
        var name: String
        var type: DebtType
        var subtype: String
        var principal: Double
        var nominalAPR: Double
        var startDate: Date
        var endDate: Date? = nil
        var loanMethod: LoanRepaymentMethod
        var termMonths: Int
        var billingDay: Int
        var repaymentDay: Int
        var statementCycles: Int
        var minimumRepaymentRate: Double
        var minimumRepaymentFloor: Double
        var minimumIncludesFees: Bool
        var minimumIncludesPenalty: Bool
        var minimumIncludesInterest: Bool
        var minimumIncludesInstallmentPrincipal: Bool
        var minimumIncludesInstallmentFee: Bool
        var installmentPeriods: Int
        var installmentPrincipal: Double
        var installmentFeeRatePerPeriod: Double
        var installmentFeeMode: CreditCardInstallmentFeeMode
        var penaltyDailyRate: Double
        var overdueFeeFlat: Double
        var creditCardOverdueInterestBase: OverdueInterestBase = .principalOnly
        var creditCardOverduePenaltyMode: OverduePenaltyMode = .simple
        var loanOverdueInterestBase: OverdueInterestBase = .principalOnly
        var privateOverdueInterestBase: OverdueInterestBase = .principalOnly
    }

    static func rebuildDebt(
        modelContext: ModelContext? = nil,
        debt: Debt,
        draft: Draft,
        ruleProfile: CalculationRuleProfile?
    ) throws {
        let previousCreditCardDetail = debt.creditCardDetail
        let preservedStatementRefreshDate = previousCreditCardDetail?.lastStatementRefreshedAt
        let preservedStatementBalance = previousCreditCardDetail?.lastStatementBalance ?? 0
        let preservedStatementMinimumDue = previousCreditCardDetail?.lastStatementMinimumDue ?? 0
        let preservedStatementInstallmentFee = previousCreditCardDetail?.lastStatementInstallmentFee ?? 0

        let effectiveRule = debt.customRule ?? ruleProfile.map {
            let rule = DebtCustomRule(debt: debt)
            RuleProfileResolver.assign($0, to: debt)
            return debt.customRule ?? rule
        } ?? RuleProfileResolver.ensureCustomRule(for: debt)

        let creditCardDetail = draft.type == .creditCard ? CreditCardDebtDetail(
            billingDay: draft.billingDay,
            repaymentDay: draft.repaymentDay,
            graceDays: 0,
            statementCycles: 1,
            interestFreeRule: .statementBased,
            minimumRepaymentRate: draft.minimumRepaymentRate > 0 ? draft.minimumRepaymentRate : effectiveRule.defaultCreditCardMinimumRate,
            minimumRepaymentFloor: draft.minimumRepaymentFloor > 0 ? draft.minimumRepaymentFloor : effectiveRule.defaultCreditCardMinimumFloor,
            minimumIncludesFees: draft.minimumIncludesFees,
            minimumIncludesPenalty: draft.minimumIncludesPenalty,
            minimumIncludesInterest: draft.minimumIncludesInterest,
            minimumIncludesInstallmentPrincipal: draft.minimumIncludesInstallmentPrincipal,
            minimumIncludesInstallmentFee: draft.minimumIncludesInstallmentFee,
            installmentPeriods: draft.subtype == "信用卡分期" ? draft.installmentPeriods : 0,
            installmentPrincipal: draft.subtype == "信用卡分期" ? draft.installmentPrincipal : 0,
            installmentFeeRatePerPeriod: draft.installmentFeeRatePerPeriod,
            installmentFeeMode: draft.installmentFeeMode,
            penaltyDailyRate: draft.penaltyDailyRate > 0 ? draft.penaltyDailyRate : effectiveRule.defaultCreditCardPenaltyDailyRate,
            overdueFeeFlat: draft.overdueFeeFlat > 0 ? draft.overdueFeeFlat : effectiveRule.defaultCreditCardOverdueFeeFlat,
            overdueGraceDays: 0,
            overdueInterestBase: draft.creditCardOverdueInterestBase,
            lastStatementRefreshedAt: preservedStatementRefreshDate,
            lastStatementBalance: preservedStatementBalance,
            lastStatementMinimumDue: preservedStatementMinimumDue,
            lastStatementInstallmentFee: preservedStatementInstallmentFee
        ) : nil

        try FinanceEngine.validateDebtInput(
            name: draft.name,
            type: draft.type,
            principal: draft.principal,
            nominalAPR: draft.nominalAPR,
            startDate: draft.startDate,
            endDate: draft.endDate,
            loanTermMonths: draft.type == .loan ? draft.termMonths : nil,
            creditCardDetail: creditCardDetail
        )

        debt.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        debt.type = draft.type
        debt.subtype = draft.subtype
        debt.principal = draft.principal
        debt.nominalAPR = draft.nominalAPR
        debt.effectiveAPR = FinanceEngine.effectiveAPR(nominalAPR: draft.nominalAPR)
        debt.startDate = draft.startDate
        debt.endDate = draft.type == .loan ? draft.endDate : nil
        debt.customRule = effectiveRule

        if let modelContext {
            debt.repaymentPlans.forEach { modelContext.delete($0) }
            debt.overdueEvents.forEach { modelContext.delete($0) }
            debt.repaymentRecords.forEach { modelContext.delete($0) }
            debt.reminderTasks.forEach { modelContext.delete($0) }
            if let creditCardDetail = debt.creditCardDetail {
                modelContext.delete(creditCardDetail)
            }
            if let loanDetail = debt.loanDetail {
                modelContext.delete(loanDetail)
            }
            if let privateLoanDetail = debt.privateLoanDetail {
                modelContext.delete(privateLoanDetail)
            }
        }

        debt.creditCardDetail = nil
        debt.loanDetail = nil
        debt.privateLoanDetail = nil
        debt.repaymentPlans.removeAll()
        debt.overdueEvents.removeAll()
        debt.repaymentRecords.removeAll()
        debt.reminderTasks.removeAll()

        switch draft.type {
        case .creditCard:
            guard let detail = creditCardDetail else { return }
            debt.creditCardDetail = detail
            let isInstallmentTrack = draft.subtype == "信用卡分期"
            let planCycles = isInstallmentTrack ? max(draft.installmentPeriods, 1) : 1
            let rows = FinanceEngine.generateCreditCardPlan(
                principal: draft.principal,
                annualRate: draft.nominalAPR,
                cycles: planCycles,
                startDate: draft.startDate,
                detail: detail,
                kind: isInstallmentTrack ? .installment : .statement
            )
            debt.repaymentPlans = rows.map { row in
                RepaymentPlan(
                    periodIndex: row.period,
                    dueDate: row.dueDate,
                    statementDate: row.statementDate,
                    principalDue: row.principal,
                    statementPrincipalDue: row.statementPrincipal,
                    installmentPrincipalDue: row.installmentPrincipal,
                    interestDue: row.interest,
                    feeDue: row.fee,
                    minimumDue: row.minimumDue,
                    installmentFeeDue: row.installmentFee,
                    isInterestFree: row.isInterestFree,
                    debt: debt
                )
            }

        case .loan:
            let loanPenaltyDefault = max(draft.nominalAPR / 365 * 1.5, 0)
            debt.loanDetail = LoanDebtDetail(
                repaymentMethod: draft.loanMethod,
                termMonths: draft.termMonths,
                maturityDate: draft.endDate,
                isMortgage: draft.subtype == "抵押贷款",
                penaltyDailyRate: loanPenaltyDefault,
                overdueFeeFlat: effectiveRule.defaultLoanOverdueFeeFlat,
                overdueGraceDays: 0,
                overdueInterestBase: draft.loanOverdueInterestBase
            )
            let rows = FinanceEngine.generateLoanPlan(
                principal: draft.principal,
                annualRate: draft.nominalAPR,
                termMonths: draft.termMonths,
                method: draft.loanMethod,
                startDate: draft.startDate
            )
            debt.repaymentPlans = rows.map { row in
                RepaymentPlan(
                    periodIndex: row.period,
                    dueDate: row.dueDate,
                    principalDue: row.principal,
                    interestDue: row.interest,
                    minimumDue: row.principal + row.interest,
                    debt: debt
                )
            }

        case .privateLending:
            debt.privateLoanDetail = PrivateLoanDebtDetail(
                isInterestFree: draft.subtype == "无息借贷",
                agreedAPR: draft.subtype == "无息借贷" ? 0 : draft.nominalAPR,
                penaltyDailyRate: effectiveRule.defaultPrivateLoanPenaltyDailyRate,
                overdueFeeFlat: effectiveRule.defaultPrivateLoanOverdueFeeFlat,
                overdueGraceDays: 0,
                overdueInterestBase: draft.privateOverdueInterestBase
            )
            debt.repaymentPlans = [
                RepaymentPlan(
                    periodIndex: 1,
                    dueDate: Calendar.current.date(byAdding: .month, value: 12, to: draft.startDate) ?? draft.startDate,
                    principalDue: draft.principal,
                    interestDue: draft.subtype == "无息借贷" ? 0 : draft.principal * draft.nominalAPR,
                    minimumDue: draft.subtype == "无息借贷" ? draft.principal : draft.principal * (1 + draft.nominalAPR),
                    debt: debt
                )
            ]
        }

        DebtLifecycleService.refreshStatus(debt: debt)
        ReminderDomainService.rebuildReminders(for: debt, modelContext: modelContext)
    }
}

@MainActor
enum AppPreferenceService {
    private static let reminderNotificationsEnabledKey = "reminderNotificationsEnabled"
    private static let guidanceMonthlyBudgetKey = "guidanceMonthlyBudget"
    private static let trialStartedAtKey = "subscriptionTrialStartedAt"
    private static let trialReminderLastShownAtKey = "subscriptionTrialReminderLastShownAt"

    static let subscriptionTrialDurationDays = 7
    static let trialReminderIntervalDays = 3

    static var reminderNotificationsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: reminderNotificationsEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: reminderNotificationsEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: reminderNotificationsEnabledKey)
        }
    }

    static var guidanceMonthlyBudget: Double {
        get {
            let value = UserDefaults.standard.double(forKey: guidanceMonthlyBudgetKey)
            return value > 0 ? value : 3000
        }
        set {
            UserDefaults.standard.set(newValue, forKey: guidanceMonthlyBudgetKey)
        }
    }

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static var trialStartedAt: Date {
        get {
            if let date = UserDefaults.standard.object(forKey: trialStartedAtKey) as? Date {
                return date
            }
            let now = Date()
            UserDefaults.standard.set(now, forKey: trialStartedAtKey)
            return now
        }
        set {
            UserDefaults.standard.set(newValue, forKey: trialStartedAtKey)
        }
    }

    static var trialReminderLastShownAt: Date? {
        get {
            UserDefaults.standard.object(forKey: trialReminderLastShownAtKey) as? Date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: trialReminderLastShownAtKey)
        }
    }

    static func markTrialReminderShown(at date: Date = Date()) {
        trialReminderLastShownAt = date
    }
}

@MainActor
enum ReminderNotificationService {
    struct AuthorizationSnapshot {
        var status: UNAuthorizationStatus
        var notificationsEnabled: Bool

        var canSchedule: Bool {
            notificationsEnabled && (status == .authorized || status == .provisional || status == .ephemeral)
        }

        var statusText: String {
            switch status {
            case .authorized:
                return "已授权"
            case .denied:
                return "已拒绝"
            case .notDetermined:
                return "未决定"
            case .provisional:
                return "临时授权"
            case .ephemeral:
                return "临时会话授权"
            @unknown default:
                return "未知状态"
            }
        }
    }

    static func currentAuthorizationSnapshot() async -> AuthorizationSnapshot {
        if AppPreferenceService.isRunningTests {
            return AuthorizationSnapshot(status: .authorized, notificationsEnabled: AppPreferenceService.reminderNotificationsEnabled)
        }

        let settings = await notificationSettings()
        return AuthorizationSnapshot(
            status: settings.authorizationStatus,
            notificationsEnabled: AppPreferenceService.reminderNotificationsEnabled
        )
    }

    static func requestAuthorization() async -> AuthorizationSnapshot {
        if AppPreferenceService.isRunningTests {
            AppPreferenceService.reminderNotificationsEnabled = true
            return AuthorizationSnapshot(status: .authorized, notificationsEnabled: true)
        }

        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted {
            AppPreferenceService.reminderNotificationsEnabled = true
        }
        return await currentAuthorizationSnapshot()
    }

    static func sync(reminders: [ReminderTask], now: Date = Date()) async {
        let identifiers = reminders.map(\.notificationIdentifier)
        for reminder in reminders {
            reminder.lastNotificationSyncAt = now
            reminder.isNotificationScheduled = false
            reminder.notificationErrorMessage = ""
        }

        guard !AppPreferenceService.isRunningTests else { return }

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)

        let snapshot = await currentAuthorizationSnapshot()
        guard snapshot.notificationsEnabled else {
            reminders.forEach { $0.notificationErrorMessage = "用户已关闭应用内提醒调度" }
            return
        }
        guard snapshot.canSchedule else {
            reminders.forEach { $0.notificationErrorMessage = "系统通知权限状态：\(snapshot.statusText)" }
            return
        }

        for reminder in reminders {
            guard !reminder.isCompleted else {
                reminder.notificationErrorMessage = "提醒已完成，不再调度"
                continue
            }
            guard reminder.remindAt > now else {
                reminder.notificationErrorMessage = "提醒时间已过，不再调度"
                continue
            }

            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.message
            content.sound = .default

            let dateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.remindAt)
            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
            let request = UNNotificationRequest(identifier: reminder.notificationIdentifier, content: content, trigger: trigger)

            do {
                try await center.add(request)
                reminder.isNotificationScheduled = true
            } catch {
                reminder.notificationErrorMessage = error.localizedDescription
            }
        }
    }

    static func removeNotifications(forDebtID debtID: UUID) async {
        guard !AppPreferenceService.isRunningTests else { return }
        let center = UNUserNotificationCenter.current()
        let pendingIdentifiers = await pendingRequestIdentifiers(matching: debtID.uuidString)
        center.removePendingNotificationRequests(withIdentifiers: pendingIdentifiers)
        center.removeDeliveredNotifications(withIdentifiers: pendingIdentifiers)
    }

    private static func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private static func pendingRequestIdentifiers(matching token: String) async -> [String] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier).filter { $0.contains(token) })
            }
        }
    }
}

@MainActor
enum CreditCardStatementService {
    struct UpdateResult {
        var rebuiltPlanCount: Int
        var nextMinimumDue: Double
        var nextDueDate: Date?
        var warnings: [String]
    }

    static func applyStatementUpdate(
        debt: Debt,
        refreshedAt: Date,
        statementBalance: Double,
        minimumDue: Double,
        installmentFee: Double,
        modelContext: ModelContext? = nil
    ) -> UpdateResult {
        guard debt.type == .creditCard, let detail = debt.creditCardDetail else {
            return UpdateResult(rebuiltPlanCount: 0, nextMinimumDue: 0, nextDueDate: nil, warnings: ["仅信用卡债务支持账单更新重建"])
        }

        detail.lastStatementRefreshedAt = refreshedAt
        detail.lastStatementBalance = max(statementBalance, 0)
        detail.lastStatementMinimumDue = max(minimumDue, 0)
        detail.lastStatementInstallmentFee = max(installmentFee, 0)

        var warnings: [String] = []
        let hasUnresolvedOverdue = debt.overdueEvents.contains { !$0.isResolved }
        if hasUnresolvedOverdue {
            warnings.append("当前存在未处理逾期，仅重建未逾期的未来计划。")
        }

        let plansToRebuild = debt.repaymentPlans
            .filter { $0.status == .pending }
            .sorted(by: { $0.dueDate < $1.dueDate })

        guard !plansToRebuild.isEmpty else {
            ReminderDomainService.rebuildReminders(for: debt, modelContext: modelContext)
            return UpdateResult(
                rebuiltPlanCount: 0,
                nextMinimumDue: max(minimumDue, 0),
                nextDueDate: nil,
                warnings: warnings.isEmpty ? ["当前没有可重建的待还信用卡计划。"] : warnings
            )
        }

        let firstPeriodIndex = plansToRebuild.first?.periodIndex ?? 1
        let cycles = max(plansToRebuild.count, 1)
        let track: CreditCardPlanKind = debt.subtype == "信用卡分期" ? .installment : .statement
        let carryoverPrincipal = plansToRebuild.reduce(0) { $0 + max($1.principalDue, 0) }
        let carryoverPlanFees = plansToRebuild.reduce(0) { $0 + max($1.feeDue, 0) }
        let previousDueDate = plansToRebuild.first?.dueDate
        let accruedInterest = previousDueDate.map {
            FinanceEngine.calculateCreditCardRevolvingInterest(
                principal: carryoverPrincipal,
                annualRate: debt.nominalAPR,
                from: $0,
                to: refreshedAt
            )
        } ?? 0
        let rebuildDetail = CreditCardDebtDetail(
            billingDay: detail.billingDay,
            repaymentDay: detail.repaymentDay,
            graceDays: detail.graceDays,
            statementCycles: 1,
            interestFreeRule: detail.interestFreeRule,
            minimumRepaymentRate: detail.minimumRepaymentRate,
            minimumRepaymentFloor: detail.minimumRepaymentFloor,
            minimumIncludesFees: detail.minimumIncludesFees,
            minimumIncludesPenalty: detail.minimumIncludesPenalty,
            minimumIncludesInterest: detail.minimumIncludesInterest,
            minimumIncludesInstallmentPrincipal: detail.minimumIncludesInstallmentPrincipal,
            minimumIncludesInstallmentFee: detail.minimumIncludesInstallmentFee,
            installmentPeriods: track == .installment ? cycles : detail.installmentPeriods,
            installmentPrincipal: detail.installmentPrincipal,
            installmentFeeRatePerPeriod: detail.installmentFeeRatePerPeriod,
            installmentFeeMode: detail.installmentFeeMode,
            penaltyDailyRate: detail.penaltyDailyRate,
            overdueFeeFlat: detail.overdueFeeFlat,
            overdueGraceDays: detail.overdueGraceDays,
            overdueInterestBase: detail.overdueInterestBase,
            lastStatementRefreshedAt: detail.lastStatementRefreshedAt,
            lastStatementBalance: detail.lastStatementBalance,
            lastStatementMinimumDue: detail.lastStatementMinimumDue,
            lastStatementInstallmentFee: detail.lastStatementInstallmentFee
        )
        let rows = FinanceEngine.generateCreditCardPlan(
            principal: max(statementBalance, 0.01),
            annualRate: debt.nominalAPR,
            cycles: cycles,
            startDate: refreshedAt,
            detail: rebuildDetail,
            kind: track
        )

        if let modelContext {
            plansToRebuild.forEach { modelContext.delete($0) }
        }
        debt.repaymentPlans.removeAll { plan in
            plansToRebuild.contains(where: { $0.id == plan.id })
        }

        let rebuiltPlans = rows.enumerated().map { offset, sourceRow in
            var row = sourceRow
            if offset == 0 {
                row.interest = round((row.interest + accruedInterest) * 100) / 100
                row.fee = round((row.fee + max(carryoverPlanFees, installmentFee)) * 100) / 100
                row.installmentFee = round((row.installmentFee + installmentFee) * 100) / 100
                row.isInterestFree = row.isInterestFree && row.interest == 0
                row.minimumDue = max(
                    minimumDue,
                    FinanceEngine.calculateCreditCardMinimumDue(
                        statementPrincipal: row.statementPrincipal,
                        installmentPrincipal: row.installmentPrincipal,
                        statementInterest: row.interest,
                        statementFees: row.fee,
                        installmentFee: row.installmentFee,
                        penaltyInterest: 0,
                        minimumRate: detail.minimumRepaymentRate,
                        minimumFloor: detail.minimumRepaymentFloor,
                        includesFees: detail.minimumIncludesFees,
                        includesPenalty: detail.minimumIncludesPenalty,
                        includesInterest: detail.minimumIncludesInterest,
                        includesInstallmentPrincipal: detail.minimumIncludesInstallmentPrincipal,
                        includesInstallmentFee: detail.minimumIncludesInstallmentFee
                    )
                )
            }

            return RepaymentPlan(
                periodIndex: firstPeriodIndex + offset,
                dueDate: row.dueDate,
                statementDate: row.statementDate,
                principalDue: row.principal,
                statementPrincipalDue: row.statementPrincipal,
                installmentPrincipalDue: row.installmentPrincipal,
                interestDue: row.interest,
                feeDue: row.fee,
                minimumDue: row.minimumDue,
                installmentFeeDue: row.installmentFee,
                isInterestFree: row.isInterestFree,
                debt: debt
            )
        }

        debt.repaymentPlans.append(contentsOf: rebuiltPlans)
        debt.principal = max(statementBalance, 0)
        DebtLifecycleService.refreshStatus(debt: debt)
        ReminderDomainService.rebuildReminders(for: debt, now: refreshedAt, modelContext: modelContext)

        return UpdateResult(
            rebuiltPlanCount: rebuiltPlans.count,
            nextMinimumDue: rebuiltPlans.first?.minimumDue ?? max(minimumDue, 0),
            nextDueDate: rebuiltPlans.first?.dueDate,
            warnings: accruedInterest > 0 ? warnings + ["检测到未全额还款，已自动补计循环利息。"] : warnings
        )
    }
}

@MainActor
enum ReminderDomainService {
    private static let repaymentLeadDaysDefault = 3
    private static let statementOffsetDaysDefault = 1

    static func rebuildReminders(
        for debt: Debt,
        now: Date = Date(),
        modelContext: ModelContext? = nil
    ) {
        if let modelContext {
            debt.reminderTasks.forEach { modelContext.delete($0) }
        }
        debt.reminderTasks.removeAll()

        guard debt.status != .settled else { return }

        let leadDays = debt.customRule?.repaymentReminderLeadDays ?? repaymentLeadDaysDefault
        let statementOffset = debt.customRule?.creditCardStatementReminderOffsetDays ?? statementOffsetDaysDefault
        let requiresStatementRefresh = debt.customRule?.requireCreditCardStatementRefresh ?? true
        var generatedTasks: [ReminderTask] = []
        var deduplicationKeys = Set<String>()

        for plan in debt.repaymentPlans
            .filter({ $0.status != .paid })
            .sorted(by: { $0.dueDate < $1.dueDate }) {
            let repaymentKey = "repayment-\(debt.id.uuidString)-\(plan.id.uuidString)"
            let remindAt = Calendar.current.date(byAdding: .day, value: -leadDays, to: plan.dueDate) ?? plan.dueDate
            appendReminder(
                into: &generatedTasks,
                deduplicationKeys: &deduplicationKeys,
                reminder: ReminderTask(
                    title: "还款提醒 · \(debt.name)",
                    message: "请在到期日前处理第\(plan.periodIndex)期还款，计划到期日为\(formattedDate(plan.dueDate))。",
                    remindAt: remindAt,
                    category: .repaymentDue,
                    deduplicationKey: repaymentKey,
                    referenceDate: plan.dueDate,
                    isCompleted: plan.status == .paid,
                    createdAt: now,
                    debt: debt,
                    plan: plan
                )
            )

            if debt.type == .creditCard,
               requiresStatementRefresh,
               let statementDate = plan.statementDate,
               shouldCreateStatementReminder(for: debt, statementDate: statementDate) {
                let statementKey = "statement-\(debt.id.uuidString)-\(statementDate.timeIntervalSince1970)"
                let statementReminderDate = Calendar.current.date(byAdding: .day, value: statementOffset, to: statementDate) ?? statementDate
                appendReminder(
                    into: &generatedTasks,
                    deduplicationKeys: &deduplicationKeys,
                    reminder: ReminderTask(
                        title: "更新信用卡账单 · \(debt.name)",
                        message: "账单日已过，请核对最新账单金额、最低还款和分期变化，并更新这笔信用卡债务。",
                        remindAt: statementReminderDate,
                        category: .creditCardStatementRefresh,
                        deduplicationKey: statementKey,
                        referenceDate: statementDate,
                        isCompleted: false,
                        createdAt: now,
                        debt: debt,
                        plan: plan
                    )
                )
            }
        }

        debt.reminderTasks = generatedTasks
        if let modelContext {
            generatedTasks.forEach { modelContext.insert($0) }
        }
        Task { @MainActor in
            await ReminderNotificationService.sync(reminders: debt.reminderTasks)
        }
    }

    static func markCompleted(_ reminder: ReminderTask, completedAt: Date = Date()) {
        reminder.isCompleted = true
        reminder.completedAt = completedAt
    }

    static func markCreditCardStatementUpdated(
        debt: Debt,
        refreshedAt: Date = Date(),
        statementBalance: Double,
        minimumDue: Double,
        installmentFee: Double,
        modelContext: ModelContext? = nil
    ) -> CreditCardStatementService.UpdateResult {
        let result = CreditCardStatementService.applyStatementUpdate(
            debt: debt,
            refreshedAt: refreshedAt,
            statementBalance: statementBalance,
            minimumDue: minimumDue,
            installmentFee: installmentFee,
            modelContext: modelContext
        )
        for reminder in debt.reminderTasks where reminder.category == .creditCardStatementRefresh {
            if let referenceDate = reminder.referenceDate, referenceDate <= refreshedAt {
                markCompleted(reminder, completedAt: refreshedAt)
            }
        }
        return result
    }

    private static func shouldCreateStatementReminder(for debt: Debt, statementDate: Date) -> Bool {
        guard let detail = debt.creditCardDetail else { return false }
        if let lastRefresh = detail.lastStatementRefreshedAt, lastRefresh >= statementDate {
            return false
        }
        return true
    }

    private static func appendReminder(
        into reminders: inout [ReminderTask],
        deduplicationKeys: inout Set<String>,
        reminder: ReminderTask
    ) {
        guard !deduplicationKeys.contains(reminder.deduplicationKey) else { return }
        deduplicationKeys.insert(reminder.deduplicationKey)
        reminders.append(reminder)
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

@MainActor
enum DebtGuidanceService {
    struct ActionItem: Identifiable {
        let id = UUID()
        var title: String
        var detail: String
        var priority: Int
    }

    struct Alternative: Identifiable {
        var id: StrategyMethod { method }
        var method: StrategyMethod
        var totalInterest: Double
        var payoffDate: Date
        var isFeasible: Bool
        var reason: String?
    }

    struct Recommendation {
        var monthlyBudget: Double
        var minimumFeasibleBudget: Double
        var recommendedMethod: StrategyMethod?
        var payoffDate: Date?
        var totalInterest: Double
        var monthsToPayoff: Int
        var interestSavingsVsWorst: Double
        var monthsSavedVsSlowest: Int
        var actions: [ActionItem]
        var risks: [String]
        var alternatives: [Alternative]

        var isFeasible: Bool {
            recommendedMethod != nil
        }
    }

    static func build(
        debts: [Debt],
        monthlyBudget: Double,
        startDate: Date = Date(),
        constraints: FinanceEngine.StrategyConstraints
    ) -> Recommendation {
        let detailed = FinanceEngine.compareStrategiesDetailed(
            debts: debts,
            monthlyBudget: monthlyBudget,
            startDate: startDate,
            constraints: constraints
        )

        let alternatives: [Alternative] = StrategyMethod.allCases.compactMap { method in
            guard let result = detailed[method] else { return nil }
            let timeline = FinanceEngine.decodeStrategyTimeline(from: result.timelineJSON)
            return Alternative(
                method: method,
                totalInterest: result.totalInterest,
                payoffDate: result.payoffDate,
                isFeasible: timeline?.completed ?? false,
                reason: timeline?.infeasibleReason
            )
        }

        let feasibleAlternatives = alternatives.filter(\.isFeasible)
        let recommended = feasibleAlternatives.min {
            if Calendar.current.compare($0.payoffDate, to: $1.payoffDate, toGranularity: .day) == .orderedSame {
                return $0.totalInterest < $1.totalInterest
            }
            return $0.payoffDate < $1.payoffDate
        }

        let minimumDueRequirement = constraints.includeMinimumDue
            ? debts.reduce(0) {
                $0 + max(
                    $1.repaymentPlans.filter { $0.status != .paid }.sorted(by: { $0.dueDate < $1.dueDate }).first?.minimumDue ?? 0,
                    0
                )
            }
            : 0
        let overdueRequirement = constraints.includeOverduePenalty && constraints.prioritizeOverdueBalances
            ? debts.reduce(0) { partial, debt in
                partial + debt.overdueEvents.filter { !$0.isResolved }.reduce(0) { $0 + $1.overdueFee + $1.penaltyInterest + $1.overdueInterest }
            }
            : 0
        let minimumFeasibleBudget = constraints.minimumMonthlyReserve
            + (constraints.requireFullOverdueCoverage ? overdueRequirement : 0)
            + (constraints.requireFullMinimumCoverage ? minimumDueRequirement : 0)

        var actions: [ActionItem] = []
        let overdueDebts = debts.filter { $0.overdueEvents.contains(where: { !$0.isResolved }) }
        for (index, debt) in overdueDebts.sorted(by: {
            let left = $0.overdueEvents.filter { !$0.isResolved }.reduce(0) { $0 + $1.overdueFee + $1.penaltyInterest + $1.overdueInterest }
            let right = $1.overdueEvents.filter { !$0.isResolved }.reduce(0) { $0 + $1.overdueFee + $1.penaltyInterest + $1.overdueInterest }
            return left > right
        }).prefix(3).enumerated() {
            let overdueCost = debt.overdueEvents.filter { !$0.isResolved }.reduce(0) { $0 + $1.overdueFee + $1.penaltyInterest + $1.overdueInterest }
            actions.append(ActionItem(title: "优先处理逾期：\(debt.name)", detail: "当前逾期成本约 ¥\(currencyText(overdueCost))，建议立即止损。", priority: index + 1))
        }

        let statementRefreshDebts = debts.filter { debt in
            debt.reminderTasks.contains { !$0.isCompleted && $0.category == .creditCardStatementRefresh }
        }
        for debt in statementRefreshDebts.prefix(2) {
            actions.append(ActionItem(title: "更新账单：\(debt.name)", detail: "账单日已过，请先更新最新账单后再执行清偿策略。", priority: 2))
        }

        if let recommendedMethod = recommended?.method,
           let recommendedResult = detailed[recommendedMethod],
           let timeline = FinanceEngine.decodeStrategyTimeline(from: recommendedResult.timelineJSON),
           let firstTarget = timeline.records.first?.targetedDebtName {
            actions.append(ActionItem(title: "本月执行重点", detail: "在满足约束后，将额外预算优先投入 \(firstTarget)。", priority: 3))
        }

        if monthlyBudget + 0.01 < minimumFeasibleBudget {
            actions.append(
                ActionItem(
                    title: "先补足执行预算",
                    detail: "当前月预算为 ¥\(currencyText(monthlyBudget))，至少需要 ¥\(currencyText(minimumFeasibleBudget)) 才能满足硬约束；若短期无法补足，建议尽快联系债权方协商并寻求专业帮助。",
                    priority: 1
                )
            )
        }

        let nextDuePlans = debts
            .flatMap { debt in debt.repaymentPlans.filter { $0.status != .paid }.map { (debt.name, $0) } }
            .sorted(by: { $0.1.dueDate < $1.1.dueDate })
        if let nextDue = nextDuePlans.first {
            actions.append(ActionItem(title: "最近一期还款", detail: "\(nextDue.0) 将于 \(formattedDate(nextDue.1.dueDate)) 到期，最低应还 ¥\(currencyText(nextDue.1.minimumDue))。", priority: 2))
        }

        var risks: [String] = []
        if overdueRequirement > 0 {
            risks.append("当前存在未结清逾期，罚息与逾期费用仍在累积。")
        }
        if !statementRefreshDebts.isEmpty {
            risks.append("存在未更新的信用卡账单，若不先更新，策略结果可能偏差。")
        }
        if recommended == nil {
            risks.append(feasibleAlternatives.isEmpty ? (alternatives.first(where: { !$0.isFeasible })?.reason ?? "当前预算下暂无完全可执行策略。") : "暂无推荐策略。")
        }
        if monthlyBudget + 0.01 < minimumFeasibleBudget {
            risks.append("当前预算低于最低还款硬约束，建议尽快联系债权方协商并寻求专业帮助。")
        }
        let weightedAPR = DataStatisticsDomainService.build(debts: debts, records: [], overdueEvents: debts.flatMap(\.overdueEvents)).weightedAverageAPR
        if weightedAPR > 0.18 {
            risks.append("当前债务组合加权年化较高，建议优先偿还高利率债务。")
        }

        let worstFeasibleInterest = feasibleAlternatives.map(\.totalInterest).max() ?? recommended?.totalInterest ?? 0
        let slowestFeasiblePayoff = feasibleAlternatives.map(\.payoffDate).max() ?? recommended?.payoffDate ?? startDate
        let monthsToPayoff = recommended.map { Calendar.current.dateComponents([.month], from: startDate, to: $0.payoffDate).month ?? 0 } ?? 0
        let monthsSavedVsSlowest = recommended.map {
            max(Calendar.current.dateComponents([.month], from: $0.payoffDate, to: slowestFeasiblePayoff).month ?? 0, 0)
        } ?? 0

        return Recommendation(
            monthlyBudget: monthlyBudget,
            minimumFeasibleBudget: minimumFeasibleBudget,
            recommendedMethod: recommended?.method,
            payoffDate: recommended?.payoffDate,
            totalInterest: recommended?.totalInterest ?? 0,
            monthsToPayoff: monthsToPayoff,
            interestSavingsVsWorst: max(worstFeasibleInterest - (recommended?.totalInterest ?? worstFeasibleInterest), 0),
            monthsSavedVsSlowest: monthsSavedVsSlowest,
            actions: actions.sorted(by: { $0.priority < $1.priority }),
            risks: risks,
            alternatives: alternatives
        )
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func currencyText(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

@MainActor
enum RepaymentDomainService {
    private static let tolerance = 0.01

    struct ExecutionResult {
        var record: RepaymentRecord
        var remainingAmount: Double
    }

    private static func syncOverdueEvent(_ event: OverdueEvent, settledAt: Date) {
        let resolved = event.overdueFee <= tolerance
            && event.penaltyInterest <= tolerance
            && event.overduePrincipal <= tolerance
            && event.overdueInterest <= tolerance
        event.isResolved = resolved
        event.endDate = resolved ? (event.endDate ?? settledAt) : nil
    }

    static func applyRepayment(
        debt: Debt,
        amount: Double,
        note: String,
        paidAt: Date,
        allocationOrder: PaymentAllocationOrder
    ) -> ExecutionResult {
        var remaining = max(amount, 0)
        var appliedOverdueFee = 0.0
        var appliedPenalty = 0.0
        var appliedInterest = 0.0
        var appliedPrincipal = 0.0
        var appliedPlanFee = 0.0

        let unresolved = debt.overdueEvents
            .filter { !$0.isResolved }
            .sorted(by: { $0.startDate < $1.startDate })

        func applyToOverdueFees() {
            for event in unresolved where remaining > 0 {
                let applied = min(max(event.overdueFee, 0), remaining)
                event.overdueFee = max(event.overdueFee - applied, 0)
                remaining -= applied
                appliedOverdueFee += applied
                syncOverdueEvent(event, settledAt: paidAt)
            }
        }

        func applyToPenalty() {
            for event in unresolved where remaining > 0 {
                let applied = min(max(event.penaltyInterest, 0), remaining)
                event.penaltyInterest = max(event.penaltyInterest - applied, 0)
                remaining -= applied
                appliedPenalty += applied
                syncOverdueEvent(event, settledAt: paidAt)
            }
        }

        var primaryPlan: RepaymentPlan?
        let planQueue = debt.repaymentPlans
            .filter { $0.status != .paid }
            .sorted(by: { $0.dueDate < $1.dueDate })

        func applyToPlanInterestAndFees() {
            for plan in planQueue where remaining > 0 {
                if primaryPlan == nil { primaryPlan = plan }

                let feeDemand = max(plan.feeDue, 0)
                let feeApplied = min(feeDemand, remaining)
                plan.feeDue = max(plan.feeDue - feeApplied, 0)
                if plan.installmentFeeDue > 0 {
                    plan.installmentFeeDue = max(plan.installmentFeeDue - feeApplied, 0)
                }
                remaining -= feeApplied
                appliedPlanFee += feeApplied

                let interestApplied = min(max(plan.interestDue, 0), remaining)
                plan.interestDue = max(plan.interestDue - interestApplied, 0)
                remaining -= interestApplied
                appliedInterest += interestApplied

                for event in unresolved where event.plan?.id == plan.id {
                    event.overduePrincipal = max(plan.principalDue, 0)
                    event.overdueInterest = max(plan.interestDue, 0)
                    syncOverdueEvent(event, settledAt: paidAt)
                }
            }
        }

        func applyToPlanPrincipal() {
            for plan in planQueue where remaining > 0 {
                if primaryPlan == nil { primaryPlan = plan }

                let principalApplied = min(max(plan.principalDue, 0), remaining)
                plan.principalDue = max(plan.principalDue - principalApplied, 0)
                if plan.statementPrincipalDue > 0 {
                    let statementPart = min(plan.statementPrincipalDue, principalApplied)
                    plan.statementPrincipalDue = max(plan.statementPrincipalDue - statementPart, 0)
                    let installmentPart = principalApplied - statementPart
                    if installmentPart > 0 {
                        plan.installmentPrincipalDue = max(plan.installmentPrincipalDue - installmentPart, 0)
                    }
                } else if plan.installmentPrincipalDue > 0 {
                    plan.installmentPrincipalDue = max(plan.installmentPrincipalDue - principalApplied, 0)
                }
                remaining -= principalApplied
                appliedPrincipal += principalApplied

                for event in unresolved where event.plan?.id == plan.id {
                    event.overduePrincipal = max(plan.principalDue, 0)
                    event.overdueInterest = max(plan.interestDue, 0)
                    syncOverdueEvent(event, settledAt: paidAt)
                }
            }
        }

        for component in allocationOrder.components {
            switch component {
            case .overdueFee:
                applyToOverdueFees()
            case .penaltyInterest:
                applyToPenalty()
            case .interest:
                applyToPlanInterestAndFees()
            case .principal:
                applyToPlanPrincipal()
            }

            if remaining <= 0 { break }
        }

        if remaining > 0 {
            applyToPlanInterestAndFees()
            applyToPlanPrincipal()
        }

        if planQueue.isEmpty && remaining > 0 {
            let directPrincipalApplied = min(max(debt.principal, 0), remaining)
            debt.principal = max(debt.principal - directPrincipalApplied, 0)
            remaining -= directPrincipalApplied
            appliedPrincipal += directPrincipalApplied
        }

        DebtLifecycleService.refreshStatus(debt: debt)

        let appliedAmount = appliedOverdueFee + appliedPenalty + appliedPlanFee + appliedInterest + appliedPrincipal
        let allocation = PaymentAllocation(
            overdueFee: appliedOverdueFee,
            penaltyInterest: appliedPenalty,
            interest: appliedInterest,
            principal: appliedPrincipal
        )

        let payload: [String: Any] = [
            "allocation": [
                "overdueFee": allocation.overdueFee,
                "penaltyInterest": allocation.penaltyInterest,
                "interest": allocation.interest,
                "fee": appliedPlanFee,
                "principal": allocation.principal
            ],
            "inputAmount": amount,
            "appliedAmount": appliedAmount,
            "remainingAmount": remaining,
            "calculatedAt": ISO8601DateFormatter().string(from: paidAt)
        ]
        let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: [])
        let allocationJSON = jsonData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        let record = RepaymentRecord(
            paidAt: paidAt,
            amount: appliedAmount,
            allocationJSON: allocationJSON,
            note: note,
            debt: debt,
            plan: primaryPlan
        )

        ReminderDomainService.rebuildReminders(for: debt)

        return ExecutionResult(record: record, remainingAmount: remaining)
    }
}

@MainActor
enum OverdueDomainService {
    private static let tolerance = 0.01

    struct RegistrationResult {
        var event: OverdueEvent
        var isNew: Bool
    }

    static func registerOverdue(
        debt: Debt,
        startDate: Date,
        penaltyMode: OverduePenaltyMode,
        dailyRate: Double,
        fixedFee: Double
    ) -> RegistrationResult {
        let now = Date()
        let targetPlan = debt.repaymentPlans
            .filter {
                ($0.status == .pending || $0.status == .overdue)
                && ($0.principalDue > tolerance || $0.interestDue > tolerance || $0.feeDue > tolerance)
            }
            .sorted(by: { $0.dueDate < $1.dueDate })
            .first

        let principal = max(targetPlan?.principalDue ?? debt.outstandingPrincipal, 0)
        let interest = max(targetPlan?.interestDue ?? 0, 0)
        let fee = max(fixedFee, 0)
        let effectiveStartDate = max(startDate, targetPlan?.dueDate ?? startDate)
        let overdueBase = resolvedOverdueBase(principal: principal, interest: interest, debt: debt)

        if let existing = debt.overdueEvents.first(where: { !$0.isResolved && $0.plan?.id == targetPlan?.id }) {
            existing.startDate = effectiveStartDate
            existing.overduePrincipal = principal
            existing.overdueInterest = interest
            existing.penaltyInterest = FinanceEngine.calculateOverduePenalty(
                baseAmount: overdueBase,
                dailyRate: dailyRate,
                startDate: existing.startDate,
                endDate: now,
                mode: penaltyMode
            )
            existing.overdueFee = max(existing.overdueFee, fee)
            existing.isResolved = false
            existing.endDate = nil
            targetPlan?.status = .overdue
            DebtLifecycleService.refreshStatus(debt: debt)
            ReminderDomainService.rebuildReminders(for: debt)
            return RegistrationResult(event: existing, isNew: false)
        }

        let event = OverdueEvent(
            startDate: effectiveStartDate,
            overduePrincipal: principal,
            overdueInterest: interest,
            penaltyInterest: FinanceEngine.calculateOverduePenalty(
                baseAmount: overdueBase,
                dailyRate: dailyRate,
                startDate: effectiveStartDate,
                endDate: now,
                mode: penaltyMode
            ),
            overdueFee: fee,
            isResolved: overdueBase <= tolerance && fee <= tolerance,
            debt: debt,
            plan: targetPlan
        )

        if event.isResolved {
            event.endDate = now
        } else {
            targetPlan?.status = .overdue
        }

        DebtLifecycleService.refreshStatus(debt: debt)
        ReminderDomainService.rebuildReminders(for: debt)
        return RegistrationResult(event: event, isNew: true)
    }

    private static func resolvedOverdueBase(principal: Double, interest: Double, debt: Debt) -> Double {
        switch debt.type {
        case .creditCard:
            switch debt.creditCardDetail?.overdueInterestBase ?? debt.customRule?.defaultCreditCardOverdueInterestBase ?? .principalOnly {
            case .principalOnly:
                return principal
            case .principalAndInterest:
                return principal + interest
            }
        case .loan, .privateLending:
            let base: OverdueInterestBase = debt.loanDetail?.overdueInterestBase
                ?? debt.privateLoanDetail?.overdueInterestBase
                ?? .principalOnly
            switch base {
            case .principalOnly:
                return principal
            case .principalAndInterest:
                return principal + interest
            }
        }
    }
}
