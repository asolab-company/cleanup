import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding =
        false
    @StateObject private var subscriptionManager = SubscriptionManager()
    @State private var showOnboarding = false
    @State private var showPaywall = false
    @State private var appUnlocked = false
    @State private var delayPaywallCloseButton = true
    @State private var didRequestATT = false

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
                    Task { @MainActor in
                        if hasCompletedOnboarding {
                            await subscriptionManager.refreshSubscriptionStatus()
                            let hasSubscription =
                                subscriptionManager.hasActiveSubscription

                            withAnimation(.easeInOut(duration: 0.25)) {
                                if hasSubscription {
                                    appUnlocked = true
                                } else {
                                    delayPaywallCloseButton = false
                                    showPaywall = true
                                }
                            }
                        } else {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showOnboarding = true
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            guard !didRequestATT else { return }
            didRequestATT = true
            AppsFlyerService.shared.startRespectingTrackingAuthorization()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
