import Foundation

struct ExternalLinkItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let url: URL
}

enum AppExternalLinks {
    private static let defaultSupportEmailAddress = "wangpingyi12@outlook.com"

    private static var supportEmailAddress: String {
        (Bundle.main.object(forInfoDictionaryKey: "SupportEmail") as? String) ?? defaultSupportEmailAddress
    }

    static let manageSubscriptions = ExternalLinkItem(
        id: "manage-subscriptions",
        title: "管理 App Store 订阅",
        subtitle: "打开 Apple 账户订阅管理页，查看、取消或恢复自动续费项目。",
        url: URL(string: "https://apps.apple.com/account/subscriptions")!
    )

    static let appleMediaTerms = ExternalLinkItem(
        id: "apple-media-terms",
        title: "Apple 媒体服务条款",
        subtitle: "查看 App Store 订阅与媒体服务适用条款。",
        url: URL(string: "https://www.apple.com/legal/internet-services/itunes/cn/terms.html")!
    )

    static let applePrivacy = ExternalLinkItem(
        id: "apple-privacy",
        title: "Apple 隐私政策",
        subtitle: "查看 Apple 在支付、账户与系统服务中的隐私说明。",
        url: URL(string: "https://www.apple.com/legal/privacy/zh-cn/")!
    )

    static let privacyPolicyChinese = ExternalLinkItem(
        id: "privacy-policy-zh",
        title: "隐私政策（简体中文）",
        subtitle: "项目文档站点中的中文隐私政策页面。",
        url: URL(string: "https://wangpingyi12-oss.github.io/personal-debt/privacy-policy-zh-CN.html")!
    )

    static let privacyPolicyEnglish = ExternalLinkItem(
        id: "privacy-policy-en",
        title: "Privacy Policy (English)",
        subtitle: "Project-hosted English privacy policy page.",
        url: URL(string: "https://wangpingyi12-oss.github.io/personal-debt/privacy-policy-en-US.html")!
    )

    static let supportChinese = ExternalLinkItem(
        id: "support-zh",
        title: "支持页面（简体中文）",
        subtitle: "面向中文用户的帮助与联系入口。",
        url: URL(string: "https://wangpingyi12-oss.github.io/personal-debt/support-zh-CN.html")!
    )

    static let supportEnglish = ExternalLinkItem(
        id: "support-en",
        title: "Support Page (English)",
        subtitle: "English support and contact information.",
        url: URL(string: "https://wangpingyi12-oss.github.io/personal-debt/support-en-US.html")!
    )

    static let supportEmail = ExternalLinkItem(
        id: "support-email",
        title: "联系邮箱",
        subtitle: supportEmailAddress,
        url: URL(string: "mailto:\(supportEmailAddress)")!
    )

    static let subscriptionLinks = [manageSubscriptions]

    static let privacyLinks = [
        privacyPolicyChinese,
        privacyPolicyEnglish,
        appleMediaTerms,
        applePrivacy
    ]

    static let supportLinks = [
        supportChinese,
        supportEnglish,
        supportEmail
    ]
}
