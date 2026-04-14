import SwiftUI

private enum RootPhase: Equatable {
    case splash
    case onboarding
    case webPaywall(URL)
    case nativePaywall
    case main
}

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding =
        false
    @StateObject private var subscriptionManager = SubscriptionManager()

    @State private var phase: RootPhase = .splash
    @State private var splashStartedAt: Date?
    @State private var delayPaywallCloseButton = true
    @State private var didRequestATT = false

    @State private var isWebShellLoading = false
    @State private var webLoadingStartedAt: Date?

    private static let minimumSplashDuration: TimeInterval = 2.0

    var body: some View {
        Group {
            switch phase {
            case .splash:
                LoadingView {
                    Task { await runBootstrap() }
                }

            case .onboarding:
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        hasCompletedOnboarding = true
                        delayPaywallCloseButton = true
                        phase = .nativePaywall
                    }
                }

            case .webPaywall(let url):
                ZStack {
                    CleanerPaywallWebView(
                        url: url,
                        onPaymentSuccess: handleWebPaymentSuccess,
                        onInitialPageReady: handleWebInitialPageReady
                    )
                    .ignoresSafeArea()

                    if isWebShellLoading {
                        WebShellLoadingOverlay()
                            .transition(.opacity)
                            .zIndex(1)
                    }
                }

            case .nativePaywall:
                PaywallView(
                    subscriptionManager: subscriptionManager,
                    delayCloseButton: delayPaywallCloseButton,
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            phase = .main
                        }
                    },
                    onUnlocked: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            phase = .main
                        }
                    }
                )

            case .main:
                MainView(subscriptionManager: subscriptionManager) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        delayPaywallCloseButton = false
                        phase = .nativePaywall
                    }
                }
            }
        }
        .animation(nil, value: phase)
        .onAppear {
            if splashStartedAt == nil {
                splashStartedAt = Date()
            }
            guard !didRequestATT else { return }
            didRequestATT = true
            AppsFlyerService.shared.startRespectingTrackingAuthorization()
        }
        .onChange(of: subscriptionManager.hasActiveSubscription) { _, sub in
            guard sub else { return }
            if case .nativePaywall = phase {
                withAnimation(.easeInOut(duration: 0.25)) {
                    phase = .main
                }
            }
        }
    }

    @MainActor
    private func runBootstrap() async {
        await subscriptionManager.refreshSubscriptionStatus()

        if let start = splashStartedAt {
            let elapsed = Date().timeIntervalSince(start)
            let remaining = max(0, Self.minimumSplashDuration - elapsed)
            if remaining > 0 {
                try? await Task.sleep(
                    nanoseconds: UInt64(remaining * 1_000_000_000)
                )
            }
        }

        if subscriptionManager.hasActiveSubscription {
            withAnimation(.easeInOut(duration: 0.25)) {
                phase = .main
            }
            return
        }

        if let url = await CleanerStartupRemoteConfig.fetchWebURL() {
            webLoadingStartedAt = Date()
            isWebShellLoading = true
            withAnimation(.easeInOut(duration: 0.25)) {
                phase = .webPaywall(url)
            }
            return
        }

        if hasCompletedOnboarding {
            delayPaywallCloseButton = false
            withAnimation(.easeInOut(duration: 0.25)) {
                phase = .nativePaywall
            }
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                phase = .onboarding
            }
        }
    }

    @MainActor
    private func handleWebPaymentSuccess() {
        hasCompletedOnboarding = true
        subscriptionManager.unlockPremiumFromWebCheckout()
        isWebShellLoading = false
        webLoadingStartedAt = nil
        withAnimation(.easeInOut(duration: 0.25)) {
            phase = .main
        }
    }

    @MainActor
    private func handleWebInitialPageReady() {
        let startedAt = webLoadingStartedAt
        Task {
            if let start = startedAt {
                let elapsed = Date().timeIntervalSince(start)
                let remaining = max(0, Self.minimumSplashDuration - elapsed)
                if remaining > 0 {
                    try? await Task.sleep(
                        nanoseconds: UInt64(remaining * 1_000_000_000)
                    )
                }
            }
            await MainActor.run {
                if isWebShellLoading {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isWebShellLoading = false
                    }
                }
                webLoadingStartedAt = nil
            }
        }
    }
}

private struct WebShellLoadingOverlay: View {
    private let progress: Double = 1.0

    var body: some View {
        Image("app_logo")
            .resizable()
            .scaledToFit()
            .frame(width: 170, height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
            .shadow(
                color: colorFromHex("000000", alpha: 0.20),
                radius: 10,
                y: 5
            )
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .center
            )
            .overlay(alignment: .bottom) {
                VStack(spacing: 8) {
                    ProgressView(value: progress, total: 1)
                        .progressViewStyle(.linear)
                        .tint(colorFromHex("3873E9"))
                        .frame(maxWidth: 250)
                        .scaleEffect(x: 1, y: 1.6, anchor: .center)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(colorFromHex("ABB7EF"))
                                .frame(height: 8)
                        )

                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 18, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(colorFromHex("8585AD"))
                }
                .padding(.horizontal, 24)
                .padding(.bottom)
            }
            .background(
                Image("app_bg")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
