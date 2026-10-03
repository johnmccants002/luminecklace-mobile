import SwiftUI

struct RecipientRevealPresentationView: View {
    let revealState: RecipientRevealState
    var retryAction: (() -> Void)?
    var retryConfirmationAction: (() -> Void)?
    var feedbackState: RecipientFeedbackPresentationState = .disabled
    var selectReaction: ((LumiReaction) -> Void)?
    var retryReaction: (() -> Void)?
    var setResponseComposerPresented: ((Bool) -> Void)?
    var updateResponseDraft: ((String) -> Void)?
    var submitResponse: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var presentation = RecipientPresentationCoordinator()
    @State private var showsFeedbackControls = false

    private let particles: [RecipientParticleSpec] = [
        .init(x: 0.24, size: 10, duration: 16, delay: 0.0, drift: -12, opacity: 0.07),
        .init(x: 0.54, size: 8, duration: 18, delay: 1.8, drift: 10, opacity: 0.06),
        .init(x: 0.80, size: 11, duration: 17, delay: 0.9, drift: -9, opacity: 0.07)
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if !isShowingOpening,
                   let lumi = presentation.lumi,
                   lumi.experiencePresetKey != .classicWordRise {
                    LumiExperienceRenderer(
                        content: LumiExperienceContent(
                            presetKey: lumi.experiencePresetKey,
                            primaryText: lumi.text,
                            secondaryText: lumi.secondaryText
                        ),
                        isActive: true,
                        layer: .backgroundOnly
                    )
                    .ignoresSafeArea()
                } else {
                    backgroundGradient
                        .ignoresSafeArea()
                }

                GrainTexture()
                    .ignoresSafeArea()

                if isShowingOpening, !reduceMotion {
                    particleLayer
                        .transition(.opacity)
                }

                content
                    .frame(maxWidth: 480, maxHeight: .infinity)
                    .padding(.horizontal, horizontalPadding(for: geometry.size.width))
                    .padding(.vertical, 20)
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
        .task(id: feedbackVisibilityTrigger) {
            showsFeedbackControls = false
            guard feedbackVisibilityTrigger.isEligible else { return }

            if !reduceMotion {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
            }

            withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.4)) {
                showsFeedbackControls = true
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.2) : .easeInOut(duration: 0.45),
            value: isShowingOpening
        )
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
                        showsAttachmentAction: presentation.phase == .complete,
                        showsFeedbackControls: showsFeedbackControls,
                        showsConfirmationRetry: presentation.phase == .complete
                            && isConfirmationTemporarilyFailed,
                        feedbackState: feedbackState,
                        reduceMotion: reduceMotion,
                        timing: presentation.timing,
                        retryConfirmationAction: retryConfirmationAction,
                        selectReaction: selectReaction,
                        retryReaction: retryReaction,
                        setResponseComposerPresented: setResponseComposerPresented,
                        updateResponseDraft: updateResponseDraft,
                        submitResponse: submitResponse
                    )
                    .transition(messageTransition(for: lumi.presentation.textPosition))
                }
            case .error:
                terminalContent
            case .loading, .introVisible, .introFading:
                EmptyView()
            }
        }
    }

    private var backgroundGradient: some View {
        LumiBackgroundResolver.background(
            for: isShowingOpening
                ? .heart
                : presentation.lumi?.presentation.background ?? .heart
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

    private var isConfirmationTemporarilyFailed: Bool {
        guard feedbackState.isEnabled,
              case let .revealed(_, confirmationState) = revealState,
              confirmationState == .temporarilyFailed else {
            return false
        }
        return true
    }

    private var feedbackVisibilityTrigger: FeedbackVisibilityTrigger {
        let isConfirmed: Bool
        if case let .revealed(_, confirmationState) = revealState,
           case .confirmed = confirmationState {
            isConfirmed = true
        } else {
            isConfirmed = false
        }

        return FeedbackVisibilityTrigger(
            isEligible: feedbackState.isEnabled
                && presentation.phase == .complete
                && isConfirmed,
            reduceMotion: reduceMotion
        )
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

    private func messageTransition(for position: LumiTextPositionKey) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        switch position {
        case .top:
            return .move(edge: .top).combined(with: .opacity)
        case .center:
            return .opacity
        case .bottom:
            return .move(edge: .bottom).combined(with: .opacity)
        }
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
    let showsAttachmentAction: Bool
    let showsFeedbackControls: Bool
    let showsConfirmationRetry: Bool
    let feedbackState: RecipientFeedbackPresentationState
    let reduceMotion: Bool
    let timing: RecipientRevealTiming
    var retryConfirmationAction: (() -> Void)?
    var selectReaction: ((LumiReaction) -> Void)?
    var retryReaction: (() -> Void)?
    var setResponseComposerPresented: ((Bool) -> Void)?
    var updateResponseDraft: ((String) -> Void)?
    var submitResponse: (() -> Void)?

    @Environment(\.openURL) private var openURL

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 22) {
                    Group {
                        if lumi.experiencePresetKey == .classicWordRise {
                            revealedText
                        } else {
                            LumiExperienceRenderer(
                                content: LumiExperienceContent(
                                    presetKey: lumi.experiencePresetKey,
                                    primaryText: lumi.text,
                                    secondaryText: lumi.secondaryText
                                ),
                                isActive: true,
                                layer: .messageOnly
                            )
                        }
                    }
                        .font(
                            .system(
                                size: LumiTextLayoutResolver.effectivePointSize(
                                    for: lumi.presentation.textSize,
                                    characterCount: lumi.text.count
                                ),
                                weight: .regular,
                                design: LumiTextLayoutResolver.fontDesign(for: lumi.presentation.font)
                            )
                        )
                        .multilineTextAlignment(
                            LumiTextLayoutResolver.textAlignment(for: lumi.presentation.textAlignment)
                        )
                        .lineSpacing(7)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(
                            maxWidth: 430,
                            alignment: LumiTextLayoutResolver.horizontalAlignment(
                                for: lumi.presentation.textAlignment
                            )
                        )
                        .frame(
                            maxWidth: .infinity,
                            minHeight: max(
                                0,
                                geometry.size.height - reservedTrailingHeight
                            ),
                            alignment: LumiTextLayoutResolver.verticalAlignment(
                                for: lumi.presentation.textPosition
                            )
                        )
                        .padding(.top, 32)
                        .accessibilityLabel(
                            "Lumi message. \(lumi.text) \(lumi.secondaryText ?? "")"
                        )

                    if showsAttachmentAction,
                       let attachment = lumi.attachment,
                       let destinationURL = attachment.supportedDestinationURL {
                        Button {
                            openURL(destinationURL)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 20, weight: .semibold))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(attachment.safeCallToActionLabel)
                                        .font(.headline)
                                    Text(attachment.recipientDetail ?? "Website")
                                        .font(.caption)
                                        .opacity(0.76)
                                }

                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .opacity(0.7)
                            }
                            .foregroundStyle(
                                LumiBackgroundResolver.foreground(for: lumi.presentation.background)
                            )
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(.white.opacity(0.22), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: 430)
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .move(edge: .bottom))
                        )
                        .accessibilityLabel(attachment.safeCallToActionLabel)
                        .accessibilityHint(attachment.openAccessibilityHint)
                    }

                    if showsConfirmationRetry {
                        VStack(spacing: 10) {
                            Text("The connection faded before this Lumi finished opening.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.82))
                                .multilineTextAlignment(.center)

                            if let retryConfirmationAction {
                                Button("Reconnect", action: retryConfirmationAction)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(minHeight: 44)
                                    .padding(.horizontal, 20)
                                    .background(.white.opacity(0.14), in: Capsule())
                            }
                        }
                        .frame(maxWidth: 430)
                        .padding(16)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                        .transition(.opacity)
                    }

                    if showsFeedbackControls {
                        RecipientFeedbackView(
                            state: feedbackState,
                            selectReaction: selectReaction,
                            retryReaction: retryReaction,
                            setResponseComposerPresented: setResponseComposerPresented,
                            updateResponseDraft: updateResponseDraft,
                            submitResponse: submitResponse
                        )
                        .transition(
                            reduceMotion
                                ? .opacity
                                : .opacity.combined(with: .offset(y: 10))
                        )
                    }
                }
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(
                LumiTextLayoutResolver.scrollAnchor(for: lumi.presentation.textPosition)
            )
        }
        .animation(.easeOut(duration: reduceMotion ? 0.2 : 0.35), value: showsAttachmentAction)
        .animation(.easeOut(duration: reduceMotion ? 0.2 : 0.4), value: showsFeedbackControls)
    }

    private var supportedAttachmentURL: URL? {
        lumi.attachment?.supportedDestinationURL
    }

    private var reservedTrailingHeight: CGFloat {
        var height: CGFloat = 64
        if showsAttachmentAction && supportedAttachmentURL != nil {
            height += 100
        }
        if showsConfirmationRetry {
            height += 150
        }
        if showsFeedbackControls {
            height += 300
        }
        return height
    }

    private var revealedText: Text {
        tokens.reduce(Text("")) { result, token in
            let isVisible = token.wordIndex.map { $0 < revealedWordCount } ?? true
            let shouldRise = !reduceMotion
                && lumi.presentation.revealPreset == .wordRise
                && !isVisible

            let tokenText = Text(verbatim: token.text)
                .foregroundColor(
                    LumiBackgroundResolver.foreground(for: lumi.presentation.background)
                        .opacity(isVisible ? 1 : 0)
                )
                .baselineOffset(shouldRise ? -timing.wordRise : 0)
            return Text("\(result)\(tokenText)")
        }
    }
}

private struct FeedbackVisibilityTrigger: Equatable {
    let isEligible: Bool
    let reduceMotion: Bool
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
