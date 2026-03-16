import StoreKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var subscriptionManager: SubscriptionManager
    let onBack: () -> Void
    let onGoPremium: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 18) {
                HStack {
                    Button(action: onBack) {
                        ZStack {
                            Image("app_ic_back")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 40, height: 40)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("Settings")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(colorFromHex("101015"))

                    Spacer()

                    Color.clear.frame(width: 40, height: 40)
                }
                .padding(.top, 6)

                if !subscriptionManager.hasActiveSubscription {
                    Button(action: onGoPremium) {
                        HStack(spacing: 10) {
                            Image("app_ic_premium")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                            Text("Go to Premium")
                                .font(.system(size: 20, weight: .medium))
                        }
                        .foregroundStyle(colorFromHex("FFFFFF"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 68)
                        .background(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(colorFromHex("3873E9"))
                        )
                        .shadow(
                            color: colorFromHex("3873E9", alpha: 0.8),
                            radius: 6,
                            y: 4
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
                }
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    SettingsRow(
                        iconImageName: "app_ic_sett_1",
                        title: "Privacy Policy",
                        action: { openURL(AppLinks.privacyPolicy) }
                    )
                    .padding(.top)

                    SettingsRow(
                        iconImageName: "app_ic_sett_5",
                        title: "Terms Of Service",
                        action: { openURL(AppLinks.termsOfUse) }
                    )

                    ShareLink(item: AppLinks.shareApp) {
                        SettingsRowContent(
                            iconImageName: "app_ic_sett_4",
                            title: "Share App"
                        )
                    }
                    .buttonStyle(.plain)

                    SettingsRow(
                        iconImageName: "app_ic_sett_3",
                        title: "Support",
                        action: { openURL(AppLinks.support) }
                    )

                    SettingsRow(
                        iconImageName: "app_ic_sett_2",
                        title: "Rate Us",
                        action: { requestReview() }
                    )
                }
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
        .background(
            Image("app_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        )
    }
}

private struct SettingsRow: View {
    let iconImageName: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRowContent(iconImageName: iconImageName, title: title)
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsRowContent: View {
    let iconImageName: String
    let title: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {

                Image(iconImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
            }

            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(colorFromHex("101015"))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .allowsTightening(true)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(colorFromHex("918CB7"))
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: 92)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(colorFromHex("FFFFFF", alpha: 0.50))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(
                            colorFromHex("FFFFFF", alpha: 0.65),
                            lineWidth: 2
                        )
                )
        )
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(
            subscriptionManager: SubscriptionManager(),
            onBack: {},
            onGoPremium: {}
        )
    }
}
