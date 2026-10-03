import Foundation
import XCTest
@testable import lumiclip

final class RecipientFeedbackContractTests: XCTestCase {
    override func tearDown() {
        RecipientFeedbackURLProtocol.handler = nil
        super.tearDown()
    }

    func testFeedbackModelsDecodeAllShapesAndUnknownReaction() throws {
        let decoder = makeDecoder()
        let full = try decoder.decode(
            LumiFeedback.self,
            from: Data(
                #"{"reaction":"touched","reactionAt":"2026-08-01T12:00:00.123Z","responseText":"Exactly what I needed.","respondedAt":"2026-08-01T12:01:00Z"}"#.utf8
            )
        )
        XCTAssertEqual(full.reaction, .touched)
        XCTAssertEqual(full.responseText, "Exactly what I needed.")
        XCTAssertNotNil(full.reactionAt)
        XCTAssertNotNil(full.respondedAt)

        let reactionOnly = try decoder.decode(
            LumiFeedback.self,
            from: Data(#"{"reaction":"heart","reactionAt":null,"responseText":null,"respondedAt":null}"#.utf8)
        )
        XCTAssertEqual(reactionOnly.reaction, .heart)
        XCTAssertNil(reactionOnly.responseText)

        let responseOnly = try decoder.decode(
            LumiFeedback.self,
            from: Data(#"{"reaction":null,"reactionAt":null,"responseText":"Thank you","respondedAt":null}"#.utf8)
        )
        XCTAssertNil(responseOnly.reaction)
        XCTAssertEqual(responseOnly.responseText, "Thank you")

        let unknown = try decoder.decode(
            LumiFeedback.self,
            from: Data(#"{"reaction":"future_reaction","responseText":"Still valid"}"#.utf8)
        )
        XCTAssertNil(unknown.reaction)
        XCTAssertEqual(unknown.responseText, "Still valid")
    }

    func testReactionRequestUsesContractAndDecodesFractionalDate() async throws {
        let service = RecipientTapService(
            baseURL: URL(string: "https://example.test")!,
            session: makeSession()
        )
        RecipientFeedbackURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/tap/reaction")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try Self.bodyData(from: request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
            XCTAssertEqual(json, ["revealSessionId": "session-1", "reaction": "touched"])
            return Self.response(
                request,
                status: 200,
                body: #"{"status":"reacted","feedback":{"reaction":"touched","reactionAt":"2026-08-01T12:00:00.123Z","responseText":null,"respondedAt":null}}"#
            )
        }

        let feedback = try await service.setReaction(
            revealSessionId: "session-1",
            reaction: .touched
        )
        XCTAssertEqual(feedback.reaction, .touched)
        XCTAssertNotNil(feedback.reactionAt)
    }

    func testResponseRequestTrimsAtViewModelBoundaryAndMapsServerErrors() async throws {
        let service = RecipientTapService(
            baseURL: URL(string: "https://example.test")!,
            session: makeSession()
        )
        RecipientFeedbackURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/tap/response")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try Self.bodyData(from: request)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
            XCTAssertEqual(json["revealSessionId"], "session-2")
            XCTAssertEqual(json["text"], "Words kept private")
            return Self.response(request, status: 409, body: #"{"code":"already_responded"}"#)
        }

        await assertFeedbackError(.alreadyResponded) {
            _ = try await service.submitResponse(
                revealSessionId: "session-2",
                text: "Words kept private"
            )
        }

        RecipientFeedbackURLProtocol.handler = {
            Self.response($0, status: 410, body: #"{"code":"expired_session"}"#)
        }
        await assertFeedbackError(.expiredSession) {
            _ = try await service.setReaction(revealSessionId: "session-2", reaction: .wow)
        }

        RecipientFeedbackURLProtocol.handler = {
            Self.response($0, status: 400, body: #"{"code":"invalid_request"}"#)
        }
        await assertFeedbackError(.invalidRequest) {
            _ = try await service.submitResponse(revealSessionId: "session-2", text: "x")
        }

        RecipientFeedbackURLProtocol.handler = {
            Self.response($0, status: 200, body: #"{"status":"reacted","feedback":"malformed"}"#)
        }
        await assertFeedbackError(.invalidPayload) {
            _ = try await service.setReaction(revealSessionId: "session-2", reaction: .heart)
        }

        RecipientFeedbackURLProtocol.handler = { _ in throw URLError(.timedOut) }
        await assertFeedbackError(.temporaryFailure) {
            _ = try await service.setReaction(revealSessionId: "session-2", reaction: .heart)
        }
    }

    func testReactionAccessibilityContract() {
        XCTAssertEqual(LumiReaction.allCases.map(\.emoji), ["❤️", "🥹", "😂", "✨", "🫶", "😮"])
        XCTAssertEqual(
            LumiReaction.allCases.map(\.accessibilityLabel),
            ["Loved it", "Felt this", "Made me laugh", "Beautiful", "Sending love", "Wow"]
        )
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecipientFeedbackURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) {
                return date
            }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid date")
            )
        }
        return decoder
    }

    private func assertFeedbackError(
        _ expected: RecipientFeedbackServiceError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)")
        } catch let error as RecipientFeedbackServiceError {
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

private final class RecipientFeedbackURLProtocol: URLProtocol, @unchecked Sendable {
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
