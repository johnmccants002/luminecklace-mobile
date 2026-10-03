import SwiftUI

struct ExploreFeedView: View {
    @ObservedObject private var appState: AppState
    @StateObject private var viewModel: ExploreViewModel

    @State private var activeExperienceID: ExploreLumi.ID?
    @State private var selectedExperience: ExploreLumi?
    @State private var savedExperienceIDs: Set<ExploreLumi.ID> = []
    @State private var addedExperienceIDs: Set<ExploreLumi.ID> = []
    @State private var toastExperienceID: ExploreLumi.ID?
    @State private var toastDismissTask: Task<Void, Never>?
    @State private var actionError: String?

    init(appState: AppState) {
        self.appState = appState
        _viewModel = StateObject(wrappedValue: ExploreViewModel(appState: appState))
        _activeExperienceID = State(initialValue: nil)
    }

    private var experiences: [ExploreLumi] {
        viewModel.messages.map(ExploreLumi.init(template:))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.state {
            case .idle, .loading:
                ExploreCatalogStatusView(
                    title: "Loading Explore…",
                    message: "Finding Lumis for your necklace.",
                    systemImage: "sparkles",
                    showsProgress: true
                )
            case .empty:
                ExploreCatalogStatusView(
                    title: "Nothing here yet",
                    message: "New Lumi experiences will appear here when they’re available.",
                    systemImage: "heart.slash"
                )
            case let .failed(message):
                ExploreCatalogStatusView(
                    title: "Explore couldn’t load",
                    message: message,
                    systemImage: "wifi.exclamationmark",
                    retryAction: { Task { await viewModel.reload() } }
                )
            case .loaded:
                if experiences.isEmpty {
                    ExploreCatalogStatusView(
                        title: "Nothing here yet",
                        message: "New Lumi experiences will appear here when they’re available.",
                        systemImage: "heart.slash"
                    )
                } else {
                    feed
                }
            }

            if toastExperienceID != nil {
                VStack {
                    Spacer()
                    Label("Added to Up Next", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LumiTheme.Colors.ink)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 46)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.42), lineWidth: 1))
                        .shadow(color: .black.opacity(0.18), radius: 16, y: 7)
                        .padding(.bottom, 92)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .allowsHitTesting(false)
                .zIndex(5)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedExperience) { experience in
            LumiDetailsSheet(
                experience: experience,
                isAdded: isExperienceAdded(experience.id),
                onAdd: { addToNecklace(experience) },
                onCustomize: { primaryText, secondaryText, destination in
                    addToNecklace(
                        experience,
                        destination: destination,
                        customization: LibraryTextCustomization(
                            primaryText: primaryText,
                            secondaryText: secondaryText
                        )
                    )
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
        .onDisappear {
            toastDismissTask?.cancel()
        }
        .task {
            await viewModel.loadIfNeeded()
            if let first = viewModel.messages.first,
               !viewModel.messages.contains(where: { $0.id == activeExperienceID ?? "" }) {
                activeExperienceID = first.id
            }
        }
        .alert("Couldn’t add this Lumi", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "Please try again.")
        }
    }

    private var feed: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(experiences) { experience in
                        ExploreExperiencePage(
                            experience: experience,
                            topSafeAreaInset: proxy.safeAreaInsets.top,
                            isActive: activeExperienceID == experience.id,
                            isSaved: savedExperienceIDs.contains(experience.id),
                            isAdded: isExperienceAdded(experience.id),
                            onSave: { toggleSaved(experience) },
                            onAdd: { addToNecklace(experience) },
                            onShowDetails: { selectedExperience = experience }
                        )
                        .containerRelativeFrame(.vertical)
                        .id(experience.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $activeExperienceID)
            .ignoresSafeArea(edges: .top)
        }
    }

    private func toggleSaved(_ experience: ExploreLumi) {
        if savedExperienceIDs.contains(experience.id) {
            savedExperienceIDs.remove(experience.id)
        } else {
            savedExperienceIDs.insert(experience.id)
        }
        appState.hapticsManager.impact(enabled: appState.settings.hapticsEnabled)
    }

    private func isExperienceAdded(_ id: ExploreLumi.ID) -> Bool {
        addedExperienceIDs.contains(id)
            || viewModel.messages.first(where: { $0.id == id })?.isQueued == true
    }

    private func addToNecklace(
        _ experience: ExploreLumi,
        destination: QueueSection = .upNext,
        customization: LibraryTextCustomization? = nil
    ) {
        guard !addedExperienceIDs.contains(experience.id) else { return }
        guard let template = viewModel.messages.first(where: { $0.id == experience.id }) else {
            actionError = "This development preview is not available in the production catalog yet."
            return
        }
        Task {
            let added = await viewModel.enqueue(
                template,
                destination: destination,
                customization: customization
            )
            guard added else {
                actionError = viewModel.actionError ?? "Please try again."
                return
            }
            addedExperienceIDs.insert(experience.id)
            appState.hapticsManager.impact(enabled: appState.settings.hapticsEnabled)

            toastDismissTask?.cancel()
            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                toastExperienceID = experience.id
            }
            toastDismissTask = Task {
                try? await Task.sleep(for: .milliseconds(1800))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.28)) {
                    if toastExperienceID == experience.id {
                        toastExperienceID = nil
                    }
                }
            }
        }
    }
}

private struct ExploreCatalogStatusView: View {
    let title: String
    let message: String
    let systemImage: String
    var showsProgress = false
    var retryAction: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 120)
                if showsProgress {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.large)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 42, weight: .light))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.title2.weight(.bold))
                Text(message)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                if let retryAction {
                    Button("Retry", action: retryAction)
                        .font(.headline)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 28)
                        .frame(minHeight: 50)
                        .background(.white, in: Capsule())
                }
                Spacer(minLength: 80)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: 420)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ExploreExperiencePage: View {
    let experience: ExploreLumi
    let topSafeAreaInset: CGFloat
    let isActive: Bool
    let isSaved: Bool
    let isAdded: Bool
    let onSave: () -> Void
    let onAdd: () -> Void
    let onShowDetails: () -> Void

    var body: some View {
        ZStack {
            LumiExperienceView(experience: experience, isActive: isActive)

            VStack(spacing: 0) {
                header
                Spacer(minLength: 20)
                information
            }
            .padding(.horizontal, 20)
            .padding(.top, topSafeAreaInset + 12)
            .padding(.bottom, 18)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Explore")
                .font(.title2.weight(.semibold))
            Text("For You")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
            Spacer()
        }
        .foregroundStyle(experience.foregroundColor)
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
    }

    private var information: some View {
        VStack(spacing: 15) {
            HStack(alignment: .bottom, spacing: 14) {
                Button(action: onShowDetails) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(experience.title)
                            .font(.title3.weight(.bold))
                        Text("\(experience.category) · \(experience.mood) · \(experience.durationSeconds) sec")
                            .font(.subheadline.weight(.medium))
                            .opacity(0.78)
                        Label("Tap for details", systemImage: "chevron.up")
                            .font(.caption.weight(.semibold))
                            .opacity(0.70)
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                VStack(spacing: 14) {
                    ExploreActionButton(
                        title: isSaved ? "Saved" : "Save",
                        systemImage: isSaved ? "heart.fill" : "heart",
                        foregroundColor: experience.foregroundColor,
                        action: onSave
                    )
                    ExploreActionButton(
                        title: "Details",
                        systemImage: "ellipsis",
                        foregroundColor: experience.foregroundColor,
                        action: onShowDetails
                    )
                }
            }
            .foregroundStyle(experience.foregroundColor)
            .shadow(color: .black.opacity(0.20), radius: 9, y: 4)

            Button(action: onAdd) {
                Label(
                    isAdded ? "Added" : "Add to Necklace",
                    systemImage: isAdded ? "checkmark" : "plus"
                )
                .font(.headline)
                .foregroundStyle(isAdded ? experience.foregroundColor : LumiTheme.Colors.ink)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(isAdded ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.white), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(isAdded ? 0.34 : 0), lineWidth: 1))
                .shadow(color: .black.opacity(0.17), radius: 13, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(isAdded)
            .accessibilityHint(isAdded ? "Already added for this session" : "Simulates adding this experience to Up Next")
        }
    }
}

private struct ExploreActionButton: View {
    let title: String
    let systemImage: String
    let foregroundColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(foregroundColor)
        }
        .buttonStyle(.plain)
    }
}

private struct LumiDetailsSheet: View {
    let experience: ExploreLumi
    let isAdded: Bool
    let onAdd: () -> Void
    let onCustomize: (String, String?, QueueSection) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showsCustomize = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(experience.title)
                            .font(LumiTheme.Typography.display(31))
                            .foregroundStyle(LumiTheme.Colors.ink)
                        Text(experience.displayMessage)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(LumiTheme.Colors.ink.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 0) {
                        detailRow("Mood", value: experience.mood)
                        Divider()
                        detailRow("Category", value: experience.category)
                        Divider()
                        detailRow("Animation", value: experience.animationName)
                        Divider()
                        detailRow("Background", value: experience.backgroundName)
                        Divider()
                        detailRow("Duration", value: "\(experience.durationSeconds) seconds")
                    }
                    .padding(.horizontal, 17)
                    .background(LumiTheme.Colors.blush.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                    VStack(spacing: 11) {
                        Button {
                            onAdd()
                            dismiss()
                        } label: {
                            Label(isAdded ? "Added to Necklace" : "Add to Necklace", systemImage: isAdded ? "checkmark" : "plus")
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isAdded)

                        Button {
                            showsCustomize = true
                        } label: {
                            Text("Customize")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(20)
            }
            .background(LumiTheme.Colors.pageBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showsCustomize) {
                ExploreCustomizationSheet(
                    experience: experience,
                    onAdd: onCustomize
                )
            }
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(LumiTheme.Colors.ink.opacity(0.58))
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LumiTheme.Colors.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 13)
    }
}

private struct ExploreCustomizationSheet: View {
    let experience: ExploreLumi
    let onAdd: (String, String?, QueueSection) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isTextFocused: Bool
    @State private var primaryText: String
    @State private var secondaryText: String
    @State private var destination: QueueSection = .upNext
    @State private var activeSlot: TextSlot = .primary
    @State private var isTextEditing = false

    private enum TextSlot: String {
        case primary = "Message"
        case secondary = "Second reveal"
    }

    init(
        experience: ExploreLumi,
        onAdd: @escaping (String, String?, QueueSection) -> Void
    ) {
        self.experience = experience
        self.onAdd = onAdd
        _primaryText = State(initialValue: experience.message)
        _secondaryText = State(initialValue: experience.secondaryText ?? "")
    }

    var body: some View {
        ZStack {
            LumiExperienceRenderer(
                content: previewContent,
                isActive: !isTextEditing,
                showsMessage: !isTextEditing
            )
            .ignoresSafeArea()

            ambientCanvasDecoration
                .ignoresSafeArea()

            if isTextEditing {
                textEditor
                    .transition(.opacity)
            } else {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { beginEditing(.primary) }
                    .accessibilityLabel("Edit Lumi message")
                    .accessibilityAddTraits(.isButton)
            }

            VStack {
                topBar
                Spacer()
            }

            if !isTextEditing {
                HStack {
                    Spacer()
                    lockedPresetRail
                }
                .padding(.trailing, 10)
                .padding(.top, 132)
                .padding(.bottom, 220)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomControls }
        .preferredColorScheme(.dark)
        .onChange(of: isTextFocused) { _, focused in
            guard !focused, isTextEditing else { return }
            finishEditing()
        }
    }

    private var previewContent: LumiExperienceContent {
        LumiExperienceContent(
            presetKey: experience.presetKey,
            primaryText: primaryText,
            secondaryText: secondaryText.nilIfBlank
        )
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.34), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
            }
            .accessibilityLabel("Close composer")
            .opacity(isTextEditing ? 0 : 1)
            .allowsHitTesting(!isTextEditing)

            Spacer()

            if isTextEditing {
                Text("\(activeText.count)/\(activeLimit)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(activeText.count > activeLimit ? Color.yellow : .white.opacity(0.82))

                Button("Done", action: finishEditing)
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(.black.opacity(0.38), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
            } else {
                Button(action: addCustomizedLumi) {
                    Text("Add")
                        .font(.headline)
                        .frame(minWidth: 72, minHeight: 44)
                        .background(
                            LinearGradient(
                                colors: [LumiTheme.Colors.rose, Color(red: 1, green: 0.46, blue: 0.35)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: Capsule()
                        )
                }
                .disabled(!canAdd)
                .opacity(canAdd ? 1 : 0.48)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var textEditor: some View {
        ZStack(alignment: .topLeading) {
            if activeText.isEmpty {
                Text(activeSlot == .primary ? "Write your Lumi" : "Write the second reveal")
                    .font(activeFont)
                    .foregroundStyle(experience.foregroundColor.opacity(0.36))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }

            TextEditor(text: activeTextBinding)
                .scrollContentBackground(.hidden)
                .font(activeFont)
                .multilineTextAlignment(.center)
                .foregroundStyle(experience.foregroundColor)
                .tint(.white)
                .focused($isTextFocused)
                .accessibilityLabel(activeSlot.rawValue)
        }
        .padding(.horizontal, 68)
        .padding(.top, 108)
        .padding(.bottom, 84)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var lockedPresetRail: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(.black.opacity(0.46)).frame(width: 46, height: 46)
                Image(systemName: "lock.fill").font(.system(size: 17, weight: .semibold))
            }
            Text("Preset").font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.white)
        .frame(width: 64)
        .accessibilityLabel("Preset visuals locked")
    }

    private var bottomControls: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.28))
                .frame(width: 40, height: 4)
                .padding(.top, 7)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isTextEditing ? "Edit text" : "Customize")
                        .font(.headline)
                    Text(experience.title)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                }
                Spacer()
                Label("Preset locked", systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)

            HStack(spacing: 10) {
                slotButton(.primary)
                if experience.secondaryText != nil { slotButton(.secondary) }
            }
            .padding(.horizontal, 18)

            if !isTextEditing {
                Picker("Destination", selection: $destination) {
                    Text("Up Next").tag(QueueSection.upNext)
                    Text("Reserve").tag(QueueSection.reserve)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 18)
                .padding(.top, 12)
            }
        }
        .padding(.bottom, 12)
        .foregroundStyle(.white)
        .background(.ultraThinMaterial)
        .background(.black.opacity(0.68))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
    }

    private func slotButton(_ slot: TextSlot) -> some View {
        let selected = activeSlot == slot
        return Button {
            beginEditing(slot)
        } label: {
            Label(slot.rawValue, systemImage: slot == .primary ? "text.quote" : "sparkles")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? Color.white : Color.white.opacity(0.08), in: Capsule())
                .foregroundStyle(selected ? Color.black : Color.white)
                .overlay(Capsule().stroke(.white.opacity(selected ? 1 : 0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var ambientCanvasDecoration: some View {
        LinearGradient(colors: [.clear, .black.opacity(0.28)], startPoint: .center, endPoint: .bottom)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var activeText: String { activeSlot == .primary ? primaryText : secondaryText }
    private var activeLimit: Int { activeSlot == .primary ? 500 : 250 }
    private var activeFont: Font {
        if activeSlot == .secondary {
            return .system(.largeTitle, design: .rounded, weight: .semibold)
        }
        switch experience.presetKey {
        case .classicWordRise, .goldenHour:
            return .system(.largeTitle, design: .serif, weight: .medium)
        case .midnight:
            return .system(.largeTitle, design: .serif)
        case .proudOfYou:
            return .system(.largeTitle, design: .rounded, weight: .bold)
        case .playful:
            return .system(.largeTitle, design: .rounded, weight: .heavy)
        case .calm:
            return .system(.largeTitle, design: .rounded, weight: .light)
        case .memory:
            return .system(.largeTitle, design: .serif, weight: .medium)
        case .timedSurprise:
            return .system(.title2, design: .rounded, weight: .medium)
        }
    }

    private var activeTextBinding: Binding<String> {
        Binding(
            get: { activeText },
            set: { value in
                if activeSlot == .primary {
                    primaryText = String(value.prefix(500))
                } else {
                    secondaryText = String(value.prefix(250))
                }
            }
        )
    }

    private var canAdd: Bool {
        let primary = primaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !primary.isEmpty && primary.count <= 500 && secondaryText.count <= 250
    }

    private func beginEditing(_ slot: TextSlot) {
        activeSlot = slot
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { isTextEditing = true }
        Task { await Task.yield(); isTextFocused = true }
    }

    private func finishEditing() {
        isTextFocused = false
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { isTextEditing = false }
    }

    private func addCustomizedLumi() {
        guard canAdd else { return }
        onAdd(primaryText.trimmingCharacters(in: .whitespacesAndNewlines), secondaryText.nilIfBlank, destination)
        dismiss()
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
