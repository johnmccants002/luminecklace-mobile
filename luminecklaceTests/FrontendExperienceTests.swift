import XCTest
@testable import luminecklace

@MainActor
final class FrontendExperienceTests: XCTestCase {
    func testSavedInspirationSurvivesReloadAndIsIsolatedByAccount() throws {
        let suite = "frontend-test-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let state = makeState(userID: "one")
        let first = ExploreViewModel(appState: state, bookmarkDefaults: defaults)
        first.toggleSaved(template)
        let reopened = ExploreViewModel(appState: state, bookmarkDefaults: defaults)
        XCTAssertEqual(reopened.savedMessages, [template])
        XCTAssertTrue(ExploreViewModel(appState: makeState(userID: "two"), bookmarkDefaults: defaults).savedMessages.isEmpty)
        reopened.toggleSaved(template)
        XCTAssertTrue(ExploreViewModel(appState: state, bookmarkDefaults: defaults).savedMessages.isEmpty)
    }

    func testCorruptSavedInspirationDoesNotPreventOpeningExplore() throws {
        let suite = "frontend-test-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("not-json".utf8), forKey: "lumi.saved-inspiration.one")
        XCTAssertTrue(ExploreViewModel(appState: makeState(userID: "one"), bookmarkDefaults: defaults).savedMessages.isEmpty)
    }

    func testComposerUsesTheSectionItWasOpenedFromAndReturnsThere() {
        let state = makeState()
        state.route = .reserveEditor
        state.openLumiComposer()
        XCTAssertEqual(state.composerDestination, .reserve)
        XCTAssertEqual(state.route, .lumiComposer)
        state.cancelLumiComposer()
        XCTAssertEqual(state.route, .reserveEditor)
        state.route = .senderHome
        state.openLumiComposer()
        XCTAssertEqual(state.composerDestination, .upNext)
    }

    func testResetPasswordValidatesBeforeCallingService() async {
        let auth = FrontendAuthStub()
        let model = AuthViewModel(appState: AppState(authService: auth))
        model.email = "invalid"
        await model.resetPassword()
        XCTAssertTrue(auth.resetEmails.isEmpty)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(model.resetConfirmation)
    }

    func testResetPasswordNormalizesEmailAndShowsAccountSafeConfirmation() async {
        let auth = FrontendAuthStub()
        let model = AuthViewModel(appState: AppState(authService: auth))
        model.email = "  Sender@Example.com  "
        await model.resetPassword()
        XCTAssertEqual(auth.resetEmails, ["sender@example.com"])
        XCTAssertNil(model.errorMessage)
        XCTAssertNotNil(model.resetConfirmation)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.isResettingPassword)
    }

    func testResetPasswordFailureAllowsRetryWithoutLosingEmail() async {
        let auth = FrontendAuthStub()
        auth.shouldFail = true
        let model = AuthViewModel(appState: AppState(authService: auth))
        model.email = "sender@example.com"
        await model.resetPassword()
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(model.resetConfirmation)
        XCTAssertFalse(model.isLoading)
        auth.shouldFail = false
        await model.resetPassword()
        XCTAssertEqual(auth.resetEmails.count, 2)
        XCTAssertEqual(model.email, "sender@example.com")
        XCTAssertNil(model.errorMessage)
        XCTAssertNotNil(model.resetConfirmation)
    }

    func testPasswordResetRejectsConcurrentSubmission() async {
        let auth = FrontendAuthStub()
        auth.delay = .milliseconds(80)
        let model = AuthViewModel(appState: AppState(authService: auth))
        model.email = "sender@example.com"
        async let first: Void = model.resetPassword()
        try? await Task.sleep(for: .milliseconds(10))
        await model.resetPassword()
        await first
        XCTAssertEqual(auth.resetEmails.count, 1)
    }

    func testPaginationFailureKeepsMessagesAndCanRetry() async {
        let service = FrontendLibraryStub()
        service.responses = [
            .success(MessageLibraryResponse(categories: [], messages: [template], nextCursor: "next")),
            .failure(URLError(.notConnectedToInternet)),
            .success(MessageLibraryResponse(categories: [], messages: [], nextCursor: nil))
        ]
        let model = ExploreViewModel(appState: makeState(), service: service)
        await model.reload()
        await model.loadMoreIfNeeded(after: template)
        XCTAssertEqual(model.messages, [template])
        XCTAssertEqual(model.state, .loaded)
        XCTAssertNotNil(model.paginationError)
        XCTAssertTrue(model.hasMore)
        await model.loadMoreIfNeeded(after: template)
        XCTAssertNil(model.paginationError)
        XCTAssertFalse(model.hasMore)
        XCTAssertEqual(model.messages, [template])
    }

    private var template: MessageTemplate {
        MessageTemplate(id: "inspiration", title: "A little encouragement", text: "I believe in you.", category: MessageTemplateCategory(key: "encouragement", name: "Encouragement"), presentation: LibraryMessagePresentation(theme: "heart", animation: "breathe", sound: "soft"))
    }

    private func makeState(userID: String = "sender") -> AppState {
        let state = AppState(authService: FrontendAuthStub())
        state.user = User(id: userID, email: "sender@example.com", displayName: "Alex", subscriptionTier: .free)
        state.ownedNecklaces = [NecklaceTag(id: "necklace", name: "Heart necklace", sku: "HEART", themeKey: "heart", isEquipped: true, rarity: nil, includedPackage: "Love", lifecycleStatus: "active")]
        return state
    }
}

@MainActor
private final class FrontendAuthStub: AuthenticationServicing {
    // Avoid the simulator runtime’s isolated-deinit crash for this test double.
    nonisolated deinit {}
    var hasAccessToken = false
    var resetEmails: [String] = []
    var shouldFail = false
    var delay: Duration = .zero
    func signIn(email: String, password: String) async throws -> AuthResult { throw URLError(.notConnectedToInternet) }
    func resetPassword(email: String) async throws {
        resetEmails.append(email)
        try await Task.sleep(for: delay)
        if shouldFail { throw URLError(.notConnectedToInternet) }
    }
    func me() async throws -> User { throw URLError(.notConnectedToInternet) }
    func signOut() async throws { }
    func clearLocalSession() { }
}

private final class FrontendLibraryStub: MessageLibraryServing {
    nonisolated deinit {}
    var responses: [Result<MessageLibraryResponse, Error>] = []
    func library(query: MessageLibraryQuery) async throws -> MessageLibraryResponse {
        try responses.removeFirst().get()
    }
    func addMessage(necklaceId: String, request: AddLibraryMessageRequest) async throws -> QueueCreationResult {
        throw URLError(.notConnectedToInternet)
    }
}
