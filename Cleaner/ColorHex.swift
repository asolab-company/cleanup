import SwiftUI

func colorFromHex(_ hex: String, alpha: Double = 1.0) -> Color {
    let hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "#", with: "")
    guard hex.count == 6, let value = UInt64(hex, radix: 16) else {
        return Color.red
    }

    return Color(
        .sRGB,
        red: Double((value >> 16) & 0xFF) / 255.0,
        green: Double((value >> 8) & 0xFF) / 255.0,
        blue: Double(value & 0xFF) / 255.0,
        opacity: alpha
    )
}
