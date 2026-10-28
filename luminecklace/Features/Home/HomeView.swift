import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showPreviewSheet = false
    @State private var selectedRecentLumi: RevealedLumi?

    private var recentItems: [RevealedLumi] { viewModel.recentlyRevealed }

    var body: some View {
        ZStack {
            LumiTheme.Colors.pageBackground.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        if let notice = viewModel.composerNotice {
                            LumiSuccessBanner(message: notice, onDismiss: viewModel.dismissComposerNotice)
                        }
                        queueContent
                        Text("Reveals & responses")
                            .font(LumiTheme.Typography.headline(24))
                            .id("recently-revealed")
                        recentActivityCard
                    }
                    .padding(20)
                }
                .refreshable { await viewModel.retryQueueLoad() }
                .onChange(of: viewModel.notificationHomeFocusId) { _, focusId in
                    guard focusId != nil else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut) {
                        proxy.scrollTo("recently-revealed", anchor: .top)
                    }
                }
            }
        }
        .foregroundStyle(LumiTheme.Colors.ink)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showPreviewSheet) {
            HomeAppClipPreview(revealState: viewModel.previewRevealState)
        }
        .sheet(item: $selectedRecentLumi) { lumi in
            RevealedLumiFeedbackDetail(lumi: lumi)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Lumi").font(LumiTheme.Typography.display(34))
                Spacer()
                if viewModel.necklaces.count > 1 {
                    Menu {
                        ForEach(viewModel.necklaces) { necklace in
                            Button { viewModel.chooseNecklace(necklace.id) } label: {
                                if necklace.isEquipped { Label(necklace.name, systemImage: "checkmark") }
                                else { Text(necklace.name) }
                            }
                        }
                    } label: {
                        Label("Switch necklace", systemImage: "chevron.up.chevron.down")
                            .font(.subheadline)
                            .frame(minHeight: 44)
                    }
                }
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text("\(viewModel.greeting(for: context.date)), \(viewModel.greetingName).")
                    .font(.subheadline)
                    .foregroundStyle(LumiTheme.Colors.ink.opacity(0.75))
            }
        }
    }

    @ViewBuilder
    private var queueContent: some View {
        switch viewModel.queuePresentation {
        case .loading:
            HomeQueueStatusCard(title: "Loading your Lumis…", detail: "Checking what’s ready for the next tap.", systemImage: "sparkles", showsProgress: true)
        case let .unavailable(message):
            HomeQueueStatusCard(title: "Your messages couldn’t load", detail: message, systemImage: "wifi.exclamationmark", retryAction: { Task { await viewModel.retryQueueLoad() } })
        case .loaded:
            featuredCard
            QueueHomeSummaryCard(
                title: "Upcoming messages", messages: viewModel.queuedMessages + viewModel.reserveMessages,
                detail: "Manage the order of messages after this reveal.",
                onOpen: viewModel.openUpNextEditor
            )
        }
    }

    private var featuredCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(viewModel.necklaceName, systemImage: "heart.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LumiTheme.Colors.rose)

            Text(viewModel.featuredMessage == nil ? "Their first Lumi starts here" : "Ready for the next tap")
                .font(LumiTheme.Typography.headline(24))

            if let message = viewModel.featuredMessage {
                Text("“\(message.text)”")
                    .font(.system(.title3, design: .serif))
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
                LumiAttachmentBadge(attachment: message.attachment)
                Text("They’ll see this message when they tap their necklace. Preview to read it in full.")
                    .font(.subheadline)
                    .foregroundStyle(LumiTheme.Colors.ink.opacity(0.75))
            } else {
                Text("Write a message for someone you love. It will be waiting when they tap their necklace.")
                    .font(.body)
                    .foregroundStyle(LumiTheme.Colors.ink.opacity(0.75))
            }

            if viewModel.canAddLumi {
                Button(action: viewModel.openLumiComposer) {
                    Label("Add a Lumi", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Text("This necklace is inactive. You can preview its messages, but can’t add new ones yet.")
                    .font(.subheadline)
                    .foregroundStyle(LumiTheme.Colors.ink.opacity(0.75))
            }

            if viewModel.featuredMessage != nil {
                Button { showPreviewSheet = true } label: {
                    Label("Preview their experience", systemImage: "eye")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(LumiTheme.Colors.rose)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var recentActivityCard: some View {
        Group {
            if recentItems.isEmpty {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.92, green: 0.38, blue: 0.50).opacity(0.13))
                            .frame(width: 46, height: 46)

                        Image(systemName: "eye")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color(red: 0.92, green: 0.38, blue: 0.50))
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Nothing revealed yet")
                            .font(.system(.body, design: .rounded, weight: .medium))
                            .foregroundStyle(Color(red: 0.18, green: 0.19, blue: 0.31))

                        Text("Revealed messages, reactions, and replies appear here after they tap their necklace.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(LumiTheme.Colors.ink.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
                .accessibilityElement(children: .combine)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(recentItems.enumerated()), id: \.element.id) { index, item in
                        recentActivityEntry(item, index: index)

                        if index < recentItems.count - 1 {
                            Divider()
                                .overlay(Color(red: 0.91, green: 0.88, blue: 0.87))
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.84))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(red: 0.95, green: 0.88, blue: 0.87), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.95, green: 0.86, blue: 0.84).opacity(0.20), radius: 14, y: 8)
    }

    @ViewBuilder
    private func recentActivityEntry(_ item: RevealedLumi, index: Int) -> some View {
        if item.feedback?.hasVisibleFeedback == true {
            Button {
                selectedRecentLumi = item
            } label: {
                recentActivityRow(item, index: index, showsDisclosure: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the full reaction and response")
        } else {
            recentActivityRow(item, index: index, showsDisclosure: false)
        }
    }

    private func recentActivityRow(
        _ item: RevealedLumi,
        index: Int,
        showsDisclosure: Bool
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(recentTint(for: index).opacity(0.14))
                    .frame(width: 44, height: 44)

                Image(systemName: "eye.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(recentTint(for: index))
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.text)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color(red: 0.18, green: 0.19, blue: 0.31))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                LumiAttachmentBadge(attachment: item.attachment)

                if let reaction = item.feedback?.reaction {
                    Text("\(reaction.emoji)  \(reaction.accessibilityLabel)")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color(red: 0.72, green: 0.25, blue: 0.39))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color(red: 0.98, green: 0.89, blue: 0.91), in: Capsule())
                }

                if let response = item.feedback?.responseText,
                   !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("“\(response)”")
                        .font(.system(.subheadline, design: .serif))
                        .foregroundStyle(Color(red: 0.34, green: 0.35, blue: 0.46))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(viewModel.revealedSubtitle(for: item.revealedAt))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(LumiTheme.Colors.ink.opacity(0.75))
            }

            Spacer(minLength: 0)

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(LumiTheme.Colors.ink.opacity(0.75))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func recentTint(for index: Int) -> Color {
        switch index % 3 {
        case 0:
            return Color(red: 0.92, green: 0.38, blue: 0.50)
        case 1:
            return Color(red: 0.66, green: 0.50, blue: 0.82)
        default:
            return Color(red: 0.92, green: 0.58, blue: 0.42)
        }
    }

}

private struct HomeQueueStatusCard: View {
    let title: String
    let detail: String
    let systemImage: String
    var showsProgress = false
    var retryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            if showsProgress {
                ProgressView()
                    .tint(LumiTheme.Colors.rose)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(LumiTheme.Colors.rose)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(LumiTheme.Typography.headline(20))
                    .foregroundStyle(LumiTheme.Colors.ink)
                Text(detail)
                    .font(LumiTheme.Typography.body(15))
                    .foregroundStyle(LumiTheme.Colors.ink.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let retryAction {
                Button("Try Again", action: retryAction)
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.white.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(LumiTheme.Colors.cardStroke, lineWidth: 1)
        )
    }
}

private struct QueueHomeSummaryCard: View {
    let title: String
    let messages: [Message]
    let detail: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(title) · \(messages.count)")
                        .font(.headline)
                        .foregroundStyle(LumiTheme.Colors.ink)
                    Text(messages.first?.text ?? "No messages yet")
                        .font(.subheadline)
                        .foregroundStyle(LumiTheme.Colors.ink)
                        .lineLimit(2)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(LumiTheme.Colors.ink.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .foregroundStyle(LumiTheme.Colors.ink.opacity(0.65))
                    .accessibilityHidden(true)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Manage messages in \(title)")
    }
}

private struct RevealedLumiFeedbackDetail: View {
    let lumi: RevealedLumi

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    detailSection(title: "Original Lumi") {
                        Text(lumi.text)
                            .font(.system(.title3, design: .serif))
                            .foregroundStyle(Color(red: 0.17, green: 0.18, blue: 0.30))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    detailSection(title: "Revealed") {
                        Text(
                            lumi.revealedAt.formatted(
                                .dateTime
                                    .month(.wide)
                                    .day()
                                    .year()
                                    .hour()
                                    .minute()
                            )
                        )
                        .font(.body)
                        .foregroundStyle(.secondary)
                    }

                    if let reaction = lumi.feedback?.reaction {
                        detailSection(title: "Reaction") {
                            HStack(spacing: 12) {
                                Text(reaction.emoji)
                                    .font(.system(size: 34))
                                Text(reaction.accessibilityLabel)
                                    .font(.system(.headline, design: .rounded))
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }

                    if let response = lumi.feedback?.responseText,
                       !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        detailSection(title: "Written response") {
                            Text("“\(response)”")
                                .font(.system(.title3, design: .serif))
                                .foregroundStyle(Color(red: 0.25, green: 0.26, blue: 0.38))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(red: 0.99, green: 0.97, blue: 0.96))
            .navigationTitle("Lumi response")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func detailSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct HomeAppClipPreview: View {
    let revealState: RecipientRevealState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RecipientRevealPresentationView(
                revealState: revealState,
                feedbackState: HomePreviewFactory.feedbackPresentationState
            )

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.24), in: Circle())
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.28), lineWidth: 1)
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close App Clip preview")
            .padding(.top, 12)
            .padding(.trailing, 18)
        }
        .onAppear {
            UIAccessibility.post(
                notification: .screenChanged,
                argument: "App Clip preview"
            )
        }
    }
}
