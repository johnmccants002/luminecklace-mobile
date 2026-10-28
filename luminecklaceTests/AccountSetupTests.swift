import XCTest
@testable import luminecklace

@MainActor
final class AccountSetupTests: XCTestCase {
    func testInvalidEmailsDoNotRequestSetup() async {
        let service = SetupStub()
        let model = AccountSetupViewModel(service: service)
        for email in ["", "sender", "sender@", "@example.com", "sender@example", "sender@example..com", "sender name@example.com"] {
            model.email = email
            await model.requestSetupLink()
            XCTAssertNotNil(model.errorMessage)
            XCTAssertNil(model.requestedEmail)
        }
        XCTAssertTrue(service.emails.isEmpty)
    }

    func testRequestNormalizesEmailAndRecordsOnlyAcceptedAddress() async {
        let service = SetupStub()
        let model = AccountSetupViewModel(email: " Sender@Example.com ", service: service)
        await model.requestSetupLink()
        XCTAssertEqual(service.emails, ["sender@example.com"])
        XCTAssertEqual(model.requestedEmail, "sender@example.com")
        model.email = "another@example.com"
        XCTAssertEqual(model.requestedEmail, "sender@example.com")
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
    }

    func testFailureRetainsEmailAndAllowsRetry() async {
        let service = SetupStub()
        service.shouldFail = true
        let model = AccountSetupViewModel(email: "sender@example.com", service: service)
        await model.requestSetupLink()
        XCTAssertEqual(model.email, "sender@example.com")
        XCTAssertNil(model.requestedEmail)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
        service.shouldFail = false
        await model.requestSetupLink()
        XCTAssertEqual(service.emails.count, 2)
        XCTAssertEqual(model.requestedEmail, model.email)
        XCTAssertNil(model.errorMessage)
    }

    func testDuplicateSubmissionIsIgnored() async {
        let service = SetupStub()
        service.delay = .milliseconds(80)
        let model = AccountSetupViewModel(email: "sender@example.com", service: service)
        async let first: Void = model.requestSetupLink()
        try? await Task.sleep(for: .milliseconds(10))
        await model.requestSetupLink()
        await first
        XCTAssertEqual(service.emails.count, 1)
    }

    func testServiceUsesPublicRecoveryContractAndAccepts202() async throws {
        SetupURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/auth/invitations/recover")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            var body = request.httpBody
            if body == nil, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 1024)
                var data = Data()
                while stream.hasBytesAvailable {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    if count <= 0 { break }
                    data.append(contentsOf: bytes.prefix(count))
                }
                body = data
            }
            let payload = try JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: String]
            XCTAssertEqual(payload, ["email": "sender@example.com"])
            return (202, Data(#"{"success":true,"message":"If the account is eligible, a new setup link will be sent."}"#.utf8))
        }
        defer { SetupURLProtocol.handler = nil }
        try await makeService().requestSetupLink(email: "sender@example.com")
    }

    func testServiceRejectsServerFailureAndMalformedSuccess() async {
        defer { SetupURLProtocol.handler = nil }
        for (status, payload) in [(500, #"{"error":"Unavailable"}"#), (200, #"{"success":false}"#), (200, #"{}"#)] {
            SetupURLProtocol.handler = { _ in (status, Data(payload.utf8)) }
            do {
                try await makeService().requestSetupLink(email: "sender@example.com")
                XCTFail("Expected rejection")
            } catch { }
        }
    }

    func testPasswordResetUsesPublicEndpointAndAccepts202() async throws {
        SetupURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/auth/password/reset")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (202, Data(#"{"success":true}"#.utf8))
        }
        defer { SetupURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SetupURLProtocol.self]
        let auth = AuthService(client: APIClient(baseURL: URL(string: "https://example.test")!, session: URLSession(configuration: config)))
        try await auth.resetPassword(email: "sender@example.com")
    }

    func testPasswordResetRejectsMalformedSuccessAndUnavailableServer() async {
        defer { SetupURLProtocol.handler = nil }
        for (status, payload) in [(200, #"{}"#), (200, #"{"success":false}"#), (503, #"{"error":"Unavailable"}"#)] {
            SetupURLProtocol.handler = { _ in (status, Data(payload.utf8)) }
            let config = URLSessionConfiguration.ephemeral
            config.protocolClasses = [SetupURLProtocol.self]
            let auth = AuthService(client: APIClient(baseURL: URL(string: "https://example.test")!, session: URLSession(configuration: config)))
            do {
                try await auth.resetPassword(email: "sender@example.com")
                XCTFail("Expected rejection")
            } catch { }
        }
    }

    private func makeService() -> InvitationRecoveryService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SetupURLProtocol.self]
        return InvitationRecoveryService(client: APIClient(baseURL: URL(string: "https://example.test")!, session: URLSession(configuration: config)))
    }
}

@MainActor
private final class SetupStub: InvitationRecoveryServicing {
    nonisolated deinit {}
    var emails: [String] = []
    var shouldFail = false
    var delay: Duration = .zero
    func requestSetupLink(email: String) async throws {
        emails.append(email)
        try await Task.sleep(for: delay)
        if shouldFail { throw URLError(.notConnectedToInternet) }
    }
}

private final class SetupURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}
