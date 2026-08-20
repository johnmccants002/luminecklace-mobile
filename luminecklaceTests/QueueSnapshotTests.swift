import XCTest
@testable import luminecklace

@MainActor
final class QueueSnapshotTests: XCTestCase {
    private let service = SenderService()

    override func tearDown() {
        QueuePayloadURLProtocol.responseBody = nil
        super.tearDown()
    }

    func testContinuousSequenceKeepsCurrentUpNextAndReserveOrder() throws {
        let snapshot = try QueueSnapshot(
            necklaceId: "necklace",
            revision: 7,
            current: message("current"),
            upNext: [message("up-1"), message("up-2")],
            reserve: [message("reserve-1"), message("reserve-2")]
        )

        XCTAssertEqual(
            snapshot.continuousSequence.map(\.id),
            ["current", "up-1", "up-2", "reserve-1", "reserve-2"]
        )
    }

    func testHomeQueuePresentationDistinguishesValidEmptyFromUnavailable() throws {
        let emptySnapshot = try QueueSnapshot(
            necklaceId: "necklace",
            revision: 1,
            current: nil,
            upNext: [],
            reserve: []
        )

        XCTAssertEqual(
            HomeQueuePresentation(syncState: .loaded, snapshot: emptySnapshot),
            .loaded(.empty)
        )
        XCTAssertEqual(
            HomeQueuePresentation(
                syncState: .failed("Queue details are unavailable."),
                snapshot: nil
            ),
            .unavailable("Queue details are unavailable.")
        )
        XCTAssertEqual(
            HomeQueuePresentation(syncState: .loading, snapshot: nil),
            .loading
        )
    }

    func testSnapshotRejectsMessageInMultipleSections() {
        XCTAssertThrowsError(
            try QueueSnapshot(
                necklaceId: "necklace",
                revision: 1,
                current: message("same"),
                upNext: [message("same")],
                reserve: []
            )
        )
    }

    func testServiceDecodesSnapshotWithoutSortingServerArrays() throws {
        let payload: [String: Any] = [
            "queue": [
                "revision": 9,
                "current": lumi("current"),
                "upNext": [lumi("up-2"), lumi("up-1")],
                "reserve": [lumi("reserve-2"), lumi("reserve-1")]
            ]
        ]

        let snapshot = try XCTUnwrap(
            service.mapQueueSnapshot(
                from: payload,
                necklaceId: "necklace",
                fallbackThemeKey: "heart"
            )
        )

        XCTAssertEqual(snapshot.current?.id, "current")
        XCTAssertEqual(snapshot.upNext.map(\.id), ["up-2", "up-1"])
        XCTAssertEqual(snapshot.reserve.map(\.id), ["reserve-2", "reserve-1"])
    }

    func testServiceRejectsDuplicateSnapshotMembership() {
        let payload: [String: Any] = [
            "queue": [
                "revision": 2,
                "current": lumi("current"),
                "upNext": [lumi("duplicate")],
                "reserve": [lumi("duplicate")]
            ]
        ]

        XCTAssertNil(
            service.mapQueueSnapshot(
                from: payload,
                necklaceId: "necklace",
                fallbackThemeKey: "heart"
            )
        )
    }

    func testMutationPayloadsDescribeExactQueueActions() {
        XCTAssertEqual(
            QueueMutation.reorder(
                section: .reserve,
                orderedMessageIDs: ["two", "one"]
            ).payload as NSDictionary,
            [
                "type": "reorder",
                "section": "reserve",
                "orderedMessageIds": ["two", "one"]
            ] as NSDictionary
        )

        XCTAssertEqual(
            QueueMutation.move(
                messageID: "message",
                destination: .upNext,
                placement: .first
            ).payload as NSDictionary,
            [
                "type": "move",
                "messageId": "message",
                "destination": "up_next",
                "placement": "first"
            ] as NSDictionary
        )
    }

    func testEmptyCollectionIsValidButMissingCollectionIsNot() async throws {
        let networkService = makeNetworkService()
        QueuePayloadURLProtocol.responseBody = Data(#"{"necklaces":[]}"#.utf8)
        let emptyNecklaces = try await networkService.listSenderNecklaces()
        XCTAssertEqual(emptyNecklaces, [])

        QueuePayloadURLProtocol.responseBody = Data(#"{"status":"ok"}"#.utf8)
        await assertInvalidPayload {
            _ = try await networkService.listSenderNecklaces()
        }
    }

    func testInvalidSuccessfulJSONAndMissingStableIDsFail() async {
        let networkService = makeNetworkService()
        QueuePayloadURLProtocol.responseBody = Data("[]".utf8)
        await assertInvalidPayload {
            _ = try await networkService.listSenderNecklaces()
        }

        QueuePayloadURLProtocol.responseBody = Data(#"{"necklaces":[{"name":"Missing ID"}]}"#.utf8)
        await assertInvalidPayload {
            _ = try await networkService.listSenderNecklaces()
        }
        XCTAssertNil(service.mapLumi(from: ["text": "Missing ID"], fallbackThemeKey: "heart"))
    }

    func testMalformedQueueEntriesFailAndLegacyQueueRequiresRealFields() throws {
        XCTAssertNil(
            service.mapNecklace(from: [
                "id": "malformed",
                "queue": [["id": "valid", "text": "Valid"], ["text": "Missing ID"]]
            ])
        )

        let unavailable = try XCTUnwrap(service.mapNecklace(from: ["id": "unavailable"]))
        XCTAssertNil(unavailable.queueSnapshot)

        let legacy = try XCTUnwrap(service.mapNecklace(from: [
            "id": "legacy",
            "queue": [["id": "one", "text": "First"], ["id": "two", "text": "Second"]]
        ]))
        XCTAssertEqual(legacy.queueSnapshot?.revision, 0)
        XCTAssertEqual(legacy.queueSnapshot?.continuousSequence.map(\.id), ["one", "two"])
    }

    private func makeNetworkService() -> SenderService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QueuePayloadURLProtocol.self]
        let suiteName = "QueueSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("test-token", forKey: TokenStore.legacyKey)
        return SenderService(
            client: APIClient(
                baseURL: URL(string: "https://queue.example.test")!,
                session: URLSession(configuration: configuration),
                tokenStore: TokenStore(defaults: defaults)
            )
        )
    }

    private func assertInvalidPayload(operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("Expected invalidPayload")
        } catch APIError.invalidPayload {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func message(_ id: String) -> Message {
        Message(
            id: id,
            text: id,
            packageId: "test",
            timestamp: Date(timeIntervalSince1970: 1),
            experience: Experience(
                themeKey: "heart",
                animationKey: "breathe",
                soundKey: "soft"
            )
        )
    }

    private func lumi(_ id: String) -> [String: Any] {
        [
            "id": id,
            "text": id,
            "presentation": [
                "theme": "heart",
                "animation": "breathe",
                "sound": "soft"
            ]
        ]
    }
}

private final class QueuePayloadURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responseBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let body = Self.responseBody else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
