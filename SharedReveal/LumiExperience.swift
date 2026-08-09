import SwiftUI

nonisolated enum LumiExperiencePresetKey: String, Codable, CaseIterable, Hashable, Sendable {
    case classicWordRise = "classic_word_rise_v1"
    case goldenHour = "golden_hour_v1"
    case midnight = "midnight_v1"
    case proudOfYou = "proud_of_you_v1"
    case playful = "playful_v1"
    case calm = "calm_v1"
    case memory = "memory_v1"
    case timedSurprise = "timed_surprise_v1"

    init(serverValue: String?) {
        self = serverValue.flatMap(Self.init(rawValue:)) ?? .classicWordRise
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(serverValue: try? container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

nonisolated struct LumiExperienceContent: Hashable, Sendable {
    let presetKey: LumiExperiencePresetKey
    let primaryText: String
    let secondaryText: String?

    init(
        presetKey: LumiExperiencePresetKey,
        primaryText: String,
        secondaryText: String? = nil
    ) {
        self.presetKey = presetKey
        self.primaryText = primaryText
        self.secondaryText = secondaryText
    }

    var accessibilityText: String {
        [primaryText, secondaryText].compactMap { $0 }.joined(separator: " ")
    }
}

struct LumiExperienceRenderer: View {
    let content: LumiExperienceContent
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0
    @State private var revealedWordCount = 0
    @State private var atmosphereMoves = false

    var body: some View {
        ZStack {
            background
            atmosphere
            message
                .padding(.horizontal, 34)
                .frame(maxWidth: 620)
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityText)
        .task(id: isActive) {
            resetPlayback()
            guard isActive else { return }
            await play()
        }
    }

    @ViewBuilder private var background: some View {
        switch content.presetKey {
        case .classicWordRise, .goldenHour:
            LinearGradient(colors: [.orange, .pink, .purple.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .midnight:
            RadialGradient(colors: [Color(red: 0.17, green: 0.16, blue: 0.37), Color(red: 0.02, green: 0.03, blue: 0.12)], center: .topTrailing, startRadius: 20, endRadius: 760)
        case .proudOfYou:
            LinearGradient(colors: [.white, Color(red: 0.91, green: 0.96, blue: 1), Color(red: 1, green: 0.91, blue: 0.76)], startPoint: .top, endPoint: .bottomTrailing)
        case .playful:
            LinearGradient(colors: [.purple, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .calm:
            LinearGradient(colors: [Color(red: 0.08, green: 0.25, blue: 0.39), Color(red: 0.16, green: 0.43, blue: 0.56), Color(red: 0.30, green: 0.56, blue: 0.64)], startPoint: .top, endPoint: .bottomTrailing)
        case .memory:
            LinearGradient(colors: [Color(red: 0.22, green: 0.12, blue: 0.20), Color(red: 0.45, green: 0.27, blue: 0.32), Color(red: 0.12, green: 0.10, blue: 0.17)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .timedSurprise:
            RadialGradient(colors: [Color(red: 0.57, green: 0.18, blue: 0.44), Color(red: 0.22, green: 0.06, blue: 0.25), Color(red: 0.06, green: 0.02, blue: 0.10)], center: atmosphereMoves ? .topTrailing : .bottomLeading, startRadius: 30, endRadius: 780)
        }
    }

    @ViewBuilder private var atmosphere: some View {
        GeometryReader { proxy in
            switch content.presetKey {
            case .midnight:
                ForEach(Array(stars.enumerated()), id: \.offset) { index, point in
                    Circle().fill(.white.opacity(index.isMultiple(of: 3) ? 0.85 : 0.4))
                        .frame(width: index.isMultiple(of: 4) ? 4 : 2)
                        .position(x: proxy.size.width * point.x, y: proxy.size.height * point.y)
                        .opacity(atmosphereMoves ? 0.25 : 1)
                }
            case .playful:
                let colors: [Color] = [.yellow, .cyan, .orange, .pink, .purple, .yellow]
                let sizes: [CGFloat] = [66, 88, 52, 94, 74, 48]
                let xPositions: [CGFloat] = [0.12, 0.86, 0.78, 0.15, 0.86, 0.22]
                let yPositions: [CGFloat] = [0.18, 0.14, 0.45, 0.57, 0.78, 0.88]
                ForEach(0..<6, id: \.self) { index in
                    Circle().fill(colors[index].opacity(0.48))
                        .frame(width: sizes[index])
                        .position(x: proxy.size.width * xPositions[index], y: proxy.size.height * yPositions[index])
                        .offset(y: atmosphereMoves ? -20 : 20)
                }
            default:
                Circle().fill(accentColor.opacity(0.2))
                    .frame(width: proxy.size.width * 1.15)
                    .blur(radius: 45)
                    .scaleEffect(atmosphereMoves ? 1.1 : 0.75)
                    .position(x: proxy.size.width * 0.52, y: proxy.size.height * 0.45)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder private var message: some View {
        switch content.presetKey {
        case .classicWordRise, .goldenHour:
            wordReveal.font(.system(size: 40, weight: .medium, design: .serif))
                .multilineTextAlignment(.center).lineSpacing(8)
        case .midnight:
            animatedText(font: .system(size: 38, design: .serif), offset: 32)
        case .proudOfYou:
            VStack(spacing: 0) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    Text(word).font(.system(size: 49, weight: .bold, design: .rounded))
                        .opacity(index < revealedWordCount ? 1 : 0)
                        .offset(x: index < revealedWordCount ? 0 : (index.isMultiple(of: 2) ? -24 : 24))
                }
            }.foregroundStyle(foreground)
        case .playful:
            animatedText(font: .system(size: 38, weight: .heavy, design: .rounded), scale: 0.66)
        case .calm:
            animatedText(font: .system(size: 36, weight: .light, design: .rounded), blur: 13)
        case .memory:
            VStack(spacing: 22) {
                Rectangle().fill(foreground.opacity(0.65)).frame(width: phase > 0 ? 54 : 0, height: 1)
                animatedText(font: .system(size: 37, weight: .medium, design: .serif), offset: 22, blur: 8)
            }
        case .timedSurprise:
            VStack(spacing: 30) {
                Text(content.primaryText).font(.system(size: 25, weight: .medium, design: .rounded))
                    .foregroundStyle(foreground.opacity(phase >= 2 ? 0.52 : 0.82))
                    .opacity(phase >= 1 ? 1 : 0)
                if let secondaryText = content.secondaryText {
                    Text(secondaryText).font(.system(size: 39, weight: .semibold, design: .rounded))
                        .foregroundStyle(foreground).multilineTextAlignment(.center)
                        .opacity(phase >= 2 ? 1 : 0).blur(radius: phase >= 2 ? 0 : 10)
                }
            }
        }
    }

    private func animatedText(font: Font, offset: CGFloat = 0, scale: CGFloat = 1, blur: CGFloat = 9) -> some View {
        Text(content.primaryText).font(font).foregroundStyle(foreground)
            .multilineTextAlignment(.center).lineSpacing(10)
            .opacity(phase > 0 ? 1 : 0).blur(radius: phase > 0 ? 0 : blur)
            .offset(y: phase > 0 ? 0 : offset).scaleEffect(phase > 0 ? 1 : scale)
    }

    private var wordReveal: Text {
        words.enumerated().reduce(Text("")) { result, entry in
            let prefix = entry.offset == 0 ? "" : " "
            return result + Text(prefix + entry.element).foregroundColor(foreground.opacity(entry.offset < revealedWordCount ? 1 : 0))
        }
    }

    private var words: [String] { content.primaryText.split(separator: " ").map(String.init) }
    private var foreground: Color { content.presetKey == .proudOfYou ? Color(red: 0.13, green: 0.15, blue: 0.24) : .white }
    private var accentColor: Color { content.presetKey == .calm ? .cyan : .pink }

    @MainActor private func resetPlayback() {
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { phase = 0; revealedWordCount = 0; atmosphereMoves = false }
    }

    @MainActor private func play() async {
        if reduceMotion { phase = 3; revealedWordCount = words.count; return }
        withAnimation(.easeInOut(duration: content.presetKey == .playful ? 3.4 : 7).repeatForever(autoreverses: true)) { atmosphereMoves = true }
        do {
            switch content.presetKey {
            case .classicWordRise, .goldenHour, .proudOfYou:
                try await Task.sleep(for: .milliseconds(350))
                for index in 1...max(words.count, 1) {
                    try Task.checkCancellation()
                    withAnimation(.easeOut(duration: 0.3)) { revealedWordCount = index }
                    try await Task.sleep(for: .milliseconds(content.presetKey == .proudOfYou ? 180 : 155))
                }
            case .timedSurprise:
                try await Task.sleep(for: .milliseconds(500)); withAnimation(.easeOut(duration: 0.9)) { phase = 1 }
                try await Task.sleep(for: .milliseconds(1750)); withAnimation(.easeInOut(duration: 1.25)) { phase = 2 }
            default:
                try await Task.sleep(for: .milliseconds(520)); withAnimation(.easeOut(duration: 1.4)) { phase = 1 }
            }
        } catch { return }
    }

    private let stars: [CGPoint] = [
        .init(x: 0.11, y: 0.12), .init(x: 0.27, y: 0.22), .init(x: 0.43, y: 0.09),
        .init(x: 0.73, y: 0.18), .init(x: 0.89, y: 0.31), .init(x: 0.18, y: 0.42),
        .init(x: 0.58, y: 0.35), .init(x: 0.82, y: 0.51), .init(x: 0.34, y: 0.60),
        .init(x: 0.68, y: 0.70), .init(x: 0.12, y: 0.78), .init(x: 0.92, y: 0.84)
    ]
}
