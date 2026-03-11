import SwiftUI
import UIKit

struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var page = 0

    var body: some View {
        ZStack {
            GeometryReader { _ in
                TabView(selection: $page) {
                    ForEach(0..<3, id: \.self) { index in
                        OnboardingImageCard(
                            imageName: index == 0
                                ? "app_ic_onbording03"
                                : (index == 1
                                    ? "app_ic_onbording02"
                                    : "app_ic_onbording01")
                        )
                        .tag(index)
                        .offset(y: DeviceTraits.isSmallDevice ? -90 : 0)

                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .top
                )
                .ignoresSafeArea(.container, edges: .top)
                .offset(y: -windowTopInset())
            }
            .ignoresSafeArea(.container, edges: .top)
            .overlay(alignment: .bottom) {
                VStack(spacing: DeviceTraits.isSmallDevice ? 12 : 18) {
                    Text(
                        page == 0
                            ? "Clean Your Gallery\nWith Swipes"
                            : (page == 1
                                ? "Find Duplicates And\nSimilar Photos"
                                : "Free Up Storage In\nSeconds")
                    )
                    .multilineTextAlignment(.center)
                    .font(
                        .system(
                            size: DeviceTraits.isSmallDevice ? 26 : 32,
                            weight: .heavy
                        )
                    )
                    .foregroundStyle(colorFromHex("3873E9"))
                    .lineSpacing(3)
                    .padding(.horizontal, 8)

                    Text(
                        page == 0
                            ? "Swipe left to delete unwanted photos and videos, swipe right to keep what matters."
                            : (page == 1
                                ? "Quickly remove duplicate and similar photos to free up space."
                                : "Clean your gallery fast and keep your phone organized.")
                    )
                    .multilineTextAlignment(.center)
                    .font(
                        .system(
                            size: DeviceTraits.isSmallDevice ? 14 : 16,
                            weight: .regular
                        )
                    )
                    .foregroundStyle(colorFromHex("1E1E1E", alpha: 0.88))
                    .padding(.horizontal, 24)

                    HStack(spacing: 12) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(
                                    index == page
                                        ? colorFromHex("3873E9")
                                        : colorFromHex("9492C4")
                                )
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.horizontal, 8)

                    PrimaryActionButton(
                        title: page == 2 ? "Get Started" : "Continue",
                        isDisabled: false,
                        action: continueTapped
                    )
                    .padding(.horizontal, 22)

                    VStack(spacing: 2) {
                        Text("By Proceeding You Accept")
                            .font(.system(size: 12))
                            .foregroundStyle(colorFromHex("8585AD"))

                        HStack(spacing: 4) {
                            Link(
                                "Terms Of Use",
                                destination: AppLinks.termsOfUse
                            )
                            Text("And")
                                .foregroundStyle(colorFromHex("8585AD"))
                            Link(
                                "Privacy Policy",
                                destination: AppLinks.privacyPolicy
                            )
                        }
                        .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                }
                .padding(.bottom)
            }
        }
        .background(
            Image("app_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        )
    }

    private func continueTapped() {
        if page < 2 {
            withAnimation(.easeInOut(duration: 0.25)) {
                page += 1
            }
        } else {
            onFinish()
        }
    }

    private func windowTopInset() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap {
            $0 as? UIWindowScene
        }
        let windows = scenes.flatMap { $0.windows }
        return windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.top ?? 0
    }
}

private struct OnboardingImageCard: View {
    let imageName: String

    var body: some View {
        ZStack {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .top
                )
        }
        .frame(maxWidth: .infinity)
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(onFinish: {})
    }
}
