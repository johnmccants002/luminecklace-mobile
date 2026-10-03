import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    @State private var showHeader = false
    @State private var showHero = false
    @State private var showSections = false
    @State private var showPreviewSheet = false
    @State private var driftPulse = false
    @State private var selectedRecentLumi: RevealedLumi?

    private var heroQuote: String {
        viewModel.featuredMessage?.text ?? "Write your first Lumi so her necklace has a moment to hold."
    }

    private var heroStatusText: String {
        switch viewModel.featuredLumi {
        case .current:
            "Waiting for her"
        case .upNext:
            "Queued in Up Next"
        case .reserve:
            "Saved in Reserve"
        case .empty:
            "Needs your first Lumi"
        }
    }

    private var summaryLines: [(systemImage: String, text: String)] {
        switch viewModel.featuredLumi {
        case .current:
            return [
                ("lock.fill", "Not revealed yet"),
                ("clock.fill", "Saved and ready to send")
            ]
        case let .upNext(_, count):
            return [
                ("clock.fill", "Waiting in Up Next"),
                ("tray.full.fill", count == 1 ? "1 Lumi ready" : "\(count) Lumis ready")
            ]
        case let .reserve(_, count):
            return [
                ("archivebox.fill", "Waiting in Reserve"),
                ("tray.full.fill", count == 1 ? "1 Lumi saved" : "\(count) Lumis saved")
            ]
        case .empty:
            return [
                ("lock.fill", "No Lumi published yet"),
                ("clock.fill", "Tap Add a Lumi to begin")
            ]
        }
    }

    private var upNextItems: [Message] {
        viewModel.queuedMessages
    }

    private var recentItems: [RevealedLumi] {
        viewModel.recentlyRevealed
    }

    private var reserveItems: [Message] {
        viewModel.reserveMessages
    }

    var body: some View {
        ZStack {
            background

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                    header
                        .opacity(showHeader ? 1 : 0)
                        .offset(y: showHeader ? 0 : 10)

                    greetingBlock
                        .opacity(showHeader ? 1 : 0)
                        .offset(y: showHeader ? 0 : 10)

                    queueContent

                    Spacer(minLength: 4)
                }
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
                .onChange(of: viewModel.notificationHomeFocusId) { _, focusId in
                    guard focusId != nil else { return }
                    withAnimation(.easeInOut) {
                        proxy.scrollTo("recently-revealed", anchor: .top)
                    }
                }
            }
        }
        .preferredColorScheme(.light)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showPreviewSheet) {
            HomeAppClipPreview(revealState: viewModel.previewRevealState)
        }
        .sheet(item: $selectedRecentLumi) { lumi in
            RevealedLumiFeedbackDetail(lumi: lumi)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                showHeader = true
            }

            Task {
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.easeOut(duration: 0.55)) {
                    showHero = true
                }

                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.easeOut(duration: 0.55)) {
                    showSections = true
                }
            }

            withAnimation(.easeInOut(duration: 4.5).repeatForever(autoreverses: true)) {
                driftPulse.toggle()
            }
        }
    }

    @ViewBuilder
    private var queueContent: some View {
        switch viewModel.queuePresentation {
        case .loading:
            HomeQueueStatusCard(
                title: "Loading your Lumis…",
                detail: "Checking what’s waiting in your necklace.",
                systemImage: "sparkles",
                showsProgress: true
            )
        case let .unavailable(message):
            HomeQueueStatusCard(
                title: "Your queue couldn’t load",
                detail: message,
                systemImage: "wifi.exclamationmark",
                retryAction: { Task { await viewModel.retryQueueLoad() } }
            )
        case .loaded:
            loadedQueueContent
        }
    }

    @ViewBuilder
    private var loadedQueueContent: some View {
        featuredCard
            .opacity(showHero ? 1 : 0)
            .offset(y: showHero ? 0 : 14)

        sectionHeader(
            title: "Up next",
            icon: "sparkles",
            actionTitle: "Edit Up Next",
            action: { viewModel.openUpNextEditor() }
        )
        .opacity(showSections ? 1 : 0)
        .offset(y: showSections ? 0 : 12)

        upNextCard
            .opacity(showSections ? 1 : 0)
            .offset(y: showSections ? 0 : 12)

        sectionHeader(
            title: "Reserve",
            icon: "sparkles",
            actionTitle: "Edit Reserve",
            action: { viewModel.openReserveEditor() }
        )
        .opacity(showSections ? 1 : 0)
        .offset(y: showSections ? 0 : 12)

        QueueHomeSummaryCard(
            messages: reserveItems,
            emptyTitle: "Reserve is empty",
            emptyDetail: "Add messages here to keep them behind Up Next.",
            onOpen: { viewModel.openReserveEditor() }
        )
        .opacity(showSections ? 1 : 0)
        .offset(y: showSections ? 0 : 12)

        sectionHeader(
            title: "Revealed recently",
            icon: "sparkles",
            actionTitle: nil,
            action: nil
        )
        .id("recently-revealed")
        .opacity(showSections ? 1 : 0)
        .offset(y: showSections ? 0 : 12)

        recentActivityCard
            .opacity(showSections ? 1 : 0)
            .offset(y: showSections ? 0 : 12)
    }

    private var background: some View {
        ZStack {
            Color(red: 0.988, green: 0.980, blue: 0.972).ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.96, blue: 0.94).opacity(0.95),
                    Color(red: 0.99, green: 0.95, blue: 0.92).opacity(0.88),
                    Color(red: 0.97, green: 0.89, blue: 0.91).opacity(0.80)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(red: 0.99, green: 0.86, blue: 0.88).opacity(0.24))
                .frame(width: 300, height: 300)
                .blur(radius: 42)
                .offset(x: 140, y: -220)
                .scaleEffect(driftPulse ? 1.03 : 0.97)

            Circle()
                .fill(Color(red: 0.99, green: 0.88, blue: 0.76).opacity(0.22))
                .frame(width: 260, height: 260)
                .blur(radius: 44)
                .offset(x: -140, y: 360)
                .scaleEffect(driftPulse ? 0.97 : 1.02)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(red: 0.93, green: 0.47, blue: 0.55))

                Text("Lumi")
                    .font(.system(.title, design: .serif, weight: .semibold))
                    .foregroundStyle(Color(red: 0.14, green: 0.15, blue: 0.28))
            }

            Spacer(minLength: 12)

            Button {
                // Placeholder until notifications/profile get real destinations.
            } label: {
                Image(systemName: "bell")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color(red: 0.16, green: 0.17, blue: 0.29))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.9))
                    .clipShape(Circle())
                    .shadow(color: Color.black.opacity(0.04), radius: 10, y: 5)
                    .overlay(alignment: .topTrailing) {
                        Circle()
                            .fill(Color(red: 0.90, green: 0.33, blue: 0.47))
                            .frame(width: 10, height: 10)
                            .offset(x: -2, y: 2)
                    }
            }
            .buttonStyle(.plain)

            avatar
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.86, blue: 0.78),
                            Color(red: 0.94, green: 0.68, blue: 0.52)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 52, height: 52)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                )
                .shadow(color: Color.black.opacity(0.07), radius: 12, y: 6)

            Text(viewModel.avatarInitials)
                .lumiScaledFont(size: 17, relativeTo: .body, weight: .semibold, design: .rounded, maximumSize: 22)
                .foregroundStyle(Color(red: 0.16, green: 0.17, blue: 0.29))
        }
    }

    private var greetingBlock: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 8) {
                Text("\(viewModel.greeting(for: context.date)),")
                    .font(.system(.largeTitle, design: .serif, weight: .medium))
                    .foregroundStyle(Color(red: 0.16, green: 0.17, blue: 0.29))

                HStack(spacing: 8) {
                    Text(viewModel.greetingName)
                        .font(.system(.largeTitle, design: .serif, weight: .medium))
                        .foregroundStyle(Color(red: 0.16, green: 0.17, blue: 0.29))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text("♥")
                        .font(.system(size: 31, weight: .medium, design: .serif))
                        .foregroundStyle(Color(red: 0.16, green: 0.17, blue: 0.29))
                }

                Text(viewModel.heroHeadline)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color(red: 0.46, green: 0.49, blue: 0.58))
            }
        }
        .padding(.top, 4)
    }

    private var featuredCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                heroPendant

                VStack(alignment: .leading, spacing: 12) {
                    Text(viewModel.necklaceName)
                        .font(.system(.title2, design: .serif, weight: .medium))
                        .foregroundStyle(Color(red: 0.16, green: 0.17, blue: 0.29))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    Text(heroStatusText)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(Color(red: 0.83, green: 0.28, blue: 0.39))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color(red: 0.99, green: 0.90, blue: 0.91))
                        .clipShape(Capsule())

                    Text("“\(heroQuote)”")
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(Color(red: 0.17, green: 0.18, blue: 0.31))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    LumiAttachmentBadge(attachment: viewModel.featuredMessage?.attachment)

                    Divider()
                        .overlay(Color(red: 0.90, green: 0.84, blue: 0.82))

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(summaryLines.enumerated()), id: \.offset) { _, item in
                            HStack(spacing: 8) {
                                Image(systemName: item.systemImage)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.42, green: 0.43, blue: 0.50))
                                    .frame(width: 18)

                                Text(item.text)
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(Color(red: 0.42, green: 0.43, blue: 0.50))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Button {
                    showPreviewSheet = true
                } label: {
                    Label("Preview", systemImage: "eye")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    viewModel.openLumiComposer()
                } label: {
                    Label("Add a Lumi", systemImage: "sparkles")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color(red: 0.96, green: 0.85, blue: 0.84), lineWidth: 1)
        )
        .shadow(color: Color(red: 0.93, green: 0.79, blue: 0.77).opacity(0.35), radius: 18, y: 8)
    }

    private var heroPendant: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.92, blue: 0.84),
                            Color(red: 0.92, green: 0.75, blue: 0.50),
                            Color(red: 0.83, green: 0.59, blue: 0.28)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 132, height: 132)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.86), lineWidth: 5)
                )
                .shadow(color: Color(red: 0.93, green: 0.78, blue: 0.63).opacity(0.34), radius: 16, y: 8)

            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 102, height: 102)

            VStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                Text("L")
                    .lumiScaledFont(size: 28, relativeTo: .title, weight: .semibold, design: .serif, maximumSize: 36)
                    .foregroundStyle(Color.white)
            }

            Circle()
                .fill(Color.white.opacity(0.88))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "heart.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 0.90, green: 0.33, blue: 0.47))
                )
                .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
                .offset(x: 37, y: 38)
        }
    }

    private var upNextCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if upNextItems.isEmpty {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.96, green: 0.84, blue: 0.85).opacity(0.55))
                            .frame(width: 54, height: 54)

                        Image(systemName: "sparkles")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color(red: 0.90, green: 0.33, blue: 0.47))
                    }

                    VStack(spacing: 6) {
                        Text("No Lumis waiting")
                            .font(.system(.title3, design: .serif, weight: .medium))
                            .foregroundStyle(Color(red: 0.16, green: 0.17, blue: 0.29))

                        Text("Add a Lumi when you’re ready to leave her another moment.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color(red: 0.46, green: 0.49, blue: 0.58))
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                    }

                    if viewModel.canAddLumi {
                        Button {
                            viewModel.openLumiComposer()
                        } label: {
                            Label("Add a Lumi", systemImage: "sparkles")
                                .font(.system(.headline, design: .rounded, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(red: 0.90, green: 0.33, blue: 0.47))
                                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 22)
                .padding(.vertical, 24)
            } else {
                ForEach(Array(upNextItems.enumerated()), id: \.element.id) { index, message in
                    HStack(alignment: .center, spacing: 14) {
                        dragDots

                        ZStack {
                            Circle()
                                .fill(numberTint(for: index).opacity(0.18))
                                .frame(width: 38, height: 38)

                            Text("\(index + 1)")
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                .foregroundStyle(numberTint(for: index))
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            Text(message.text)
                                .font(.system(.body, design: .rounded))
                                .foregroundStyle(Color(red: 0.18, green: 0.19, blue: 0.31))
                                .fixedSize(horizontal: false, vertical: true)
                            LumiAttachmentBadge(attachment: message.attachment)
                        }

                        Spacer(minLength: 0)

                        dragDots
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 16)

                    if index < upNextItems.count - 1 {
                        Divider()
                            .overlay(Color(red: 0.91, green: 0.88, blue: 0.87))
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

                        Text("Her revealed Lumis will appear here after she taps the necklace.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Color(red: 0.46, green: 0.49, blue: 0.58))
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
                    .foregroundStyle(Color(red: 0.46, green: 0.49, blue: 0.58))
            }

            Spacer(minLength: 0)

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(Color(red: 0.46, green: 0.49, blue: 0.58))
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

    private func sectionHeader(
        title: String,
        icon: String,
        actionTitle: String?,
        action: (() -> Void)?
    ) -> some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.92, green: 0.58, blue: 0.42))

                Text(title)
                    .font(.system(.headline, design: .serif, weight: .medium))
                    .foregroundStyle(Color(red: 0.16, green: 0.17, blue: 0.29))
            }

            Spacer(minLength: 12)

            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: "pencil")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(Color(red: 0.90, green: 0.33, blue: 0.47))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }

    private func numberTint(for index: Int) -> Color {
        switch index {
        case 0:
            return Color(red: 0.92, green: 0.39, blue: 0.50)
        case 1:
            return Color(red: 0.65, green: 0.52, blue: 0.84)
        default:
            return Color(red: 0.94, green: 0.67, blue: 0.29)
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
    let messages: [Message]
    let emptyTitle: String
    let emptyDetail: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                Image(systemName: messages.isEmpty ? "tray" : "list.number")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(LumiTheme.Colors.rose)
                    .frame(width: 48, height: 48)
                    .background(LumiTheme.Colors.roseSoft.opacity(0.72), in: RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 5) {
                    Text(messages.isEmpty ? emptyTitle : "\(messages.count) \(messages.count == 1 ? "Lumi" : "Lumis") in Reserve")
                        .font(LumiTheme.Typography.headline(17))
                        .foregroundStyle(LumiTheme.Colors.ink)

                    Text(messages.first.map { "First in Reserve: \($0.text)" } ?? emptyDetail)
                        .font(LumiTheme.Typography.body(14))
                        .foregroundStyle(LumiTheme.Colors.ink.opacity(0.66))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LumiTheme.Colors.ink.opacity(0.42))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.88))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(LumiTheme.Colors.cardStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(messages.isEmpty ? "\(emptyTitle). \(emptyDetail)" : "\(messages.count) messages in Reserve")
        .accessibilityHint("Opens the Reserve editor")
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

private struct DragDots: View {
    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 2) {
                    Circle().frame(width: 3, height: 3)
                    Circle().frame(width: 3, height: 3)
                }
                .foregroundStyle(Color(red: 0.80, green: 0.78, blue: 0.78))
            }
        }
        .opacity(0.9)
        .frame(width: 16)
    }
}

private extension HomeView {
    var dragDots: some View {
        DragDots()
    }
}
