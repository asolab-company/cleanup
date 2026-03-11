import StoreKit
import SwiftUI

struct PaywallView: View {
    @ObservedObject var subscriptionManager: SubscriptionManager
    let delayCloseButton: Bool
    let onClose: () -> Void
    let onUnlocked: () -> Void

    private let orderedProductIDs = AppSubscriptionIDs.all

    @State private var selectedProductID = AppSubscriptionIDs.yearly
    @State private var showCloseButton = false
    @State private var closeDelayTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    if showCloseButton {
                        Button(action: onClose) {
                            Image("app_ic_close")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(width: 40, height: 40)
                    }
                    Spacer()
                }

                Text("Upgrade for full access")
                    .font(
                        .system(
                            size: DeviceTraits.isSmallDevice ? 26 : 32,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(colorFromHex("101015"))

                Text(
                    "Free up space on your phone in seconds.\nThis app helps you quickly clean your gallery using simple swipes."
                )
                .font(
                    .system(
                        size: DeviceTraits.isSmallDevice ? 14 : 16,
                        weight: .regular
                    )
                )
                .foregroundStyle(colorFromHex("101015", alpha: 0.92))
                if !DeviceTraits.isSmallDevice {
                    Spacer()
                }
                Image("app_bg_paywall")
                    .resizable()
                    .scaledToFit()

                    .frame(maxWidth: .infinity, alignment: .center)
                if !DeviceTraits.isSmallDevice {
                    Spacer()
                }

                VStack(spacing: 14) {
                    VStack(spacing: DeviceTraits.isSmallDevice ? 2 : 10) {
                        ForEach(orderedProductIDs, id: \.self) {
                            productID in
                            productRow(productID: productID)
                        }
                    }

                    HStack(spacing: 8) {
                        Image("ic_shield")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        Text("Cancel Anytime")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(colorFromHex("3873E9"))
                    .frame(maxWidth: .infinity)

                    PrimaryActionButton(
                        title: "Continue",
                        isDisabled: subscriptionManager.isPurchasing
                            || subscriptionManager.product(
                                for: selectedProductID
                            ) == nil,
                        action: purchaseSelected
                    )

                    if let error = subscriptionManager.errorText,
                        !error.isEmpty
                    {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    HStack {
                        Link(
                            "Privacy Policy",
                            destination: AppLinks.privacyPolicy
                        )
                        .foregroundStyle(colorFromHex("918CB7"))
                        Spacer()
                        Button(action: restorePurchases) {
                            Text("Restore")
                                .foregroundStyle(colorFromHex("918CB7"))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Link(
                            "Terms of Use",
                            destination: AppLinks.termsOfUse
                        )
                        .foregroundStyle(colorFromHex("918CB7"))
                    }
                    .font(.system(size: 12, weight: .regular))
                    .padding(.horizontal, 18)
                }

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(
                .horizontal,
                22
            )
            .padding(.bottom)
            .background(
                Image("app_bg")
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            )
        }
        .task {
            await subscriptionManager.loadProducts()
            if await subscriptionManager.hasActiveSubscription() {
                onUnlocked()
            }
        }
        .onAppear(perform: handleCloseButtonAppearance)
        .onDisappear {
            closeDelayTask?.cancel()
            closeDelayTask = nil
        }
    }

    private func productRow(productID: String) -> some View {
        let selected = selectedProductID == productID
        let priceText = subscriptionManager.formattedPrice(for: productID)
        let productImageName =
            selected ? "app_bg_mainplug_sel" : "app_bg_mainplug"
        let periodText: String = {
            if let product = subscriptionManager.product(for: productID),
                let period = product.subscription?.subscriptionPeriod
            {
                switch period.unit {
                case .week:
                    return "Week"
                case .month:
                    return "Month"
                case .year:
                    return "Year"
                case .day:
                    return "\(period.value)d"
                @unknown default:
                    return ""
                }
            }

            switch productID {
            case AppSubscriptionIDs.weekly:
                return "Week"
            case AppSubscriptionIDs.monthly:
                return "Month"
            case AppSubscriptionIDs.yearly:
                return "Year"
            default:
                return ""
            }
        }()

        return Button {
            selectedProductID = productID
        } label: {
            HStack {

                Text(
                    productID == AppSubscriptionIDs.weekly
                        ? "Weekly Access"
                        : (productID == AppSubscriptionIDs.monthly
                            ? "Monthly Access" : "Annual Access")
                )
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(colorFromHex("101015"))
                .offset(y: -4)

                Spacer(minLength: 16)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(priceText)
                        .font(
                            .system(
                                size: DeviceTraits.isSmallDevice ? 16 : 18,
                                weight: .medium
                            )
                        )
                        .foregroundStyle(colorFromHex("66666D"))
                    Text(periodText)
                        .font(
                            .system(size: 12, weight: .medium)
                        )
                        .foregroundStyle(colorFromHex("8585AD"))
                }
                .offset(y: -4)
            }
            .padding(.horizontal, 30)
            .frame(height: 62)
            .background(
                Image(productImageName)
                    .resizable()
                    .scaledToFill()

            )

        }
        .buttonStyle(.plain)
    }

    private func purchaseSelected() {
        Task {
            let success = await subscriptionManager.purchase(
                productID: selectedProductID
            )
            if success {
                onUnlocked()
            }
        }
    }

    private func restorePurchases() {
        Task {
            let restored = await subscriptionManager.restorePurchases()
            if restored {
                onUnlocked()
            }
        }
    }

    private func handleCloseButtonAppearance() {
        closeDelayTask?.cancel()

        if !delayCloseButton {
            showCloseButton = true
            return
        }

        showCloseButton = false
        closeDelayTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                showCloseButton = true
            }
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
