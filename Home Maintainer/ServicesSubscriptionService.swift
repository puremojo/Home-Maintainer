//
//  SubscriptionService.swift
//  Home Maintainer
//

import Foundation
import StoreKit
import FirebaseFunctions

// Product IDs must match App Store Connect and updateSubscriptionTier Cloud Function
private let standardProductID = "EstraDOS.Home-Maintainer.subscription.standard"
private let proProductID = "EstraDOS.Home-Maintainer.subscription.pro"

@Observable
class SubscriptionService {
    var products: [Product] = []
    var activeProductID: String? = nil
    var isLoading = false
    var purchaseError: String?

    private let productIDs = [standardProductID, proProductID]
    private var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = startTransactionListener()
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Public API

    func purchase(_ product: Product) async {
        await MainActor.run {
            isLoading = true
            purchaseError = nil
        }
        defer { Task { @MainActor in isLoading = false } }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await syncTierUpgrade(productID: product.id)
                await transaction.finish()
                await MainActor.run { activeProductID = product.id }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            await MainActor.run { purchaseError = error.localizedDescription }
        }
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    var standardProduct: Product? { products.first { $0.id == standardProductID } }
    var proProduct: Product? { products.first { $0.id == proProductID } }

    // MARK: - Private

    private func loadProducts() async {
        do {
            let loaded = try await Product.products(for: productIDs)
            await MainActor.run {
                products = loaded.sorted { $0.price < $1.price }
            }
        } catch {
            await MainActor.run { purchaseError = error.localizedDescription }
        }
    }

    private func refreshEntitlements() async {
        // Use early-return helper to avoid mutating a captured var across suspension points
        let foundID = await firstActiveEntitlementID()
        await MainActor.run { activeProductID = foundID }

        if let id = foundID {
            await syncTierUpgrade(productID: id)
        } else {
            await syncTierDowngrade()
        }
    }

    private func firstActiveEntitlementID() async -> String? {
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result),
               productIDs.contains(transaction.productID) {
                return transaction.productID
            }
        }
        return nil
    }

    private func syncTierUpgrade(productID: String) async {
        let callable = Functions.functions().httpsCallable("updateSubscriptionTier")
        _ = try? await callable.call(["productID": productID])
    }

    private func syncTierDowngrade() async {
        let callable = Functions.functions().httpsCallable("downgradeToFree")
        _ = try? await callable.call([:] as [String: Any])
    }

    private func startTransactionListener() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            guard let self else { return }
            for await result in Transaction.updates {
                guard let transaction = try? self.checkVerified(result) else { continue }
                if self.productIDs.contains(transaction.productID) {
                    await self.syncTierUpgrade(productID: transaction.productID)
                    await MainActor.run { self.activeProductID = transaction.productID }
                }
                await transaction.finish()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw SubscriptionError.verificationFailed
        case .verified(let value): return value
        }
    }
}

enum SubscriptionError: LocalizedError {
    case verificationFailed
    var errorDescription: String? { "Purchase verification failed." }
}
