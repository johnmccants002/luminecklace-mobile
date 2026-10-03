import Foundation

nonisolated protocol RecipientTapServicing {
    func resolveTap(token: String) async throws -> ResolveTapResponse
    func confirmReveal(revealSessionId: String) async throws -> ConfirmRevealResponse
    func setReaction(revealSessionId: String, reaction: LumiReaction) async throws -> LumiFeedback
    func submitResponse(revealSessionId: String, text: String) async throws -> LumiFeedback
}

nonisolated struct TapResolutionService: RecipientTapServicing {
    private let baseURL: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder: JSONDecoder

    init(baseURL: URL = APIConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(Self.decodeISO8601Date)
        self.decoder = decoder
    }

    func resolveTap(token: String) async throws -> ResolveTapResponse {
        try await post(
            path: "/api/tap/resolve",
            body: ResolveTapRequest(token: token),
            responseType: ResolveTapResponse.self
        )
    }

    func confirmReveal(revealSessionId: String) async throws -> ConfirmRevealResponse {
        let response = try await post(
            path: "/api/tap/revealed",
            body: ConfirmRevealRequest(revealSessionId: revealSessionId),
            responseType: ConfirmRevealResponse.self
        )
        guard response.status == "revealed" else {
            throw APIError.invalidPayload
        }
        return response
    }

    func setReaction(
        revealSessionId: String,
        reaction: LumiReaction
    ) async throws -> LumiFeedback {
        let response = try await post(
            path: "/api/tap/reaction",
            body: SetReactionRequest(revealSessionId: revealSessionId, reaction: reaction),
            responseType: ReactionSubmissionResponse.self,
            feedbackRequest: .reaction
        )
        guard response.status == "reacted" else {
            throw RecipientFeedbackServiceError.invalidPayload
        }
        return response.feedback
    }

    func submitResponse(
        revealSessionId: String,
        text: String
    ) async throws -> LumiFeedback {
        let response = try await post(
            path: "/api/tap/response",
            body: SubmitResponseRequest(revealSessionId: revealSessionId, text: text),
            responseType: WrittenResponseSubmissionResponse.self,
            feedbackRequest: .response
        )
        guard response.status == "responded" else {
            throw RecipientFeedbackServiceError.invalidPayload
        }
        return response.feedback
    }

    private func post<Request: Encodable, Response: Decodable>(
        path: String,
        body: Request,
        responseType: Response.Type,
        feedbackRequest: FeedbackRequestKind? = nil
    ) async throws -> Response {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = path
        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.post.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if feedbackRequest != nil {
                throw RecipientFeedbackServiceError.temporaryFailure
            }
            throw error
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            if feedbackRequest != nil {
                throw RecipientFeedbackServiceError.temporaryFailure
            }
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let feedbackRequest {
                throw Self.feedbackError(
                    statusCode: httpResponse.statusCode,
                    data: data,
                    requestKind: feedbackRequest
                )
            }
            throw APIError.serverError(
                statusCode: httpResponse.statusCode,
                message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            if feedbackRequest != nil {
                throw RecipientFeedbackServiceError.invalidPayload
            }
            throw APIError.invalidPayload
        }
    }

    private static func feedbackError(
        statusCode: Int,
        data: Data,
        requestKind: FeedbackRequestKind
    ) -> RecipientFeedbackServiceError {
        let code = serverErrorCode(from: data)
        switch code {
        case "invalid_request", "invalid_payload", "validation_error":
            return .invalidRequest
        case "reveal_not_confirmed", "not_revealed", "reveal_pending":
            return .revealNotConfirmed
        case "expired", "expired_session", "session_expired":
            return .expiredSession
        case "already_responded", "response_already_submitted":
            return .alreadyResponded
        default:
            switch statusCode {
            case 400, 422:
                return .invalidRequest
            case 409 where requestKind == .response:
                return .alreadyResponded
            case 410:
                return .expiredSession
            case 412:
                return .revealNotConfirmed
            default:
                return .temporaryFailure
            }
        }
    }

    private static func serverErrorCode(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        if let code = dictionary["code"] as? String {
            return code.lowercased()
        }
        if let error = dictionary["error"] as? String {
            return error.lowercased()
        }
        if let error = dictionary["error"] as? [String: Any],
           let code = error["code"] as? String {
            return code.lowercased()
        }
        return nil
    }

    private static func decodeISO8601Date(decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        if let date = iso8601WithFractionalSeconds.date(from: value) ?? iso8601.date(from: value) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Invalid ISO-8601 date."
        )
    }

    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601 = ISO8601DateFormatter()
}

nonisolated private enum FeedbackRequestKind: Equatable {
    case reaction
    case response
}
