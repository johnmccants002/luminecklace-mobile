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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isTextFocused: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var selectedTool: ComposerTool? = .background
    @State private var departingTool: ComposerTool?
    @State private var isPreparingTextEditing = false
    @State private var isTextEditing = false
    @State private var textEntryTask: Task<Void, Never>?

    private enum ComposerTool: String, CaseIterable {
        case background = "Background"

        var icon: String {
            switch self {
            case .background: "paintpalette"
            }
        }
    }

    var body: some View {
        ZStack {
            LumiBackgroundResolver.background(for: appState.composerBackground)
                .ignoresSafeArea()

            ambientCanvasDecoration
                .ignoresSafeArea()

            composerCanvas

            VStack {
                topBar
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            HStack {
                Spacer()
                toolRail
            }
            .padding(.trailing, 10)
            .padding(.top, dynamicTypeSize.isAccessibilitySize ? 106 : 132)
            .padding(.bottom, selectedTool == nil ? 82 : 190)
            .opacity(isTextModeActive ? 0 : 1)
            .offset(x: reduceMotion || !isTextModeActive ? 0 : 18)
            .allowsHitTesting(!isTextModeActive)
            .accessibilityHidden(isTextModeActive)

            if let errorMessage, !errorMessage.isEmpty {
                VStack {
                    Spacer()
                    Text(errorMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.red.opacity(0.88), in: Capsule())
                        .padding(.bottom, selectedTool == nil ? 82 : 210)
                }
                .padding(.horizontal, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomControls
        }
        .preferredColorScheme(.dark)
        .onChange(of: isTextFocused) { _, focused in
            guard !focused, isTextEditing else { return }
            withAnimation(composerTransitionAnimation) {
                isTextEditing = false
            }
        }
        .onDisappear {
            textEntryTask?.cancel()
        }
    }

    private var composerCanvas: some View {
        let pointSize = LumiTextLayoutResolver.effectivePointSize(
            for: appState.composerTextSize,
            characterCount: appState.composerDraftText.count
        )
        let horizontalAlignment = LumiTextLayoutResolver.horizontalAlignment(
            for: appState.composerTextAlignment
        )
        let verticalAlignment = LumiTextLayoutResolver.verticalAlignment(
            for: appState.composerTextPosition
        )

        return GeometryReader { _ in
            TextField(
                "",
                text: composerDraftBinding,
                prompt: Text("Tap to write your message")
                    .foregroundStyle(
                        LumiBackgroundResolver.foreground(for: appState.composerBackground)
                            .opacity(0.34)
                    ),
                axis: .vertical
            )
            .lineLimit(1...16)
            .font(
                .system(
                    size: pointSize,
                    weight: .regular,
                    design: LumiTextLayoutResolver.fontDesign(for: appState.composerFont)
                )
            )
            .multilineTextAlignment(
                LumiTextLayoutResolver.textAlignment(for: appState.composerTextAlignment)
            )
            .foregroundStyle(LumiBackgroundResolver.foreground(for: appState.composerBackground))
            .tint(.white)
            .focused($isTextFocused)
            .textFieldStyle(.plain)
            .allowsHitTesting(isTextEditing)
            .frame(maxWidth: .infinity, alignment: horizontalAlignment)
            // Symmetric bounds keep centered text anchored while the side rail
            // fades and while the keyboard changes the available height.
            .padding(.horizontal, 76)
            .padding(.top, 108)
            .padding(.bottom, 72)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: verticalAlignment)
            .overlay {
                if !isTextEditing {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            beginTextEditing()
                        }
                        .accessibilityElement()
                        .accessibilityLabel(
                            appState.composerDraftText.isEmpty
                                ? "Tap to write your message"
                                : "Edit Lumi message"
                        )
                        .accessibilityAddTraits(.isButton)
                }
            }
            .accessibilityLabel("Lumi message")
            .accessibilityHint("Enter up to 500 characters")
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                textEntryTask?.cancel()
                isTextFocused = false
                appState.cancelLumiComposer()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.34), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.12), lineWidth: 1))
            }
            .accessibilityLabel("Close composer")
            .opacity(isTextModeActive ? 0 : 1)
            .allowsHitTesting(!isTextModeActive)

            Spacer()

            if appState.composerDraftText.count >= 400 {
                Text("\(appState.composerDraftText.count)/500")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(
                        appState.composerDraftText.count > 500
                            ? Color.yellow
                            : Color.white.opacity(0.82)
                    )
                    .padding(.trailing, 6)
                    .transition(.opacity)
            }

            if isTextModeActive {
                Button("Done") {
                    finishTextEditing()
                }
                .font(.headline)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(.black.opacity(0.38), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
                .accessibilityHint("Finishes editing the message")
                .transition(.opacity)
            } else {
                Button {
                    advanceFromComposer()
                } label: {
                    Group {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text(appState.composerIsEditing ? "Save" : "Next")
                                .font(.headline)
                        }
                    }
                    .frame(minWidth: 72, minHeight: 44)
                    .background(
                        LinearGradient(
                            colors: [
                                LumiTheme.Colors.rose,
                                Color(red: 1.0, green: 0.46, blue: 0.35)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
                }
                .disabled(!canAdvance || isSaving)
                .opacity(canAdvance ? 1 : 0.48)
                .accessibilityHint(
                    appState.composerIsEditing
                        ? "Saves your changes"
                        : "Saves this Lumi to Up Next"
                )
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var toolRail: some View {
        VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 8 : 12) {
            ForEach(ComposerTool.allCases, id: \.self) { tool in
                let selected = selectedTool == tool
                Button {
                    withAnimation(composerTransitionAnimation) {
                        selectedTool = selected ? nil : tool
                    }
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(.black.opacity(selected ? 0.58 : 0.42))
                                .frame(width: 46, height: 46)
                            Image(systemName: tool.icon)
                                .font(.system(size: 19, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                            if selected {
                                Circle()
                                    .stroke(.white, lineWidth: 2)
                                    .frame(width: 46, height: 46)

                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .background(.black, in: Circle())
                                    .offset(x: 17, y: 17)
                                    .accessibilityHidden(true)
                            }
                        }

                        Text(tool.rawValue)
                            .font(.caption2.weight(.semibold))
                            .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                    }
                    .frame(width: 64)
                    .frame(minHeight: 58)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .accessibilityValue(selected ? "Selected" : "Not selected")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private var bottomControls: some View {
        if isTextEditing {
            textEditingAccessory
            .transition(editingBarTransition)
        } else if isPreparingTextEditing, let departingTool {
            // Retain the outgoing drawer's measured height while it fades.
            // This prevents the canvas from resizing before the keyboard starts
            // its own safe-area animation.
            toolDrawer(for: departingTool)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else if let selectedTool {
            toolDrawer(for: selectedTool)
                .transition(panelTransition)
        } else {
            Button {
                beginTextEditing()
            } label: {
                Label("Tap text to edit", systemImage: "pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .frame(minHeight: 50)
                    .background(.black.opacity(0.28), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 14)
            .transition(.opacity)
        }
    }

    private var textEditingAccessory: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LumiFontKey.allCases, id: \.self) { font in
                        let selected = appState.composerFont == font
                        Button {
                            withAnimation(composerTransitionAnimation) {
                                appState.composerFont = font
                            }
                        } label: {
                            Text(font.rawValue.capitalized)
                                .font(
                                    .system(
                                        size: 15,
                                        weight: selected ? .semibold : .regular,
                                        design: LumiTextLayoutResolver.fontDesign(for: font)
                                    )
                                )
                                .padding(.horizontal, 15)
                                .frame(height: 36)
                                .background(
                                    selected ? Color.white : Color.white.opacity(0.08),
                                    in: Capsule()
                                )
                                .foregroundStyle(selected ? Color.black : Color.white)
                                .overlay(
                                    Capsule().stroke(
                                        selected ? Color.white : Color.white.opacity(0.16),
                                        lineWidth: 1
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(font.rawValue.capitalized) font")
                        .accessibilityValue(selected ? "Selected" : "Not selected")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 14)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(LumiTextAlignmentKey.allCases, id: \.self) { alignment in
                            Button(alignment.accessibilityName) {
                                appState.composerTextAlignment = alignment
                            }
                        }
                    } label: {
                        editingToolLabel(
                            icon: appState.composerTextAlignment.systemImage,
                            title: "Align"
                        )
                    }
                    .accessibilityLabel("Text alignment")
                    .accessibilityValue(appState.composerTextAlignment.accessibilityName)

                    Menu {
                        ForEach(LumiTextSizeKey.allCases, id: \.self) { size in
                            Button(size.rawValue.capitalized) {
                                appState.composerTextSize = size
                            }
                        }
                    } label: {
                        editingToolLabel(icon: "textformat.size", title: "Size")
                    }
                    .accessibilityLabel("Text size")
                    .accessibilityValue(appState.composerTextSize.rawValue.capitalized)

                    Menu {
                        ForEach(LumiTextPositionKey.allCases, id: \.self) { position in
                            Button(position.rawValue.capitalized) {
                                appState.composerTextPosition = position
                            }
                        }
                    } label: {
                        editingToolLabel(
                            icon: appState.composerTextPosition.systemImage,
                            title: "Position"
                        )
                    }
                    .accessibilityLabel("Text position")
                    .accessibilityValue(appState.composerTextPosition.rawValue.capitalized)
                }
                .padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
        .background(.black.opacity(0.7))
    }

    private func editingToolLabel(
        icon: String,
        title: String
    ) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
        }
        .frame(width: 58, height: 43)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func toolDrawer(for tool: ComposerTool) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.28))
                .frame(width: 40, height: 4)
                .padding(.top, 7)

            HStack {
                Text(tool.rawValue)
                    .font(.headline)
                Spacer()
                Button("Done") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        selectedTool = nil
                    }
                }
                .font(.headline)
                .foregroundStyle(Color(red: 1.0, green: 0.30, blue: 0.54))
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 10)

            drawerContent(for: tool)
                .padding(.bottom, 12)
        }
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.white)
        .background(.ultraThinMaterial)
        .background(.black.opacity(0.62))
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 24,
                topTrailingRadius: 24
            )
        )
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(
                topLeadingRadius: 24,
                topTrailingRadius: 24
            )
            .stroke(.white.opacity(0.1), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func drawerContent(for tool: ComposerTool) -> some View {
        switch tool {
        case .background:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(LumiBackgroundKey.allCases, id: \.self) { background in
                        let selected = appState.composerBackground == background
                        Button {
                            appState.composerBackground = background
                        } label: {
                            VStack(spacing: 7) {
                                LumiBackgroundResolver.background(for: background)
                                    .frame(width: 64, height: 82)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(.white, lineWidth: selected ? 3 : 0)
                                    )
                                    .overlay(alignment: .topTrailing) {
                                        if selected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.black, .white)
                                                .padding(7)
                                        }
                                    }

                                Text(background.rawValue.capitalized)
                                    .font(.caption.weight(selected ? .bold : .regular))
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(selected ? "Selected" : "Not selected")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 20)
            }
            // A horizontal ScrollView has an ambiguous intrinsic height inside
            // a safe-area inset. Reserve its full thumbnail height so the
            // drawer is measured above the home indicator instead of clipped.
            .frame(height: 108)

        }
    }

    private var ambientCanvasDecoration: some View {
        GeometryReader { geometry in
            ZStack {
                Circle()
                    .fill(.white.opacity(0.13))
                    .frame(width: geometry.size.width * 0.72)
                    .blur(radius: 70)
                    .offset(
                        x: geometry.size.width * 0.28,
                        y: geometry.size.height * 0.14
                    )

                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geometry.size.height * 0.32)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var canAdvance: Bool {
        let trimmed = appState.composerDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 500
    }

    private func advanceFromComposer() {
        finishTextEditing()
        save(to: .upNext)
    }

    private var isTextModeActive: Bool {
        isPreparingTextEditing || isTextEditing
    }

    private var composerTransitionAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.24)
    }

    private var panelTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .move(edge: .bottom).combined(with: .opacity)
    }

    private var editingBarTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .move(edge: .bottom).combined(with: .opacity)
    }

    private func beginTextEditing() {
        guard !isTextModeActive else { return }
        textEntryTask?.cancel()
        errorMessage = nil

        guard !reduceMotion, let selectedTool else {
            self.selectedTool = nil
            activateTextEditing()
            return
        }

        departingTool = selectedTool
        withAnimation(composerTransitionAnimation) {
            isPreparingTextEditing = true
            self.selectedTool = nil
        }

        textEntryTask = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            activateTextEditing()
        }
    }

    private func activateTextEditing() {
        withAnimation(composerTransitionAnimation) {
            isPreparingTextEditing = false
            isTextEditing = true
        }
        departingTool = nil

        Task {
            await Task.yield()
            guard isTextEditing else { return }
            isTextFocused = true
        }
    }

    private func finishTextEditing() {
        textEntryTask?.cancel()
        textEntryTask = nil
        isTextFocused = false
        withAnimation(composerTransitionAnimation) {
            isPreparingTextEditing = false
            isTextEditing = false
        }
        departingTool = nil
    }

    private func save(to destination: QueueSection) {
        Task {
            isSaving = true
            errorMessage = nil
            defer { isSaving = false }
            do {
                try await appState.addLumi(
                    text: appState.composerDraftText,
                    destination: destination
                )
            } catch {
                withAnimation(.easeOut(duration: 0.2)) {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private var composerDraftBinding: Binding<String> {
        Binding(
            get: { appState.composerDraftText },
            set: { appState.composerDraftText = String($0.prefix(500)) }
        )
    }
}

struct UpNextEditorView: View {
    var body: some View {
        QueueSectionEditorView(section: .upNext)
    }
}

struct ReserveEditorView: View {
    var body: some View {
        QueueSectionEditorView(section: .reserve)
    }
}

private struct QueueSectionEditorView: View {
    @EnvironmentObject private var appState: AppState
    @State private var editMode: EditMode = .active
    @State private var pendingRemoval: Message?

    let section: QueueSection

    private var messages: [Message] {
        section == .upNext ? appState.queueMessages : appState.reserveMessages
    }

    private var title: String {
        section == .upNext ? "Edit Up Next" : "Edit Reserve"
    }

    private var explanation: String {
        section == .upNext
            ? "These messages appear after the current Lumi, in this order."
            : "Reserve continues after Up Next. It stays here until Up Next runs out or you move a message forward."
    }

    private var emptyTitle: String {
        section == .upNext ? "Nothing is Up Next" : "Reserve is empty"
    }

    private var emptyDetail: String {
        section == .upNext
            ? "When the current Lumi is revealed, Reserve will continue in its own order."
            : "Add messages here to keep them behind Up Next."
    }

    var body: some View {
        ZStack {
            LumiTheme.Colors.pageBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                header

                if let error = appState.queueActionError {
                    QueueErrorBanner(message: error) {
                        appState.clearQueueActionError()
                    }
                }

                if messages.isEmpty {
                    EmptyStateView(
                        title: emptyTitle,
                        subtitle: emptyDetail,
                        systemImage: section == .upNext ? "sparkles" : "tray"
                    )
                    Spacer(minLength: 0)
                } else {
                    Text("Drag to reorder. Use the menu for queue actions.")
                        .font(LumiTheme.Typography.body(14))
                        .foregroundStyle(LumiTheme.Colors.ink.opacity(0.66))

                    List {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            QueueActionRow(
                                index: index,
                                message: message,
                                section: section,
                                isDisabled: appState.isQueueMutating,
                                onMakeNext: { appState.makeUpNext(message.id) },
                                onMoveToReserve: { appState.moveToReserve(message.id) },
                                onMoveToUpNext: { appState.moveToUpNext(message.id) },
                                onImmediateNext: { appState.addAsImmediateNext(message.id) },
                                onEdit: { appState.openLumiComposer(editing: message, in: section) },
                                onRemove: { pendingRemoval = message }
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        .onMove { source, destination in
                            appState.reorderMessages(
                                in: section,
                                from: source,
                                to: destination
                            )
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.editMode, $editMode)
                }
            }
            .padding(20)

            if appState.isQueueMutating {
                ProgressView("Saving order…")
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("Saving queue order")
            }
        }
        .onAppear { editMode = .active }
        .task {
            await appState.refreshQueueSnapshot()
        }
        .alert(
            "Remove this Lumi?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            presenting: pendingRemoval
        ) { message in
            Button("Remove", role: .destructive) {
                appState.removeQueuedMessage(message.id)
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRemoval = nil
            }
        } message: { _ in
            Text("This removes the Lumi from the necklace sequence.")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(LumiTheme.Typography.display(34))
                    .foregroundStyle(LumiTheme.Colors.ink)

                Text(explanation)
                    .font(LumiTheme.Typography.body(15))
                    .foregroundStyle(LumiTheme.Colors.ink.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button("Done") {
                appState.closeQueueEditor()
            }
            .buttonStyle(SecondaryButtonStyle())
            .frame(maxWidth: 76)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct QueueErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .font(LumiTheme.Typography.body(13))
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("Dismiss error")
        }
        .foregroundStyle(.red)
        .padding(12)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct QueueActionRow: View {
    let index: Int
    let message: Message
    let section: QueueSection
    let isDisabled: Bool
    let onMakeNext: () -> Void
    let onMoveToReserve: () -> Void
    let onMoveToUpNext: () -> Void
    let onImmediateNext: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            queueStylePreview

            VStack(alignment: .leading, spacing: 5) {
                Text("\(index + 1). \(message.text)")
                    .font(
                        .system(
                            size: 16,
                            design: LumiTextLayoutResolver.fontDesign(for: message.experience.fontKey)
                        )
                    )
                    .foregroundStyle(LumiTheme.Colors.ink)
                    .multilineTextAlignment(
                        LumiTextLayoutResolver.textAlignment(for: message.experience.textAlignment)
                    )
                    .lineLimit(3)
                    .frame(
                        maxWidth: .infinity,
                        alignment: LumiTextLayoutResolver.horizontalAlignment(
                            for: message.experience.textAlignment
                        )
                    )

                Text(
                    "\(message.experience.textSize.rawValue.capitalized) · "
                    + "\(message.experience.textAlignment.rawValue.capitalized) · "
                    + message.experience.textPosition.rawValue.capitalized
                )
                .font(.caption)
                .foregroundStyle(LumiTheme.Colors.ink.opacity(0.56))

                LumiAttachmentBadge(attachment: message.attachment)
            }

            Menu {
                Button("Edit Lumi", systemImage: "pencil", action: onEdit)
                if section == .upNext {
                    Button("Make next", systemImage: "arrow.up.to.line", action: onMakeNext)
                    Button("Move to Reserve", systemImage: "tray.and.arrow.down", action: onMoveToReserve)
                } else {
                    Button("Move to Up Next", systemImage: "arrow.up.forward", action: onMoveToUpNext)
                    Button("Add as immediate next", systemImage: "arrow.up.to.line", action: onImmediateNext)
                }
                Divider()
                Button("Remove", systemImage: "trash", role: .destructive, action: onRemove)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .disabled(isDisabled)
            .accessibilityLabel("Actions for \(message.text)")
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }

    private var queueStylePreview: some View {
        Text("Aa")
            .font(
                .system(
                    size: message.experience.textSize == .large ? 18 : 14,
                    design: LumiTextLayoutResolver.fontDesign(for: message.experience.fontKey)
                )
            )
            .foregroundStyle(
                LumiBackgroundResolver.foreground(for: message.experience.backgroundKey)
            )
            .frame(
                maxWidth: .infinity,
                alignment: LumiTextLayoutResolver.horizontalAlignment(
                    for: message.experience.textAlignment
                )
            )
            .padding(7)
            .frame(
                width: 58,
                height: 70,
                alignment: LumiTextLayoutResolver.verticalAlignment(
                    for: message.experience.textPosition
                )
            )
            .background(
                LumiBackgroundResolver.background(for: message.experience.backgroundKey)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topLeading) {
                Text("\(index + 1)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.black.opacity(0.32), in: Circle())
                    .offset(x: -5, y: -5)
            }
            .accessibilityHidden(true)
    }
}

struct RecipientRevealView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        RecipientRevealPresentationView(
            revealState: appState.recipientRevealState,
            retryAction: appState.retryRecipientReveal
        )
        .onChange(of: appState.recipientRevealState) { _, state in
            if case let .waiting(lumi) = state {
                appState.completeRecipientHold(for: lumi)
            }
        }
        .onAppear {
            if case let .waiting(lumi) = appState.recipientRevealState {
                appState.completeRecipientHold(for: lumi)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
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
