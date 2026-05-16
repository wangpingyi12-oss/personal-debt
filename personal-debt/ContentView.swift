//
//  ContentView.swift
//  personal-debt
//
//  Created by Mac on 2026/5/14.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @State private var showingSubscription = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    subscriptionStatusRow

                    if subscriptionStore.isReadOnly {
                        readOnlyNoticeRow
                    }
                }

                Section("M1 Models") {
                    Label("CreditCard / Loan / PersonalLending models are registered", systemImage: "internaldrive")
                    Label("Facts, fallback data, and simulations use separate models", systemImage: "rectangle.3.group")
                }

                Section("M2 Engines") {
                    Label("Credit card billing and payment recalculation", systemImage: "creditcard")
                    Label("Loan schedule, overdue, and allocation engines", systemImage: "calendar")
                    Label("Personal lending P0 schedule and payment engines", systemImage: "person.2")
                    Label("Strategy simulation snapshot engine", systemImage: "chart.line.uptrend.xyaxis")
                }
            }
            .navigationTitle("Debt Manager")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSubscription = true
                    } label: {
                        Label("Subscription", systemImage: "creditcard")
                    }
                }
            }
            .sheet(isPresented: $showingSubscription) {
                SubscriptionView()
                    .environmentObject(subscriptionStore)
            }
            .alert(item: $subscriptionStore.message) { message in
                Alert(
                    title: Text(message.title),
                    message: Text(message.detail),
                    dismissButton: .default(Text("OK"))
                )
            }
            .task {
                await subscriptionStore.start()
            }
        }
    }

    private var subscriptionStatusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: subscriptionStatusIcon)
                .foregroundStyle(subscriptionStore.hasFullAccess ? .green : .orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(subscriptionStore.accessState.statusTitle)
                    .font(.headline)

                Text(subscriptionStore.accessState.statusDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button(subscriptionStore.hasFullAccess ? "Manage" : "Subscribe") {
                showingSubscription = true
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    private var subscriptionStatusIcon: String {
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

    private var readOnlyNoticeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Read-only access", systemImage: "lock")
                .font(.headline)

            Text("You can review existing debt data. Creating, editing, deleting, recording payments, and write-backed analytics refreshes should call the subscription gate before saving.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                showingSubscription = true
            } label: {
                Label("Unlock Editing", systemImage: "lock.open")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    ContentView()
        .environmentObject(
            SubscriptionStore.preview(
                accessState: .trialActive(
                    expiresAt: Date().addingTimeInterval(9 * 86_400),
                    daysRemaining: 9
                )
            )
        )
}
