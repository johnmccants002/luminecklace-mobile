import SwiftUI

struct ExploreView: View {
    @StateObject private var viewModel: ExploreViewModel
    @State private var personalizedTemplate: MessageTemplate?

    init(appState: AppState) {
        _viewModel = StateObject(wrappedValue: ExploreViewModel(appState: appState))
    }

    var body: some View {
        ZStack(alignment: .top) {
            LumiTheme.Colors.pageBackground.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    header
                    necklaceSelector
                    categoryPicker
                    catalog
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .refreshable {
                await viewModel.reload()
            }

            if let confirmation = viewModel.confirmation {
                confirmationBanner(confirmation)
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $viewModel.searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Find the right words"
        )
        .task {
            await viewModel.loadIfNeeded()
        }
        .task(id: viewModel.searchText) {
            await viewModel.searchChanged()
        }
        .sheet(item: $personalizedTemplate) { template in
            PersonalizeLibraryMessageSheet(template: template, viewModel: viewModel)
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { personalizedTemplate == nil && viewModel.actionError != nil },
                set: { if !$0 { viewModel.clearActionError() } }
            ),
            actions: {
                Button("OK", role: .cancel) { viewModel.clearActionError() }
            },
            message: {
                Text(viewModel.actionError ?? "")
            }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("A little inspiration")
                .font(LumiTheme.Typography.display(34))
                .foregroundStyle(LumiTheme.Colors.ink)
            Text("Find a thought that feels like yours, then send it as-is or make it more personal.")
                .font(LumiTheme.Typography.body(15))
                .foregroundStyle(LumiTheme.Colors.ink.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var necklaceSelector: some View {
        if let selected = viewModel.selectedNecklace {
            HStack(spacing: 12) {
                Image(systemName: "heart.circle.fill")
                    .font(.title2)
                    .foregroundStyle(LumiTheme.Colors.rose)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Adding to")
                        .font(.caption)
                        .foregroundStyle(LumiTheme.Colors.ink.opacity(0.62))
                    Text(selected.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(LumiTheme.Colors.ink)
                }
                Spacer()
                if viewModel.necklaces.count > 1 {
                    Menu {
                        ForEach(viewModel.necklaces) { necklace in
                            Button {
                                Task { await viewModel.chooseNecklace(necklace.id) }
                            } label: {
                                if necklace.id == selected.id {
                                    Label(necklace.name, systemImage: "checkmark")
                                } else {
                                    Text(necklace.name)
                                }
                            }
                        }
                    } label: {
                        Label("Switch", systemImage: "chevron.up.chevron.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(LumiTheme.Colors.rose)
                            .frame(minHeight: 44)
                    }
                    .accessibilityHint("Choose which necklace receives this Lumi")
                }
            }
            .glassCard()
        } else {
            EmptyStateView(
                title: "No necklace ready",
                subtitle: "Link an eligible Lumi necklace before adding a message.",
                systemImage: "heart.slash"
            )
        }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                categoryButton(title: "All", key: nil)
                ForEach(viewModel.categories) { category in
                    categoryButton(title: category.name, key: category.key)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityLabel("Message categories")
    }

    private func categoryButton(title: String, key: String?) -> some View {
        let selected = viewModel.selectedCategoryKey == key
        return Button {
            Task { await viewModel.selectCategory(key) }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Color.white : LumiTheme.Colors.ink.opacity(0.78))
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(selected ? LumiTheme.Colors.rose : Color.white.opacity(0.82))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(LumiTheme.Colors.cardStroke, lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var catalog: some View {
        switch viewModel.state {
        case .idle, .loading:
            VStack(spacing: 12) {
                ProgressView()
                    .tint(LumiTheme.Colors.rose)
                Text("Gathering thoughtful words…")
                    .font(.subheadline)
                    .foregroundStyle(LumiTheme.Colors.ink.opacity(0.68))
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .accessibilityElement(children: .combine)
        case .failed(let message):
            VStack(spacing: 14) {
                EmptyStateView(
                    title: "The words aren’t here yet",
                    subtitle: message,
                    systemImage: "wifi.exclamationmark"
                )
                Button("Try Again") {
                    Task { await viewModel.reload() }
                }
                .buttonStyle(SecondaryButtonStyle())
                .accessibilityHint("Reload message suggestions")
            }
        case .empty:
            EmptyStateView(
                title: "No messages found",
                subtitle: viewModel.searchText.isEmpty
                    ? "There aren’t any published messages in this category yet."
                    : "Try a different phrase or category.",
                systemImage: "text.magnifyingglass"
            )
        case .loaded:
            ForEach(viewModel.messages) { message in
                MessageLibraryCard(
                    message: message,
                    isEnqueuing: viewModel.enqueuingMessageIDs.contains(message.id),
                    canEnqueue: viewModel.canEnqueue,
                    onAdd: {
                        Task { await viewModel.enqueue(message) }
                    },
                    onPersonalize: {
                        viewModel.clearActionError()
                        personalizedTemplate = message
                    }
                )
                .onAppear {
                    Task { await viewModel.loadMoreIfNeeded(after: message) }
                }
            }
            if viewModel.loadingMore {
                ProgressView("More thoughtful words…")
                    .tint(LumiTheme.Colors.rose)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }

    private func confirmationBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LumiTheme.Colors.ink)
            Spacer()
            Button {
                viewModel.clearConfirmation()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Dismiss confirmation")
        }
        .padding(.leading, 16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

private struct MessageLibraryCard: View {
    let message: MessageTemplate
    let isEnqueuing: Bool
    let canEnqueue: Bool
    let onAdd: () -> Void
    let onPersonalize: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(message.category.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LumiTheme.Colors.rose)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(LumiTheme.Colors.roseSoft, in: Capsule())
                Spacer()
                if message.isQueued == true {
                    Label("In queue", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LumiTheme.Colors.ink.opacity(0.62))
                } else if message.wasRecentlyRevealed == true {
                    Label("Recently used", systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LumiTheme.Colors.ink.opacity(0.62))
                }
            }

            Text(message.text)
                .font(.title3.weight(.medium))
                .foregroundStyle(LumiTheme.Colors.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Suggested message: \(message.text)")

            HStack(spacing: 10) {
                Button(action: onPersonalize) {
                    Text("Personalize")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!canEnqueue || isEnqueuing)
                .accessibilityHint("Edit this suggestion before adding it")

                Button(action: onAdd) {
                    Group {
                        if isEnqueuing {
                            ProgressView()
                                .tint(.white)
                                .accessibilityLabel("Adding to queue")
                        } else {
                            Text("Add to Queue")
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canEnqueue || isEnqueuing)
                .accessibilityHint("Adds this suggestion to the selected necklace")
            }
        }
        .glassCard()
    }
}

private struct PersonalizeLibraryMessageSheet: View {
    let template: MessageTemplate
    @ObservedObject var viewModel: ExploreViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(template: MessageTemplate, viewModel: ExploreViewModel) {
        self.template = template
        self.viewModel = viewModel
        _text = State(initialValue: template.text)
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !trimmedText.isEmpty && text.count <= 500
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LumiTheme.Colors.pageBackground.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    Text("Make it sound like you")
                        .font(LumiTheme.Typography.display(30))
                        .foregroundStyle(LumiTheme.Colors.ink)
                    TextEditor(text: $text)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(minHeight: 190)
                        .background(Color.white.opacity(0.84))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(text.count > 500 ? Color.red : LumiTheme.Colors.cardStroke)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .accessibilityLabel("Personalized Lumi message")

                    HStack {
                        Text(text.count > 500 ? "Keep your Lumi to 500 characters." : "Your words will be saved as a snapshot.")
                            .font(.caption)
                            .foregroundStyle(text.count > 500 ? Color.red : LumiTheme.Colors.ink.opacity(0.62))
                        Spacer()
                        Text("\(text.count)/500")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(text.count > 500 ? Color.red : LumiTheme.Colors.ink.opacity(0.62))
                            .accessibilityLabel("\(text.count) of 500 characters")
                    }
                    if let error = viewModel.actionError {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("Error. \(error)")
                    }
                    Spacer()
                    Button {
                        Task {
                            if await viewModel.enqueue(template, personalizedText: text) {
                                dismiss()
                            }
                        }
                    } label: {
                        if viewModel.enqueuingMessageIDs.contains(template.id) {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel("Adding to queue")
                        } else {
                            Text("Add to Queue")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!isValid || viewModel.enqueuingMessageIDs.contains(template.id))
                }
                .padding(20)
            }
            .navigationTitle("Personalize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(viewModel.enqueuingMessageIDs.contains(template.id))
    }
}
