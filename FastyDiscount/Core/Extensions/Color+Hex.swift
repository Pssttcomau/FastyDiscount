import SwiftUI

// MARK: - Color Hex Extension

extension Color {
    /// Creates a `Color` from a hex string such as `"#FF6B35"` or `"FF6B35"`.
    /// Returns `nil` if the string cannot be parsed as a 6-digit RGB hex value.
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6 else { return nil }

        var rgbValue: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgbValue) else { return nil }

        let red   = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let green = Double((rgbValue & 0x00FF00) >> 8)  / 255.0
        let blue  = Double(rgbValue & 0x0000FF)          / 255.0

        self.init(red: red, green: green, blue: blue)
    }
}
