import SwiftUI
import UIKit

struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var page = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $page) {
                ForEach(0..<3, id: \.self) { index in
                    OnboardingImageCard(imageName: imageName(for: index))
                        .tag(index)
                        .offset(y: DeviceTraits.isSmallDevice ? -40 : -65)
                       
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack(spacing: DeviceTraits.isSmallDevice ? 8 : 12) {
                Text(
                    page == 0
                        ? "Optimize Your\nStorage!"
                        : (page == 1
                            ? "Compress Videos\nsmartly!"
                            : "Begin Your\nCleanup!")
                )
                .multilineTextAlignment(.center)
                .font(
                    .system(
                        size: DeviceTraits.isSmallDevice ? 24 : 32,
                        weight: .heavy
                    )
                )
                .foregroundStyle(colorFromHex("161616"))
                .lineSpacing(3)
                .padding(.horizontal, 8)

                Text(
                    page == 0
                        ? "Quickly scan and remove unnecessary files to keep your device running smooth."
                        : (page == 1
                            ? "Reduce file size without losing quality to save space instantly."
                            : "Easily clean outdated or unused contacts to keep your list organized.")
                )
                .multilineTextAlignment(.center)
                .font(
                    .system(
                        size: DeviceTraits.isSmallDevice ? 14 : 18,
                        weight: .regular
                    )
                )
                .foregroundStyle(colorFromHex("#161616", alpha: 0.88))
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
                    title: page == 2 ? "Start" : "Next",
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
            .padding(.top, DeviceTraits.isSmallDevice ? 12 : 20)
            .background(
                UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: 38,
                        bottomLeading: 0,
                        bottomTrailing: 0,
                        topTrailing: 38
                    ),
                    style: .continuous
                )
                .fill(.white)
                .shadow(
                    color: colorFromHex("1E1E1E", alpha: 0.08),
                    radius: 18,
                    y: -2
                )
                .ignoresSafeArea()
            )
        }
        .background(
            Image("app_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                
        )
     
    }

    private func imageName(for index: Int) -> String {
        switch index {
        case 0:
            return "app_ic_onbording01"
        case 1:
            return "app_ic_onbording02"
        default:
            return "app_ic_onbording03"
        }
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

    private func windowBottomInset() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap {
            $0 as? UIWindowScene
        }
        let windows = scenes.flatMap { $0.windows }
        return windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.bottom ?? 0
    }
}

private struct OnboardingImageCard: View {
    let imageName: String

    var body: some View {
        GeometryReader { geometry in
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height + 24,
                    alignment: .top
                )
                .clipped()
        }
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(onFinish: {})
    }
}
