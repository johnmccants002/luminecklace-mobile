import SwiftUI

struct RecipientRevealPresentationView: View {
    let revealState: RecipientRevealState
    var retryAction: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var presentation = RecipientPresentationCoordinator()

    private let particles: [RecipientParticleSpec] = [
        .init(x: 0.24, size: 10, duration: 16, delay: 0.0, drift: -12, opacity: 0.07),
        .init(x: 0.54, size: 8, duration: 18, delay: 1.8, drift: 10, opacity: 0.06),
        .init(x: 0.80, size: 11, duration: 17, delay: 0.9, drift: -9, opacity: 0.07)
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()

                GrainTexture()
                    .ignoresSafeArea()

                if isShowingOpening, !reduceMotion {
                    particleLayer
                        .transition(.opacity)
                }

                content
                    .frame(maxWidth: 480, maxHeight: .infinity)
                    .padding(.horizontal, horizontalPadding(for: geometry.size.width))
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            presentation.start(reduceMotion: reduceMotion)
            presentation.update(revealState: revealState, reduceMotion: reduceMotion)
        }
        .onChange(of: revealState) { _, newState in
            presentation.update(revealState: newState, reduceMotion: reduceMotion)
        }
        .onChange(of: reduceMotion) { _, newValue in
            presentation.update(revealState: revealState, reduceMotion: newValue)
        }
        .onDisappear {
            presentation.cancel()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isShowingOpening {
            RecipientOpeningPresentation(
                reduceMotion: reduceMotion,
                phraseVisible: presentation.phase != .introFading
            )
        } else {
            switch presentation.phase {
            case .messageRevealing, .complete:
                if let lumi = presentation.lumi {
                    RecipientMessageView(
                        lumi: lumi,
                        tokens: presentation.tokens,
                        revealedWordCount: presentation.revealedWordCount,
                        reduceMotion: reduceMotion,
                        timing: presentation.timing
                    )
                    .transition(.opacity)
                }
            case .error:
                terminalContent
            case .loading, .introVisible, .introFading:
                EmptyView()
            }
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.30, green: 0.10, blue: 0.18),
                Color(red: 0.59, green: 0.33, blue: 0.34),
                Color(red: 0.89, green: 0.78, blue: 0.66),
                Color(red: 0.96, green: 0.89, blue: 0.73)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var particleLayer: some View {
        ZStack {
            ForEach(particles) { particle in
                HeartParticle(
                    xPosition: particle.x,
                    startY: 0.96,
                    endY: 0.62,
                    size: particle.size,
                    duration: particle.duration,
                    delay: particle.delay,
                    drift: particle.drift,
                    opacity: particle.opacity
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var isShowingOpening: Bool {
        switch presentation.phase {
        case .loading, .introVisible, .introFading:
            return true
        case .messageRevealing, .complete, .error:
            return false
        }
    }

    @ViewBuilder
    private var terminalContent: some View {
        switch presentation.terminalState {
        case .empty:
            RecipientStatusView(
                icon: "moon.stars",
                title: "No message is waiting yet.",
                detail: "This necklace is ready. There just isn’t a new Lumi to open right now."
            )
        case .unavailable:
            RecipientStatusView(
                icon: "heart.slash",
                title: "This Lumi isn’t available.",
                detail: "The link may be incomplete or the necklace may not be active yet."
            )
        case let .error(error):
            errorContent(for: error)
        case .awaitingInvocation, .resolving, .waiting, .revealing, .revealed, nil:
            EmptyView()
        }
    }

    private func horizontalPadding(for width: CGFloat) -> CGFloat {
        width < 360 ? 20 : 28
    }

    @ViewBuilder
    private func errorContent(for error: RecipientRevealError) -> some View {
        switch error {
        case .invalidInvocation:
            RecipientStatusView(
                icon: "link.badge.plus",
                title: "We couldn’t find this Lumi.",
                detail: error.errorDescription ?? "Please tap the necklace again."
            )
        case .invalidPayload, .network:
            RecipientStatusView(
                icon: error == .network ? "wifi.exclamationmark" : "heart.slash",
                title: error == .network
                    ? "The connection faded."
                    : "This message couldn’t be opened.",
                detail: error.errorDescription ?? "Please try again.",
                actionTitle: retryAction == nil ? nil : "Try Again",
                action: retryAction
            )
        }
    }
}

private struct RecipientOpeningPresentation: View {
    let reduceMotion: Bool
    let phraseVisible: Bool

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 26) {
            LumiPendantMark(reduceMotion: reduceMotion)

            VStack(spacing: 10) {
                Text("A Lumi is opening for you.")
                    .clipTitle()

                Text("Something meaningful is on its way.")
                    .clipBody()
            }
            .opacity(appeared && phraseVisible ? 1 : 0)
            .offset(y: reduceMotion || appeared ? 0 : 10)
            .animation(
                .easeOut(duration: phraseVisible ? (reduceMotion ? 0.25 : 0.7) : 0.5),
                value: phraseVisible
            )

            ProgressView()
                .tint(.white.opacity(0.9))
                .controlSize(.small)
                .opacity(phraseVisible ? 1 : 0)
                .animation(.easeOut(duration: 0.5), value: phraseVisible)
                .accessibilityLabel("Loading your Lumi message")
        }
        .accessibilityElement(children: .contain)
        .onAppear {
            withAnimation(.easeOut(duration: reduceMotion ? 0.25 : 0.7)) {
                appeared = true
            }
        }
    }
}

private struct LumiPendantMark: View {
    let reduceMotion: Bool

    @State private var isGlowing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(isGlowing ? 0.16 : 0.07))
                .frame(width: 112, height: 112)
                .blur(radius: isGlowing ? 13 : 8)
                .scaleEffect(reduceMotion ? 1 : (isGlowing ? 1.08 : 0.92))

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.26),
                            Color(red: 0.77, green: 0.30, blue: 0.38).opacity(0.34)
                        ],
                        center: .topLeading,
                        startRadius: 4,
                        endRadius: 50
                    )
                )
                .frame(width: 76, height: 76)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.32), lineWidth: 1)
                )
                .shadow(color: Color.white.opacity(isGlowing ? 0.28 : 0.12), radius: 18)

            Image(systemName: "heart.fill")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(Color.white.opacity(0.94))
        }
        .accessibilityLabel("Lumi pendant")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.6).repeatForever(autoreverses: true)) {
                isGlowing = true
            }
        }
    }
}

private struct RecipientMessageView: View {
    let lumi: ResolvedLumi
    let tokens: [RecipientMessageToken]
    let revealedWordCount: Int
    let reduceMotion: Bool
    let timing: RecipientRevealTiming

    var body: some View {
        ScrollView {
            revealedText
                .font(.system(.largeTitle, design: .serif, weight: .regular))
                .multilineTextAlignment(.center)
                .lineSpacing(7)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 430)
                .padding(.vertical, 32)
                .accessibilityLabel("Lumi message. \(lumi.text)")
        }
        .scrollIndicators(.hidden)
        .defaultScrollAnchor(.center)
    }

    private var revealedText: Text {
        tokens.reduce(Text("")) { result, token in
            let isVisible = token.wordIndex.map { $0 < revealedWordCount } ?? true
            let shouldRise = !reduceMotion
                && lumi.presentation.revealPreset == .wordRise
                && !isVisible

            let tokenText = Text(verbatim: token.text)
                .foregroundColor(.white.opacity(isVisible ? 1 : 0))
                .baselineOffset(shouldRise ? -timing.wordRise : 0)
            return Text("\(result)\(tokenText)")
        }
    }
}

private struct RecipientStatusView: View {
    let icon: String
    let title: String
    let detail: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(Color.white.opacity(0.92))
                .accessibilityHidden(true)

            Text(title)
                .clipTitle()

            Text(detail)
                .clipBody()

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(ClipPrimaryButtonStyle())
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: 420)
    }
}

private struct GrainTexture: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<72 {
                let x = CGFloat((index * 47) % 101) / 101 * size.width
                let y = CGFloat((index * 71) % 103) / 103 * size.height
                let diameter: CGFloat = index.isMultiple(of: 3) ? 1.2 : 0.7
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)),
                    with: .color(.white.opacity(0.22))
                )
            }
        }
        .blendMode(.softLight)
        .opacity(0.18)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ClipPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.83, green: 0.27, blue: 0.37),
                        Color(red: 0.70, green: 0.10, blue: 0.22)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

private struct RecipientParticleSpec: Identifiable {
    let id = UUID()
    let x: CGFloat
    let size: CGFloat
    let duration: Double
    let delay: Double
    let drift: CGFloat
    let opacity: Double
}

private extension Text {
    func clipTitle() -> some View {
        self
            .font(.system(.largeTitle, design: .serif, weight: .regular))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .lineSpacing(4)
    }

    func clipBody() -> some View {
        self
            .font(.system(.body, design: .serif, weight: .regular))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.white.opacity(0.84))
    }
}
