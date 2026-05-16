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
            .navigationTitle("Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
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

            Text("Start with 15 days free. After the trial, keep full editing access with one auto-renewable subscription. Existing data remains viewable if you do not subscribe.")
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
            Text("Choose a Plan")
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
                                    Text("Best value")
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
                                Text("Fallback")
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
                Label("Loading App Store prices", systemImage: "arrow.triangle.2.circlepath")
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
                    Label("Restore Purchases", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(subscriptionStore.isPurchasing || subscriptionStore.isRestoring)
        }
    }

    private var complianceDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Subscription Terms")
                .font(.headline)

            Label("No feature tiers: one subscription unlocks full editing access.", systemImage: "checkmark.circle")
            Label("Payment is charged to your Apple ID through App Store In-App Purchase.", systemImage: "apple.logo")
            Label("The subscription renews automatically unless cancelled at least 24 hours before the end of the current period.", systemImage: "repeat")
            Label("You can manage or cancel the subscription in your App Store account settings.", systemImage: "person.crop.circle")
            Label("After the free trial ends, a subscription is required for edits. Existing data remains available to view.", systemImage: "eye")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var legalLinks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Legal")
                .font(.headline)

            Link(destination: SubscriptionCatalog.termsOfUseURL) {
                Label("Terms of Use", systemImage: "doc.text")
            }

            Link(destination: SubscriptionCatalog.privacyPolicyURL) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }

            Link(destination: SubscriptionCatalog.applePrivacyURL) {
                Label("Apple Privacy", systemImage: "apple.logo")
            }

            Link(destination: SubscriptionCatalog.manageSubscriptionsURL) {
                Label("Manage Subscription", systemImage: "gearshape")
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
