import Foundation

protocol MessageLibraryServing {
    func library(query: MessageLibraryQuery) async throws -> MessageLibraryResponse
    func addMessage(
        necklaceId: String,
        request: AddLibraryMessageRequest
    ) async throws -> QueueCreationResult
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
    ) async throws -> QueueCreationResult {
        var body: [String: Any] = [
            "messageId": request.messageId,
            "destination": request.destination.rawValue
        ]
        if let customization = request.customization {
            var customizationBody: [String: Any] = [:]
            if let primaryText = customization.primaryText {
                customizationBody["primaryText"] = primaryText
            }
            customizationBody["secondaryText"] = customization.secondaryText ?? NSNull()
            body["customization"] = customizationBody
        }
        let payload = try await client.requestObject(
            method: .post,
            path: "/api/sender/necklaces/\(necklaceId)/lumis/from-library",
            body: body,
            authorized: true
        )
        guard let lumiPayload = JSONLookup.dictionary(payload, keys: ["lumi"]),
              let message = SenderService().mapLumi(
                from: lumiPayload,
                fallbackThemeKey: "heart"
              ) else {
            throw APIError.invalidPayload
        }

        return QueueCreationResult(
            message: message,
            snapshot: SenderService().mapQueueSnapshot(
                from: payload,
                necklaceId: necklaceId,
                fallbackThemeKey: "heart"
            ),
            queuePosition: JSONLookup.int(lumiPayload, keys: ["queuePosition", "position"])
        )
    }
}
