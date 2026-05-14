import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CardSection {
                        Text("订阅与法务入口")
                            .font(.title2.bold())
                        Text("该工程已收敛为最小可用结构，仅保留订阅购买/恢复、隐私与条款外链、支持与联系入口。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    CardSection {
                        SectionHeader(
                            title: "保留功能",
                            subtitle: "其余债务、策略、提醒、统计与相关路由已删除或断开引用。"
                        )

                        VStack(spacing: 14) {
                            NavigationEntryRow(
                                title: "订阅中心",
                                subtitle: "浏览套餐、购买、恢复购买并同步权益状态。",
                                icon: "star.fill",
                                color: .orange
                            ) {
                                SubscriptionManagementView()
                            }

                            NavigationEntryRow(
                                title: "法务与隐私",
                                subtitle: "集中查看隐私政策、Apple 条款与隐私相关外链。",
                                icon: "shield.lefthalf.filled",
                                color: .green
                            ) {
                                PrivacyLinksView()
                            }

                            NavigationEntryRow(
                                title: "支持与联系",
                                subtitle: "打开帮助页面或通过邮箱联系支持。",
                                icon: "questionmark.circle.fill",
                                color: .blue
                            ) {
                                SupportLinksView()
                            }
                        }
                    }

                    CardSection {
                        SectionHeader(title: "直接入口")

                        ForEach([AppExternalLinks.manageSubscriptions, AppExternalLinks.supportEmail]) { item in
                            ExternalLinkRow(item: item)
                        }
                    }
                }
                .padding()
            }
            .background(AppColors.backgroundGray)
            .navigationTitle("设置")
        }
    }
}

private struct PrivacyLinksView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CardSection {
                    SectionHeader(
                        title: "隐私与条款",
                        subtitle: "保留项目隐私政策、Apple 隐私政策与媒体服务条款入口。"
                    )

                    ForEach(AppExternalLinks.privacyLinks) { item in
                        ExternalLinkRow(item: item)
                    }
                }
            }
            .padding()
        }
        .background(AppColors.backgroundGray)
        .navigationTitle("法务与隐私")
    }
}

private struct SupportLinksView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CardSection {
                    SectionHeader(
                        title: "支持与联系",
                        subtitle: "保留帮助页与联系邮箱入口。"
                    )

                    ForEach(AppExternalLinks.supportLinks) { item in
                        ExternalLinkRow(item: item)
                    }
                }
            }
            .padding()
        }
        .background(AppColors.backgroundGray)
        .navigationTitle("支持与联系")
    }
}
