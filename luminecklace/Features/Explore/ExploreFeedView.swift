import SwiftUI

struct ExploreFeedView: View {
    @ObservedObject private var appState: AppState
    @StateObject private var viewModel: ExploreViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var activeExperienceID: ExploreLumi.ID?
    @State private var selectedExperience: ExploreLumi?
    @State private var showsSaved = false
    @State private var showsSharingHelp = false
    @State private var addedExperienceIDs: Set<ExploreLumi.ID> = []
    @State private var toast: String?
    @State private var toastDismissTask: Task<Void, Never>?

    init(appState: AppState, service: MessageLibraryServing? = nil) {
        self.appState = appState
        _viewModel = StateObject(wrappedValue: ExploreViewModel(appState: appState, service: service))
    }

    private var templates: [MessageTemplate] {
        guard showsSaved else { return viewModel.messages }
        let query = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return viewModel.savedMessages.filter {
            query.isEmpty || ($0.title ?? "").localizedCaseInsensitiveContains(query)
                || $0.text.localizedCaseInsensitiveContains(query)
                || $0.category.name.localizedCaseInsensitiveContains(query)
        }
    }

    private var experiences: [ExploreLumi] { templates.map(ExploreLumi.init(template:)) }

    var body: some View {
        ZStack(alignment: .bottom) {
            if dynamicTypeSize.isAccessibilitySize {
                LumiTheme.Colors.pageBackground.ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
            catalog
            if let toast {
                Text(toast)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LumiTheme.Colors.ink)
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .padding(.bottom, 80)
                    .accessibilityAddTraits(.updatesFrequently)
                    .allowsHitTesting(false)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { discoveryControls }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !showsSaved, let error = viewModel.paginationError {
                VStack(spacing: 8) {
                    Text(error).font(.subheadline)
                    Button("Try again") {
                        if let last = viewModel.messages.last {
                            Task { await viewModel.loadMoreIfNeeded(after: last) }
                        }
                    }
                    .frame(minHeight: 44)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .foregroundStyle(LumiTheme.Colors.ink)
                .background(LumiTheme.Colors.cream)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsSharingHelp) {
            NavigationStack {
                ShareToLumiHelpView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showsSharingHelp = false }
                        }
                    }
            }
        }
        .fullScreenCover(item: $selectedExperience) { experience in
            ExploreCustomizationSheet(
                experience: experience,
                necklaceName: viewModel.selectedNecklace?.name ?? "Your necklace",
                canEnqueue: viewModel.canEnqueue && !isExperienceAdded(experience.id)
            ) { primary, secondary, destination in
                let unchanged = primary == experience.message && secondary == experience.secondaryText
                return await addToNecklace(experience, destination: destination,
                    customization: unchanged ? nil : LibraryTextCustomization(primaryText: primary, secondaryText: secondary))
            }
        }
        .task { await viewModel.loadIfNeeded() }
        .task(id: viewModel.searchText) {
            if !showsSaved { await viewModel.searchChanged() }
        }
        .onChange(of: showsSaved) { _, saved in
            activeExperienceID = nil
            if !saved { Task { await viewModel.reload() } }
        }
        .onChange(of: appState.equippedNecklace?.id) { _, _ in
            addedExperienceIDs = []
            Task { await viewModel.loadIfNeeded() }
        }
        .onDisappear { toastDismissTask?.cancel(); toast = nil }
    }

    private var exploreHeading: some View {
        HStack(spacing: 4) {
            Text("Explore").font(LumiTheme.Typography.headline(24))
            Button { showsSharingHelp = true } label: {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("How to share a link to Lumi")
        }
    }

    private var discoveryControls: some View {
        VStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    exploreHeading
                    Spacer()
                    inspirationPicker.frame(width: 210)
                }
                VStack(alignment: .leading) {
                    exploreHeading
                    inspirationPicker
                }
            }
            HStack {
                Image(systemName: "magnifyingglass").accessibilityHidden(true)
                TextField("Find words for a moment or feeling", text: $viewModel.searchText)
                    .font(.subheadline)
                    .submitLabel(.search)
                    .accessibilityLabel("Search inspiration")
                if !viewModel.searchText.isEmpty {
                    Button { viewModel.searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            if showsSaved {
                Text("Saved on this device for your account. Nothing is added to the necklace until you choose Add.")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !viewModel.categories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        categoryButton("All", key: nil)
                        ForEach(viewModel.categories) { category in
                            categoryButton(category.name, key: category.key)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .foregroundStyle(LumiTheme.Colors.ink)
        .background(LumiTheme.Colors.pageBackground)
    }

    private var inspirationPicker: some View {
        Picker("Inspiration", selection: $showsSaved) {
            Text("Discover").tag(false)
            Text("Saved").tag(true)
        }
        .pickerStyle(.segmented)
    }

    private func categoryButton(_ title: String, key: String?) -> some View {
        Button { Task { await viewModel.selectCategory(key) } } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .foregroundStyle(viewModel.selectedCategoryKey == key ? .white : LumiTheme.Colors.ink)
                .background(viewModel.selectedCategoryKey == key ? LumiTheme.Colors.rose : Color.white, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(viewModel.selectedCategoryKey == key ? .isSelected : [])
    }

    @ViewBuilder
    private var catalog: some View {
        if showsSaved {
            if experiences.isEmpty {
                ExploreCatalogStatusView(title: "Your inspiration, kept close", message: "Tap Save on a message to find it here. Try clearing your search if you’ve saved something already.", systemImage: "heart")
            } else { feed }
        } else {
            switch viewModel.state {
            case .idle, .loading:
                ExploreCatalogStatusView(title: "Loading inspiration…", message: "Finding the right words.", systemImage: "sparkles", showsProgress: true)
            case .empty:
                ExploreCatalogStatusView(title: "No matching Lumis", message: "Try another feeling or occasion, or clear your search and choose All.", systemImage: "magnifyingglass")
            case let .failed(message):
                ExploreCatalogStatusView(title: "Explore couldn’t load", message: message, systemImage: "wifi.exclamationmark", retryAction: { Task { await viewModel.reload() } })
            case .loaded:
                feed
            }
        }
    }

    @ViewBuilder
    private var feed: some View {
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(experiences) { experience in
                        VStack(alignment: .leading, spacing: 16) {
                            Text(experience.title).font(.headline)
                            Text(experience.displayMessage).font(.body)
                            Button {
                                if let template = templates.first(where: { $0.id == experience.id }) {
                                    viewModel.toggleSaved(template)
                                }
                            } label: {
                                Label(viewModel.savedMessages.contains { $0.id == experience.id } ? "Saved" : "Save inspiration", systemImage: "heart")
                                    .frame(minHeight: 44)
                            }
                            Button(isExperienceAdded(experience.id) ? "Added" : "Make it yours") { selectedExperience = experience }
                                .disabled(isExperienceAdded(experience.id))
                                .buttonStyle(PrimaryButtonStyle())
                        }
                        .foregroundStyle(LumiTheme.Colors.ink)
                        .glassCard()
                        .task {
                            if !showsSaved, let template = templates.first(where: { $0.id == experience.id }) {
                                await viewModel.loadMoreIfNeeded(after: template)
                            }
                        }
                    }
                }
                .padding(16)
            }
        } else {
            immersiveFeed
        }
    }

    private var immersiveFeed: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(experiences) { experience in
                    ExploreExperiencePage(
                        experience: experience,
                        topSafeAreaInset: 0,
                        isActive: (activeExperienceID ?? experiences.first?.id) == experience.id,
                        isSaved: viewModel.savedMessages.contains { $0.id == experience.id },
                        isAdded: isExperienceAdded(experience.id),
                        onSave: {
                            if let template = templates.first(where: { $0.id == experience.id }) {
                                viewModel.toggleSaved(template)
                            }
                        },
                        onAdd: { selectedExperience = experience }
                    )
                    .containerRelativeFrame(.vertical)
                    .id(experience.id)
                    .task {
                        if !showsSaved, let template = templates.first(where: { $0.id == experience.id }) {
                            await viewModel.loadMoreIfNeeded(after: template)
                        }
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $activeExperienceID)
        .scrollDismissesKeyboard(.interactively)
    }

    private func isExperienceAdded(_ id: ExploreLumi.ID) -> Bool {
        addedExperienceIDs.contains(id) || viewModel.messages.first(where: { $0.id == id })?.isQueued == true
    }

    private func addToNecklace(_ experience: ExploreLumi, destination: QueueSection, customization: LibraryTextCustomization? = nil) async -> String? {
        guard let template = (viewModel.messages + viewModel.savedMessages).first(where: { $0.id == experience.id }) else {
            return "This message is no longer available. Refresh Explore and try again."
        }
        guard !isExperienceAdded(experience.id) else { return "This Lumi is already in the necklace sequence." }
        let added = await viewModel.enqueue(template, destination: destination, customization: customization)
        guard added else { return viewModel.actionError ?? "This Lumi couldn’t be added. Please try again." }
        addedExperienceIDs.insert(experience.id)
        appState.hapticsManager.impact(enabled: appState.settings.hapticsEnabled)
        toastDismissTask?.cancel()
        toast = "Added to \(destination.displayName)"
        toastDismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            toast = nil
        }
        return nil
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
                        .tint(LumiTheme.Colors.rose)
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
                    .foregroundStyle(LumiTheme.Colors.ink.opacity(0.75))
                    .multilineTextAlignment(.center)
                if let retryAction {
                    Button("Retry", action: retryAction)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .frame(minHeight: 50)
                        .background(LumiTheme.Colors.rose, in: Capsule())
                }
                Spacer(minLength: 80)
            }
            .foregroundStyle(LumiTheme.Colors.ink)
            .frame(maxWidth: 420)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
        }
        .background(LumiTheme.Colors.pageBackground)
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

    var body: some View {
        ZStack {
            LumiExperienceView(experience: experience, isActive: isActive)

            VStack(spacing: 0) {
                Spacer(minLength: 20)
                information
            }
            .padding(.horizontal, 20)
            .padding(.top, topSafeAreaInset + 12)
            .padding(.bottom, 18)
        }
    }

    private var information: some View {
        VStack(spacing: 15) {
            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(experience.title).font(.title3.weight(.bold))
                    Text("\(experience.category) · \(experience.mood) · \(experience.durationSeconds) sec")
                        .font(.subheadline.weight(.medium))
                        .opacity(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ExploreActionButton(
                    title: isSaved ? "Saved" : "Save",
                    systemImage: isSaved ? "heart.fill" : "heart",
                    foregroundColor: experience.foregroundColor,
                    action: onSave
                )
            }
            .foregroundStyle(experience.foregroundColor)
            .shadow(color: .black.opacity(0.20), radius: 9, y: 4)

            Button(action: onAdd) {
                Label(
                    isAdded ? "Added" : "Make it yours",
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
            .accessibilityHint(isAdded ? "Already in the necklace sequence" : "Review, personalize, and choose when this Lumi appears")
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

struct ExploreCustomizationSheet: View {
    let experience: ExploreLumi
    let necklaceName: String
    let canEnqueue: Bool
    let onAdd: (String, String?, QueueSection) async -> String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isTextFocused: Bool
    @State private var primaryText: String
    @State private var secondaryText: String
    @State private var destination: QueueSection = .upNext
    @State private var activeSlot: TextSlot = .primary
    @State private var isTextEditing = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showsDiscardConfirmation = false
    @State private var showsReview = false

    private enum TextSlot: String {
        case primary = "Message"
        case secondary = "Second reveal"
    }

    init(
        experience: ExploreLumi,
        necklaceName: String,
        canEnqueue: Bool,
        onAdd: @escaping (String, String?, QueueSection) async -> String?
    ) {
        self.experience = experience
        self.onAdd = onAdd
        self.necklaceName = necklaceName
        self.canEnqueue = canEnqueue
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

        }
        .disabled(isSaving)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomControls.disabled(isSaving) }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .confirmationDialog("Discard your changes?", isPresented: $showsDiscardConfirmation, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) { }
        }
        .sheet(isPresented: $showsReview) { reviewSheet }
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
            Button {
                if primaryText != experience.message || secondaryText != (experience.secondaryText ?? "") {
                    showsDiscardConfirmation = true
                } else { dismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.34), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
            }
            .disabled(isSaving)
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
                Button { showsReview = true } label: {
                    Text("Review")
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .frame(minWidth: 72, minHeight: 44)
                        .background(
                            LinearGradient(
                                colors: [LumiTheme.Colors.rose, LumiTheme.Colors.rose],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: Capsule()
                        )
                }
                .disabled(!canAdd || isSaving)
                .opacity(canAdd && !isSaving ? 1 : 0.48)
                .accessibilityLabel("Review your Lumi")
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

            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)

            if !canEnqueue {
                Text("Choose an active necklace in Home to add a new Lumi.")
                    .font(.subheadline).padding(.horizontal, 20)
            }
            HStack(spacing: 10) {
                slotButton(.primary)
                if experience.secondaryText != nil { slotButton(.secondary) }
            }
            .padding(.horizontal, 18)


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

    private var reviewSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(necklaceName).font(.subheadline.weight(.semibold))
                        .foregroundStyle(LumiTheme.Colors.rose)
                    Text(primaryText).font(.system(.title3, design: .serif)).glassCard()
                    if let secondary = secondaryText.nilIfBlank {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Second reveal").font(.headline)
                            Text(secondary).font(.system(.title3, design: .serif))
                        }.glassCard()
                    }
                    QueueDestinationPicker(selection: $destination)
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                    PrimaryButton(title: "Add to \(destination.displayName)", isLoading: isSaving, action: addCustomizedLumi)
                        .disabled(!canAdd || isSaving)
                }.padding(20)
            }
            .foregroundStyle(LumiTheme.Colors.ink)
            .background(LumiTheme.Colors.pageBackground)
            .navigationTitle("Review your Lumi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Keep editing") { showsReview = false }.disabled(isSaving)
                }
            }
        }
        .preferredColorScheme(.light)
        .interactiveDismissDisabled(isSaving)
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
                    primaryText = value
                } else {
                    secondaryText = value
                }
            }
        )
    }

    private var canAdd: Bool {
        let primary = primaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        return canEnqueue && !primary.isEmpty && primary.count <= 500 && secondaryText.count <= 250
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
        guard canAdd, !isSaving else { return }
        isSaving = true
        Task {
            errorMessage = await onAdd(primaryText.trimmingCharacters(in: .whitespacesAndNewlines), secondaryText.nilIfBlank, destination)
            isSaving = false
            if errorMessage == nil { dismiss() }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
