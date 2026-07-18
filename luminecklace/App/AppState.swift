import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var route: RootRoute = .auth
    @Published var user: User?
    @Published var ownedNecklaces: [NecklaceTag] = []
    @Published var packages: [Package] = MockData.defaultPackages
    @Published var favorites: [Message] = []
    @Published var currentMessage: Message?
    @Published var showRetapHint = false
    @Published var settings = UserSettings()
    @Published var recipientRevealState: RecipientRevealState = .idle
    @Published var claimAssistanceSubmitted = false
    @Published var lastBootstrapError: String?

    let authService = AuthService()
    let senderService = SenderService()
    let messageService = MessageService()
    let tapResolutionService = TapResolutionService()
    let soundManager = SoundManager()
    let hapticsManager = HapticsManager()

    private var didAttemptSessionRestore = false
    private var didReceiveTapLink = false
    private let lastTagIdKey = "lumi_last_tag_id"

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

    private var preferredTagId: String? {
        equippedNecklace?.id ?? persistedTagId
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
        claimAssistanceSubmitted = false
        lastBootstrapError = nil

        do {
            _ = try await senderService.claimPendingOrdersForUser()
            let fetched = try await senderService.listSenderNecklacesWithCurrentMessage()
            ownedNecklaces = withSingleEquipped(from: fetched)

            guard !ownedNecklaces.isEmpty else {
                currentMessage = nil
                route = .noOrderAssist
                return
            }

            if let persistedTagId, ownedNecklaces.contains(where: { $0.id == persistedTagId }) {
                setEquipped(necklaceId: persistedTagId)
            } else if let primary = ownedNecklaces.first(where: \.isEquipped) {
                setEquipped(necklaceId: primary.id)
            } else if let first = ownedNecklaces.first {
                setEquipped(necklaceId: first.id)
            }

            if ownedNecklaces.count > 1 {
                route = .necklaceSelection
                return
            }

            await routeAfterNecklaceSelection()
        } catch APIError.unauthorized {
            authService.clearLocalSession()
            route = .auth
        } catch {
            lastBootstrapError = error.localizedDescription
            route = .noOrderAssist
        }
    }

    func routeAfterNecklaceSelection() async {
        guard let equipped = equippedNecklace else {
            route = .noOrderAssist
            return
        }

        if equipped.hasPublishedMessage {
            await fetchMessage()
            route = .senderHome
        } else {
            currentMessage = nil
            route = .firstMessageSetup
        }
    }

    func chooseNecklace(_ necklaceId: String) {
        setEquipped(necklaceId: necklaceId)
        Task { await routeAfterNecklaceSelection() }
    }

    func publishFirstMessage(text: String) async throws {
        guard let necklace = equippedNecklace else {
            throw APIError.missingRequiredField("equippedNecklace")
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.serverError(statusCode: 400, message: "Please write a message before publishing.")
        }

        let published = try await senderService.publishMessage(
            necklaceId: necklace.id,
            text: trimmed,
            themeKey: necklace.themeKey
        )
        currentMessage = published
        markCurrentNecklaceAsPublished()
        route = .senderHome
    }

    func submitClaimAssistance(orderEmail: String?) async {
        do {
            try await senderService.submitClaimAssistance(orderEmail: orderEmail)
            claimAssistanceSubmitted = true
            lastBootstrapError = nil
        } catch {
            claimAssistanceSubmitted = false
            lastBootstrapError = error.localizedDescription
        }
    }

    func signOut() {
        Task {
            try? await authService.signOut()
        }

        route = .auth
        user = nil
        currentMessage = nil
        ownedNecklaces = []
        persistedTagId = nil
        favorites = []
        packages = MockData.defaultPackages
        showRetapHint = false
        settings = UserSettings()
        claimAssistanceSubmitted = false
        lastBootstrapError = nil
        recipientRevealState = .idle
        didReceiveTapLink = false
    }

    func setEquipped(necklaceId: String) {
        ownedNecklaces = ownedNecklaces.map {
            var item = $0
            item.isEquipped = item.id == necklaceId
            return item
        }
        persistedTagId = necklaceId
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

    func saveFavorite(_ message: Message) {
        guard !favorites.contains(where: { $0.id == message.id }) else { return }
        favorites.insert(message, at: 0)
    }

    func removeFavorite(_ message: Message) {
        favorites.removeAll { $0.id == message.id }
    }

    func fetchMessage() async {
        guard let user else { return }
        do {
            let msg = try await messageService.getMessage(
                tagId: preferredTagId,
                fallbackThemeKey: equippedNecklace?.themeKey,
                enabledPackages: packages.filter(\.isEnabled),
                subscriptionTier: user.subscriptionTier
            )
            currentMessage = msg
            soundManager.play(soundKey: msg.experience.soundKey, enabled: settings.soundEnabled)
            hapticsManager.impact(enabled: settings.hapticsEnabled)
        } catch APIError.unauthorized {
            signOut()
        } catch {
            print("Message fetch failed: \(error.localizedDescription)")
        }
    }

    func handleIncomingHandoff(url: URL) {
        guard FeatureFlags.senderFirstFlowEnabled else { return }
        guard let tapToken = Self.extractTapToken(from: url) else { return }
        didReceiveTapLink = true
        route = .recipientReveal
        recipientRevealState = .resolving

        Task {
            do {
                let resolved = try await tapResolutionService.resolveTap(tapToken: tapToken)
                currentMessage = resolved.message
                recipientRevealState = resolved.state
            } catch {
                currentMessage = Message(
                    id: UUID().uuidString,
                    text: "Your Lumi is getting everything ready. Try tapping again in a moment.",
                    packageId: "love",
                    timestamp: Date(),
                    experience: Experience(
                        themeKey: "heart",
                        animationKey: "breathe",
                        soundKey: "soft"
                    )
                )
                recipientRevealState = .softError
            }
        }
    }

    func returnFromRecipientReveal() {
        if user == nil {
            route = .auth
            return
        }

        if ownedNecklaces.isEmpty {
            route = .noOrderAssist
        } else {
            route = .senderHome
        }
    }

    private static func extractTapToken(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let keys = ["tap_token", "tag_ref", "tagId", "token", "h"]
        for key in keys {
            if let value = components.queryItems?.first(where: { $0.name == key })?.value,
               !value.isEmpty {
                return value
            }
        }

        if url.scheme == "luminecklace" {
            let trimmedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !trimmedPath.isEmpty {
                return trimmedPath
            }
        }

        if components.path.hasPrefix("/tap/") || components.path.hasPrefix("/clip/") {
            let pathComponents = components.path
                .split(separator: "/")
                .map(String.init)
                .filter { !$0.isEmpty }
            if let last = pathComponents.last, !last.isEmpty {
                return last
            }
        }
        return nil
    }

    private func withSingleEquipped(from necklaces: [NecklaceTag]) -> [NecklaceTag] {
        if necklaces.contains(where: \.isEquipped) {
            return necklaces
        }
        return necklaces.enumerated().map { index, item in
            var updated = item
            updated.isEquipped = index == 0
            return updated
        }
    }

    private func markCurrentNecklaceAsPublished() {
        guard let currentId = equippedNecklace?.id else { return }
        ownedNecklaces = ownedNecklaces.map { necklace in
            guard necklace.id == currentId else { return necklace }
            var updated = necklace
            updated.hasPublishedMessage = true
            return updated
        }
    }
}
