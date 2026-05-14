import SwiftUI

struct SubscriptionManagementView: View {
    @State private var products: [SubscriptionProductPresentation] = []
    @State private var entitlements: [SubscriptionEntitlementSnapshot] = []
    @State private var selectedProductID: String?
    @State private var isLoading = false
    @State private var isRestoring = false
    @State private var purchasingProductID: String?
    @State private var feedbackMessage = ""
    @State private var warnings: [String] = []
    @State private var isShowingFeedback = false
    @State private var confirmingProduct: SubscriptionProductPresentation?

    private var selectedProduct: SubscriptionProductPresentation? {
        if let selectedProductID {
            return products.first(where: { $0.id == selectedProductID })
        }
        return products.first
    }

    private var isBusy: Bool {
        isLoading || isRestoring || purchasingProductID != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                entitlementSection
                subscriptionPlansSection
                subscriptionLinksSection
            }
            .padding()
        }
        .background(AppColors.backgroundGray)
        .navigationTitle("订阅中心")
        .task {
            await refreshStoreState(showFeedback: false)
        }
        .confirmationDialog(
            "确认购买",
            isPresented: Binding(
                get: { confirmingProduct != nil },
                set: { if !$0 { confirmingProduct = nil } }
            )
        ) {
            if let confirmingProduct {
                Button("确认购买") {
                    Task {
                        await purchase(productID: confirmingProduct.id)
                    }
                }
            }
            Button("取消", role: .cancel) {
                confirmingProduct = nil
            }
        } message: {
            if let confirmingProduct {
                Text("你将通过 Apple ID 购买 \(confirmingProduct.title)（\(confirmingProduct.priceText)），可随时前往系统订阅管理页修改续费设置。")
            }
        }
        .alert("操作结果", isPresented: $isShowingFeedback) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(([feedbackMessage] + warnings).filter { !$0.isEmpty }.joined(separator: "\n"))
        }
    }

    private var entitlementSection: some View {
        CardSection {
            SectionHeader(
                title: "当前订阅状态",
                subtitle: "仅保留订阅购买、恢复与权益检查相关逻辑。"
            )

            if isLoading && entitlements.isEmpty {
                ProgressView("正在同步订阅状态")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else if entitlements.isEmpty {
                Text("当前未检测到有效订阅。你仍可购买套餐或恢复已购项目。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entitlements) { entitlement in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(entitlement.displayName)
                                .font(.headline)
                            Spacer()
                            Text(entitlement.status.rawValue)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(statusColor(for: entitlement.status).opacity(0.14))
                                .foregroundStyle(statusColor(for: entitlement.status))
                                .clipShape(Capsule())
                        }

                        Text(entitlement.timelineDescription)
                            .font(.subheadline)

                        ForEach(entitlement.detailLines, id: \.self) { line in
                            Label(line, systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }

            HStack(spacing: 12) {
                Button {
                    Task {
                        await refreshStoreState(showFeedback: true)
                    }
                } label: {
                    Label(isLoading ? "同步中..." : "校验并同步", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.primaryBlue)
                .disabled(isBusy)

                Button {
                    Task {
                        await restorePurchases()
                    }
                } label: {
                    Label(isRestoring ? "恢复中..." : "恢复购买", systemImage: "arrow.clockwise.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
            }
        }
    }

    private var subscriptionPlansSection: some View {
        CardSection {
            SectionHeader(
                title: "订阅套餐",
                subtitle: "只保留 StoreKit 商品加载、购买与恢复路径。"
            )

            if isLoading && products.isEmpty {
                ProgressView("正在加载套餐")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ForEach(products) { product in
                    Button {
                        selectedProductID = product.id
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(product.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(product.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(product.priceText)
                                        .font(.title3.bold())
                                        .foregroundStyle(AppColors.primaryBlue)
                                }

                                Spacer()

                                if selectedProductID == product.id {
                                    Text("已选择")
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(AppColors.primaryBlue.opacity(0.14))
                                        .foregroundStyle(AppColors.primaryBlue)
                                        .clipShape(Capsule())
                                }
                            }

                            ForEach(product.benefits, id: \.self) { benefit in
                                Label(benefit, systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let introBadgeText = product.introBadgeText {
                                Text(introBadgeText)
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(AppColors.accentGreen.opacity(0.12))
                                    .foregroundStyle(AppColors.accentGreen)
                                    .clipShape(Capsule())
                            }

                            if !product.isAvailableForPurchase {
                                Text("当前环境未返回该商品，请检查 App Store Connect 或 StoreKit 配置。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppColors.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(selectedProductID == product.id ? AppColors.primaryBlue : Color.clear, lineWidth: 2)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    if let selectedProduct {
                        confirmingProduct = selectedProduct
                    }
                } label: {
                    Text(primaryActionTitle)
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColors.primaryBlue)
                .disabled(isBusy || selectedProduct == nil || selectedProduct?.isAvailableForPurchase == false)
            }
        }
    }

    private var subscriptionLinksSection: some View {
        CardSection {
            SectionHeader(
                title: "订阅相关外链",
                subtitle: "保留订阅管理、条款与隐私外部入口。"
            )

            ForEach(AppExternalLinks.subscriptionLinks + [AppExternalLinks.appleMediaTerms, AppExternalLinks.applePrivacy]) { item in
                ExternalLinkRow(item: item)
            }
        }
    }

    private var primaryActionTitle: String {
        if let purchasingProductID, purchasingProductID == selectedProduct?.id {
            return "处理中..."
        }
        return selectedProduct?.isAvailableForPurchase == true ? "确认购买" : "暂不可购买"
    }

    private func refreshStoreState(showFeedback: Bool) async {
        isLoading = true
        let snapshot = await SubscriptionStoreService.loadStoreSnapshot()
        apply(snapshot: snapshot, showFeedback: showFeedback)
        isLoading = false
    }

    private func purchase(productID: String) async {
        purchasingProductID = productID
        confirmingProduct = nil
        let result = await SubscriptionStoreService.purchase(productID: productID)
        apply(snapshot: result.snapshot, showFeedback: true)
        purchasingProductID = nil
    }

    private func restorePurchases() async {
        isRestoring = true
        let snapshot = await SubscriptionStoreService.restorePurchases()
        apply(snapshot: snapshot, showFeedback: true)
        isRestoring = false
    }

    private func apply(snapshot: SubscriptionStoreSnapshot, showFeedback: Bool) {
        products = snapshot.products
        entitlements = snapshot.entitlements
        warnings = snapshot.warnings
        feedbackMessage = snapshot.message
        if selectedProductID == nil || !products.contains(where: { $0.id == selectedProductID }) {
            selectedProductID = products.first?.id
        }
        isShowingFeedback = showFeedback && (!feedbackMessage.isEmpty || !warnings.isEmpty)
    }

    private func statusColor(for status: SubscriptionLifecycleStatus) -> Color {
        switch status {
        case .trial, .active:
            return AppColors.accentGreen
        case .expiringSoon, .gracePeriod, .billingRetry:
            return AppColors.warningOrange
        case .verificationFailed, .expired, .revoked:
            return .red
        case .inactive:
            return AppColors.primaryBlue
        }
    }
}
