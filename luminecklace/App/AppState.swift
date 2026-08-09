import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var route: RootRoute = .auth
    @Published var user: User?
    @Published var ownedNecklaces: [NecklaceTag] = []
    @Published var packages: [Package] = MockData.defaultPackages
    @Published private(set) var queueSnapshot: QueueSnapshot?
    @Published private(set) var queueSyncState: QueueSyncState = .idle
    @Published private(set) var queueActionError: String?
    @Published var composerDraftText = ""
    @Published var composerBackground: LumiBackgroundKey = .heart
    @Published var composerFont: LumiFontKey = .serif
    @Published var composerTextSize: LumiTextSizeKey = .medium
    @Published var composerTextAlignment: LumiTextAlignmentKey = .center
    @Published var composerTextPosition: LumiTextPositionKey = .center
    @Published var showRetapHint = false
    @Published var settings = UserSettings()
    @Published var recipientRevealState: RecipientRevealState = .awaitingInvocation
    @Published var recipientFeedbackState: RecipientFeedbackState = .empty
    @Published var lastBootstrapError: String?
    @Published private(set) var notificationHomeFocusId: UUID?

    let authService: AuthenticationServicing
    let senderService = SenderService()
    let tapResolutionService: RecipientTapServicing
    let pushNotificationManager: PushNotificationManager
    let soundManager = SoundManager()
    let hapticsManager = HapticsManager()

    private var didAttemptSessionRestore = false
    private var didReceiveTapLink = false
    private var currentRecipientToken: String?
    private var recipientResolutionTask: Task<Void, Never>?
    private var revealConfirmationTask: Task<Void, Never>?
    private var recipientReactionTask: Task<Void, Never>?
    private var recipientResponseTask: Task<Void, Never>?
    private var isRefreshingSenderData = false
    private var confirmationSessionIDs: Set<String> = []
    private var recipientFeedbackSessionID: String?
    private let lastTagIdKey = "lumi_last_tag_id"
    private let queueCachePrefix = "lumi_queue_cache_"
    private var composerEditingMessageID: String?
    private var composerEditingSection: QueueSection?
    private var composerReturnRoute: RootRoute = .senderHome
    private let notificationNavigationService: NotificationNavigationServicing

    init(
        tapResolutionService: RecipientTapServicing = TapResolutionService(),
        authService: AuthenticationServicing? = nil,
        pushNotificationManager: PushNotificationManager? = nil,
        notificationNavigationService: NotificationNavigationServicing? = nil
    ) {
        let resolvedPushManager = pushNotificationManager ?? PushNotificationManager()
        self.tapResolutionService = tapResolutionService
        self.authService = authService ?? AuthService()
        self.pushNotificationManager = resolvedPushManager
        self.notificationNavigationService = notificationNavigationService ?? SenderService()

        resolvedPushManager.foregroundEventHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshSenderDataAfterForegroundNotification()
            }
        }
        resolvedPushManager.shouldPresentForegroundNotification = { [weak self] in
            self?.route != .recipientReveal
        }
        resolvedPushManager.notificationResponseHandler = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.consumePendingNotificationDestinationIfPossible()
            }
        }
    }

    // No actor-isolated cleanup is required here. Keeping teardown nonisolated
    // also lets short-lived AppState instances be released safely in tests.
    nonisolated deinit {}

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

    var currentMessage: Message? {
        queueSnapshot?.current
    }

    var queueMessages: [Message] {
        queueSnapshot?.upNext ?? []
    }

    var reserveMessages: [Message] {
        queueSnapshot?.reserve ?? []
    }

    var isQueueMutating: Bool {
        queueSyncState == .mutating
    }

    var composerTitle: String {
        composerIsEditing ? "Edit Lumi" : "Add a Lumi"
    }

    var composerSubtitle: String {
        composerIsEditing
            ? "Update the message and its presentation."
            : "Choose whether this Lumi should appear soon or wait in Reserve."
    }

    var composerActionTitle: String {
        composerIsEditing ? "Update Lumi" : "Add Lumi"
    }

    var composerIsEditing: Bool {
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
            pushNotificationManager.updateAuthenticatedUser(id: user?.id)
            await bootstrapSenderFlowAfterAuth()
        } catch APIError.unauthorized {
            authService.clearLocalSession()
            pushNotificationManager.updateAuthenticatedUser(id: nil)
            route = .auth
        } catch {
            route = .auth
        }
    }

    func completeAuth(with result: AuthResult) {
        user = result.user
        pushNotificationManager.updateAuthenticatedUser(id: result.user.id)
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
                queueSnapshot = nil
                queueSyncState = .idle
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
            await consumePendingNotificationDestinationIfPossible()
            await pushNotificationManager.considerContextualPrompt(
                isRecipientExperienceActive: false
            )
        } catch APIError.unauthorized {
            authService.clearLocalSession()
            pushNotificationManager.updateAuthenticatedUser(id: nil)
            route = .auth
        } catch {
            lastBootstrapError = error.localizedDescription
            route = .senderLoadError
        }
    }

    func refreshSenderDataIfNeeded() async {
        guard user != nil, !isRefreshingSenderData else { return }
        guard case .senderHome = route else { return }

        isRefreshingSenderData = true
        defer { isRefreshingSenderData = false }

        do {
            let snapshots = try await senderService.listSenderNecklaces()
            let snapshotsByID = snapshots.reduce(into: [String: NecklaceTag]()) {
                $0[$1.id] = $1
            }

            ownedNecklaces = ownedNecklaces.map { necklace in
                guard let snapshot = snapshotsByID[necklace.id] else { return necklace }
                var updated = necklace
                updated.lifecycleStatus = snapshot.lifecycleStatus
                updated.recentlyRevealed = snapshot.recentlyRevealed
                updated.reserve = snapshot.reserve
                updated.queueSnapshot = snapshot.queueSnapshot
                updated.nextLumi = snapshot.queueSnapshot?.current
                updated.queuedLumis = snapshot.queueSnapshot?.upNext ?? []
                updated.availableLumiCount = snapshot.queueSnapshot?.continuousSequence.count ?? 0
                return updated
            }

            guard let equipped = equippedNecklace else { return }
            syncQueueState(from: equipped)
        } catch APIError.unauthorized {
            authService.clearLocalSession()
            user = nil
            pushNotificationManager.updateAuthenticatedUser(id: nil)
            route = .auth
        } catch {
            // Keep the last successful sender snapshot during transient refresh failures.
        }
    }

    func refreshQueueSnapshot() async {
        guard let equippedID = equippedNecklace?.id, !isQueueMutating else { return }
        queueSyncState = .loading
        do {
            let necklaces = try await senderService.listSenderNecklaces()
            guard equippedNecklace?.id == equippedID else { return }
            guard let refreshed = necklaces.first(where: { $0.id == equippedID }),
                  let snapshot = refreshed.queueSnapshot else {
                queueSyncState = queueSnapshot == nil
                    ? .failed("Queue details are unavailable right now.")
                    : .loaded
                return
            }
            installQueueSnapshot(snapshot)
        } catch {
            guard equippedNecklace?.id == equippedID else { return }
            queueSyncState = queueSnapshot == nil
                ? .failed("Queue details couldn’t be loaded. Please try again.")
                : .loaded
            if queueSnapshot == nil {
                queueActionError = "Queue details couldn’t be loaded. Please try again."
            }
        }
    }

    func routeAfterNecklaceSelection() {
        guard let equipped = equippedNecklace else {
            queueSnapshot = nil
            queueSyncState = .idle
            route = .noNecklace
            return
        }

        syncQueueState(from: equipped)
        route = .senderHome
    }

    func chooseNecklace(_ necklaceId: String) {
        setEquipped(necklaceId: necklaceId)
    }

    func openUpNextEditor() {
        guard equippedNecklace != nil else { return }
        route = .upNextEditor
    }

    func openReserveEditor() {
        guard equippedNecklace != nil else { return }
        route = .reserveEditor
    }

    func closeQueueEditor() {
        route = .senderHome
    }

    func openLumiComposer() {
        guard canAddLumiToEquippedNecklace else { return }
        resetComposerDraft()
        composerBackground = LumiBackgroundKey(
            rawValue: equippedNecklace?.themeKey.lowercased() ?? ""
        ) ?? .heart
        switch route {
        case .upNextEditor, .reserveEditor:
            composerReturnRoute = route
        default:
            composerReturnRoute = .senderHome
        }
        route = .lumiComposer
    }

    func openLumiComposer(editing message: Message, in section: QueueSection) {
        guard canAddLumiToEquippedNecklace else { return }
        let returnRoute = route
        resetComposerDraft()
        composerEditingMessageID = message.id
        composerEditingSection = section
        composerDraftText = message.text
        composerBackground = message.experience.backgroundKey
        composerFont = message.experience.fontKey
        composerTextSize = message.experience.textSize
        composerTextAlignment = message.experience.textAlignment
        composerTextPosition = message.experience.textPosition
        composerReturnRoute = returnRoute
        route = .lumiComposer
    }

    func cancelLumiComposer() {
        let returnRoute = composerReturnRoute
        resetComposerDraft()
        route = returnRoute
    }

    func addLumi(text: String, destination: QueueSection) async throws {
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

        let experience = composerExperience
        if let editingMessageID = composerEditingMessageID {
            let edited = try await senderService.editLumi(
                necklaceId: necklace.id,
                messageId: editingMessageID,
                text: trimmed,
                experience: experience
            )
            applyEditResult(
                edited,
                messageId: editingMessageID,
                section: composerEditingSection ?? destination,
                necklaceId: necklace.id
            )
        } else {
            let created = try await senderService.addLumi(
                necklaceId: necklace.id,
                text: trimmed,
                destination: destination,
                experience: experience
            )
            applyCreationResult(created, destination: destination, necklaceId: necklace.id)
        }

        let returnRoute = composerReturnRoute
        resetComposerDraft()
        route = returnRoute
    }

    func applyLibraryLumi(
        _ result: QueueCreationResult,
        destination: QueueSection,
        toNecklaceId necklaceId: String
    ) {
        guard equippedNecklace?.id == necklaceId else { return }
        applyCreationResult(result, destination: destination, necklaceId: necklaceId)
    }

    func signOut() async {
        await pushNotificationManager.disableCurrentDevice()
        do {
            try await authService.signOut()
        } catch {
            authService.clearLocalSession()
        }
        pushNotificationManager.clearAuthenticatedState()
        route = .auth
        user = nil
        queueSnapshot = nil
        queueSyncState = .idle
        queueActionError = nil
        resetComposerDraft()
        ownedNecklaces = []
        persistedTagId = nil
        packages = MockData.defaultPackages
        showRetapHint = false
        settings = UserSettings()
        lastBootstrapError = nil
        recipientRevealState = .awaitingInvocation
        resetRecipientFeedbackState(for: nil)
        didReceiveTapLink = false
        currentRecipientToken = nil
        confirmationSessionIDs = []
        recipientResolutionTask?.cancel()
        revealConfirmationTask?.cancel()
        recipientReactionTask?.cancel()
        recipientResponseTask?.cancel()
        recipientResolutionTask = nil
        revealConfirmationTask = nil
        recipientReactionTask = nil
        recipientResponseTask = nil
    }

    func handleApplicationDidBecomeActive() async {
        await pushNotificationManager.applicationDidBecomeActive()
        await consumePendingNotificationDestinationIfPossible()
        await refreshSenderDataIfNeeded()
    }

    func consumePendingNotificationDestinationIfPossible() async {
        guard pushNotificationManager.pendingDestination != nil else { return }
        guard user != nil, authService.hasAccessToken else {
            route = .auth
            return
        }

        let destination = pushNotificationManager.pendingDestination
        let refreshed: [NecklaceTag]?
        do {
            refreshed = try await notificationNavigationService.listSenderNecklaces()
        } catch APIError.unauthorized {
            authService.clearLocalSession()
            user = nil
            pushNotificationManager.updateAuthenticatedUser(id: nil)
            route = .auth
            return
        } catch {
            refreshed = nil
        }

        if let refreshed {
            ownedNecklaces = refreshed
        }

        if let necklaceId = destination?.necklaceId,
           ownedNecklaces.contains(where: { $0.id == necklaceId }) {
            setEquipped(necklaceId: necklaceId)
        } else if let currentId = equippedNecklace?.id,
                  ownedNecklaces.contains(where: { $0.id == currentId }) {
            setEquipped(necklaceId: currentId)
        } else if let first = ownedNecklaces.first {
            setEquipped(necklaceId: first.id)
        }

        routeAfterNecklaceSelection()
        pushNotificationManager.clearPendingDestination()
        notificationHomeFocusId = UUID()
        await pushNotificationManager.clearBadge()
    }

    private func refreshSenderDataAfterForegroundNotification() async {
        guard user != nil,
              route != .recipientReveal,
              !isRefreshingSenderData else { return }
        isRefreshingSenderData = true
        defer { isRefreshingSenderData = false }

        do {
            let selectedId = equippedNecklace?.id
            let snapshots = try await notificationNavigationService.listSenderNecklaces()
            ownedNecklaces = snapshots
            if let selectedId, snapshots.contains(where: { $0.id == selectedId }) {
                setEquipped(necklaceId: selectedId)
            } else if let first = snapshots.first {
                setEquipped(necklaceId: first.id)
            }
        } catch {
            // Preserve the last successful sender data and retry on the next lifecycle event.
        }
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
            queueSnapshot = nil
            queueSyncState = .idle
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

    var recipientFeedbackPresentationState: RecipientFeedbackPresentationState {
        recipientFeedbackState.presentationState(isEnabled: true)
    }

    func retryRecipientRevealConfirmation() {
        guard case let .revealed(lumi, confirmationState) = recipientRevealState,
              confirmationState == .temporarilyFailed else { return }
        confirmRevealIfNeeded(lumi)
    }

    func selectRecipientReaction(_ reaction: LumiReaction) {
        guard recipientReactionTask == nil,
              !recipientFeedbackState.isFeedbackWindowClosed,
              recipientFeedbackState.selectedReaction != reaction,
              let lumi = confirmedRecipientLumi else { return }

        recipientFeedbackState.attemptedReaction = reaction
        recipientFeedbackState.isSubmittingReaction = true
        recipientFeedbackState.reactionErrorMessage = nil

        recipientReactionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let feedback = try await tapResolutionService.setReaction(
                    revealSessionId: lumi.revealSessionId,
                    reaction: reaction
                )
                guard !Task.isCancelled,
                      recipientFeedbackSessionID == lumi.revealSessionId else { return }
                recipientFeedbackState.selectedReaction = feedback.reaction ?? reaction
                if let responseText = feedback.responseText,
                   !responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    recipientFeedbackState.submittedResponse = responseText
                    recipientFeedbackState.isResponseLocked = true
                }
                recipientFeedbackState.isSubmittingReaction = false
                recipientFeedbackState.reactionErrorMessage = nil
                recipientReactionTask = nil
            } catch {
                guard !Task.isCancelled,
                      recipientFeedbackSessionID == lumi.revealSessionId else { return }
                let feedbackError = error as? RecipientFeedbackServiceError ?? .temporaryFailure
                recipientFeedbackState.isSubmittingReaction = false
                recipientFeedbackState.reactionErrorMessage = feedbackError.reactionMessage
                if feedbackError == .expiredSession {
                    recipientFeedbackState.isFeedbackWindowClosed = true
                    recipientFeedbackState.isResponseLocked = true
                    recipientFeedbackState.responseErrorMessage = feedbackError.responseMessage
                }
                recipientReactionTask = nil
            }
        }
    }

    func retryRecipientReaction() {
        guard let attemptedReaction = recipientFeedbackState.attemptedReaction else { return }
        selectRecipientReaction(attemptedReaction)
    }

    func setRecipientResponseComposerPresented(_ isPresented: Bool) {
        guard !recipientFeedbackState.isSubmittingResponse else { return }
        if isPresented {
            guard confirmedRecipientLumi != nil,
                  !recipientFeedbackState.isResponseLocked,
                  !recipientFeedbackState.isFeedbackWindowClosed else { return }
        }
        recipientFeedbackState.isResponseComposerPresented = isPresented
    }

    func updateRecipientResponseDraft(_ draft: String) {
        guard !recipientFeedbackState.isResponseLocked else { return }
        recipientFeedbackState.draftResponse = String(draft.prefix(250))
        recipientFeedbackState.responseErrorMessage = nil
    }

    func submitRecipientResponse() {
        guard recipientResponseTask == nil,
              !recipientFeedbackState.isResponseLocked,
              !recipientFeedbackState.isFeedbackWindowClosed,
              let lumi = confirmedRecipientLumi else { return }

        let trimmed = recipientFeedbackState.draftResponse
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 250 else { return }

        recipientFeedbackState.isSubmittingResponse = true
        recipientFeedbackState.responseErrorMessage = nil

        recipientResponseTask = Task { [weak self] in
            guard let self else { return }
            do {
                let feedback = try await tapResolutionService.submitResponse(
                    revealSessionId: lumi.revealSessionId,
                    text: trimmed
                )
                guard !Task.isCancelled,
                      recipientFeedbackSessionID == lumi.revealSessionId else { return }
                recipientFeedbackState.selectedReaction = feedback.reaction
                    ?? recipientFeedbackState.selectedReaction
                recipientFeedbackState.submittedResponse = feedback.responseText ?? trimmed
                recipientFeedbackState.draftResponse = feedback.responseText ?? trimmed
                recipientFeedbackState.isSubmittingResponse = false
                recipientFeedbackState.isResponseLocked = true
                recipientFeedbackState.isResponseComposerPresented = false
                recipientFeedbackState.responseErrorMessage = nil
                recipientResponseTask = nil
            } catch {
                guard !Task.isCancelled,
                      recipientFeedbackSessionID == lumi.revealSessionId else { return }
                let feedbackError = error as? RecipientFeedbackServiceError ?? .temporaryFailure
                recipientFeedbackState.isSubmittingResponse = false
                recipientFeedbackState.responseErrorMessage = feedbackError.responseMessage
                if feedbackError == .alreadyResponded || feedbackError == .expiredSession {
                    recipientFeedbackState.isResponseLocked = true
                    recipientFeedbackState.isResponseComposerPresented = false
                }
                if feedbackError == .expiredSession {
                    recipientFeedbackState.isFeedbackWindowClosed = true
                }
                recipientResponseTask = nil
            }
        }
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
            resetRecipientFeedbackState(for: nil)
        }

        currentRecipientToken = token
        recipientRevealState = .resolving

        recipientResolutionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let resolved = try await tapResolutionService.resolveTap(token: token)
                guard !Task.isCancelled else { return }

                switch resolved {
                case let .ready(lumi):
                    resetRecipientFeedbackState(for: lumi.revealSessionId)
                    recipientRevealState = .waiting(lumi)
                case .empty:
                    resetRecipientFeedbackState(for: nil)
                    recipientRevealState = .empty
                case .unavailable:
                    resetRecipientFeedbackState(for: nil)
                    recipientRevealState = .unavailable
                }
            } catch APIError.invalidPayload {
                guard !Task.isCancelled else { return }
                recipientRevealState = .error(.invalidPayload)
            } catch {
                guard !Task.isCancelled else { return }
                resetRecipientFeedbackState(for: nil)
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
                await reloadQueueAfterConfirmedReveal()
            } catch {
                guard !Task.isCancelled else { return }
                confirmationSessionIDs.remove(lumi.revealSessionId)
                recipientRevealState = .revealed(lumi, confirmationState: .temporarilyFailed)
            }
        }
    }

    private var confirmedRecipientLumi: ResolvedLumi? {
        guard case let .revealed(lumi, confirmationState) = recipientRevealState,
              case .confirmed = confirmationState else {
            return nil
        }
        return lumi
    }

    private func resetRecipientFeedbackState(for revealSessionID: String?) {
        guard recipientFeedbackSessionID != revealSessionID else { return }
        recipientReactionTask?.cancel()
        recipientResponseTask?.cancel()
        recipientReactionTask = nil
        recipientResponseTask = nil
        recipientFeedbackSessionID = revealSessionID
        recipientFeedbackState = .empty
    }

    private func confirmRevealWithSingleRetry(revealSessionId: String) async throws -> ConfirmRevealResponse {
        do {
            return try await tapResolutionService.confirmReveal(revealSessionId: revealSessionId)
        } catch {
            try await Task.sleep(nanoseconds: 900_000_000)
            return try await tapResolutionService.confirmReveal(revealSessionId: revealSessionId)
        }
    }

    private func reloadQueueAfterConfirmedReveal() async {
        guard let equippedID = equippedNecklace?.id else { return }
        do {
            let snapshots = try await senderService.listSenderNecklaces()
            guard let refreshed = snapshots.first(where: { $0.id == equippedID }),
                  let snapshot = refreshed.queueSnapshot else { return }
            installQueueSnapshot(snapshot)
            ownedNecklaces = ownedNecklaces.map { existing in
                guard existing.id == equippedID else { return existing }
                var updated = refreshed
                updated.isEquipped = true
                return updated
            }
        } catch {
            // The confirmed reveal remains authoritative. Home refresh will retry.
        }
    }

    private func syncQueueState(from necklace: NecklaceTag) {
        let cached = loadPersistedQueueMessages(necklaceID: necklace.id)
        let fallbackSnapshot = cached.isEmpty ? nil : try? QueueSnapshot(
            necklaceId: necklace.id,
            revision: 0,
            current: cached.first,
            upNext: Array(cached.dropFirst()),
            reserve: []
        )
        queueSnapshot = necklace.queueSnapshot ?? fallbackSnapshot
        queueSyncState = queueSnapshot == nil
            ? .failed("Queue details are unavailable right now.")
            : .loaded
        queueActionError = nil
    }

    private func applyCreationResult(
        _ result: QueueCreationResult,
        destination: QueueSection,
        necklaceId: String
    ) {
        guard equippedNecklace?.id == necklaceId else { return }

        if let snapshot = result.snapshot {
            installQueueSnapshot(snapshot)
            return
        }

        // Compatibility for the legacy create response. The backend has accepted
        // the write, but cannot yet return a revisioned snapshot.
        guard let existing = queueSnapshot
                ?? (try? QueueSnapshot(
                    necklaceId: necklaceId,
                    revision: 0,
                    current: nil,
                    upNext: [],
                    reserve: []
                )) else { return }
        let upNext = destination == .upNext
            ? existing.upNext + [result.message]
            : existing.upNext
        let reserve = destination == .reserve
            ? existing.reserve + [result.message]
            : existing.reserve
        guard let updated = try? QueueSnapshot(
            necklaceId: necklaceId,
            revision: existing.revision,
            current: existing.current,
            upNext: upNext,
            reserve: reserve
        ) else { return }
        installQueueSnapshot(updated)
    }

    private func applyEditResult(
        _ result: QueueCreationResult,
        messageId: String,
        section: QueueSection,
        necklaceId: String
    ) {
        guard equippedNecklace?.id == necklaceId else { return }
        if let snapshot = result.snapshot {
            installQueueSnapshot(snapshot)
            return
        }

        guard let existing = queueSnapshot else { return }
        let replace: (Message) -> Message = { message in
            message.id == messageId ? result.message : message
        }
        guard let updated = try? QueueSnapshot(
            necklaceId: existing.necklaceId,
            revision: existing.revision,
            current: existing.current.map(replace),
            upNext: existing.upNext.map(replace),
            reserve: existing.reserve.map(replace)
        ) else { return }
        installQueueSnapshot(updated)
    }

    func reorderMessages(in section: QueueSection, from source: IndexSet, to destination: Int) {
        guard !isQueueMutating, let existing = queueSnapshot else { return }
        var messages = section == .upNext ? existing.upNext : existing.reserve
        reorder(&messages, from: source, to: destination)
        guard let proposed = snapshot(existing, replacing: section, with: messages) else { return }
        Task {
            await persistQueueMutation(
                proposed: proposed,
                operation: .reorder(
                    section: section,
                    orderedMessageIDs: messages.map(\.id)
                )
            )
        }
    }

    func makeUpNext(_ messageID: String) {
        moveMessage(messageID, to: .upNext, placement: .first)
    }

    func moveToReserve(_ messageID: String) {
        moveMessage(messageID, to: .reserve, placement: .last)
    }

    func moveToUpNext(_ messageID: String) {
        moveMessage(messageID, to: .upNext, placement: .last)
    }

    func addAsImmediateNext(_ messageID: String) {
        moveMessage(messageID, to: .upNext, placement: .first)
    }

    func removeQueuedMessage(_ messageID: String) {
        guard !isQueueMutating,
              let existing = queueSnapshot,
              existing.current?.id != messageID else { return }
        let proposedUpNext = existing.upNext.filter { $0.id != messageID }
        let proposedReserve = existing.reserve.filter { $0.id != messageID }
        guard proposedUpNext.count != existing.upNext.count
                || proposedReserve.count != existing.reserve.count,
              let proposed = try? QueueSnapshot(
                necklaceId: existing.necklaceId,
                revision: existing.revision,
                current: existing.current,
                upNext: proposedUpNext,
                reserve: proposedReserve
              ) else { return }
        Task {
            await persistQueueMutation(
                proposed: proposed,
                operation: .remove(messageID: messageID)
            )
        }
    }

    func clearQueueActionError() {
        queueActionError = nil
        if case .failed = queueSyncState {
            queueSyncState = queueSnapshot == nil ? .idle : .loaded
        }
    }

    private func moveMessage(
        _ messageID: String,
        to destination: QueueSection,
        placement: QueuePlacement
    ) {
        guard !isQueueMutating, let existing = queueSnapshot else { return }
        guard let message = (existing.upNext + existing.reserve).first(where: { $0.id == messageID }) else {
            return
        }

        var upNext = existing.upNext.filter { $0.id != messageID }
        var reserve = existing.reserve.filter { $0.id != messageID }
        if destination == .upNext {
            if placement == .first {
                upNext.insert(message, at: 0)
            } else {
                upNext.append(message)
            }
        } else {
            if placement == .first {
                reserve.insert(message, at: 0)
            } else {
                reserve.append(message)
            }
        }

        guard let proposed = try? QueueSnapshot(
            necklaceId: existing.necklaceId,
            revision: existing.revision,
            current: existing.current,
            upNext: upNext,
            reserve: reserve
        ) else { return }
        Task {
            await persistQueueMutation(
                proposed: proposed,
                operation: .move(
                    messageID: messageID,
                    destination: destination,
                    placement: placement
                )
            )
        }
    }

    private func persistQueueMutation(
        proposed: QueueSnapshot,
        operation: QueueMutation
    ) async {
        guard !isQueueMutating,
              let confirmed = queueSnapshot,
              confirmed.necklaceId == proposed.necklaceId else { return }

        queueActionError = nil
        queueSnapshot = proposed
        queueSyncState = .mutating

        do {
            let serverSnapshot = try await senderService.mutateQueue(
                necklaceId: confirmed.necklaceId,
                expectedRevision: confirmed.revision,
                operation: operation
            )
            guard equippedNecklace?.id == serverSnapshot.necklaceId else { return }
            installQueueSnapshot(serverSnapshot)
        } catch let SenderQueueError.conflict(latest) {
            guard equippedNecklace?.id == confirmed.necklaceId else { return }
            if let latest {
                installQueueSnapshot(latest)
            } else {
                queueSnapshot = confirmed
                queueSyncState = .loaded
            }
            queueActionError = "This queue changed somewhere else. The latest order has been loaded."
        } catch {
            guard equippedNecklace?.id == confirmed.necklaceId else { return }
            queueSnapshot = confirmed
            queueSyncState = .loaded
            queueActionError = "That change couldn’t be saved. Your previous order was restored."
        }
    }

    private func snapshot(
        _ existing: QueueSnapshot,
        replacing section: QueueSection,
        with messages: [Message]
    ) -> QueueSnapshot? {
        try? QueueSnapshot(
            necklaceId: existing.necklaceId,
            revision: existing.revision,
            current: existing.current,
            upNext: section == .upNext ? messages : existing.upNext,
            reserve: section == .reserve ? messages : existing.reserve
        )
    }

    private func installQueueSnapshot(_ snapshot: QueueSnapshot) {
        queueSnapshot = snapshot
        queueSyncState = .loaded
        persistQueueMessages(snapshot.continuousSequence, necklaceID: snapshot.necklaceId)
        ownedNecklaces = ownedNecklaces.map { necklace in
            guard necklace.id == snapshot.necklaceId else { return necklace }
            var updated = necklace
            updated.queueSnapshot = snapshot
            updated.nextLumi = snapshot.current
            updated.queuedLumis = snapshot.upNext
            updated.availableLumiCount = snapshot.continuousSequence.count
            return updated
        }
    }

    private func resetComposerDraft() {
        composerDraftText = ""
        composerBackground = .heart
        composerFont = .serif
        composerTextSize = .medium
        composerTextAlignment = .center
        composerTextPosition = .center
        composerEditingMessageID = nil
        composerEditingSection = nil
        composerReturnRoute = .senderHome
    }

    private var composerExperience: Experience {
        Experience(
            themeKey: composerBackground.rawValue,
            animationKey: "breathe",
            soundKey: "soft",
            backgroundKey: composerBackground,
            fontKey: composerFont,
            textSize: composerTextSize,
            textAlignment: composerTextAlignment,
            textPosition: composerTextPosition
        )
    }

    private func persistQueueMessages(_ messages: [Message], necklaceID: String) {
        let key = queueCachePrefix + necklaceID
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(messages), forKey: key)
        } catch {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func loadPersistedQueueMessages(necklaceID: String) -> [Message] {
        let key = queueCachePrefix + necklaceID
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Message].self, from: data)) ?? []
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
