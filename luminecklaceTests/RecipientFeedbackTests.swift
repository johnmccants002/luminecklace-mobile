import Foundation
import XCTest
@testable import luminecklace

@MainActor
final class RecipientFeedbackTests: XCTestCase {
    override func tearDown() {
        FullAppFeedbackURLProtocol.handler = nil
        super.tearDown()
    }

    func testSenderMappingHandlesFeedbackVariantsWithoutDroppingLumiData() throws {
        let service = SenderService()
        let necklace = try XCTUnwrap(
            service.mapNecklace(
                from: [
                    "id": "necklace-1",
                    "name": "Lumi Necklace",
                    "recentlyRevealed": [
                        revealed(
                            id: "full",
                            feedback: [
                                "reaction": "touched",
                                "reactionAt": "2026-08-01T12:00:00.123Z",
                                "responseText": "Exactly what I needed.",
                                "respondedAt": "2026-08-01T12:01:00Z"
                            ]
                        ),
                        revealed(
                            id: "reaction-only",
                            feedback: ["reaction": "heart"]
                        ),
                        revealed(
                            id: "response-only",
                            feedback: [
                                "reaction": "future_reaction",
                                "reactionAt": "not-a-date",
                                "responseText": "Still keep these words",
                                "respondedAt": "2026-08-01T13:00:00Z"
                            ]
                        ),
                        revealed(id: "null", feedback: NSNull()),
                        revealed(id: "missing", feedback: nil)
                    ]
                ]
            )
        )

        XCTAssertEqual(necklace.recentlyRevealed.count, 5)
        let full = try XCTUnwrap(necklace.recentlyRevealed.first { $0.id == "full" })
        XCTAssertEqual(full.feedback?.reaction, .touched)
        XCTAssertEqual(full.feedback?.responseText, "Exactly what I needed.")
        XCTAssertNotNil(full.feedback?.reactionAt)
        XCTAssertNotNil(full.feedback?.respondedAt)
        XCTAssertEqual(full.experience.textPosition, .bottom)
        XCTAssertEqual(full.attachment?.provider, "instagram")
        XCTAssertEqual(full.attachment?.isSupportedInstagramLink, true)

        let responseOnly = try XCTUnwrap(necklace.recentlyRevealed.first { $0.id == "response-only" })
        XCTAssertNil(responseOnly.feedback?.reaction)
        XCTAssertNil(responseOnly.feedback?.reactionAt)
        XCTAssertEqual(responseOnly.feedback?.responseText, "Still keep these words")
        XCTAssertNotNil(responseOnly.feedback?.respondedAt)

        XCTAssertNil(necklace.recentlyRevealed.first { $0.id == "null" }?.feedback)
        XCTAssertNil(necklace.recentlyRevealed.first { $0.id == "missing" }?.feedback)
    }

    func testFullAppFeedbackNetworkingUsesExactContracts() async throws {
        let service = TapResolutionService(
            baseURL: URL(string: "https://example.test")!,
            session: makeSession()
        )
        FullAppFeedbackURLProtocol.handler = { request in
            let body = try Self.bodyData(from: request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(json["revealSessionId"], "session-1")

            if request.url?.path == "/api/tap/reaction" {
                XCTAssertEqual(json["reaction"], "sparkle")
                return Self.response(
                    request,
                    status: 200,
                    body: #"{"status":"reacted","feedback":{"reaction":"sparkle","reactionAt":"2026-08-01T12:00:00.123Z","responseText":null,"respondedAt":null}}"#
                )
            }

            XCTAssertEqual(request.url?.path, "/api/tap/response")
            XCTAssertEqual(json["text"], "Thank you")
            return Self.response(
                request,
                status: 200,
                body: #"{"status":"responded","feedback":{"reaction":"sparkle","reactionAt":"2026-08-01T12:00:00Z","responseText":"Thank you","respondedAt":"2026-08-01T12:01:00.456Z"}}"#
            )
        }

        let reaction = try await service.setReaction(revealSessionId: "session-1", reaction: .sparkle)
        XCTAssertEqual(reaction.reaction, .sparkle)
        let response = try await service.submitResponse(revealSessionId: "session-1", text: "Thank you")
        XCTAssertEqual(response.responseText, "Thank you")
        XCTAssertNotNil(response.respondedAt)
    }

    func testFullAppFeedbackStatePreservesConfirmedValuesAndDraft() async throws {
        let first = makeLumi(sessionID: "session-1")
        let second = makeLumi(sessionID: "session-2")
        let service = FullAppMockTapService(
            resolveResults: [.success(.ready(first)), .success(.ready(second))],
            reactionResults: [
                .success(LumiFeedback(reaction: .heart)),
                .failure(RecipientFeedbackServiceError.temporaryFailure),
                .success(LumiFeedback(reaction: .wow))
            ],
            responseResults: [
                .failure(RecipientFeedbackServiceError.temporaryFailure),
                .success(LumiFeedback(reaction: .wow, responseText: "Thank you"))
            ]
        )
        let appState = AppState(tapResolutionService: service)

        appState.handleIncomingHandoff(
            url: try XCTUnwrap(URL(string: "https://www.luminecklace.com/t/first"))
        )
        try await waitUntil {
            if case .waiting = appState.recipientRevealState { return true }
            return false
        }
        appState.beginAutomaticRecipientReveal(for: first)
        try await waitUntil { self.isConfirmed(appState.recipientRevealState, sessionID: "session-1") }

        appState.selectRecipientReaction(.heart)
        appState.selectRecipientReaction(.laugh)
        try await waitUntil { appState.recipientFeedbackState.selectedReaction == .heart }
        XCTAssertEqual(service.reactionRequests.map(\.reaction), [.heart])

        appState.selectRecipientReaction(.touched)
        try await waitUntil { appState.recipientFeedbackState.reactionErrorMessage != nil }
        XCTAssertEqual(appState.recipientFeedbackState.selectedReaction, .heart)

        appState.selectRecipientReaction(.wow)
        try await waitUntil { appState.recipientFeedbackState.selectedReaction == .wow }

        appState.updateRecipientResponseDraft("  Thank you  ")
        appState.submitRecipientResponse()
        try await waitUntil { appState.recipientFeedbackState.responseErrorMessage != nil }
        XCTAssertEqual(appState.recipientFeedbackState.draftResponse, "  Thank you  ")

        appState.submitRecipientResponse()
        try await waitUntil { appState.recipientFeedbackState.submittedResponse == "Thank you" }
        XCTAssertTrue(appState.recipientFeedbackState.isResponseLocked)

        appState.handleIncomingHandoff(
            url: try XCTUnwrap(URL(string: "https://www.luminecklace.com/t/second"))
        )
        try await waitUntil {
            if case let .waiting(lumi) = appState.recipientRevealState {
                return lumi.revealSessionId == "session-2"
            }
            return false
        }
        XCTAssertEqual(appState.recipientFeedbackState, .empty)
    }

    func testAlreadyRespondedPermanentlyLocksComposer() async throws {
        let lumi = makeLumi(sessionID: "session-lock")
        let service = FullAppMockTapService(
            resolveResults: [.success(.ready(lumi))],
            responseResults: [.failure(RecipientFeedbackServiceError.alreadyResponded)]
        )
        let appState = AppState(tapResolutionService: service)
        appState.handleIncomingHandoff(
            url: try XCTUnwrap(URL(string: "https://www.luminecklace.com/t/locked"))
        )
        try await waitUntil {
            if case .waiting = appState.recipientRevealState { return true }
            return false
        }
        appState.beginAutomaticRecipientReveal(for: lumi)
        try await waitUntil { self.isConfirmed(appState.recipientRevealState, sessionID: "session-lock") }

        appState.updateRecipientResponseDraft("Words remain")
        appState.setRecipientResponseComposerPresented(true)
        appState.submitRecipientResponse()
        try await waitUntil { appState.recipientFeedbackState.isResponseLocked }

        XCTAssertEqual(
            appState.recipientFeedbackState.responseErrorMessage,
            "A response has already been sent for this Lumi."
        )
        XCTAssertEqual(appState.recipientFeedbackState.draftResponse, "Words remain")
        XCTAssertFalse(appState.recipientFeedbackState.isResponseComposerPresented)
    }

    func testNewTokenCancelsPendingAutomaticReveal() async throws {
        let first = makeLumi(sessionID: "session-old")
        let second = makeLumi(sessionID: "session-new")
        let service = FullAppMockTapService(
            resolveResults: [.success(.ready(first)), .success(.ready(second))]
        )
        let appState = AppState(
            tapResolutionService: service,
            recipientRevealTransitionDelay: .milliseconds(40)
        )

        appState.handleIncomingHandoff(
            url: try XCTUnwrap(URL(string: "https://www.luminecklace.com/t/old"))
        )
        try await waitUntil {
            if case let .waiting(lumi) = appState.recipientRevealState {
                return lumi.revealSessionId == "session-old"
            }
            return false
        }
        appState.beginAutomaticRecipientReveal(for: first)

        appState.handleIncomingHandoff(
            url: try XCTUnwrap(URL(string: "https://www.luminecklace.com/t/new"))
        )
        try await waitUntil {
            if case let .waiting(lumi) = appState.recipientRevealState {
                return lumi.revealSessionId == "session-new"
            }
            return false
        }
        try await Task.sleep(for: .milliseconds(70))

        XCTAssertTrue(service.confirmRequests.isEmpty)
        guard case let .waiting(current) = appState.recipientRevealState else {
            return XCTFail("The new Lumi should remain ready to reveal.")
        }
        XCTAssertEqual(current.revealSessionId, "session-new")
    }

    private func revealed(id: String, feedback: Any?) -> [String: Any] {
        var result: [String: Any] = [
            "id": id,
            "text": "Original Lumi \(id)",
            "revealedAt": "2026-08-01T11:00:00Z",
            "attachment": [
                "type": "link",
                "provider": "instagram",
                "contentKind": "reel",
                "url": "https://www.instagram.com/reel/example/",
                "host": "instagram.com",
                "ctaLabel": "View on Instagram",
                "openMode": "external"
            ],
            "presentation": [
                "background": "midnight",
                "font": "rounded",
                "textSize": "large",
                "textAlignment": "leading",
                "textPosition": "bottom"
            ]
        ]
        if let feedback {
            result["feedback"] = feedback
        }
        return result
    }

    private func makeLumi(sessionID: String) -> ResolvedLumi {
        ResolvedLumi(
            revealSessionId: sessionID,
            necklaceDisplayName: "Lumi Necklace",
            lumiId: "lumi-\(sessionID)",
            text: "You matter.",
            presentation: NecklacePresentation(
                theme: .heart,
                animation: .breathe,
                sound: .soft
            )
        )
    }

    private func isConfirmed(_ state: RecipientRevealState, sessionID: String) -> Bool {
        if case let .revealed(lumi, .confirmed(_)) = state {
            return lumi.revealSessionId == sessionID
        }
        return false
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            if clock.now >= deadline { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FullAppFeedbackURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(
        _ request: URLRequest,
        status: Int,
        body: String
    ) -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
            Data(body.utf8)
        )
    }

    private static func bodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw try XCTUnwrap(stream.streamError) }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class FullAppMockTapService: RecipientTapServicing, @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var resolveResults: [Result<ResolveTapResponse, Error>]
    nonisolated(unsafe) private var reactionResults: [Result<LumiFeedback, Error>]
    nonisolated(unsafe) private var responseResults: [Result<LumiFeedback, Error>]
    nonisolated(unsafe) private var _reactionRequests: [(sessionID: String, reaction: LumiReaction)] = []
    nonisolated(unsafe) private var _confirmRequests: [String] = []

    init(
        resolveResults: [Result<ResolveTapResponse, Error>],
        reactionResults: [Result<LumiFeedback, Error>] = [],
        responseResults: [Result<LumiFeedback, Error>] = []
    ) {
        self.resolveResults = resolveResults
        self.reactionResults = reactionResults
        self.responseResults = responseResults
    }

    var reactionRequests: [(sessionID: String, reaction: LumiReaction)] {
        lock.withLock { _reactionRequests }
    }

    var confirmRequests: [String] {
        lock.withLock { _confirmRequests }
    }

    func resolveTap(token: String) async throws -> ResolveTapResponse {
        try lock.withLock {
            guard !resolveResults.isEmpty else {
                throw RecipientFeedbackServiceError.temporaryFailure
            }
            return try resolveResults.removeFirst().get()
        }
    }

    func confirmReveal(revealSessionId: String) async throws -> ConfirmRevealResponse {
        lock.withLock { _confirmRequests.append(revealSessionId) }
        return ConfirmRevealResponse(status: "revealed", revealedAt: Date(timeIntervalSince1970: 1))
    }

    func setReaction(revealSessionId: String, reaction: LumiReaction) async throws -> LumiFeedback {
        try lock.withLock {
            _reactionRequests.append((revealSessionId, reaction))
            guard !reactionResults.isEmpty else {
                throw RecipientFeedbackServiceError.temporaryFailure
            }
            return try reactionResults.removeFirst().get()
        }
    }

    func submitResponse(revealSessionId: String, text: String) async throws -> LumiFeedback {
        try lock.withLock {
            guard !responseResults.isEmpty else {
                throw RecipientFeedbackServiceError.temporaryFailure
            }
            return try responseResults.removeFirst().get()
        }
    }
}

private final class FullAppFeedbackURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
