import Foundation
import Security
import UniformTypeIdentifiers
import XCTest

final class ShareItemExtractorTests: XCTestCase {
    func testInstagramURLProviderAndWWWHost() async throws {
        let provider = NSItemProvider(
            item: NSURL(string: "https://www.instagram.com/reel/example/")!,
            typeIdentifier: UTType.url.identifier
        )
        let item = NSExtensionItem()
        item.attachments = [provider]
        let link = try await ShareItemExtractor().extract(from: [item])
        XCTAssertEqual(link?.provider, .instagram)
        XCTAssertEqual(link?.contentKind, "reel")
        XCTAssertEqual(link?.host, "www.instagram.com")
    }

    func testPublicWebsiteURLPreservesPathQueryAndFragment() async throws {
        let source = URL(string: "https://Example.com/articles/one?ref=lumi#details")!
        let link = ShareItemExtractor.validatedLink(source)
        XCTAssertEqual(link?.provider, .website)
        XCTAssertEqual(link?.contentKind, "link")
        XCTAssertEqual(link?.host, "example.com")
        XCTAssertEqual(link?.url.path, "/articles/one")
        XCTAssertEqual(link?.url.query, "ref=lumi")
        XCTAssertEqual(link?.url.fragment, "details")
    }

    func testInternationalHostnameUsesASCIIRepresentation() {
        let link = ShareItemExtractor.validatedLink(URL(string: "https://bücher.de/path")!)
        XCTAssertEqual(link?.provider, .website)
        XCTAssertEqual(link?.host, "xn--bcher-kva.de")
        XCTAssertEqual(link?.url.host, "xn--bcher-kva.de")
    }

    func testPlainTextSelectsFirstSupportedLink() async throws {
        let provider = NSItemProvider(
            item: NSString(
                string: "http://unsafe.test/no https://example.com/first https://instagram.com/p/second/"
            ),
            typeIdentifier: UTType.plainText.identifier
        )
        let item = NSExtensionItem()
        item.attachments = [provider]
        let link = try await ShareItemExtractor().extract(from: [item])
        XCTAssertEqual(link?.url.path, "/first")
        XCTAssertEqual(link?.provider, .website)
    }

    func testRejectsUnsafeAndPrivateDestinations() async throws {
        XCTAssertNil(ShareItemExtractor.validatedLink(URL(string: "http://instagram.com/p/no/")!))
        XCTAssertNil(ShareItemExtractor.validatedLink(URL(string: "https://user:pass@example.com/no")!))
        XCTAssertNil(ShareItemExtractor.validatedLink(URL(string: "https://localhost/no")!))
        XCTAssertNil(ShareItemExtractor.validatedLink(URL(string: "https://service.local/no")!))
        XCTAssertNil(ShareItemExtractor.validatedLink(URL(string: "https://127.0.0.1/no")!))
        XCTAssertNil(ShareItemExtractor.validatedLink(URL(string: "https://127.1/no")!))
        XCTAssertNil(ShareItemExtractor.validatedLink(URL(string: "https://192.168.1.2/no")!))
        XCTAssertNil(ShareItemExtractor.validatedLink(URL(string: "https://[::1]/no")!))
        XCTAssertNil(ShareItemExtractor.validatedLink(URL(string: "https://[fc00::1]/no")!))
        XCTAssertEqual(
            ShareItemExtractor.validatedLink(URL(string: "https://8.8.8.8/")!)?.provider,
            .website
        )
        let missing = try await ShareItemExtractor().extract(from: [])
        XCTAssertNil(missing)
    }

    func testInstagramLookalikeIsWebsiteNotInstagram() {
        let link = ShareItemExtractor.validatedLink(
            URL(string: "https://instagram.com.attacker.net/p/no/")!
        )
        XCTAssertEqual(link?.provider, .website)
        XCTAssertEqual(link?.host, "instagram.com.attacker.net")
    }

    func testCancelledExtractionThrows() async {
        let task = Task {
            try await ShareItemExtractor().extract(from: [])
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

@MainActor
final class ShareLumiViewModelTests: XCTestCase {
    func testDefaultsPrimarySelectionAndStableRetryID() async throws {
        let extractor = MockExtractor(result: ExtractedShareLink(
            url: URL(string: "https://instagram.com/reel/example/")!,
            provider: .instagram,
            host: "instagram.com",
            contentKind: "reel"
        ))
        let service = MockShareService(
            necklaces: [
                ShareNecklace(id: "other", name: "Other", lifecycleStatus: "active", isPrimary: false),
                ShareNecklace(id: "primary", name: "Primary", lifecycleStatus: "active", isPrimary: true)
            ],
            createResults: [
                .failure(URLError(.timedOut)),
                .success(Self.successResponse)
            ]
        )
        var completions = 0
        let stableID = UUID()
        let viewModel = ShareLumiViewModel(
            extractor: extractor,
            service: service,
            clientRequestId: stableID,
            onComplete: { completions += 1 },
            onCancel: {}
        )

        XCTAssertEqual(viewModel.state, .extracting)
        XCTAssertEqual(viewModel.message, ShareLumiViewModel.defaultMessage)
        XCTAssertEqual(viewModel.destination, .upNext)
        viewModel.start(items: [])
        try await waitUntil { viewModel.state == .ready }
        XCTAssertEqual(viewModel.selectedNecklaceID, "primary")

        viewModel.message = "Edited, private message"
        viewModel.submit()
        viewModel.submit()
        try await waitUntil {
            if case .failure = viewModel.state { return true }
            return false
        }
        XCTAssertEqual(service.requests.count, 1)
        XCTAssertEqual(service.requests.first?.clientRequestId, stableID)
        XCTAssertEqual(viewModel.message, "Edited, private message")
        XCTAssertEqual(viewModel.selectedNecklaceID, "primary")

        viewModel.tryAgain()
        try await waitUntil { viewModel.state == .success }
        XCTAssertEqual(service.requests.count, 2)
        XCTAssertEqual(service.requests.map(\.clientRequestId), [stableID, stableID])
        try await waitUntil { completions == 1 }
    }

    func testAuthenticationAndNoEligibleStates() async throws {
        let extractor = MockExtractor(result: ExtractedShareLink(
            url: URL(string: "https://instagram.com/p/example/")!,
            provider: .instagram,
            host: "instagram.com",
            contentKind: "post"
        ))
        let authService = MockShareService(
            necklaces: [],
            fetchError: ShareLumiServiceError.authenticationRequired
        )
        let authModel = ShareLumiViewModel(
            extractor: extractor,
            service: authService,
            onComplete: {},
            onCancel: {}
        )
        authModel.start(items: [])
        try await waitUntil { authModel.state == .authenticationRequired }

        let emptyModel = ShareLumiViewModel(
            extractor: extractor,
            service: MockShareService(necklaces: []),
            onComplete: {},
            onCancel: {}
        )
        emptyModel.start(items: [])
        try await waitUntil { emptyModel.state == .noEligibleNecklaces }
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

    private static let successResponse = CreateSharedLumiResponse(
        lumi: CreatedSharedLumi(
            id: "lumi-1",
            text: "This made me think of you.",
            queuePosition: 2,
            attachment: nil
        ),
        idempotentReplay: false
    )
}

final class ShareLumiServiceTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testBearerHeaderFilteringAndSuccessfulCreation() async throws {
        let session = makeSession()
        let tokenStore = makeTokenStore(token: "secret-token")
        let service = ShareLumiService(
            baseURL: URL(string: "https://example.test")!,
            session: session,
            tokenStore: tokenStore
        )

        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
            if request.url?.path == "/api/sender/necklaces" {
                return Self.response(request, status: 200, body: """
                {"necklaces":[
                  {"id":"primary","name":"Primary","lifecycleStatus":"active","isPrimary":true},
                  {"id":"inactive","name":"Inactive","lifecycleStatus":"inactive","isPrimary":false}
                ]}
                """)
            }
            return Self.response(request, status: 201, body: Self.successJSON)
        }

        let necklaces = try await service.fetchEligibleNecklaces()
        XCTAssertEqual(necklaces.map(\.id), ["primary"])

        let result = try await service.createSharedLumi(
            necklaceId: "primary",
            request: CreateSharedLumiRequest(
                clientRequestId: UUID(),
                url: "https://instagram.com/reel/example/",
                text: "Private text",
                destination: .upNext
            )
        )
        XCTAssertEqual(result.lumi.id, "lumi-1")
        XCTAssertFalse(result.idempotentReplay)
    }

    func testIdempotent200UnauthorizedConflictAndMalformedResponse() async throws {
        let tokenStore = makeTokenStore(token: "token")
        let session = makeSession()
        let service = ShareLumiService(
            baseURL: URL(string: "https://example.test")!,
            session: session,
            tokenStore: tokenStore
        )
        let request = CreateSharedLumiRequest(
            clientRequestId: UUID(),
            url: "https://instagram.com/p/example/",
            text: nil,
            destination: .reserve
        )

        URLProtocolStub.handler = { request in
            Self.response(
                request,
                status: 200,
                body: Self.successJSON.replacingOccurrences(of: "false", with: "true")
            )
        }
        let replay = try await service.createSharedLumi(necklaceId: "n", request: request)
        XCTAssertTrue(replay.idempotentReplay)

        URLProtocolStub.handler = { Self.response($0, status: 409, body: "{}") }
        await XCTAssertThrowsShareError(.conflict) {
            _ = try await service.createSharedLumi(necklaceId: "n", request: request)
        }

        URLProtocolStub.handler = { Self.response($0, status: 401, body: "{}") }
        await XCTAssertThrowsShareError(.authenticationRequired) {
            _ = try await service.createSharedLumi(necklaceId: "n", request: request)
        }
        XCTAssertNil(try tokenStore.read())
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private func makeTokenStore(token: String) -> SharedAuthTokenStore {
        let store = SharedAuthTokenStore(keychain: InMemoryKeychain(), accessGroup: "test.group")
        try! store.write(token)
        return store
    }

    private func XCTAssertThrowsShareError(
        _ expected: ShareLumiServiceError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)")
        } catch let error as ShareLumiServiceError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
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

    private static let successJSON = """
    {"lumi":{"id":"lumi-1","text":"Private text","queuePosition":1,
      "attachment":{"type":"link","provider":"instagram","contentKind":"reel",
      "url":"https://instagram.com/reel/example/","host":"instagram.com",
      "ctaLabel":"View on Instagram","openMode":"external"}},"idempotentReplay":false}
    """
}

private final class MockExtractor: ShareItemExtracting, @unchecked Sendable {
    let result: ExtractedShareLink?
    init(result: ExtractedShareLink?) { self.result = result }
    func extract(from items: [NSExtensionItem]) async throws -> ExtractedShareLink? { result }
}

private final class MockShareService: ShareLumiServicing, @unchecked Sendable {
    let necklaces: [ShareNecklace]
    let fetchError: Error?
    private var createResults: [Result<CreateSharedLumiResponse, Error>]
    private let lock = NSLock()
    private(set) var requests: [CreateSharedLumiRequest] = []

    init(
        necklaces: [ShareNecklace],
        fetchError: Error? = nil,
        createResults: [Result<CreateSharedLumiResponse, Error>] = []
    ) {
        self.necklaces = necklaces
        self.fetchError = fetchError
        self.createResults = createResults
    }

    func fetchEligibleNecklaces() async throws -> [ShareNecklace] {
        if let fetchError { throw fetchError }
        return necklaces.filter(\.isEligible)
    }

    func createSharedLumi(
        necklaceId: String,
        request: CreateSharedLumiRequest
    ) async throws -> CreateSharedLumiResponse {
        let result = lock.withLock { () -> Result<CreateSharedLumiResponse, Error> in
            requests.append(request)
            return createResults.isEmpty
                ? .success(ShareLumiServiceTestsSuccess.response)
                : createResults.removeFirst()
        }
        return try result.get()
    }

    func clearAuthentication() {}
}

private nonisolated enum ShareLumiServiceTestsSuccess {
    static let response = CreateSharedLumiResponse(
        lumi: CreatedSharedLumi(id: "lumi", text: "text", queuePosition: 1, attachment: nil),
        idempotentReplay: false
    )
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

private final class InMemoryKeychain: KeychainOperating, @unchecked Sendable {
    private var data: Data?
    func copyMatching(_ query: CFDictionary) -> (status: OSStatus, data: Data?) {
        guard let data else { return (errSecItemNotFound, nil) }
        return (errSecSuccess, data)
    }
    func add(_ attributes: CFDictionary) -> OSStatus {
        let values = attributes as NSDictionary
        data = values[kSecValueData] as? Data
        return errSecSuccess
    }
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        let values = attributes as NSDictionary
        data = values[kSecValueData] as? Data
        return errSecSuccess
    }
    func delete(_ query: CFDictionary) -> OSStatus {
        data = nil
        return errSecSuccess
    }
}
