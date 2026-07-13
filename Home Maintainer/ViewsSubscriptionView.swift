//
//  SubscriptionView.swift
//  Home Maintainer
//

import SwiftUI
import StoreKit

struct SubscriptionView: View {
    @Environment(AuthService.self) private var authService
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Usage This Month") {
                    UsageMeterView(data: authService.subscriptionData)
                }

                Section("Plans") {
                    FreePlanRow(isActive: authService.subscriptionData.tier == "free")

                    if let standard = subscriptionService.standardProduct {
                        ProductRow(
                            product: standard,
                            tierName: "Standard",
                            tokenDescription: "1,000,000 tokens/month",
                            isActive: subscriptionService.activeProductID == standard.id,
                            isLoading: subscriptionService.isLoading
                        ) {
                            Task { await subscriptionService.purchase(standard) }
                        }
                    }

                    if let pro = subscriptionService.proProduct {
                        ProductRow(
                            product: pro,
                            tierName: "Pro",
                            tokenDescription: "5,000,000 tokens/month",
                            isActive: subscriptionService.activeProductID == pro.id,
                            isLoading: subscriptionService.isLoading
                        ) {
                            Task { await subscriptionService.purchase(pro) }
                        }
                    }
                }

                Section {
                    Button("Restore Purchases") {
                        Task { await subscriptionService.restorePurchases() }
                    }
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        authService.signOut()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Purchase Error", isPresented: Binding(
                get: { subscriptionService.purchaseError != nil },
                set: { if !$0 { subscriptionService.purchaseError = nil } }
            )) {
                Button("OK") { subscriptionService.purchaseError = nil }
            } message: {
                if let error = subscriptionService.purchaseError {
                    Text(error)
                }
            }
        }
    }
}

// MARK: - Subviews

private struct UsageMeterView: View {
    let data: UserSubscriptionData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(data.tierDisplayName + " Plan")
                    .font(.headline)
                Spacer()
                Text("\(data.monthlyTokensUsed.formatted()) / \(data.tierLimit.formatted())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: data.usagePercentage)
                .tint(data.usagePercentage > 0.9 ? .red : data.usagePercentage > 0.7 ? .orange : .blue)

            Text("Resets \(data.tierResetDate, format: .dateTime.month(.wide).day())")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

private struct FreePlanRow: View {
    let isActive: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Free")
                    .font(.headline)
                Text("100,000 tokens/month")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Text("Current Plan")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProductRow: View {
    let product: Product
    let tierName: String
    let tokenDescription: String
    let isActive: Bool
    let isLoading: Bool
    let onPurchase: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tierName)
                    .font(.headline)
                Text(tokenDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Text("Subscribed")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Button(action: onPurchase) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Text(product.displayPrice + "/mo")
                            .font(.callout.weight(.semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isLoading)
            }
        }
    }
}

#Preview {
    SubscriptionView()
        .environment(AuthService())
        .environment(SubscriptionService())
}
