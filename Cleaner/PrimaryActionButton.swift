import SwiftUI

struct PrimaryActionButton: View {
    let title: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(colorFromHex("FFFFFF"))
                .frame(maxWidth: .infinity)
                .frame(height: DeviceTraits.isSmallDevice ? 60 : 68)
                .background(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(colorFromHex("3873E9"))
                )
                .shadow(
                    color: colorFromHex("3873E9", alpha: 0.8),
                    radius: 4,
                    y: 4
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

struct PrimaryActionButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            PrimaryActionButton(
                title: "Continue",
                isDisabled: false,
                action: {}
            )

            PrimaryActionButton(
                title: "Continue",
                isDisabled: true,
                action: {}
            )
        }
        .padding(20)

    }
}
