import Foundation

protocol MessageLibraryServing {
    func library(query: MessageLibraryQuery) async throws -> MessageLibraryResponse
    func addMessage(
        necklaceId: String,
        request: AddLibraryMessageRequest
    ) async throws -> SenderLumi
}

final class MessageLibraryService: MessageLibraryServing {
    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func library(query: MessageLibraryQuery) async throws -> MessageLibraryResponse {
        try await client.request(
            method: .get,
            path: "/api/sender/message-library",
            queryItems: query.queryItems,
            authorized: true
        )
    }

    func addMessage(
        necklaceId: String,
        request: AddLibraryMessageRequest
    ) async throws -> SenderLumi {
        let response: SenderLumiResponse = try await client.request(
            method: .post,
            path: "/api/sender/necklaces/\(necklaceId)/lumis/from-library",
            body: request,
            authorized: true
        )
        return response.lumi
    }
}
