import SwiftUI

struct RecipientClipRootView: View {
    @ObservedObject var viewModel: RecipientClipViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ambientPulse = false

    private let particles: [RecipientParticleSpec] = [
        .init(x: 0.14, size: 11, duration: 18, delay: 0.0, drift: -16, opacity: 0.08),
        .init(x: 0.30, size: 9, duration: 16, delay: 1.4, drift: 14, opacity: 0.07),
        .init(x: 0.50, size: 12, duration: 21, delay: 2.6, drift: -18, opacity: 0.08),
        .init(x: 0.70, size: 10, duration: 19, delay: 0.8, drift: -12, opacity: 0.07),
        .init(x: 0.88, size: 9, duration: 17, delay: 2.2, drift: 14, opacity: 0.07)
    ]

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            if !reduceMotion {
                particleLayer
            }

            VStack(spacing: 22) {
                Spacer(minLength: 28)

                Text("Lumi")
                    .font(.system(size: 22, weight: .light, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.86))
                    .accessibilityHidden(true)

                Spacer(minLength: 12)

                content
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 26)

                Spacer(minLength: 28)
            }
        }
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: viewModel.state)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
                ambientPulse = true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .awaitingInvocation:
            icon("heart.circle")
            Text("Tap your Lumi necklace to begin.")
                .clipTitle()
        case .resolving:
            ProgressView()
                .tint(.white)
            Text("Opening your Lumi...")
                .clipHeadline()
        case let .waiting(lumi):
            header("Something was left here for you.", necklaceName: lumi.necklaceDisplayName)
            HoldToRevealButton {
                viewModel.completeHold(for: lumi)
            }
        case let .revealing(lumi):
            header("Opening...", necklaceName: lumi.necklaceDisplayName)
            revealMotif(for: lumi)
        case let .revealed(lumi, _):
            header("Your Lumi", necklaceName: lumi.necklaceDisplayName)
            Text(lumi.text)
                .font(.system(size: 34, weight: .regular, design: .serif))
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .lineSpacing(7)
                .accessibilityLabel("Lumi message. \(lumi.text)")
        case .empty:
            icon("moon.stars")
            Text("Nothing new is waiting right now.")
                .clipTitle()
            Text("Come back again soon.")
                .clipBody()
        case .unavailable:
            icon("heart.slash")
            Text("This Lumi isn't available right now.")
                .clipTitle()
        case .error:
            icon("sparkles")
            Text("We couldn't open your Lumi.")
                .clipTitle()
            Button("Try Again") {
                viewModel.retry()
            }
            .buttonStyle(ClipPrimaryButtonStyle())
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
                    size: particle.size,
                    duration: particle.duration,
                    delay: particle.delay,
                    drift: particle.drift,
                    opacity: particle.opacity
                )
            }
        }
        .ignoresSafeArea()
    }

    private func header(_ title: String, necklaceName: String) -> some View {
        VStack(spacing: 10) {
            Text(necklaceName)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.78))
            Text(title)
                .clipTitle()
        }
        .accessibilityElement(children: .combine)
    }

    private func icon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 64, weight: .light))
            .foregroundStyle(Color.white.opacity(0.92))
            .padding(.bottom, 4)
            .accessibilityHidden(true)
    }

    private func revealMotif(for lumi: ResolvedLumi) -> some View {
        Image(systemName: lumi.presentation.theme == .champagne ? "sparkles" : "heart.fill")
            .font(.system(size: 82, weight: .regular))
            .foregroundStyle(Color.white.opacity(0.96))
            .padding(40)
            .background(Color.white.opacity(0.13), in: Circle())
            .scaleEffect(ambientPulse ? 1.04 : 0.98)
            .accessibilityHidden(true)
    }
}

private struct HoldToRevealButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isPressing = false
    @State private var progress: CGFloat = 0
    @State private var didComplete = false

    let onComplete: () -> Void

    var body: some View {
        Button {
            complete()
        } label: {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(Color.white.opacity(0.34))
                    .scaleEffect(x: didComplete ? 1 : progress, y: 1, anchor: .leading)
                Text("Hold to reveal")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
            }
        }
        .buttonStyle(.plain)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.28), lineWidth: 1))
        .accessibilityLabel("Reveal Lumi")
        .accessibilityHint("Double tap to reveal, or press and hold for one second.")
        .accessibilityAction(named: Text("Reveal")) {
            complete()
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 1.0)
                .updating($isPressing) { value, state, _ in
                    state = value
                }
                .onChanged { _ in
                    guard !didComplete else { return }
                    withAnimation(.linear(duration: reduceMotion ? 0.01 : 1.0)) {
                        progress = 1
                    }
                }
                .onEnded { finished in
                    if finished {
                        complete()
                    } else {
                        reset()
                    }
                }
        )
        .onChange(of: isPressing) { _, newValue in
            if !newValue, !didComplete, progress < 1 {
                reset()
            }
        }
        .padding(.top, 8)
    }

    private func complete() {
        guard !didComplete else { return }
        didComplete = true
        progress = 1
        onComplete()
    }

    private func reset() {
        withAnimation(.easeOut(duration: 0.18)) {
            progress = 0
        }
    }
}

private struct ClipPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold, design: .rounded))
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
            .font(.system(size: 38, weight: .regular, design: .serif))
            .minimumScaleFactor(0.74)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .lineSpacing(4)
    }

    func clipHeadline() -> some View {
        self
            .font(.system(size: 23, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
    }

    func clipBody() -> some View {
        self
            .font(.system(size: 17, weight: .regular, design: .serif))
            .multilineTextAlignment(.center)
            .foregroundStyle(Color.white.opacity(0.84))
    }
}

#Preview {
    RecipientClipRootView(viewModel: RecipientClipViewModel())
}
