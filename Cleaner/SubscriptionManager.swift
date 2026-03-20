import Combine
import Foundation

@MainActor
final class SubscriptionManager: ObservableObject {
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var hasActiveSubscription = true
    @Published var errorText: String?

    init() {}

    func loadProducts() async {
        hasActiveSubscription = true
    }

    func purchase(productID: String) async -> Bool {
        _ = productID
        hasActiveSubscription = true
        errorText = nil
        return true
    }

    func restorePurchases() async -> Bool {
        hasActiveSubscription = true
        errorText = nil
        return true
    }

    func refreshSubscriptionStatus() async {
        hasActiveSubscription = true
    }

    func checkActiveSubscription() async -> Bool {
        true
    }
}
