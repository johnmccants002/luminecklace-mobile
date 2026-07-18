import SwiftUI

enum LumiTheme {
    enum Colors {
        static let cherry = Color(red: 0.62, green: 0.07, blue: 0.16)
        static let crimson = Color(red: 0.78, green: 0.10, blue: 0.24)
        static let blush = Color(red: 0.98, green: 0.86, blue: 0.89)
        static let cream = Color(red: 0.99, green: 0.96, blue: 0.93)
        static let ink = Color(red: 0.08, green: 0.07, blue: 0.09)
        static let cardStroke = Color.white.opacity(0.32)
        static let glassTop = Color.white.opacity(0.22)
        static let glassBottom = Color.white.opacity(0.08)

        static let appGradient = LinearGradient(
            colors: [cherry, crimson, blush.opacity(0.65)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let pageBackground = LinearGradient(
            colors: [ink, cherry.opacity(0.75), cream.opacity(0.35)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    enum Typography {
        static func display(_ size: CGFloat) -> Font {
            .system(size: size, weight: .bold, design: .serif)
        }

        static func headline(_ size: CGFloat = 22) -> Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }

        static func body(_ size: CGFloat = 16) -> Font {
            .system(size: size, weight: .regular, design: .rounded)
        }

        static func mono(_ size: CGFloat = 18) -> Font {
            .system(size: size, weight: .semibold, design: .monospaced)
        }
    }
}
