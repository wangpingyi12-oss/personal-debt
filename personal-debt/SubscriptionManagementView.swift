import SwiftData
import SwiftUI

struct SubscriptionManagementView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var products: [SubscriptionProductPresentation] = []
    @State private var isLoadingProducts = false
    @State private var isRestoring = false
    @State private var purchasingProductID: String?
    @State private var selectedProductID: String?
    @State private var confirmingProduct: SubscriptionProductPresentation?
    @State private var feedbackMessage = ""
    @State private var isShowingFeedback = false

    private var isBusy: Bool {
        isLoadingProducts || isRestoring || purchasingProductID != nil
    }

    private var selectedProduct: SubscriptionProductPresentation? {
        if let selectedProductID {
            return products.first(where: { $0.id == selectedProductID }) ?? products.first
        }
        return products.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                subscriptionPlansSection
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(AppColors.backgroundGray)
        .task {
            await loadPage()
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { confirmingProduct != nil },
                set: { if !$0 { confirmingProduct = nil } }
            ),
            titleVisibility: .visible
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
                Text("你将通过 Apple ID 购买 \(confirmingProduct.title)（\(confirmingProduct.priceText)），订阅会按 App Store 规则自动续费，可随时在系统订阅设置中管理。")
            }
        }
        .alert("操作结果", isPresented: $isShowingFeedback) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(feedbackMessage)
        }
    }

    private var subscriptionPlansSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "订阅套餐")
                .padding(.horizontal, 0)
                .padding(.top, 0)

            if isLoadingProducts && products.isEmpty {
                VStack(spacing: 12) {
                    ProgressView("正在加载套餐")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .background(AppColors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                    restoreOnlyActions
                }
            } else if products.isEmpty {
                VStack(spacing: 12) {
                    emptyStateCard(
                        icon: "shippingbox",
                        title: "暂未获取到套餐",
                        detail: "当前还没有从商店环境拿到订阅商品。你可以先完成页面搭建，待 App Store Connect 创建商品后再回填商品 ID。"
                    )

                    restoreOnlyActions
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(products) { product in
                        Button {
                            selectedProductID = product.id
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .top, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(product.title)
                                            .font(.headline)
                                        Text(product.subtitle)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                        Text(product.priceText)
                                            .font(.title3.bold())
                                            .foregroundStyle(AppColors.primaryBlue)
                                    }

                                    Spacer()

                                    if selectedProduct?.id == product.id {
                                        StatusChip(title: "已选择", tint: AppColors.primaryBlue)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(product.benefits, id: \.self) { benefit in
                                        Label(benefit, systemImage: "checkmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
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
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AppColors.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(selectedProduct?.id == product.id ? AppColors.primaryBlue : Color.clear, lineWidth: 2)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    purchaseActions
                }
            }
        }
    }

    private var purchaseActions: some View {
        VStack(spacing: 12) {
            if let selectedProduct {
                Button {
                    confirmingProduct = selectedProduct
                } label: {
                    Text(primaryPurchaseTitle(for: selectedProduct))
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(purchaseButtonColor(for: selectedProduct))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(isBusy || !selectedProduct.isAvailableForPurchase)
                .opacity(isBusy || !selectedProduct.isAvailableForPurchase ? 0.6 : 1)
            }

            restorePurchaseButton
        }
    }

    private var restoreOnlyActions: some View {
        VStack(spacing: 12) {
            restorePurchaseButton
        }
    }

    private var restorePurchaseButton: some View {
        Button {
            Task { await restorePurchases() }
        } label: {
            Label(isRestoring ? "恢复购买中..." : "恢复购买", systemImage: "arrow.clockwise")
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white)
                .foregroundStyle(AppColors.primaryBlue)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppColors.primaryBlue, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .disabled(isBusy)
        .opacity(isBusy ? 0.6 : 1)
    }

    private var confirmationTitle: String {
        if purchasingProductID != nil {
            return "处理中..."
        }
        return "确认购买"
    }

    private func emptyStateCard(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
        .background(AppColors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func primaryPurchaseTitle(for product: SubscriptionProductPresentation) -> String {
        if purchasingProductID == product.id {
            return "处理中..."
        }
        if !product.isAvailableForPurchase {
            return "暂不可购买"
        }
        return "确认购买"
    }

    private func purchaseButtonColor(for product: SubscriptionProductPresentation) -> Color {
        product.isAvailableForPurchase ? AppColors.primaryBlue : .gray
    }

    private func loadPage() async {
        isLoadingProducts = true
        products = await SubscriptionCatalogService.loadProducts()
        syncSelectedProduct()
        isLoadingProducts = false
    }

    private func restorePurchases() async {
        isRestoring = true
        let result = await SubscriptionStoreService.restorePurchases(modelContext: modelContext)
        products = result.products
        syncSelectedProduct()
        presentFeedback(result.message, warnings: result.warnings)
        isRestoring = false
    }

    private func purchase(productID: String) async {
        purchasingProductID = productID
        confirmingProduct = nil
        let result = await SubscriptionStoreService.purchase(productID: productID, modelContext: modelContext)
        products = result.products
        syncSelectedProduct(preferredID: productID)
        presentFeedback(result.message)
        purchasingProductID = nil
    }

    private func syncSelectedProduct(preferredID: String? = nil) {
        if let preferredID, products.contains(where: { $0.id == preferredID }) {
            selectedProductID = preferredID
            return
        }
        if let selectedProductID, products.contains(where: { $0.id == selectedProductID }) {
            return
        }
        selectedProductID = products.first?.id
    }

    private func presentFeedback(_ message: String, warnings: [String] = []) {
        feedbackMessage = ([message] + warnings).filter { !$0.isEmpty }.joined(separator: "\n")
        isShowingFeedback = !feedbackMessage.isEmpty
    }
}

private struct StatusChip: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}
