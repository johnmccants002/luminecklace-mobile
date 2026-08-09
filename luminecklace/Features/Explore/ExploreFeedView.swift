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
        _activeExperienceID = State(initialValue: ExploreLumi.prototypes.first?.id)
    }

    private var experiences: [ExploreLumi] {
        let catalog = viewModel.messages.map(ExploreLumi.init(template:))
        if !catalog.isEmpty { return catalog }
#if DEBUG
        return ExploreLumi.prototypes
#else
        return []
#endif
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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
            .sheet(isPresented: $showsCustomize) {
                ExploreCustomizationSheet(
                    experience: experience,
                    onAdd: onCustomize
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
    @State private var primaryText: String
    @State private var secondaryText: String
    @State private var destination: QueueSection = .upNext

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
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    LumiExperienceRenderer(
                        content: LumiExperienceContent(
                            presetKey: experience.presetKey,
                            primaryText: primaryText,
                            secondaryText: secondaryText.nilIfBlank
                        ),
                        isActive: true
                    )
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Message").font(.headline)
                        TextField("Write your Lumi", text: $primaryText, axis: .vertical)
                            .lineLimit(2...6)
                            .textFieldStyle(.roundedBorder)
                        Text("\(primaryText.count)/500")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    if experience.secondaryText != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Second reveal").font(.headline)
                            TextField("Optional second message", text: $secondaryText, axis: .vertical)
                                .lineLimit(2...4)
                                .textFieldStyle(.roundedBorder)
                            Text("\(secondaryText.count)/250")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    Picker("Destination", selection: $destination) {
                        Text("Up Next").tag(QueueSection.upNext)
                        Text("Reserve").tag(QueueSection.reserve)
                    }
                    .pickerStyle(.segmented)

                    Text("Animation, timing, typography, and background are locked to this preset.")
                        .font(.footnote).foregroundStyle(.secondary)

                    Button("Add to \(destination.displayName)") {
                        onAdd(primaryText.trimmingCharacters(in: .whitespacesAndNewlines), secondaryText.nilIfBlank, destination)
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(primaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || primaryText.count > 500 || secondaryText.count > 250)
                }
                .padding(20)
            }
            .background(LumiTheme.Colors.pageBackground.ignoresSafeArea())
            .navigationTitle("Customize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
