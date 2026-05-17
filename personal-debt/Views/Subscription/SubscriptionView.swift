import SwiftUI

struct SubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptionStore: SubscriptionStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    planPicker
                    complianceDetails
                    legalLinks
                }
                .padding()
            }
            .navigationTitle("subscription.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(subscriptionStore.accessState.statusTitle, systemImage: statusIcon)
                .font(.headline)

            Text(subscriptionStore.accessState.statusDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("subscription.header.copy")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusIcon: String {
        switch subscriptionStore.accessState {
        case .loading:
            return "hourglass"
        case .trialActive:
            return "clock.badge.checkmark"
        case .subscribed:
            return "checkmark.seal"
        case .readOnly:
            return "lock"
        }
    }

    private var planPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("subscription.choosePlan")
                .font(.headline)

            ForEach(subscriptionStore.products) { option in
                Button {
                    Task {
                        await subscriptionStore.purchase(option)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: option.isYearly ? "calendar.badge.clock" : "calendar")
                            .font(.title3)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(option.title)
                                    .font(.headline)

                                if option.isYearly {
                                    Text("subscription.bestValue")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(.green.opacity(0.14), in: Capsule())
                                        .foregroundStyle(.green)
                                }
                            }

                            Text(option.calloutText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 12)

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(option.priceText)
                                .font(.headline)

                            if option.isFallbackPrice {
                                Text("subscription.fallback")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .disabled(subscriptionStore.isPurchasing || subscriptionStore.isRestoring)
            }

            if subscriptionStore.isLoadingProducts {
                Label("subscription.loadingPrices", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let productLoadingError = subscriptionStore.productLoadingError {
                Label(productLoadingError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task {
                    await subscriptionStore.restorePurchases()
                }
            } label: {
                if subscriptionStore.isRestoring {
                    ProgressView()
                } else {
                    Label("subscription.restore", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(subscriptionStore.isPurchasing || subscriptionStore.isRestoring)
        }
    }

    private var complianceDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("subscription.terms.title")
                .font(.headline)

            Label("subscription.terms.noTiers", systemImage: "checkmark.circle")
            Label("subscription.terms.appleCharge", systemImage: "apple.logo")
            Label("subscription.terms.autoRenew", systemImage: "repeat")
            Label("subscription.terms.manage", systemImage: "person.crop.circle")
            Label("subscription.terms.readOnly", systemImage: "eye")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var legalLinks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("subscription.legal")
                .font(.headline)

            Link(destination: SubscriptionCatalog.termsOfUseURL) {
                Label("subscription.termsOfUse", systemImage: "doc.text")
            }

            Link(destination: SubscriptionCatalog.privacyPolicyURL) {
                Label("subscription.privacyPolicy", systemImage: "hand.raised")
            }

            Link(destination: SubscriptionCatalog.applePrivacyURL) {
                Label("subscription.applePrivacy", systemImage: "apple.logo")
            }

            Link(destination: SubscriptionCatalog.manageSubscriptionsURL) {
                Label("subscription.manage", systemImage: "gearshape")
            }
        }
        .font(.subheadline)
    }
}

#Preview {
    SubscriptionView()
        .environmentObject(
            SubscriptionStore.preview(
                accessState: .trialActive(
                    expiresAt: Date().addingTimeInterval(3 * 86_400),
                    daysRemaining: 3
                )
            )
        )
}
