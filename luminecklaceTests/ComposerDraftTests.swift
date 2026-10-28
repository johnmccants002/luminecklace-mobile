import XCTest
import Security
@testable import luminecklace

@MainActor
final class ComposerDraftTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var store: LumiComposerDraftStore!

    override func setUp() {
        super.setUp()
        suite = "composer-drafts.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
        store = LumiComposerDraftStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        DraftURLProtocol.shouldFail = false
        store = nil
        defaults = nil
        super.tearDown()
    }

    func testDraftSurvivesNewAppStateWithPresentationAndDestination() {
        let first = state()
        first.openLumiComposer()
        first.composerDraftText = "Remember this moment"
        first.composerBackground = .midnight
        first.composerFont = .rounded
        first.composerTextSize = .large
        first.composerTextAlignment = .leading
        first.composerTextPosition = .bottom
        first.composerDestination = .reserve
        // A new state represents relaunch without an orderly composer dismissal.
        let reopened = state()
        reopened.openLumiComposer()
        XCTAssertTrue(reopened.composerRestoredDraft)
        XCTAssertEqual(reopened.composerDraftText, "Remember this moment")
        XCTAssertEqual(reopened.composerBackground, .midnight)
        XCTAssertEqual(reopened.composerFont, .rounded)
        XCTAssertEqual(reopened.composerTextSize, .large)
        XCTAssertEqual(reopened.composerTextAlignment, .leading)
        XCTAssertEqual(reopened.composerTextPosition, .bottom)
        XCTAssertEqual(reopened.composerDestination, .reserve)
    }

    func testDraftIsIsolatedByAccountAndNecklace() {
        let first = state()
        first.openLumiComposer()
        first.composerDraftText = "Private draft"
        for other in [state(user: "other"), state(necklace: "other")] {
            other.openLumiComposer()
            XCTAssertEqual(other.composerDraftText, "")
            XCTAssertFalse(other.composerRestoredDraft)
        }
        XCTAssertEqual(store.load(for: context)?.text, "Private draft")
    }

    func testSaveAndCloseKeepsDraftButExplicitDiscardRemovesIt() {
        let app = state()
        app.openLumiComposer()
        app.composerDraftText = "Finish later"
        app.cancelLumiComposer(discardDraft: false)
        XCTAssertEqual(app.route, .senderHome)
        app.openLumiComposer()
        XCTAssertEqual(app.composerDraftText, "Finish later")
        app.cancelLumiComposer()
        app.openLumiComposer()
        XCTAssertEqual(app.composerDraftText, "")
        XCTAssertNil(store.load(for: context))
    }

    func testEditingQueuedLumiDoesNotOverwriteOrDeleteOriginalDraft() {
        let app = state()
        app.openLumiComposer()
        app.composerDraftText = "Unfinished original"
        app.cancelLumiComposer(discardDraft: false)
        let message = Message(id: "queued", text: "Already queued", packageId: "personal", timestamp: Date(), experience: Experience(themeKey: "heart", animationKey: "breathe", soundKey: "soft"))
        app.route = .upNextEditor
        app.openLumiComposer(editing: message, in: .upNext)
        app.composerDraftText = "Changed queued message"
        app.cancelLumiComposer()
        XCTAssertEqual(store.load(for: context)?.text, "Unfinished original")
    }

    func testFailedSaveKeepsDraftAndSuccessfulRetryRemovesIt() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DraftURLProtocol.self]
        let tokenStore = TokenStore(sharedStore: SharedAuthTokenStore(keychain: DraftKeychain(), accessGroup: "draft.test"), defaults: defaults)
        let service = SenderService(client: APIClient(baseURL: URL(string: "https://draft.example.test")!, session: URLSession(configuration: config), tokenStore: tokenStore))
        let app = state(sender: service)
        app.openLumiComposer()
        app.composerDraftText = "Keep until confirmed"
        DraftURLProtocol.shouldFail = true
        do {
            try await app.addLumi(text: app.composerDraftText, destination: .upNext)
            XCTFail("Expected a network failure")
        } catch { }
        XCTAssertEqual(store.load(for: context)?.text, "Keep until confirmed")
        XCTAssertEqual(app.route, .lumiComposer)
        DraftURLProtocol.shouldFail = false
        try await app.addLumi(text: app.composerDraftText, destination: .upNext)
        XCTAssertNil(store.load(for: context))
        XCTAssertEqual(app.route, .senderHome)
        XCTAssertEqual(app.composerNotice, "Added to Up Next.")
    }

    func testEmptyDraftAndCorruptStorageDoNotRestore() {
        defaults.set(Data("broken".utf8), forKey: context.storageKey)
        let app = state()
        app.openLumiComposer()
        XCTAssertFalse(app.composerRestoredDraft)
        app.composerDraftText = "A message"
        app.composerDraftText = "  \n "
        XCTAssertNil(store.load(for: context))
    }

    func testLeavingRevealReturnsToTheAppropriateAccountRoute() {
        let app = state()
        app.route = .recipientReveal
        app.returnFromRecipientReveal()
        XCTAssertEqual(app.route, .senderHome)
        XCTAssertEqual(app.recipientRevealState, .awaitingInvocation)
        app.ownedNecklaces = []
        app.returnFromRecipientReveal()
        XCTAssertEqual(app.route, .noNecklace)
        app.user = nil
        app.returnFromRecipientReveal()
        XCTAssertEqual(app.route, .auth)
    }

    private var context: LumiComposerDraftContext { .init(userID: "sender", necklaceID: "necklace") }

    private func state(user: String = "sender", necklace: String = "necklace", sender: SenderService? = nil) -> AppState {
        let app = AppState(authService: DraftAuthStub(), senderService: sender, composerDraftStore: store)
        app.user = User(id: user, email: "sender@example.test", displayName: "Alex", subscriptionTier: .free)
        app.ownedNecklaces = [NecklaceTag(id: necklace, name: "Heart necklace", sku: "HEART", themeKey: "heart", isEquipped: true, rarity: nil, includedPackage: "Love")]
        app.route = .senderHome
        return app
    }
}

private struct DraftAuthStub: AuthenticationServicing {
    var hasAccessToken: Bool { false }
    func signIn(email: String, password: String) async throws -> AuthResult { throw URLError(.notConnectedToInternet) }
    func resetPassword(email: String) async throws { }
    func me() async throws -> User { throw URLError(.notConnectedToInternet) }
    func signOut() async throws { }
    func clearLocalSession() { }
}

private final class DraftURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var shouldFail = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if Self.shouldFail {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"lumi":{"id":"saved","text":"Keep until confirmed"}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

private final class DraftKeychain: KeychainOperating, @unchecked Sendable {
    func copyMatching(_ query: CFDictionary) -> (status: OSStatus, data: Data?) { (errSecSuccess, Data("test-token".utf8)) }
    func add(_ attributes: CFDictionary) -> OSStatus { errSecSuccess }
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus { errSecSuccess }
    func delete(_ query: CFDictionary) -> OSStatus { errSecSuccess }
}
