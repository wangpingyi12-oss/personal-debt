import Foundation
import StoreKit
import SwiftData

enum SubscriptionAppStoreConfig {
    // 在 App Store Connect 创建订阅后，只需要回填这里的商品 ID 和展示文案。
    static let monthlyProductID = "com.personaldebt.pro.monthly"
    static let yearlyProductID = "com.personaldebt.pro.yearly"
    static let genericIntroMessage = "如有试用或优惠资格，购买页会自动显示"
}

struct SubscriptionCatalogItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let fallbackPrice: String
    let introBadgeText: String
    let benefits: [String]
    let sortOrder: Int
}

struct SubscriptionProductPresentation: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let priceText: String
    let introBadgeText: String?
    let benefits: [String]
    let product: Product?

    var isAvailableForPurchase: Bool {
        product != nil
    }
}

@MainActor
struct SubscriptionStatusAudit {
    let currentEntitlement: SubscriptionEntitlement?
    let entitledCount: Int
    let staleCount: Int
    let invalidCount: Int
    let issues: [String]

    var headline: String {
        currentEntitlement?.status.rawValue ?? SubscriptionLifecycleStatus.inactive.rawValue
    }

    var recommendation: String {
        if let currentEntitlement {
            switch currentEntitlement.status {
            case .trial:
                if let expireAt = currentEntitlement.expireAt {
                    return "试用将于 \(expireAt.formatted(date: .abbreviated, time: .omitted)) 结束，建议提前确认是否继续订阅。"
                }
                return "当前正在试用中，建议在试用期结束前完成一次订阅验证。"
            case .active:
                return currentEntitlement.willAutoRenew ? "订阅已生效且开启自动续费，建议定期验证交易状态。" : "订阅仍然有效，但已关闭自动续费，建议在到期前决定是否续订。"
            case .expiringSoon:
                return "订阅即将到期，请及时确认续费设置或切换套餐。"
            case .gracePeriod:
                return "当前处于宽限期，服务暂未中断，请尽快更新支付方式。"
            case .billingRetry:
                return "当前处于扣费重试期，建议立即恢复支付能力并执行恢复购买。"
            case .expired:
                return "订阅已过期，可以重新购买或恢复交易进行校验。"
            case .revoked:
                return "该订阅已被撤销或退款，如有异议请在 App Store 订阅管理中处理。"
            case .verificationFailed:
                return "存在验证失败记录，建议立即重新同步并核对交易签名。"
            case .inactive:
                return "当前未开通订阅，可选择适合的套餐开始试用或购买。"
            }
        }
        return "当前未检测到有效订阅，可直接购买或恢复已购项目。"
    }
}

@MainActor
struct SubscriptionSyncResult {
    let products: [SubscriptionProductPresentation]
    let message: String
    let warnings: [String]
}

@MainActor
struct SubscriptionPurchaseResult {
    enum State {
        case success
        case pending
        case cancelled
        case unavailable
        case failed
    }

    let state: State
    let message: String
    let products: [SubscriptionProductPresentation]
}

@MainActor
struct SubscriptionAccessSnapshot {
    let hasAccess: Bool
    let isInTrial: Bool
    let trialEndsAt: Date
    let trialDaysRemaining: Int
    let shouldShowTrialReminder: Bool
    let currentEntitlement: SubscriptionEntitlement?

    var trialStatusText: String {
        if isInTrial {
            return "免费试用剩余 \(max(trialDaysRemaining, 0)) 天"
        }
        return "免费试用已结束"
    }

    var blockingMessage: String {
        if hasAccess {
            return ""
        }
        return "免费试用已结束，请订阅后继续使用 App。"
    }

    var trialReminderMessage: String {
        "你当前处于免费试用期。为避免到期影响使用，建议提前完成订阅。"
    }
}

@MainActor
enum SubscriptionAccessPolicy {
    static func resolve(entitlements: [SubscriptionEntitlement], now: Date = Date()) -> SubscriptionAccessSnapshot {
        let audit = SubscriptionLifecycleAuditService.audit(entitlements: entitlements, now: now)
        let activeEntitlement = audit.currentEntitlement
        let hasEntitlement = activeEntitlement?.status.isEntitled ?? false

        let trialStart = AppPreferenceService.trialStartedAt
        let trialDays = max(AppPreferenceService.subscriptionTrialDurationDays, 1)
        let reminderDays = max(AppPreferenceService.trialReminderIntervalDays, 1)
        let trialEndsAt = Calendar.current.date(byAdding: .day, value: trialDays, to: trialStart) ?? trialStart
        let isInTrial = now < trialEndsAt
        let remainingSeconds = max(trialEndsAt.timeIntervalSince(now), 0)
        let trialDaysRemaining = Int(ceil(remainingSeconds / 86_400))

        let reminderGraceDate = Calendar.current.date(byAdding: .day, value: reminderDays, to: trialStart) ?? trialStart
        let reminderInterval: TimeInterval = TimeInterval(reminderDays) * 86_400
        let shouldShowTrialReminder: Bool = {
            guard isInTrial, now >= reminderGraceDate else { return false }
            guard let lastShown = AppPreferenceService.trialReminderLastShownAt else { return true }
            return now.timeIntervalSince(lastShown) >= reminderInterval
        }()

        return SubscriptionAccessSnapshot(
            hasAccess: hasEntitlement || isInTrial,
            isInTrial: isInTrial,
            trialEndsAt: trialEndsAt,
            trialDaysRemaining: trialDaysRemaining,
            shouldShowTrialReminder: shouldShowTrialReminder,
            currentEntitlement: activeEntitlement
        )
    }
}

@MainActor
private struct SubscriptionTransactionSnapshot {
    let transaction: Transaction
    let verificationState: SubscriptionVerificationState
    let note: String
    let isTrialPeriod: Bool
}

@MainActor
enum SubscriptionCatalogService {
    static let catalog: [SubscriptionCatalogItem] = [
        SubscriptionCatalogItem(
            id: SubscriptionAppStoreConfig.monthlyProductID,
            title: "连续包月",
            subtitle: "适合按月灵活使用完整债务管理能力",
            fallbackPrice: "¥10/月",
            introBadgeText: SubscriptionAppStoreConfig.genericIntroMessage,
            benefits: ["解锁完整债务测算与策略分析", "适合短周期集中整理债务", "支持通过 Apple 账号恢复已购订阅"],
            sortOrder: 0
        ),
        SubscriptionCatalogItem(
            id: SubscriptionAppStoreConfig.yearlyProductID,
            title: "连续包年",
            subtitle: "适合长期持续使用完整债务管理能力",
            fallbackPrice: "¥80/年",
            introBadgeText: SubscriptionAppStoreConfig.genericIntroMessage,
            benefits: ["解锁完整债务测算与策略分析", "适合长期持续跟踪还款执行", "相较包月更适合长期使用"],
            sortOrder: 1
        )
    ]

    static var knownProductIDs: Set<String> {
        Set(catalog.map(\.id))
    }

    static func metadata(for productID: String) -> SubscriptionCatalogItem {
        catalog.first(where: { $0.id == productID })
            ?? SubscriptionCatalogItem(
                id: productID,
                title: productID,
                subtitle: "未在本地目录中配置说明",
                fallbackPrice: "待配置",
                introBadgeText: "",
                benefits: ["请在 App Store Connect 或 StoreKit 配置文件中补齐商品信息"],
                sortOrder: .max
            )
    }

    static func loadProducts() async -> [SubscriptionProductPresentation] {
        let storeProducts: [Product]
        do {
            storeProducts = try await Product.products(for: catalog.map(\.id))
        } catch {
            storeProducts = []
        }

        let productMap = Dictionary(uniqueKeysWithValues: storeProducts.map { ($0.id, $0) })
        var presentations: [SubscriptionProductPresentation] = []

        for item in catalog.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let product = productMap[item.id]
            let isEligible = await introEligibility(for: product)
            presentations.append(
                SubscriptionProductPresentation(
                    id: item.id,
                    title: product?.displayName ?? item.title,
                    subtitle: item.subtitle,
                    priceText: product?.displayPrice ?? item.fallbackPrice,
                    introBadgeText: isEligible ? item.introBadgeText : nil,
                    benefits: item.benefits,
                    product: product
                )
            )
        }

        return presentations
    }

    private static func introEligibility(for product: Product?) async -> Bool {
        guard let product, let subscription = product.subscription else { return false }
        return await subscription.isEligibleForIntroOffer
    }
}

@MainActor
enum SubscriptionLifecycleAuditService {
    private static let staleInterval: TimeInterval = 24 * 60 * 60

    static func resolveStatus(
        renewalPhase: SubscriptionRenewalPhase,
        expirationDate: Date?,
        gracePeriodExpirationDate: Date?,
        revokedDate: Date?,
        willAutoRenew: Bool,
        isVerified: Bool,
        isTrialPeriod: Bool,
        now: Date = Date()
    ) -> SubscriptionLifecycleStatus {
        guard isVerified else { return .verificationFailed }
        if revokedDate != nil || renewalPhase == .revoked {
            return .revoked
        }
        if renewalPhase == .inGracePeriod {
            return .gracePeriod
        }
        if renewalPhase == .inBillingRetry {
            return .billingRetry
        }
        if let expirationDate, expirationDate <= now {
            if let gracePeriodExpirationDate, gracePeriodExpirationDate > now {
                return .gracePeriod
            }
            return .expired
        }
        if isTrialPeriod, let expirationDate, expirationDate > now {
            return .trial
        }
        if let expirationDate {
            let daysRemaining = Calendar.current.dateComponents([.day], from: now, to: expirationDate).day ?? 0
            if !willAutoRenew || daysRemaining <= 3 {
                return .expiringSoon
            }
            return .active
        }
        switch renewalPhase {
        case .active:
            return .active
        case .expired:
            return .expired
        case .revoked:
            return .revoked
        case .inGracePeriod:
            return .gracePeriod
        case .inBillingRetry:
            return .billingRetry
        case .unknown:
            return .inactive
        }
    }

    static func audit(entitlements: [SubscriptionEntitlement], now: Date = Date()) -> SubscriptionStatusAudit {
        let sorted = entitlements.sorted { left, right in
            relevanceScore(for: left) > relevanceScore(for: right)
        }
        var staleCount = 0
        var invalidCount = 0
        var issues: [String] = []

        for entitlement in entitlements {
            if entitlement.verificationState == .failed {
                invalidCount += 1
                issues.append("\(displayName(for: entitlement)) 的交易签名未通过验证")
            }
            if let lastVerifiedAt = entitlement.lastVerifiedAt {
                if now.timeIntervalSince(lastVerifiedAt) > staleInterval {
                    staleCount += 1
                    issues.append("\(displayName(for: entitlement)) 的验证结果已超过 24 小时")
                }
            } else {
                staleCount += 1
                issues.append("\(displayName(for: entitlement)) 还没有完成过一次有效校验")
            }
            if entitlement.status.isEntitled,
               let expireAt = entitlement.expireAt,
               expireAt <= now,
               (entitlement.gracePeriodExpireAt ?? .distantPast) <= now {
                invalidCount += 1
                issues.append("\(displayName(for: entitlement)) 的本地权益已过期，请立即同步")
            }
        }

        return SubscriptionStatusAudit(
            currentEntitlement: sorted.first,
            entitledCount: entitlements.filter { $0.status.isEntitled }.count,
            staleCount: staleCount,
            invalidCount: invalidCount,
            issues: Array(Set(issues)).sorted()
        )
    }

    static func verificationDescription(for entitlement: SubscriptionEntitlement, now: Date = Date()) -> String {
        switch entitlement.verificationState {
        case .verified:
            if let lastVerifiedAt = entitlement.lastVerifiedAt {
                return "已于 \(lastVerifiedAt.formatted(date: .abbreviated, time: .shortened)) 完成验证"
            }
            return "已完成验证"
        case .stale:
            return "验证结果已陈旧，建议立即刷新"
        case .failed:
            return entitlement.verificationMessage.isEmpty ? "签名验证失败" : entitlement.verificationMessage
        case .notConfigured:
            return "当前环境尚未返回可校验的商品信息"
        case .notChecked:
            return "尚未执行验证"
        }
    }

    private static func relevanceScore(for entitlement: SubscriptionEntitlement) -> Int {
        let statusScore: Int
        switch entitlement.status {
        case .trial:
            statusScore = 900
        case .active:
            statusScore = 850
        case .expiringSoon:
            statusScore = 800
        case .gracePeriod:
            statusScore = 750
        case .billingRetry:
            statusScore = 700
        case .verificationFailed:
            statusScore = 650
        case .expired:
            statusScore = 500
        case .revoked:
            statusScore = 450
        case .inactive:
            statusScore = 100
        }
        let dateScore = entitlement.expireAt?.timeIntervalSince1970 ?? 0
        return statusScore + Int(dateScore / 100000)
    }

    private static func displayName(for entitlement: SubscriptionEntitlement) -> String {
        entitlement.productName.isEmpty ? entitlement.productId : entitlement.productName
    }
}

@MainActor
enum SubscriptionStoreService {
    private static var listenerTask: Task<Void, Never>?
    private static var hasBootstrapped = false

    static func bootstrapIfNeeded(modelContext: ModelContext) async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        _ = await syncStoreState(modelContext: modelContext)
    }

    static func startListeningIfNeeded(modelContext: ModelContext) {
        guard listenerTask == nil else { return }
        listenerTask = Task { @MainActor in
            for await update in Transaction.updates {
                switch update {
                case .verified(let transaction):
                    _ = await syncStoreState(modelContext: modelContext)
                    await transaction.finish()
                case .unverified(_, _):
                    _ = await syncStoreState(modelContext: modelContext)
                }
            }
        }
    }

    static func syncStoreState(modelContext: ModelContext, now: Date = Date()) async -> SubscriptionSyncResult {
        let products = await SubscriptionCatalogService.loadProducts()
        let statusMap = await loadStatusMap(for: products.compactMap(\.product))
        let entitlements = (try? modelContext.fetch(FetchDescriptor<SubscriptionEntitlement>())) ?? []
        let records = (try? modelContext.fetch(FetchDescriptor<SubscriptionTransactionRecord>())) ?? []
        var entitlementByProductID = Dictionary(uniqueKeysWithValues: entitlements.map { ($0.productId, $0) })
        var recordByID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        var latestSnapshots: [String: SubscriptionTransactionSnapshot] = [:]
        var warnings: [String] = []

        for await historyItem in Transaction.all {
            switch historyItem {
            case .verified(let transaction):
                guard SubscriptionCatalogService.knownProductIDs.contains(transaction.productID) else { continue }
                let snapshot = SubscriptionTransactionSnapshot(
                    transaction: transaction,
                    verificationState: .verified,
                    note: "已通过 StoreKit 验证",
                    isTrialPeriod: transaction.offer?.type == .introductory
                )
                latestSnapshots[transaction.productID] = newerSnapshot(snapshot, than: latestSnapshots[transaction.productID])
                upsertRecord(
                    snapshot: snapshot,
                    recordByID: &recordByID,
                    statusMap: statusMap,
                    now: now,
                    modelContext: modelContext
                )
            case .unverified(let transaction, let error):
                guard SubscriptionCatalogService.knownProductIDs.contains(transaction.productID) else { continue }
                let snapshot = SubscriptionTransactionSnapshot(
                    transaction: transaction,
                    verificationState: .failed,
                    note: error.localizedDescription,
                    isTrialPeriod: transaction.offer?.type == .introductory
                )
                latestSnapshots[transaction.productID] = newerSnapshot(snapshot, than: latestSnapshots[transaction.productID])
                upsertRecord(
                    snapshot: snapshot,
                    recordByID: &recordByID,
                    statusMap: statusMap,
                    now: now,
                    modelContext: modelContext
                )
                warnings.append("\(transaction.productID) 存在未通过验证的历史交易：\(error.localizedDescription)")
            }
        }

        var currentEntitlementProductIDs = Set<String>()
        for await entitlementItem in Transaction.currentEntitlements {
            switch entitlementItem {
            case .verified(let transaction):
                guard SubscriptionCatalogService.knownProductIDs.contains(transaction.productID) else { continue }
                let snapshot = SubscriptionTransactionSnapshot(
                    transaction: transaction,
                    verificationState: .verified,
                    note: "当前有效权益",
                    isTrialPeriod: transaction.offer?.type == .introductory
                )
                currentEntitlementProductIDs.insert(transaction.productID)
                latestSnapshots[transaction.productID] = newerSnapshot(snapshot, than: latestSnapshots[transaction.productID])
                upsertEntitlement(
                    snapshot: snapshot,
                    entitlementByProductID: &entitlementByProductID,
                    statusMap: statusMap,
                    now: now,
                    modelContext: modelContext
                )
            case .unverified(let transaction, let error):
                guard SubscriptionCatalogService.knownProductIDs.contains(transaction.productID) else { continue }
                let snapshot = SubscriptionTransactionSnapshot(
                    transaction: transaction,
                    verificationState: .failed,
                    note: error.localizedDescription,
                    isTrialPeriod: transaction.offer?.type == .introductory
                )
                currentEntitlementProductIDs.insert(transaction.productID)
                latestSnapshots[transaction.productID] = newerSnapshot(snapshot, than: latestSnapshots[transaction.productID])
                upsertEntitlement(
                    snapshot: snapshot,
                    entitlementByProductID: &entitlementByProductID,
                    statusMap: statusMap,
                    now: now,
                    modelContext: modelContext
                )
                warnings.append("\(transaction.productID) 的当前权益验证失败：\(error.localizedDescription)")
            }
        }

        for (productID, snapshot) in latestSnapshots where !currentEntitlementProductIDs.contains(productID) {
            upsertEntitlement(
                snapshot: snapshot,
                entitlementByProductID: &entitlementByProductID,
                statusMap: statusMap,
                now: now,
                modelContext: modelContext
            )
        }

        for entitlement in entitlementByProductID.values where latestSnapshots[entitlement.productId] == nil {
            entitlement.status = .inactive
            entitlement.renewalPhase = .unknown
            entitlement.isActive = false
            entitlement.lastSyncedAt = now
            if entitlement.verificationState == .verified {
                entitlement.verificationState = .stale
                entitlement.verificationMessage = "未从当前商店状态中读取到该商品，请检查配置或恢复购买。"
            }
        }

        try? modelContext.save()

        let message: String
        if entitlementByProductID.values.contains(where: { $0.status.isEntitled }) {
            message = "订阅状态与交易验证已完成同步。"
        } else {
            message = "已完成订阅校验，当前未检测到有效中的订阅权益。"
        }

        return SubscriptionSyncResult(products: products, message: message, warnings: Array(Set(warnings)).sorted())
    }

    static func purchase(productID: String, modelContext: ModelContext) async -> SubscriptionPurchaseResult {
        let products = await SubscriptionCatalogService.loadProducts()
        guard let storeProduct = products.first(where: { $0.id == productID })?.product else {
            return SubscriptionPurchaseResult(
                state: .unavailable,
                message: "当前环境未返回该订阅商品，请检查 App Store Connect 或 StoreKit 配置。",
                products: products
            )
        }

        do {
            let result = try await storeProduct.purchase()
            switch result {
            case .success(let verificationResult):
                switch verificationResult {
                case .verified(let transaction):
                    let syncResult = await syncStoreState(modelContext: modelContext)
                    await transaction.finish()
                    return SubscriptionPurchaseResult(
                        state: .success,
                        message: syncResult.message,
                        products: syncResult.products
                    )
                case .unverified(_, let error):
                    let syncResult = await syncStoreState(modelContext: modelContext)
                    return SubscriptionPurchaseResult(
                        state: .failed,
                        message: "购买已返回，但交易验证失败：\(error.localizedDescription)",
                        products: syncResult.products
                    )
                }
            case .pending:
                return SubscriptionPurchaseResult(
                    state: .pending,
                    message: "购买请求已提交，正在等待 App Store 完成确认。",
                    products: products
                )
            case .userCancelled:
                return SubscriptionPurchaseResult(
                    state: .cancelled,
                    message: "你已取消本次购买。",
                    products: products
                )
            @unknown default:
                return SubscriptionPurchaseResult(
                    state: .failed,
                    message: "出现未知购买结果，请稍后重试。",
                    products: products
                )
            }
        } catch {
            return SubscriptionPurchaseResult(
                state: .failed,
                message: error.localizedDescription,
                products: products
            )
        }
    }

    static func restorePurchases(modelContext: ModelContext) async -> SubscriptionSyncResult {
        do {
            try await AppStore.sync()
        } catch {
            let products = await SubscriptionCatalogService.loadProducts()
            return SubscriptionSyncResult(
                products: products,
                message: "恢复购买失败：\(error.localizedDescription)",
                warnings: []
            )
        }
        return await syncStoreState(modelContext: modelContext)
    }

    private static func loadStatusMap(for products: [Product]) async -> [String: Product.SubscriptionInfo.Status] {
        var map: [String: Product.SubscriptionInfo.Status] = [:]
        for product in products {
            guard let subscription = product.subscription,
                  let statuses = try? await subscription.status else { continue }
            for status in statuses {
                switch status.transaction {
                case .verified(let transaction):
                    if SubscriptionCatalogService.knownProductIDs.contains(transaction.productID) {
                        map[transaction.productID] = status
                    }
                case .unverified(let transaction, _):
                    if SubscriptionCatalogService.knownProductIDs.contains(transaction.productID) {
                        map[transaction.productID] = status
                    }
                }
            }
        }
        return map
    }

    private static func newerSnapshot(
        _ candidate: SubscriptionTransactionSnapshot,
        than current: SubscriptionTransactionSnapshot?
    ) -> SubscriptionTransactionSnapshot {
        guard let current else { return candidate }
        return candidate.transaction.purchaseDate >= current.transaction.purchaseDate ? candidate : current
    }

    private static func upsertEntitlement(
        snapshot: SubscriptionTransactionSnapshot,
        entitlementByProductID: inout [String: SubscriptionEntitlement],
        statusMap: [String: Product.SubscriptionInfo.Status],
        now: Date,
        modelContext: ModelContext
    ) {
        let productID = snapshot.transaction.productID
        let item = SubscriptionCatalogService.metadata(for: productID)
        let status = statusMap[productID]
        let renewalInfo = verified(status?.renewalInfo)
        let renewalPhase = mapRenewalPhase(from: status?.state, transaction: snapshot.transaction)
        let lifecycleStatus = SubscriptionLifecycleAuditService.resolveStatus(
            renewalPhase: renewalPhase,
            expirationDate: snapshot.transaction.expirationDate,
            gracePeriodExpirationDate: renewalInfo?.gracePeriodExpirationDate,
            revokedDate: snapshot.transaction.revocationDate,
            willAutoRenew: renewalInfo?.willAutoRenew ?? false,
            isVerified: snapshot.verificationState == .verified,
            isTrialPeriod: snapshot.isTrialPeriod,
            now: now
        )

        let entitlement = entitlementByProductID[productID] ?? SubscriptionEntitlement(
            productId: productID,
            productName: item.title,
            status: lifecycleStatus,
            renewalPhase: renewalPhase,
            verificationState: snapshot.verificationState,
            verificationMessage: snapshot.note,
            isActive: lifecycleStatus.isEntitled,
            willAutoRenew: renewalInfo?.willAutoRenew ?? false,
            renewalProductId: renewalInfo?.autoRenewPreference ?? productID,
            ownershipType: String(describing: snapshot.transaction.ownershipType),
            environment: String(describing: snapshot.transaction.environment),
            purchaseDate: snapshot.transaction.purchaseDate,
            expireAt: snapshot.transaction.expirationDate,
            gracePeriodExpireAt: renewalInfo?.gracePeriodExpirationDate,
            revokedAt: snapshot.transaction.revocationDate,
            originalTransactionId: String(snapshot.transaction.originalID),
            latestTransactionId: String(snapshot.transaction.id),
            trialUsed: snapshot.isTrialPeriod,
            lastVerifiedAt: snapshot.verificationState == .verified ? now : nil,
            lastSyncedAt: now
        )

        if entitlementByProductID[productID] == nil {
            modelContext.insert(entitlement)
            entitlementByProductID[productID] = entitlement
        }

        entitlement.productName = item.title
        entitlement.status = lifecycleStatus
        entitlement.renewalPhase = renewalPhase
        entitlement.verificationState = snapshot.verificationState == .verified ? .verified : .failed
        entitlement.verificationMessage = snapshot.note
        entitlement.isActive = lifecycleStatus.isEntitled
        entitlement.willAutoRenew = renewalInfo?.willAutoRenew ?? false
        entitlement.renewalProductId = renewalInfo?.autoRenewPreference ?? renewalInfo?.currentProductID ?? productID
        entitlement.ownershipType = String(describing: snapshot.transaction.ownershipType)
        entitlement.environment = String(describing: snapshot.transaction.environment)
        entitlement.purchaseDate = snapshot.transaction.purchaseDate
        entitlement.expireAt = snapshot.transaction.expirationDate
        entitlement.gracePeriodExpireAt = renewalInfo?.gracePeriodExpirationDate
        entitlement.revokedAt = snapshot.transaction.revocationDate
        entitlement.originalTransactionId = String(snapshot.transaction.originalID)
        entitlement.latestTransactionId = String(snapshot.transaction.id)
        entitlement.trialUsed = entitlement.trialUsed || snapshot.isTrialPeriod
        entitlement.lastSyncedAt = now
        if snapshot.verificationState == .verified {
            entitlement.lastVerifiedAt = now
        }
    }

    private static func upsertRecord(
        snapshot: SubscriptionTransactionSnapshot,
        recordByID: inout [String: SubscriptionTransactionRecord],
        statusMap: [String: Product.SubscriptionInfo.Status],
        now: Date,
        modelContext: ModelContext
    ) {
        let transactionID = String(snapshot.transaction.id)
        let item = SubscriptionCatalogService.metadata(for: snapshot.transaction.productID)
        let status = statusMap[snapshot.transaction.productID]
        let renewalInfo = verified(status?.renewalInfo)
        let renewalPhase = mapRenewalPhase(from: status?.state, transaction: snapshot.transaction)
        let lifecycleStatus = SubscriptionLifecycleAuditService.resolveStatus(
            renewalPhase: renewalPhase,
            expirationDate: snapshot.transaction.expirationDate,
            gracePeriodExpirationDate: renewalInfo?.gracePeriodExpirationDate,
            revokedDate: snapshot.transaction.revocationDate,
            willAutoRenew: renewalInfo?.willAutoRenew ?? false,
            isVerified: snapshot.verificationState == .verified,
            isTrialPeriod: snapshot.isTrialPeriod,
            now: now
        )

        let record = recordByID[transactionID] ?? SubscriptionTransactionRecord(
            id: transactionID,
            productId: snapshot.transaction.productID,
            productName: item.title,
            lifecycleStatus: lifecycleStatus,
            verificationState: snapshot.verificationState,
            purchaseDate: snapshot.transaction.purchaseDate,
            expirationDate: snapshot.transaction.expirationDate,
            revocationDate: snapshot.transaction.revocationDate,
            originalTransactionId: String(snapshot.transaction.originalID),
            environment: String(describing: snapshot.transaction.environment),
            ownershipType: String(describing: snapshot.transaction.ownershipType),
            isTrialPeriod: snapshot.isTrialPeriod,
            note: snapshot.note
        )

        if recordByID[transactionID] == nil {
            modelContext.insert(record)
            recordByID[transactionID] = record
        }

        record.productId = snapshot.transaction.productID
        record.productName = item.title
        record.lifecycleStatus = lifecycleStatus
        record.verificationState = snapshot.verificationState
        record.purchaseDate = snapshot.transaction.purchaseDate
        record.expirationDate = snapshot.transaction.expirationDate
        record.revocationDate = snapshot.transaction.revocationDate
        record.originalTransactionId = String(snapshot.transaction.originalID)
        record.environment = String(describing: snapshot.transaction.environment)
        record.ownershipType = String(describing: snapshot.transaction.ownershipType)
        record.isTrialPeriod = snapshot.isTrialPeriod
        record.note = snapshot.note
    }

    private static func verified<T>(_ result: VerificationResult<T>?) -> T? {
        guard let result else { return nil }
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            return nil
        }
    }

    private static func mapRenewalPhase(
        from renewalState: Product.SubscriptionInfo.RenewalState?,
        transaction: Transaction
    ) -> SubscriptionRenewalPhase {
        if transaction.revocationDate != nil {
            return .revoked
        }
        guard let renewalState else {
            if let expirationDate = transaction.expirationDate, expirationDate < Date() {
                return .expired
            }
            return .unknown
        }
        switch renewalState {
        case .subscribed:
            return .active
        case .inGracePeriod:
            return .inGracePeriod
        case .inBillingRetryPeriod:
            return .inBillingRetry
        case .expired:
            return .expired
        case .revoked:
            return .revoked
        default:
            return .unknown
        }
    }
}
