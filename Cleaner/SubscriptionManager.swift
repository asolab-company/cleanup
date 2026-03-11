import Combine
import Foundation
import StoreKit

@MainActor
final class SubscriptionManager: ObservableObject {
    @Published private(set) var productsByID: [String: Product] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false
    @Published var errorText: String?

    private var updateTask: Task<Void, Never>?

    init() {
        updateTask = observeTransactions()
    }

    deinit {
        updateTask?.cancel()
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let products = try await Product.products(
                for: AppSubscriptionIDs.all
            )
            var map: [String: Product] = [:]
            for product in products {
                map[product.id] = product
            }
            productsByID = map
        } catch {
            errorText = error.localizedDescription
        }
    }

    func product(for id: String) -> Product? {
        productsByID[id]
    }

    func formattedPrice(for id: String) -> String {
        productsByID[id]?.displayPrice ?? "..."
    }

    func purchase(productID: String) async -> Bool {
        guard let product = productsByID[productID] else { return false }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                return true
            case .userCancelled:
                return false
            case .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            errorText = error.localizedDescription
            return false
        }
    }

    func restorePurchases() async -> Bool {
        do {
            try await AppStore.sync()
            return await hasActiveSubscription()
        } catch {
            errorText = error.localizedDescription
            return false
        }
    }

    func hasActiveSubscription() async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if AppSubscriptionIDs.all.contains(transaction.productID) {
                return true
            }
        }
        return false
    }

    private func observeTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            for await result in Transaction.updates {
                if let transaction = try? self.checkVerified(result) {
                    await transaction.finish()
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw StoreError.failedVerification
        }
    }
}

enum StoreError: Error {
    case failedVerification
}
