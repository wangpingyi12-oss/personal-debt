import Foundation

enum SubscriptionLifecycleStatus: String, CaseIterable, Codable, Identifiable {
    case inactive = "未开通"
    case trial = "试用中"
    case active = "订阅中"
    case expiringSoon = "即将到期"
    case gracePeriod = "宽限期"
    case billingRetry = "扣费重试"
    case expired = "已过期"
    case revoked = "已撤销"
    case verificationFailed = "验证失败"

    var id: String { rawValue }

    var isEntitled: Bool {
        switch self {
        case .trial, .active, .expiringSoon, .gracePeriod:
            return true
        case .inactive, .billingRetry, .expired, .revoked, .verificationFailed:
            return false
        }
    }
}

enum SubscriptionVerificationState: String, CaseIterable, Codable, Identifiable {
    case notChecked = "未校验"
    case verified = "已验证"
    case failed = "验证失败"
    case unavailable = "商品不可用"

    var id: String { rawValue }
}

enum SubscriptionRenewalPhase: String, CaseIterable, Codable, Identifiable {
    case active = "生效中"
    case inGracePeriod = "宽限期"
    case inBillingRetry = "扣费重试"
    case expired = "已过期"
    case revoked = "已撤销"
    case unknown = "未知"

    var id: String { rawValue }
}

struct SubscriptionEntitlementSnapshot: Identifiable, Hashable {
    let id: String
    let productId: String
    let productName: String
    let status: SubscriptionLifecycleStatus
    let renewalPhase: SubscriptionRenewalPhase
    let verificationState: SubscriptionVerificationState
    let verificationMessage: String
    let willAutoRenew: Bool
    let purchaseDate: Date?
    let expirationDate: Date?
    let gracePeriodExpirationDate: Date?
    let revokedDate: Date?
    let environment: String
    let ownershipType: String
    let isTrialPeriod: Bool
    let latestTransactionId: String
    let originalTransactionId: String
    let lastSyncedAt: Date

    var displayName: String {
        productName.isEmpty ? productId : productName
    }

    var timelineDescription: String {
        if let expirationDate {
            return "到期时间：\(expirationDate.formatted(date: .abbreviated, time: .shortened))"
        }
        if let revokedDate {
            return "撤销时间：\(revokedDate.formatted(date: .abbreviated, time: .shortened))"
        }
        return "最近同步：\(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    var detailLines: [String] {
        var lines = [
            "续费状态：\(renewalPhase.rawValue)",
            "验证状态：\(verificationState.rawValue)",
            willAutoRenew ? "已开启自动续费" : "未开启自动续费"
        ]
        if !verificationMessage.isEmpty {
            lines.append(verificationMessage)
        }
        if let gracePeriodExpirationDate {
            lines.append("宽限期截止：\(gracePeriodExpirationDate.formatted(date: .abbreviated, time: .shortened))")
        }
        return lines
    }
}
