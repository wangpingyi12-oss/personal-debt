import Foundation
import StoreKit

enum SubscriptionAppStoreConfig {
    static let monthlyProductID = "com.personaldebt.pro.monthly"
    static let yearlyProductID = "com.personaldebt.pro.yearly"
    static let introMessage = "如有试用或优惠资格，购买页会自动显示"
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

struct SubscriptionProductPresentation: Identifiable, Hashable {
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

struct SubscriptionStoreSnapshot {
    let products: [SubscriptionProductPresentation]
    let entitlements: [SubscriptionEntitlementSnapshot]
    let message: String
    let warnings: [String]
}

struct SubscriptionPurchaseResult {
    enum State {
        case success
        case pending
        case cancelled
        case unavailable
        case failed
    }

    let state: State
    let snapshot: SubscriptionStoreSnapshot
}

enum SubscriptionCatalogService {
    static let catalog: [SubscriptionCatalogItem] = [
        SubscriptionCatalogItem(
            id: SubscriptionAppStoreConfig.monthlyProductID,
            title: "连续包月",
            subtitle: "适合希望按月管理订阅的用户",
            fallbackPrice: "¥10/月",
            introBadgeText: SubscriptionAppStoreConfig.introMessage,
            benefits: ["通过 App Store 购买自动续费订阅", "支持恢复购买", "可随时跳转到 Apple 订阅管理页"],
            sortOrder: 0
        ),
        SubscriptionCatalogItem(
            id: SubscriptionAppStoreConfig.yearlyProductID,
            title: "连续包年",
            subtitle: "适合长期持续使用订阅服务的用户",
            fallbackPrice: "¥80/年",
            introBadgeText: SubscriptionAppStoreConfig.introMessage,
            benefits: ["通过 App Store 购买自动续费订阅", "支持恢复购买", "适合作为长期订阅方案"],
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
                benefits: ["请检查 App Store Connect 或 StoreKit 配置。"],
                sortOrder: .max
            )
    }

    @MainActor
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

enum SubscriptionStatusResolver {
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
        return renewalPhase == .active ? .active : .inactive
    }

    static func mapRenewalPhase(
        from renewalState: Product.SubscriptionInfo.RenewalState?,
        transaction: Transaction,
        now: Date = Date()
    ) -> SubscriptionRenewalPhase {
        if transaction.revocationDate != nil {
            return .revoked
        }
        guard let renewalState else {
            if let expirationDate = transaction.expirationDate, expirationDate < now {
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
        @unknown default:
            return .unknown
        }
    }
}

@MainActor
private struct VerifiedSubscriptionStatus {
    let renewalState: Product.SubscriptionInfo.RenewalState?
    let gracePeriodExpirationDate: Date?
    let willAutoRenew: Bool
}

@MainActor
private struct CurrentEntitlementResult {
    let snapshot: SubscriptionEntitlementSnapshot
    let warning: String?
}

@MainActor
enum SubscriptionStoreService {
    static func loadStoreSnapshot(now: Date = Date()) async -> SubscriptionStoreSnapshot {
        let products = await SubscriptionCatalogService.loadProducts()
        let productStatusMap = await loadStatusMap(for: products.compactMap(\.product))
        var entitlements: [SubscriptionEntitlementSnapshot] = []
        var warnings: [String] = []

        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                guard SubscriptionCatalogService.knownProductIDs.contains(transaction.productID) else { continue }
                if let snapshot = await makeSnapshot(
                    transaction: transaction,
                    verificationState: .verified,
                    verificationMessage: "已通过 StoreKit 验证",
                    productStatusMap: productStatusMap,
                    now: now
                ) {
                    entitlements.append(snapshot.snapshot)
                    if let warning = snapshot.warning {
                        warnings.append(warning)
                    }
                }
            case .unverified(let transaction, let error):
                guard SubscriptionCatalogService.knownProductIDs.contains(transaction.productID) else { continue }
                if let snapshot = await makeSnapshot(
                    transaction: transaction,
                    verificationState: .failed,
                    verificationMessage: error.localizedDescription,
                    productStatusMap: productStatusMap,
                    now: now
                ) {
                    entitlements.append(snapshot.snapshot)
                    warnings.append("\(transaction.productID) 验证失败：\(error.localizedDescription)")
                }
            }
        }

        entitlements.sort { left, right in
            if left.status == right.status {
                return (left.expirationDate ?? .distantPast) > (right.expirationDate ?? .distantPast)
            }
            return sortWeight(for: left.status) > sortWeight(for: right.status)
        }

        let message = entitlements.contains(where: { $0.status.isEntitled })
            ? "已同步当前订阅权益。"
            : "已同步订阅信息，当前未检测到有效订阅。"

        return SubscriptionStoreSnapshot(
            products: products,
            entitlements: entitlements,
            message: message,
            warnings: Array(Set(warnings)).sorted()
        )
    }

    static func purchase(productID: String) async -> SubscriptionPurchaseResult {
        let products = await SubscriptionCatalogService.loadProducts()
        guard let product = products.first(where: { $0.id == productID })?.product else {
            return SubscriptionPurchaseResult(
                state: .unavailable,
                snapshot: SubscriptionStoreSnapshot(
                    products: products,
                    entitlements: [],
                    message: "当前环境未返回该订阅商品，请检查 App Store Connect 或 StoreKit 配置。",
                    warnings: []
                )
            )
        }

        do {
            let purchaseResult = try await product.purchase()
            switch purchaseResult {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    let snapshot = await loadStoreSnapshot()
                    await transaction.finish()
                    return SubscriptionPurchaseResult(state: .success, snapshot: snapshot)
                case .unverified(_, let error):
                    let snapshot = await loadStoreSnapshot()
                    return SubscriptionPurchaseResult(
                        state: .failed,
                        snapshot: SubscriptionStoreSnapshot(
                            products: snapshot.products,
                            entitlements: snapshot.entitlements,
                            message: "购买已返回，但交易验证失败：\(error.localizedDescription)",
                            warnings: snapshot.warnings
                        )
                    )
                }
            case .pending:
                let snapshot = await loadStoreSnapshot()
                return SubscriptionPurchaseResult(
                    state: .pending,
                    snapshot: SubscriptionStoreSnapshot(
                        products: snapshot.products,
                        entitlements: snapshot.entitlements,
                        message: "购买请求已提交，正在等待 App Store 完成确认。",
                        warnings: snapshot.warnings
                    )
                )
            case .userCancelled:
                let snapshot = await loadStoreSnapshot()
                return SubscriptionPurchaseResult(
                    state: .cancelled,
                    snapshot: SubscriptionStoreSnapshot(
                        products: snapshot.products,
                        entitlements: snapshot.entitlements,
                        message: "你已取消本次购买。",
                        warnings: snapshot.warnings
                    )
                )
            @unknown default:
                let snapshot = await loadStoreSnapshot()
                return SubscriptionPurchaseResult(
                    state: .failed,
                    snapshot: SubscriptionStoreSnapshot(
                        products: snapshot.products,
                        entitlements: snapshot.entitlements,
                        message: "出现未知购买结果，请稍后重试。",
                        warnings: snapshot.warnings
                    )
                )
            }
        } catch {
            let snapshot = await loadStoreSnapshot()
            return SubscriptionPurchaseResult(
                state: .failed,
                snapshot: SubscriptionStoreSnapshot(
                    products: snapshot.products,
                    entitlements: snapshot.entitlements,
                    message: error.localizedDescription,
                    warnings: snapshot.warnings
                )
            )
        }
    }

    static func restorePurchases() async -> SubscriptionStoreSnapshot {
        do {
            try await AppStore.sync()
        } catch {
            let snapshot = await loadStoreSnapshot()
            return SubscriptionStoreSnapshot(
                products: snapshot.products,
                entitlements: snapshot.entitlements,
                message: "恢复购买失败：\(error.localizedDescription)",
                warnings: snapshot.warnings
            )
        }
        return await loadStoreSnapshot()
    }

    private static func loadStatusMap(for products: [Product]) async -> [String: VerifiedSubscriptionStatus] {
        var map: [String: VerifiedSubscriptionStatus] = [:]
        for product in products {
            guard let subscription = product.subscription,
                  let statuses = try? await subscription.status else { continue }
            for status in statuses {
                let renewalInfo = verified(status.renewalInfo)
                let transaction = verified(status.transaction)
                guard let renewalInfo, let transaction,
                      SubscriptionCatalogService.knownProductIDs.contains(transaction.productID) else { continue }
                map[transaction.productID] = VerifiedSubscriptionStatus(
                    renewalState: status.state,
                    gracePeriodExpirationDate: renewalInfo.gracePeriodExpirationDate,
                    willAutoRenew: renewalInfo.willAutoRenew
                )
            }
        }
        return map
    }

    private static func makeSnapshot(
        transaction: Transaction,
        verificationState: SubscriptionVerificationState,
        verificationMessage: String,
        productStatusMap: [String: VerifiedSubscriptionStatus],
        now: Date
    ) async -> CurrentEntitlementResult? {
        let metadata = SubscriptionCatalogService.metadata(for: transaction.productID)
        let statusInfo = productStatusMap[transaction.productID]
        let renewalPhase = SubscriptionStatusResolver.mapRenewalPhase(
            from: statusInfo?.renewalState,
            transaction: transaction,
            now: now
        )
        let lifecycleStatus = SubscriptionStatusResolver.resolveStatus(
            renewalPhase: renewalPhase,
            expirationDate: transaction.expirationDate,
            gracePeriodExpirationDate: statusInfo?.gracePeriodExpirationDate,
            revokedDate: transaction.revocationDate,
            willAutoRenew: statusInfo?.willAutoRenew ?? false,
            isVerified: verificationState == .verified,
            isTrialPeriod: transaction.offer?.type == .introductory,
            now: now
        )
        let snapshot = SubscriptionEntitlementSnapshot(
            id: String(transaction.id),
            productId: transaction.productID,
            productName: metadata.title,
            status: lifecycleStatus,
            renewalPhase: renewalPhase,
            verificationState: verificationState,
            verificationMessage: verificationMessage,
            willAutoRenew: statusInfo?.willAutoRenew ?? false,
            purchaseDate: transaction.purchaseDate,
            expirationDate: transaction.expirationDate,
            gracePeriodExpirationDate: statusInfo?.gracePeriodExpirationDate,
            revokedDate: transaction.revocationDate,
            environment: String(describing: transaction.environment),
            ownershipType: String(describing: transaction.ownershipType),
            isTrialPeriod: transaction.offer?.type == .introductory,
            latestTransactionId: String(transaction.id),
            originalTransactionId: String(transaction.originalID),
            lastSyncedAt: now
        )
        return CurrentEntitlementResult(snapshot: snapshot, warning: lifecycleStatus == .verificationFailed ? verificationMessage : nil)
    }

    private static func verified<T>(_ verification: VerificationResult<T>?) -> T? {
        guard let verification else { return nil }
        switch verification {
        case .verified(let value):
            return value
        case .unverified:
            return nil
        }
    }

    private static func sortWeight(for status: SubscriptionLifecycleStatus) -> Int {
        switch status {
        case .trial: return 90
        case .active: return 80
        case .expiringSoon: return 70
        case .gracePeriod: return 60
        case .billingRetry: return 50
        case .verificationFailed: return 40
        case .expired: return 30
        case .revoked: return 20
        case .inactive: return 10
        }
    }
}
