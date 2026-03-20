import SwiftUI

struct PaywallView: View {
    @ObservedObject var subscriptionManager: SubscriptionManager
    let delayCloseButton: Bool
    let onClose: () -> Void
    let onUnlocked: () -> Void

    var body: some View {
        Color.clear
            .ignoresSafeArea()
            .onAppear {
                // Paywall is temporarily disabled.
                onUnlocked()
            }
    }

}

struct PaywallView_Previews: PreviewProvider {
    static var previews: some View {
        PaywallView(
            subscriptionManager: SubscriptionManager(),
            delayCloseButton: true,
            onClose: {},
            onUnlocked: {}
        )
    }
}
