import SwiftUI

enum LumiTheme {
    enum Colors {
        static let ink = Color(red: 0.15, green: 0.16, blue: 0.29)
        static let rose = Color(red: 0.91, green: 0.34, blue: 0.49)
        static let roseSoft = Color(red: 0.97, green: 0.89, blue: 0.91)
        static let blush = Color(red: 0.99, green: 0.95, blue: 0.95)
        static let cream = Color(red: 0.99, green: 0.97, blue: 0.94)
        static let sand = Color(red: 0.98, green: 0.91, blue: 0.84)
        static let gold = Color(red: 0.87, green: 0.69, blue: 0.35)
        static let cardStroke = Color(red: 0.96, green: 0.84, blue: 0.83)
        static let glassTop = Color.white.opacity(0.78)
        static let glassBottom = Color(red: 0.99, green: 0.95, blue: 0.95).opacity(0.92)

        static let appGradient = LinearGradient(
            colors: [cream, blush, roseSoft],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let pageBackground = LinearGradient(
            colors: [
                Color(red: 0.99, green: 0.98, blue: 0.97),
                Color(red: 0.99, green: 0.95, blue: 0.94),
                Color(red: 0.97, green: 0.89, blue: 0.91)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    enum Typography {
        static func display(_ size: CGFloat) -> Font {
            .system(size: size, weight: .medium, design: .serif)
        }

        static func headline(_ size: CGFloat = 22) -> Font {
            .system(size: size, weight: .medium, design: .serif)
        }

        static func body(_ size: CGFloat = 16) -> Font {
            .system(size: size, weight: .regular, design: .rounded)
        }

        static func mono(_ size: CGFloat = 18) -> Font {
            .system(size: size, weight: .semibold, design: .monospaced)
        }
    }
}
