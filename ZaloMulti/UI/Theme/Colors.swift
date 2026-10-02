import SwiftUI

extension Color {

    static let zaloPrimary = Color(hex: "#0068FF")
    static let zaloDark = Color(hex: "#0052CC")
    static let zaloLight = Color(hex: "#E8F0FE")

    static let statusRunning = Color(hex: "#007AFF")
    static let statusStopped = Color.secondary
    static let statusPaused = Color(hex: "#FF9500")
    static let statusCreating = Color(hex: "#5AC8FA")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension Color {
    static let avatarGradients: [(Color, Color)] = [
        (Color(hex: "#007AFF"), Color(hex: "#5E5CE6")),
        (Color(hex: "#30D158"), Color(hex: "#34C759")),
        (Color(hex: "#FF6B35"), Color(hex: "#FF9500")),
        (Color(hex: "#BF5AF2"), Color(hex: "#AF52DE")),
        (Color(hex: "#FF3B30"), Color(hex: "#FF6B6B")),
        (Color(hex: "#5AC8FA"), Color(hex: "#007AFF")),
        (Color(hex: "#FF9500"), Color(hex: "#FFCC00")),
        (Color(hex: "#64D2FF"), Color(hex: "#5AC8FA")),
    ]

    static func avatarGradient(for index: Int) -> (Color, Color) {
        avatarGradients[index % avatarGradients.count]
    }
}
