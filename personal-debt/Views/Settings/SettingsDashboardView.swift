import SwiftUI

struct SettingsDashboardView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CardSection {
                        SectionHeader(
                            title: "设置",
                            subtitle: "保留订阅能力，并集中展示法务/支持入口。"
                        )

                        NavigationEntryRow(
                            title: "订阅中心",
                            subtitle: "浏览套餐、购买、恢复与权益同步。",
                            icon: "star.fill",
                            color: .orange
                        ) {
                            SubscriptionManagementView()
                        }
                    }

                    CardSection {
                        SectionHeader(title: "法务与支持")
                        ForEach(AppExternalLinks.privacyLinks + AppExternalLinks.supportLinks + AppExternalLinks.subscriptionLinks) { item in
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
