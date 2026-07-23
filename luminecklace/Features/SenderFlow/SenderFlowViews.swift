import SwiftUI

struct PostAuthBootstrapView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            LumiTheme.Colors.pageBackground.ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .tint(LumiTheme.Colors.rose)
                    .scaleEffect(1.2)
                Text("Loading your Lumis...")
                    .font(LumiTheme.Typography.headline(22))
                    .foregroundStyle(LumiTheme.Colors.ink)
                Text("We are finding the necklaces linked to your account.")
                    .font(LumiTheme.Typography.body(15))
                    .foregroundStyle(LumiTheme.Colors.ink.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 22)
            }
            .padding(24)
            .glassCard()
            .padding(20)
        }
    }
}

struct NoNecklaceView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            LumiTheme.Colors.pageBackground.ignoresSafeArea()

            VStack(spacing: 18) {
                EmptyStateView(
                    title: "No Lumi linked",
                    subtitle: "There isn't a necklace connected to this account yet.",
                    systemImage: "heart.slash"
                )

                VStack(spacing: 12) {
                    PrimaryButton(title: "Try Again") {
                        Task { await appState.bootstrapSenderFlowAfterAuth() }
                    }

                    Button("Sign Out") {
                        appState.signOut()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(20)
        }
    }
}

struct SenderLoadErrorView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            LumiTheme.Colors.pageBackground.ignoresSafeArea()

            VStack(spacing: 18) {
                EmptyStateView(
                    title: "We couldn't load your Lumi",
                    subtitle: "Check your connection and try again.",
                    systemImage: "wifi.exclamationmark"
                )

                VStack(spacing: 12) {
                    PrimaryButton(title: "Try Again") {
                        Task { await appState.bootstrapSenderFlowAfterAuth() }
                    }

                    Button("Sign Out") {
                        appState.signOut()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(20)
        }
    }
}

struct LumiComposerView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            LumiTheme.Colors.pageBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(appState.composerTitle)
                        .font(LumiTheme.Typography.display(32))
                        .foregroundStyle(LumiTheme.Colors.ink)

                    Text(appState.composerSubtitle)
                        .font(LumiTheme.Typography.body(15))
                        .foregroundStyle(LumiTheme.Colors.ink.opacity(0.72))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your Lumi")
                            .font(LumiTheme.Typography.body(14).weight(.medium))
                            .foregroundStyle(LumiTheme.Colors.ink.opacity(0.84))

                        TextEditor(text: composerDraftBinding)
                            .frame(minHeight: 140)
                            .padding(8)
                            .background(Color.white.opacity(0.94))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(LumiTheme.Colors.cardStroke, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(LumiTheme.Colors.ink)

                        Text("\(appState.composerDraftText.count)/500")
                            .font(LumiTheme.Typography.body(12))
                            .foregroundStyle(appState.composerDraftText.count > 500 ? .red : LumiTheme.Colors.ink.opacity(0.56))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    MessageCardView(message: previewMessage)

                    if let errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(LumiTheme.Typography.body(14))
                    }

                    PrimaryButton(title: appState.composerActionTitle, isLoading: isSaving) {
                        Task {
                            isSaving = true
                            defer { isSaving = false }
                            do {
                                try await appState.addLumi(text: appState.composerDraftText)
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }

                    Button("Cancel") {
                        appState.cancelLumiComposer()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
                .padding(20)
            }
        }
    }

    private var previewMessage: Message {
        let text = appState.composerDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        return Message(
            id: "preview",
            text: text.isEmpty ? "Write a Lumi to preview it here." : text,
            packageId: "love",
            timestamp: Date(),
            experience: Experience(
                themeKey: appState.equippedNecklace?.themeKey ?? "heart",
                animationKey: "breathe",
                soundKey: "soft"
            )
        )
    }

    private var composerDraftBinding: Binding<String> {
        Binding(
            get: { appState.composerDraftText },
            set: { appState.composerDraftText = $0 }
        )
    }
}

struct QueueEditorView: View {
    @EnvironmentObject private var appState: AppState
    @State private var editMode: EditMode = .active

    var body: some View {
        ZStack {
            LumiTheme.Colors.pageBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                queueHeader

                if appState.queueMessages.isEmpty {
                    EmptyStateView(
                        title: "Your queue is empty",
                        subtitle: "Reserve will keep the necklace glowing until you add another personal Lumi.",
                        systemImage: "sparkles"
                    )

                    LumiReserveCard(
                        state: LumiReserveViewState(summary: appState.equippedReserve)
                    )

                    Spacer(minLength: 0)
                } else {
                    MessageCardView(message: appState.queueMessages.first)

                    Text("Drag to reorder. The top item sends first.")
                        .font(LumiTheme.Typography.body(14))
                        .foregroundStyle(LumiTheme.Colors.ink.opacity(0.66))

                    List {
                        ForEach(Array(appState.queueMessages.enumerated()), id: \.element.id) { index, message in
                            QueueMessageRowView(
                                index: index,
                                message: message,
                                onEdit: {
                                    appState.openLumiComposer(editing: message)
                                }
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        .onMove(perform: appState.moveQueueMessages)
                        .onDelete(perform: appState.deleteQueueMessages)

                        LumiReserveCard(
                            state: LumiReserveViewState(summary: appState.equippedReserve)
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 14, leading: 0, bottom: 8, trailing: 0))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.editMode, $editMode)
                    .frame(maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(20)
        }
        .onAppear {
            editMode = .active
        }
    }

    private var queueHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Edit queue")
                    .font(LumiTheme.Typography.display(34))
                    .foregroundStyle(LumiTheme.Colors.ink)

                Text("This is the order your messages will reveal on the necklace.")
                    .font(LumiTheme.Typography.body(15))
                    .foregroundStyle(LumiTheme.Colors.ink.opacity(0.72))
            }

            Spacer(minLength: 12)

            Button("Done") {
                appState.closeQueueEditor()
            }
            .buttonStyle(SecondaryButtonStyle())
            .frame(maxWidth: 76)
        }
    }
}

struct LumiReserveCard: View {
    let state: LumiReserveViewState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LumiTheme.Colors.gold)

                Text("Lumi Reserve")
                    .font(LumiTheme.Typography.headline(20))
                    .foregroundStyle(LumiTheme.Colors.ink)

                Spacer(minLength: 8)

                statusBadge
            }

            Text(state.message)
                .font(LumiTheme.Typography.body(14))
                .foregroundStyle(LumiTheme.Colors.ink.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)

            if case .loading = state {
                ProgressView()
                    .tint(LumiTheme.Colors.rose)
                    .accessibilityLabel("Loading Lumi Reserve details")
            } else if let summary = state.summary {
                reserveCounts(summary)

                if !summary.categories.isEmpty {
                    categoryGrid(summary.categories)
                }
            }

            Label(
                "Personal Lumis always reveal before Reserve Lumis.",
                systemImage: "checkmark.shield"
            )
            .font(LumiTheme.Typography.body(12))
            .foregroundStyle(LumiTheme.Colors.ink.opacity(0.56))
        }
        .glassCard()
    }

    private var statusBadge: some View {
        Text(state.statusLabel)
            .font(LumiTheme.Typography.body(12).weight(.semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(statusColor.opacity(0.12))
            .clipShape(Capsule())
            .accessibilityLabel("Lumi Reserve status: \(state.statusLabel)")
    }

    private var statusColor: Color {
        switch state {
        case .empty, .partiallyApproved, .enabled:
            return LumiTheme.Colors.rose
        case .loading, .unavailable, .disabled:
            return LumiTheme.Colors.ink.opacity(0.58)
        }
    }

    private func reserveCounts(_ summary: LumiReserveSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(summary.approvedCount) of \(summary.totalCount) approved")
                .font(LumiTheme.Typography.headline(17))
                .foregroundStyle(LumiTheme.Colors.ink)
                .accessibilityLabel(summary.approvalAccessibilityLabel)

            if summary.totalCount > 0 {
                ProgressView(
                    value: Double(summary.approvedCount),
                    total: Double(summary.totalCount)
                )
                .tint(summary.enabled ? LumiTheme.Colors.rose : LumiTheme.Colors.ink.opacity(0.35))
                .accessibilityHidden(true)
            }
        }
    }

    private func categoryGrid(_ categories: [LumiReserveCategorySummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reserve categories")
                .font(LumiTheme.Typography.body(13).weight(.semibold))
                .foregroundStyle(LumiTheme.Colors.ink.opacity(0.72))

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 138), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(categories) { category in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.displayName)
                            .font(LumiTheme.Typography.body(13).weight(.semibold))
                            .foregroundStyle(LumiTheme.Colors.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("\(category.approvedCount) of \(category.totalCount)")
                            .font(LumiTheme.Typography.body(12))
                            .foregroundStyle(LumiTheme.Colors.ink.opacity(0.62))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(11)
                    .background(LumiTheme.Colors.roseSoft.opacity(0.54))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(category.approvalAccessibilityLabel)
                }
            }
        }
    }
}

private struct QueueMessageRowView: View {
    let index: Int
    let message: Message
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(orderTint.opacity(0.18))
                    .frame(width: 36, height: 36)

                Text("\(index + 1)")
                    .font(LumiTheme.Typography.body(14).weight(.semibold))
                    .foregroundStyle(orderTint)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(message.text)
                    .font(LumiTheme.Typography.body(16))
                    .foregroundStyle(LumiTheme.Colors.ink)
                    .lineLimit(3)

                HStack(spacing: 8) {
                    Text(message.packageId.capitalized)
                        .font(LumiTheme.Typography.body(11).weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(LumiTheme.Colors.roseSoft)
                        .foregroundStyle(LumiTheme.Colors.rose)
                        .clipShape(Capsule())

                    if index == 0 {
                        Text("Sends first")
                            .font(LumiTheme.Typography.body(11).weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(LumiTheme.Colors.sand.opacity(0.35))
                            .foregroundStyle(LumiTheme.Colors.ink.opacity(0.75))
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer(minLength: 8)

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LumiTheme.Colors.rose)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.9))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(LumiTheme.Colors.cardStroke, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(LumiTheme.Colors.cardStroke, lineWidth: 1)
        )
    }

    private var orderTint: Color {
        switch index {
        case 0:
            return LumiTheme.Colors.rose
        case 1:
            return Color(red: 0.65, green: 0.52, blue: 0.84)
        default:
            return LumiTheme.Colors.gold
        }
    }
}

struct RecipientRevealView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LumiTheme.Colors.pageBackground.ignoresSafeArea()
            FloatingHeartsBackground()

            VStack(spacing: 16) {
                switch appState.recipientRevealState {
                case .awaitingInvocation:
                    Image(systemName: "heart.circle")
                        .font(.system(size: 58, weight: .light))
                        .foregroundStyle(LumiTheme.Colors.rose)
                    Text("Tap your Lumi necklace to begin.")
                        .font(LumiTheme.Typography.display(34))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(LumiTheme.Colors.ink)
                case .resolving:
                    ProgressView()
                        .tint(LumiTheme.Colors.rose)
                    Text("Opening your Lumi...")
                        .font(LumiTheme.Typography.headline(24))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(LumiTheme.Colors.ink)
                case let .waiting(lumi):
                    recipientHeader(title: "Something was left here for you.", necklaceName: lumi.necklaceDisplayName)
                    HoldToRevealButton {
                        appState.completeRecipientHold(for: lumi)
                    }
                case let .revealing(lumi):
                    recipientHeader(title: "Opening...", necklaceName: lumi.necklaceDisplayName)
                    heartRevealMotif(for: lumi)
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                case let .revealed(lumi, _):
                    recipientHeader(title: "Your Lumi", necklaceName: lumi.necklaceDisplayName)
                    Text(lumi.text)
                        .font(LumiTheme.Typography.display(36))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(LumiTheme.Colors.ink)
                        .lineSpacing(6)
                        .padding(.horizontal, 12)
                        .accessibilityLabel("Lumi message. \(lumi.text)")
                case .empty:
                    EmptyStateView(
                        title: "Nothing new is waiting right now.",
                        subtitle: "Come back again soon.",
                        systemImage: "moon.stars"
                    )
                case .unavailable:
                    EmptyStateView(
                        title: "This Lumi isn't available right now.",
                        subtitle: "",
                        systemImage: "heart.slash"
                    )
                case .error:
                    EmptyStateView(
                        title: "We couldn't open your Lumi.",
                        subtitle: "",
                        systemImage: "sparkles"
                    )
                    Button("Try Again") {
                        appState.retryRecipientReveal()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(20)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: appState.recipientRevealState)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func recipientHeader(title: String, necklaceName: String) -> some View {
        VStack(spacing: 10) {
            Text(necklaceName)
                .font(LumiTheme.Typography.body(14).weight(.medium))
                .foregroundStyle(LumiTheme.Colors.rose)
            Text(title)
                .font(LumiTheme.Typography.display(36))
                .multilineTextAlignment(.center)
                .foregroundStyle(LumiTheme.Colors.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private func heartRevealMotif(for lumi: ResolvedLumi) -> some View {
        Image(systemName: lumi.presentation.theme == .champagne ? "sparkles" : "heart.fill")
            .font(.system(size: 74, weight: .regular))
            .foregroundStyle(LumiTheme.Colors.rose)
            .padding(36)
            .background(LumiTheme.Colors.glassTop.opacity(0.92), in: Circle())
            .overlay(
                Circle()
                    .stroke(LumiTheme.Colors.cardStroke, lineWidth: 1)
            )
            .shadow(color: LumiTheme.Colors.rose.opacity(0.14), radius: 14, y: 8)
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
                    .fill(Color.white.opacity(0.95))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [LumiTheme.Colors.rose.opacity(0.95), LumiTheme.Colors.gold.opacity(0.88)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .scaleEffect(x: didComplete ? 1 : progress, y: 1, anchor: .leading)
                Text("Hold to reveal")
                    .font(LumiTheme.Typography.body(18).weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
            }
        }
        .buttonStyle(.plain)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(LumiTheme.Colors.cardStroke, lineWidth: 1))
        .shadow(color: LumiTheme.Colors.rose.opacity(0.14), radius: 12, y: 8)
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
        .padding(.top, 10)
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
