import SwiftUI

enum BenzoTheme {
    static let accent = Color(hex: "d4749c")
    static let accentSoft = Color(hex: "d4749c").opacity(0.08)
    static let background = Color(hex: "f6f5f3")
    static let surface = Color.white
    static let text = Color(hex: "1a1a1a")
    static let textMuted = Color(hex: "999999")
    static let textFaint = Color(hex: "cccccc")
    static let border = Color.black.opacity(0.06)
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255
        )
    }
}
