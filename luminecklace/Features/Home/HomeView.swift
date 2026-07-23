import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    @State private var showHeader = false
    @State private var showHero = false
    @State private var showSections = false
    @State private var showPreviewSheet = false
    @State private var driftPulse = false

    private var heroQuote: String {
        viewModel.message?.text ?? "Write your first Lumi so her necklace has a moment to hold."
    }

    private var heroStatusText: String {
        viewModel.message == nil ? "Needs your first Lumi" : "Waiting for her"
    }

    private var summaryLines: [(systemImage: String, text: String)] {
        if viewModel.message != nil {
            return [
                ("lock.fill", "Not revealed yet"),
                ("clock.fill", "Saved and ready to send")
            ]
        }

        return [
            ("lock.fill", "No Lumi published yet"),
            ("clock.fill", "Tap Add a Lumi to begin")
        ]
    }

    private var upNextItems: [Message] {
        viewModel.queuedMessages
    }

    private var recentItems: [HomeRecentItem] {
        if let message = viewModel.message {
            return [
                HomeRecentItem(
                    icon: "eye.fill",
                    tint: Color(red: 0.92, green: 0.38, blue: 0.50),
                    title: message.text,
                    subtitle: "Ready for her next tap"
                ),
                HomeRecentItem(
                    icon: "heart.fill",
                    tint: Color(red: 0.66, green: 0.50, blue: 0.82),
                    title: "Draft locked in",
                    subtitle: "Open the queue editor to reorder messages"
                )
            ]
        }

        return [
            HomeRecentItem(
                icon: "sparkles",
                tint: Color(red: 0.92, green: 0.58, blue: 0.42),
                title: "Nothing revealed yet",
                subtitle: "Your first Lumi will appear here after setup"
            ),
            HomeRecentItem(
                icon: "heart.fill",
                tint: Color(red: 0.66, green: 0.50, blue: 0.82),
                title: "First message not published",
                subtitle: "Tap Add a Lumi to continue"
            )
        ]
    }

    var body: some View {
        ZStack {
            background

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                        .opacity(showHeader ? 1 : 0)
                        .offset(y: showHeader ? 0 : 10)

                    greetingBlock
                        .opacity(showHeader ? 1 : 0)
                        .offset(y: showHeader ? 0 : 10)

                    featuredCard
                        .opacity(showHero ? 1 : 0)
                        .offset(y: showHero ? 0 : 14)

                    sectionHeader(
                        title: "Up next",
                        icon: "sparkles",
                        actionTitle: upNextItems.isEmpty ? nil : "Edit queue",
                        action: upNextItems.isEmpty ? nil : { viewModel.openQueueEditor() }
                    )
                    .opacity(showSections ? 1 : 0)
                    .offset(y: showSections ? 0 : 12)

                    upNextCard
                        .opacity(showSections ? 1 : 0)
                        .offset(y: showSections ? 0 : 12)

                    LumiReserveCard(
                        state: LumiReserveViewState(summary: viewModel.reserve)
                    )
                    .opacity(showSections ? 1 : 0)
                    .offset(y: showSections ? 0 : 12)

                    sectionHeader(
                        title: "Revealed recently",
                        icon: "sparkles",
                        actionTitle: nil,
                        action: nil
                    )
                    .opacity(showSections ? 1 : 0)
                    .offset(y: showSections ? 0 : 12)

                    recentActivityCard
                        .opacity(showSections ? 1 : 0)
                        .offset(y: showSections ? 0 : 12)

                    Spacer(minLength: 4)
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.light)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showPreviewSheet) {
            HomePreviewSheet(
                title: viewModel.necklaceName,
                subtitle: viewModel.message?.text ?? "No custom Lumi has been published yet.",
                actionTitle: "Close"
            )
            .presentationDetents([.medium])
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
                    .font(.system(size: 28, weight: .semibold, design: .serif))
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
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.16, green: 0.17, blue: 0.29))
        }
    }

    private var greetingBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Good morning,")
                .font(.system(size: 31, weight: .medium, design: .serif))
                .foregroundStyle(Color(red: 0.16, green: 0.17, blue: 0.29))

            HStack(spacing: 8) {
                Text(viewModel.greetingName)
                    .font(.system(size: 31, weight: .medium, design: .serif))
                    .foregroundStyle(Color(red: 0.16, green: 0.17, blue: 0.29))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("♥")
                    .font(.system(size: 31, weight: .medium, design: .serif))
                    .foregroundStyle(Color(red: 0.16, green: 0.17, blue: 0.29))
            }

            Text(viewModel.heroHeadline)
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .foregroundStyle(Color(red: 0.46, green: 0.49, blue: 0.58))
        }
        .padding(.top, 4)
    }

    private var featuredCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                heroPendant

                VStack(alignment: .leading, spacing: 12) {
                    Text(viewModel.necklaceName)
                        .font(.system(size: 23, weight: .medium, design: .serif))
                        .foregroundStyle(Color(red: 0.16, green: 0.17, blue: 0.29))
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    Text(heroStatusText)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.83, green: 0.28, blue: 0.39))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color(red: 0.99, green: 0.90, blue: 0.91))
                        .clipShape(Capsule())

                    Text("“\(heroQuote)”")
                        .font(.system(size: 21, weight: .regular, design: .serif))
                        .foregroundStyle(Color(red: 0.17, green: 0.18, blue: 0.31))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

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
                                    .font(.system(size: 14, weight: .regular, design: .rounded))
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
                    .font(.system(size: 28, weight: .semibold, design: .serif))
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
                            .font(.system(size: 19, weight: .medium, design: .serif))
                            .foregroundStyle(Color(red: 0.16, green: 0.17, blue: 0.29))

                        Text("Add a Lumi when you’re ready to leave her another moment.")
                            .font(.system(size: 15, weight: .regular, design: .rounded))
                            .foregroundStyle(Color(red: 0.46, green: 0.49, blue: 0.58))
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                    }

                    if viewModel.canAddLumi {
                        Button {
                            viewModel.openLumiComposer()
                        } label: {
                            Label("Add a Lumi", systemImage: "sparkles")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
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
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(numberTint(for: index))
                        }

                        Text(message.text)
                            .font(.system(size: 17, weight: .regular, design: .rounded))
                            .foregroundStyle(Color(red: 0.18, green: 0.19, blue: 0.31))
                            .fixedSize(horizontal: false, vertical: true)

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
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(recentItems.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(item.tint.opacity(0.16))
                            .frame(width: 44, height: 44)

                        Image(systemName: item.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(item.tint)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title)
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .foregroundStyle(Color(red: 0.18, green: 0.19, blue: 0.31))
                            .lineLimit(2)

                        Text(item.subtitle)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(Color(red: 0.46, green: 0.49, blue: 0.58))
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.56, green: 0.57, blue: 0.65))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 16)

                if index < recentItems.count - 1 {
                    Divider()
                        .overlay(Color(red: 0.91, green: 0.88, blue: 0.87))
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
                    .font(.system(size: 18, weight: .medium, design: .serif))
                    .foregroundStyle(Color(red: 0.16, green: 0.17, blue: 0.29))
            }

            Spacer(minLength: 12)

            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: "pencil")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
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

private struct HomeRecentItem {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
}

private struct HomePreviewSheet: View {
    let title: String
    let subtitle: String
    let actionTitle: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.97, blue: 0.95),
                    Color(red: 0.98, green: 0.92, blue: 0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text("Preview")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.86, green: 0.32, blue: 0.46))

                Text(title)
                    .font(.system(size: 28, weight: .medium, design: .serif))
                    .foregroundStyle(Color(red: 0.16, green: 0.17, blue: 0.29))

                Text(subtitle)
                    .font(.system(size: 19, weight: .regular, design: .serif))
                    .foregroundStyle(Color(red: 0.30, green: 0.31, blue: 0.42))
                    .lineSpacing(4)

                Spacer()

                Button(actionTitle) {
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(22)
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
