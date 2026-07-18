import SwiftUI

struct PostAuthBootstrapView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            LumiTheme.Colors.pageBackground.ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
                Text("Finding your Lumi order...")
                    .font(LumiTheme.Typography.headline(22))
                    .foregroundStyle(.white)
                Text("We are linking your sender account to your pending necklace.")
                    .font(LumiTheme.Typography.body(15))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22)
            }
            .padding(24)
            .glassCard()
            .padding(20)
        }
    }
}

struct NoOrderAssistView: View {
    @EnvironmentObject private var appState: AppState
    @State private var orderEmail = ""
    @State private var isSubmitting = false

    var body: some View {
        ZStack {
            LumiTheme.Colors.pageBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("We couldn't find your order yet")
                        .font(LumiTheme.Typography.display(32))
                        .foregroundStyle(.white)

                    Text("If you used a different checkout email, we can help link your necklace.")
                        .font(LumiTheme.Typography.body(15))
                        .foregroundStyle(.white.opacity(0.82))

                    if appState.claimAssistanceSubmitted {
                        EmptyStateView(
                            title: "Request sent",
                            subtitle: "Support will verify your order and connect it to this account.",
                            systemImage: "checkmark.circle"
                        )
                    }

                    if let error = appState.lastBootstrapError, !error.isEmpty {
                        Text(error)
                            .font(LumiTheme.Typography.body(14))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    LumiTextField(
                        label: "Checkout Email (optional)",
                        text: $orderEmail,
                        keyboardType: .emailAddress
                    )

                    PrimaryButton(title: "Request Order Link Help", isLoading: isSubmitting) {
                        Task {
                            isSubmitting = true
                            await appState.submitClaimAssistance(orderEmail: orderEmail)
                            isSubmitting = false
                        }
                    }

                    PrimaryButton(title: "Try Again") {
                        Task { await appState.bootstrapSenderFlowAfterAuth() }
                    }

                    Button("Sign Out") {
                        appState.signOut()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(20)
            }
        }
    }
}

struct NecklaceSelectionView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            LumiTheme.Colors.pageBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Choose a necklace to set up")
                        .font(LumiTheme.Typography.display(32))
                        .foregroundStyle(.white)

                    Text("Pick which Lumi should get your first sender message.")
                        .font(LumiTheme.Typography.body(15))
                        .foregroundStyle(.white.opacity(0.82))

                    ForEach(appState.ownedNecklaces) { necklace in
                        Button {
                            appState.chooseNecklace(necklace.id)
                        } label: {
                            NecklaceCardView(necklace: necklace)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
        }
    }
}

struct FirstMessageSetupView: View {
    @EnvironmentObject private var appState: AppState
    @State private var draftText = ""
    @State private var isPublishing = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            LumiTheme.Colors.pageBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Set up your first Lumi message")
                        .font(LumiTheme.Typography.display(32))
                        .foregroundStyle(.white)

                    Text("This message appears when your recipient taps the necklace.")
                        .font(LumiTheme.Typography.body(15))
                        .foregroundStyle(.white.opacity(0.82))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your message")
                            .font(LumiTheme.Typography.body(14).weight(.medium))
                            .foregroundStyle(.white.opacity(0.9))

                        TextEditor(text: $draftText)
                            .frame(minHeight: 140)
                            .padding(8)
                            .background(LumiTheme.Colors.ink.opacity(0.34))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(.white.opacity(0.24), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(.white)
                    }

                    MessageCardView(message: previewMessage)

                    if let errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(LumiTheme.Typography.body(14))
                    }

                    PrimaryButton(title: "Publish Message", isLoading: isPublishing) {
                        Task {
                            isPublishing = true
                            defer { isPublishing = false }
                            do {
                                try await appState.publishFirstMessage(text: draftText)
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private var previewMessage: Message {
        Message(
            id: "preview",
            text: draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Write your first message to preview it here."
                : draftText,
            packageId: "love",
            timestamp: Date(),
            experience: Experience(
                themeKey: appState.equippedNecklace?.themeKey ?? "heart",
                animationKey: "breathe",
                soundKey: "soft"
            )
        )
    }
}

struct RecipientRevealView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            LumiTheme.Colors.appGradient.ignoresSafeArea()
            FloatingHeartsBackground()

            VStack(spacing: 16) {
                switch appState.recipientRevealState {
                case .idle, .resolving:
                    ProgressView()
                        .tint(.white)
                    Text("Revealing your Lumi message...")
                        .font(LumiTheme.Typography.headline(24))
                        .foregroundStyle(.white)
                case .message:
                    Text("A message for you")
                        .font(LumiTheme.Typography.display(36))
                        .foregroundStyle(.white)
                    MessageCardView(message: appState.currentMessage)
                case .fallback:
                    Text("Your Lumi moment")
                        .font(LumiTheme.Typography.display(36))
                        .foregroundStyle(.white)
                    MessageCardView(message: appState.currentMessage)
                case .softError:
                    EmptyStateView(
                        title: "Your Lumi is almost ready",
                        subtitle: appState.currentMessage?.text ?? "Try tapping again in a moment.",
                        systemImage: "sparkles"
                    )
                }

                Button("Open Full Lumi App") {
                    appState.returnFromRecipientReveal()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(20)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }
}
