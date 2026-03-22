import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding =
        false
    @StateObject private var subscriptionManager = SubscriptionManager()
    @State private var showOnboarding = false
    @State private var showPaywall = false
    @State private var appUnlocked = false
    @State private var delayPaywallCloseButton = true

    var body: some View {
        Group {
            if appUnlocked {
                MainView(subscriptionManager: subscriptionManager) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        appUnlocked = false
                        delayPaywallCloseButton = false
                        showPaywall = true
                    }
                }
            } else if showPaywall {
                PaywallView(
                    subscriptionManager: subscriptionManager,
                    delayCloseButton: delayPaywallCloseButton,
                    onClose: { appUnlocked = true },
                    onUnlocked: { appUnlocked = true }
                )
            } else if showOnboarding {
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        hasCompletedOnboarding = true
                        delayPaywallCloseButton = true
                        showPaywall = true
                    }
                }
            } else {
                LoadingView {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if hasCompletedOnboarding {
                            appUnlocked = true
                        } else {
                            showOnboarding = true
                        }
                    }
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
