import SwiftUI

nonisolated enum LumiTextSizeKey: String, Codable, CaseIterable, Sendable {
    case small
    case medium
    case large

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .medium
    }
}

nonisolated enum LumiTextAlignmentKey: String, Codable, CaseIterable, Sendable {
    case leading
    case center
    case trailing

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .center
    }
}

nonisolated enum LumiTextPositionKey: String, Codable, CaseIterable, Sendable {
    case top
    case center
    case bottom

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .center
    }
}

nonisolated enum LumiBackgroundKey: String, Codable, CaseIterable, Sendable {
    case heart
    case champagne
    case rose
    case midnight

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .heart
    }
}

nonisolated enum LumiFontKey: String, Codable, CaseIterable, Sendable {
    case serif
    case rounded

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: value) ?? .serif
    }
}

nonisolated struct LumiPresentationLayout: Codable, Hashable, Sendable {
    static let `default` = LumiPresentationLayout()

    let textSize: LumiTextSizeKey
    let textAlignment: LumiTextAlignmentKey
    let textPosition: LumiTextPositionKey

    init(
        textSize: LumiTextSizeKey = .medium,
        textAlignment: LumiTextAlignmentKey = .center,
        textPosition: LumiTextPositionKey = .center
    ) {
        self.textSize = textSize
        self.textAlignment = textAlignment
        self.textPosition = textPosition
    }

    private enum CodingKeys: String, CodingKey {
        case textSize
        case textAlignment
        case textPosition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        textSize = try container.decodeIfPresent(LumiTextSizeKey.self, forKey: .textSize) ?? .medium
        textAlignment = try container.decodeIfPresent(LumiTextAlignmentKey.self, forKey: .textAlignment) ?? .center
        textPosition = try container.decodeIfPresent(LumiTextPositionKey.self, forKey: .textPosition) ?? .center
    }
}

enum LumiTextLayoutResolver {
    static func textAlignment(for key: LumiTextAlignmentKey) -> TextAlignment {
        switch key {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    static func horizontalAlignment(for key: LumiTextAlignmentKey) -> Alignment {
        switch key {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    static func verticalAlignment(for key: LumiTextPositionKey) -> Alignment {
        switch key {
        case .top: .top
        case .center: .center
        case .bottom: .bottom
        }
    }

    static func scrollAnchor(for key: LumiTextPositionKey) -> UnitPoint {
        switch key {
        case .top: .top
        case .center: .center
        case .bottom: .bottom
        }
    }

    /// The selected size remains semantic. For long messages we only reduce its
    /// effective point size within a readable bound, then rely on scrolling.
    static func effectivePointSize(
        for key: LumiTextSizeKey,
        characterCount: Int
    ) -> CGFloat {
        let preferred: CGFloat
        let minimum: CGFloat
        switch key {
        case .small:
            preferred = 26
            minimum = 23
        case .medium:
            preferred = 35
            minimum = 26
        case .large:
            preferred = 44
            minimum = 29
        }

        switch characterCount {
        case ...160:
            return preferred
        case ...300:
            return max(minimum, preferred * 0.88)
        default:
            return max(minimum, preferred * 0.76)
        }
    }

    static func fontDesign(for key: LumiFontKey) -> Font.Design {
        switch key {
        case .serif: .serif
        case .rounded: .rounded
        }
    }

}

extension LumiTextAlignmentKey {
    var accessibilityName: String {
        switch self {
        case .leading: "Align left"
        case .center: "Align center"
        case .trailing: "Align right"
        }
    }

    var systemImage: String {
        switch self {
        case .leading: "text.alignleft"
        case .center: "text.aligncenter"
        case .trailing: "text.alignright"
        }
    }
}

extension LumiTextPositionKey {
    var systemImage: String {
        switch self {
        case .top: "rectangle.topthird.inset.filled"
        case .center: "rectangle.center.inset.filled"
        case .bottom: "rectangle.bottomthird.inset.filled"
        }
    }
}

enum LumiBackgroundResolver {
    static func background(for key: LumiBackgroundKey) -> LinearGradient {
        let colors: [Color]
        switch key {
        case .heart:
            colors = [
                Color(red: 0.30, green: 0.10, blue: 0.18),
                Color(red: 0.70, green: 0.28, blue: 0.38),
                Color(red: 0.96, green: 0.74, blue: 0.68)
            ]
        case .champagne:
            colors = [
                Color(red: 0.30, green: 0.20, blue: 0.14),
                Color(red: 0.67, green: 0.50, blue: 0.28),
                Color(red: 0.96, green: 0.88, blue: 0.68)
            ]
        case .rose:
            colors = [
                Color(red: 0.36, green: 0.12, blue: 0.24),
                Color(red: 0.72, green: 0.34, blue: 0.48),
                Color(red: 0.96, green: 0.76, blue: 0.80)
            ]
        case .midnight:
            colors = [
                Color(red: 0.04, green: 0.06, blue: 0.16),
                Color(red: 0.10, green: 0.14, blue: 0.30),
                Color(red: 0.22, green: 0.20, blue: 0.42)
            ]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func foreground(for key: LumiBackgroundKey) -> Color {
        .white
    }
}
