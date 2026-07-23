import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var route: RootRoute = .auth
    @Published var user: User?
    @Published var ownedNecklaces: [NecklaceTag] = []
    @Published var packages: [Package] = MockData.defaultPackages
    @Published var currentMessage: Message?
    @Published var queueMessages: [Message] = []
    @Published var composerDraftText = ""
    @Published var showRetapHint = false
    @Published var settings = UserSettings()
    @Published var recipientRevealState: RecipientRevealState = .awaitingInvocation
    @Published var lastBootstrapError: String?

    let authService = AuthService()
    let senderService = SenderService()
    let tapResolutionService = TapResolutionService()
    let soundManager = SoundManager()
    let hapticsManager = HapticsManager()

    private var didAttemptSessionRestore = false
    private var didReceiveTapLink = false
    private var currentRecipientToken: String?
    private var recipientResolutionTask: Task<Void, Never>?
    private var revealConfirmationTask: Task<Void, Never>?
    private var confirmationSessionIDs: Set<String> = []
    private let lastTagIdKey = "lumi_last_tag_id"
    private let queueCachePrefix = "lumi_queue_cache_"
    private var composerEditingMessageID: String?
    private var composerReturnRoute: RootRoute = .senderHome

    var equippedNecklace: NecklaceTag? {
        ownedNecklaces.first(where: { $0.isEquipped })
    }

    private var persistedTagId: String? {
        get { UserDefaults.standard.string(forKey: lastTagIdKey) }
        set {
            if let newValue, !newValue.isEmpty {
                UserDefaults.standard.set(newValue, forKey: lastTagIdKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastTagIdKey)
            }
        }
    }

    var canAddLumiToEquippedNecklace: Bool {
        guard let status = equippedNecklace?.lifecycleStatus else { return false }
        return status == "active" || status == "pending_sender_setup"
    }

    var equippedReserve: LumiReserveSummary? {
        equippedNecklace?.reserve
    }

    var composerTitle: String {
        isEditingComposer ? "Edit Lumi" : "Add a Lumi"
    }

    var composerSubtitle: String {
        isEditingComposer
            ? "Update this message in the queue. The necklace will keep the current order."
            : "This will be added to the end of the queue."
    }

    var composerActionTitle: String {
        isEditingComposer ? "Update Lumi" : "Save Lumi"
    }

    var composerIsEditing: Bool {
        composerEditingMessageID != nil
    }

    private var isEditingComposer: Bool {
        composerEditingMessageID != nil
    }

    func restoreSessionIfNeeded() async {
        guard !didAttemptSessionRestore else { return }
        didAttemptSessionRestore = true

        guard FeatureFlags.senderFirstFlowEnabled else {
            route = .auth
            return
        }

        guard authService.hasAccessToken else {
            if didReceiveTapLink {
                return
            }
            route = .auth
            return
        }

        do {
            user = try await authService.me()
            await bootstrapSenderFlowAfterAuth()
        } catch APIError.unauthorized {
            authService.clearLocalSession()
            route = .auth
        } catch {
            route = .auth
        }
    }

    func completeAuth(with result: AuthResult) {
        user = result.user
        Task { await bootstrapSenderFlowAfterAuth() }
    }

    func bootstrapSenderFlowAfterAuth() async {
        guard user != nil else {
            route = .auth
            return
        }

        route = .postAuthBootstrap
        lastBootstrapError = nil

        do {
            ownedNecklaces = try await senderService.listSenderNecklaces()

            guard !ownedNecklaces.isEmpty else {
                currentMessage = nil
                persistedTagId = nil
                route = .noNecklace
                return
            }

            if let persistedTagId, ownedNecklaces.contains(where: { $0.id == persistedTagId }) {
                setEquipped(necklaceId: persistedTagId)
            } else if let primary = ownedNecklaces.first(where: \.isEquipped) {
                setEquipped(necklaceId: primary.id)
            } else if let first = ownedNecklaces.first {
                setEquipped(necklaceId: first.id)
            }

            routeAfterNecklaceSelection()
        } catch APIError.unauthorized {
            authService.clearLocalSession()
            route = .auth
        } catch {
            lastBootstrapError = error.localizedDescription
            route = .senderLoadError
        }
    }

    func routeAfterNecklaceSelection() {
        guard let equipped = equippedNecklace else {
            currentMessage = nil
            route = .noNecklace
            return
        }

        syncQueueState(from: equipped)
        route = .senderHome
    }

    func chooseNecklace(_ necklaceId: String) {
        setEquipped(necklaceId: necklaceId)
    }

    func openQueueEditor() {
        guard equippedNecklace != nil else { return }
        route = .queueEditor
    }

    func closeQueueEditor() {
        route = .senderHome
    }

    func openLumiComposer(editing message: Message? = nil) {
        guard canAddLumiToEquippedNecklace else { return }
        composerEditingMessageID = message?.id
        composerDraftText = message?.text ?? ""
        composerReturnRoute = route == .queueEditor ? .queueEditor : .senderHome
        route = .lumiComposer
    }

    func cancelLumiComposer() {
        resetComposerDraft()
        route = composerReturnRoute
    }

    func addLumi(text: String) async throws {
        guard let necklace = equippedNecklace else {
            throw APIError.missingRequiredField("equippedNecklace")
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.serverError(statusCode: 400, message: "Please write a Lumi before saving.")
        }
        guard trimmed.count <= 500 else {
            throw APIError.serverError(statusCode: 400, message: "Your Lumi must be 500 characters or fewer.")
        }

        if let editingMessageID = composerEditingMessageID {
            updateQueueMessage(id: editingMessageID, text: trimmed)
        } else {
            let created = try await senderService.addLumi(
                necklaceId: necklace.id,
                text: trimmed
            )
            appendQueueMessage(created)
        }

        resetComposerDraft()
        route = composerReturnRoute
    }

    func signOut() {
        Task {
            try? await authService.signOut()
        }

        route = .auth
        user = nil
        currentMessage = nil
        queueMessages = []
        composerDraftText = ""
        composerEditingMessageID = nil
        composerReturnRoute = .senderHome
        ownedNecklaces = []
        persistedTagId = nil
        packages = MockData.defaultPackages
        showRetapHint = false
        settings = UserSettings()
        lastBootstrapError = nil
        recipientRevealState = .awaitingInvocation
        didReceiveTapLink = false
        currentRecipientToken = nil
        confirmationSessionIDs = []
        recipientResolutionTask?.cancel()
        revealConfirmationTask?.cancel()
        recipientResolutionTask = nil
        revealConfirmationTask = nil
    }

    func setEquipped(necklaceId: String) {
        ownedNecklaces = ownedNecklaces.map {
            var item = $0
            item.isEquipped = item.id == necklaceId
            return item
        }
        persistedTagId = necklaceId
        if let equipped = equippedNecklace {
            syncQueueState(from: equipped)
        } else {
            queueMessages = []
            currentMessage = nil
        }
    }

    func togglePackage(_ packageId: String, isEnabled: Bool) {
        packages = packages.map { package in
            guard package.id == packageId else { return package }
            if package.isPremium && user?.subscriptionTier != .premium {
                return package
            }
            var updated = package
            updated.isEnabled = isEnabled
            return updated
        }
    }

    func handleIncomingHandoff(url: URL) {
        guard FeatureFlags.senderFirstFlowEnabled else { return }
        guard let token = RecipientInvocationParser.token(from: url) else { return }
        didReceiveTapLink = true
        route = .recipientReveal
        resolveRecipientTap(token: token)
    }

    func retryRecipientReveal() {
        guard let currentRecipientToken else {
            recipientRevealState = .awaitingInvocation
            return
        }
        resolveRecipientTap(token: currentRecipientToken, force: true)
    }

    func completeRecipientHold(for lumi: ResolvedLumi) {
        guard case let .waiting(current) = recipientRevealState,
              current.revealSessionId == lumi.revealSessionId else {
            return
        }

        recipientRevealState = .revealing(lumi)
        hapticsManager.impact(enabled: settings.hapticsEnabled)

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 420_000_000)
            guard let self, !Task.isCancelled else { return }
            self.recipientRevealState = .revealed(lumi, confirmationState: .pending)
            self.confirmRevealIfNeeded(lumi)
        }
    }

    private func resolveRecipientTap(token: String, force: Bool = false) {
        if !force,
           currentRecipientToken == token,
           shouldIgnoreDuplicateInvocation {
            return
        }

        recipientResolutionTask?.cancel()
        if currentRecipientToken != token {
            revealConfirmationTask?.cancel()
        }

        currentRecipientToken = token
        currentMessage = nil
        recipientRevealState = .resolving

        recipientResolutionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let resolved = try await tapResolutionService.resolveTap(token: token)
                guard !Task.isCancelled else { return }

                switch resolved {
                case let .ready(lumi):
                    recipientRevealState = .waiting(lumi)
                case .empty:
                    recipientRevealState = .empty
                case .unavailable:
                    recipientRevealState = .unavailable
                }
            } catch APIError.invalidPayload {
                guard !Task.isCancelled else { return }
                recipientRevealState = .error(.invalidPayload)
            } catch {
                guard !Task.isCancelled else { return }
                recipientRevealState = .error(.network)
            }
        }
    }

    func returnFromRecipientReveal() {
        if user == nil {
            route = .auth
            return
        }

        if ownedNecklaces.isEmpty {
            route = .noNecklace
        } else {
            currentMessage = queueMessages.first
            route = .senderHome
        }
    }

    private var shouldIgnoreDuplicateInvocation: Bool {
        switch recipientRevealState {
        case .resolving, .waiting, .revealing:
            return true
        case .awaitingInvocation, .revealed, .empty, .unavailable, .error:
            return false
        }
    }

    private func confirmRevealIfNeeded(_ lumi: ResolvedLumi) {
        guard !confirmationSessionIDs.contains(lumi.revealSessionId) else { return }
        confirmationSessionIDs.insert(lumi.revealSessionId)
        recipientRevealState = .revealed(lumi, confirmationState: .confirming)

        revealConfirmationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await confirmRevealWithSingleRetry(revealSessionId: lumi.revealSessionId)
                guard !Task.isCancelled else { return }
                recipientRevealState = .revealed(lumi, confirmationState: .confirmed(response.revealedAt))
            } catch {
                guard !Task.isCancelled else { return }
                recipientRevealState = .revealed(lumi, confirmationState: .temporarilyFailed)
            }
        }
    }

    private func confirmRevealWithSingleRetry(revealSessionId: String) async throws -> ConfirmRevealResponse {
        do {
            return try await tapResolutionService.confirmReveal(revealSessionId: revealSessionId)
        } catch {
            try await Task.sleep(nanoseconds: 900_000_000)
            return try await tapResolutionService.confirmReveal(revealSessionId: revealSessionId)
        }
    }

    private func updateEquippedNecklace(with createdLumi: Message) {
        guard let currentId = equippedNecklace?.id else { return }
        let updatedQueue = queueMessages + [createdLumi]
        ownedNecklaces = ownedNecklaces.map { necklace in
            guard necklace.id == currentId else { return necklace }
            var updated = necklace
            updated.availableLumiCount = updatedQueue.count
            updated.nextLumi = updatedQueue.first
            updated.queuedLumis = updatedQueue
            return updated
        }
        queueMessages = updatedQueue
        currentMessage = updatedQueue.first
        persistQueueMessages(updatedQueue, necklaceID: currentId)
    }

    private func syncQueueState(from necklace: NecklaceTag) {
        let localQueue = loadPersistedQueueMessages(necklaceID: necklace.id)
        let resolvedQueue = localQueue.isEmpty ? (necklace.queuedLumis.isEmpty ? necklace.nextLumi.map { [$0] } ?? [] : necklace.queuedLumis) : localQueue
        queueMessages = resolvedQueue
        currentMessage = resolvedQueue.first
        persistQueueMessages(resolvedQueue, necklaceID: necklace.id)
        ownedNecklaces = ownedNecklaces.map { item in
            guard item.id == necklace.id else { return item }
            var updated = item
            updated.availableLumiCount = resolvedQueue.count
            updated.nextLumi = resolvedQueue.first
            updated.queuedLumis = resolvedQueue
            return updated
        }
    }

    private func appendQueueMessage(_ message: Message) {
        guard let currentId = equippedNecklace?.id else { return }
        let updatedQueue = queueMessages + [message]
        queueMessages = updatedQueue
        currentMessage = updatedQueue.first
        persistQueueMessages(updatedQueue, necklaceID: currentId)
        ownedNecklaces = ownedNecklaces.map { necklace in
            guard necklace.id == currentId else { return necklace }
            var updated = necklace
            updated.availableLumiCount = updatedQueue.count
            updated.nextLumi = updatedQueue.first
            updated.queuedLumis = updatedQueue
            return updated
        }
    }

    private func updateQueueMessage(id: String, text: String) {
        guard let currentId = equippedNecklace?.id else { return }
        let updatedQueue = queueMessages.map { message -> Message in
            guard message.id == id else { return message }
            return Message(
                id: message.id,
                text: text,
                packageId: message.packageId,
                timestamp: message.timestamp,
                experience: message.experience
            )
        }
        queueMessages = updatedQueue
        currentMessage = updatedQueue.first
        persistQueueMessages(updatedQueue, necklaceID: currentId)
        ownedNecklaces = ownedNecklaces.map { necklace in
            guard necklace.id == currentId else { return necklace }
            var updated = necklace
            updated.availableLumiCount = updatedQueue.count
            updated.nextLumi = updatedQueue.first
            updated.queuedLumis = updatedQueue
            return updated
        }
    }

    func moveQueueMessages(from source: IndexSet, to destination: Int) {
        guard let currentId = equippedNecklace?.id else { return }
        var updatedQueue = queueMessages
        reorder(&updatedQueue, from: source, to: destination)
        queueMessages = updatedQueue
        currentMessage = updatedQueue.first
        persistQueueMessages(updatedQueue, necklaceID: currentId)
        ownedNecklaces = ownedNecklaces.map { necklace in
            guard necklace.id == currentId else { return necklace }
            var updated = necklace
            updated.availableLumiCount = updatedQueue.count
            updated.nextLumi = updatedQueue.first
            updated.queuedLumis = updatedQueue
            return updated
        }
    }

    func deleteQueueMessages(at offsets: IndexSet) {
        guard let currentId = equippedNecklace?.id else { return }
        let updatedQueue = queueMessages.enumerated().compactMap { index, message in
            offsets.contains(index) ? nil : message
        }
        queueMessages = updatedQueue
        currentMessage = updatedQueue.first
        persistQueueMessages(updatedQueue, necklaceID: currentId)
        ownedNecklaces = ownedNecklaces.map { necklace in
            guard necklace.id == currentId else { return necklace }
            var updated = necklace
            updated.availableLumiCount = updatedQueue.count
            updated.nextLumi = updatedQueue.first
            updated.queuedLumis = updatedQueue
            return updated
        }
    }

    private func persistQueueMessages(_ messages: [Message], necklaceID: String) {
        let key = queueCachePrefix + necklaceID
        do {
            let data = try JSONEncoder().encode(messages)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func loadPersistedQueueMessages(necklaceID: String) -> [Message] {
        let key = queueCachePrefix + necklaceID
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Message].self, from: data)) ?? []
    }

    private func resetComposerDraft() {
        composerDraftText = ""
        composerEditingMessageID = nil
        composerReturnRoute = .senderHome
    }

    private func reorder<T>(_ items: inout [T], from source: IndexSet, to destination: Int) {
        let movingItems = source.sorted().map { items[$0] }

        for index in source.sorted(by: >) {
            items.remove(at: index)
        }

        let itemsBeforeDestination = source.filter { $0 < destination }.count
        let insertionIndex = max(0, min(destination - itemsBeforeDestination, items.count))
        items.insert(contentsOf: movingItems, at: insertionIndex)
    }
}
