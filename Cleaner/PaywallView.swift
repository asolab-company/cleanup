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
        GeometryReader { _ in
            VStack(alignment: .leading, spacing: 12) {
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

                PaywallStorageWarningView()

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
            if await subscriptionManager.checkActiveSubscription() {
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

private struct PaywallStorageWarningView: View {
    private let targetMemoryUsage: Double = 0.923
    private let maxBadgeValue = 99

    @State private var currentUsage: Double = 0
    @State private var currentBadgeValue: Int = 0
    @State private var plusOpacity: Double = 0
    @State private var animationTask: Task<Void, Never>?

    private var progressTint: Color {
        interpolatedProgressColor(
            progress: currentUsage / targetMemoryUsage
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DeviceTraits.isSmallDevice ? 12 : 16) {
            if !DeviceTraits.isSmallDevice {
                HStack {
                    Spacer()
                    ZStack(alignment: .topTrailing) {
                        Image("app_ic_paywall")
                            .resizable()
                            .scaledToFit()
                            .frame(
                                width: 156,
                                height: 156
                            )

                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text("\(currentBadgeValue)")
                            Text("+")
                                .opacity(plusOpacity)
                                .scaleEffect(0.85 + (0.15 * plusOpacity))
                        }
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 34)
                        .background(
                            Circle()
                                .fill(colorFromHex("FF001F"))
                        )
                        .offset(x: -4, y: 15)
                    }
                    Spacer()
                }
            }
         

            Text("Memory usage")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(colorFromHex("1B1C24"))

            HStack(spacing: 18) {
                GeometryReader { proxy in
                    let progressWidth = max(0, proxy.size.width - 10)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(colorFromHex("DEB5C9"))

                        Capsule()
                            .fill(progressTint)
                            .frame(width: progressWidth * currentUsage)
                            .padding(5)
                    }
                }
                .frame(height: DeviceTraits.isSmallDevice ? 24 : 24)

                Text(
                    "\((currentUsage * 100).formatted(.number.precision(.fractionLength(1))))%"
                )
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(progressTint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }

            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: DeviceTraits.isSmallDevice ? 24 : 24))
                    .foregroundStyle(colorFromHex("E30034"))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: DeviceTraits.isSmallDevice ? 8 : 10) {
                    Text("Almost out of memory")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(colorFromHex("1D1D24"))

                    Text("To avoid storage getting full, please clean up your phone.")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(colorFromHex("5F6168"))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, DeviceTraits.isSmallDevice ? 24 : 28)
            .padding(.vertical, DeviceTraits.isSmallDevice ? 22 : 26)
            .frame(
                maxWidth: .infinity,
                minHeight: 100,
                maxHeight: 100,
                alignment: .leading
            )
            .background(
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(colorFromHex("DC002A", alpha: 0.1))
                    .overlay {
                        RoundedRectangle(cornerRadius: 36, style: .continuous)
                            .stroke(.white.opacity(0.45), lineWidth: 2)
                    }
            )
        }
    
        .onAppear(perform: startAnimations)
        .onDisappear {
            animationTask?.cancel()
            animationTask = nil
        }
    }

    private func startAnimations() {
        animationTask?.cancel()

        currentUsage = 0
        currentBadgeValue = 0
        plusOpacity = 0

        animationTask = Task {
            let frameNanoseconds: UInt64 = 16_666_667
            let startTime = CACurrentMediaTime()
            let firstDuration = 2.0

            while !Task.isCancelled {
                let elapsed = CACurrentMediaTime() - startTime
                let progress = min(max(elapsed / firstDuration, 0), 1)

                await MainActor.run {
                    currentUsage = targetMemoryUsage * progress
                    currentBadgeValue = Int(
                        (Double(maxBadgeValue) * progress).rounded(.down)
                    )
                }

                if progress >= 1 {
                    break
                }

                try? await Task.sleep(nanoseconds: frameNanoseconds)
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                currentUsage = targetMemoryUsage
                currentBadgeValue = maxBadgeValue
            }

            let plusStartTime = CACurrentMediaTime()
            let plusDuration = 2.0

            while !Task.isCancelled {
                let elapsed = CACurrentMediaTime() - plusStartTime
                let progress = min(max(elapsed / plusDuration, 0), 1)

                await MainActor.run {
                    plusOpacity = progress
                }

                if progress >= 1 {
                    break
                }

                try? await Task.sleep(nanoseconds: frameNanoseconds)
            }
        }
    }

    private func interpolatedProgressColor(progress: Double) -> Color {
        let clamped = min(max(progress, 0), 1)

        let startRed = 0x38
        let startGreen = 0x73
        let startBlue = 0xE9

        let endRed = 0xE3
        let endGreen = 0x00
        let endBlue = 0x34

        let red = Double(startRed)
            + (Double(endRed - startRed) * clamped)
        let green = Double(startGreen)
            + (Double(endGreen - startGreen) * clamped)
        let blue = Double(startBlue)
            + (Double(endBlue - startBlue) * clamped)

        return Color(
            .sRGB,
            red: red / 255,
            green: green / 255,
            blue: blue / 255,
            opacity: 1
        )
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
