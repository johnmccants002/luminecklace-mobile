import Foundation

nonisolated protocol ShareLumiServicing: Sendable {
    func fetchEligibleNecklaces() async throws -> [ShareNecklace]
    func createSharedLumi(necklaceId: String, request: CreateSharedLumiRequest) async throws -> CreateSharedLumiResponse
    func clearAuthentication()
}

nonisolated enum ShareLumiServiceError: LocalizedError, Equatable {
    case authenticationRequired
    case conflict
    case invalidResponse
    case server(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            "Open the Lumi app and sign in before sharing."
        case .conflict:
            "This Lumi couldn’t be added safely. Close this share and try again."
        case .invalidResponse:
            "Lumi received an unexpected response. Please try again."
        case let .server(_, message):
            message
        }
    }
}

nonisolated final class ShareLumiService: ShareLumiServicing, @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let tokenStore: SharedAuthTokenStore
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        baseURL: URL = ShareLumiService.resolveBaseURL(),
        session: URLSession = .shared,
        tokenStore: SharedAuthTokenStore = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenStore = tokenStore
    }

    func fetchEligibleNecklaces() async throws -> [ShareNecklace] {
        let response: ShareNecklaceListResponse = try await request(
            method: "GET",
            path: "/api/sender/necklaces",
            body: Optional<CreateSharedLumiRequest>.none
        )
        return response.necklaces.filter(\.isEligible)
    }

    func createSharedLumi(
        necklaceId: String,
        request: CreateSharedLumiRequest
    ) async throws -> CreateSharedLumiResponse {
        try await self.request(
            method: "POST",
            path: "/api/sender/necklaces/\(necklaceId)/lumis/from-share",
            body: request
        )
    }

    func clearAuthentication() {
        try? tokenStore.delete()
    }

    private func request<Response: Decodable, Body: Encodable>(
        method: String,
        path: String,
        body: Body?
    ) async throws -> Response {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ShareLumiServiceError.invalidResponse
        }
        components.path = path
        guard let url = components.url else {
            throw ShareLumiServiceError.invalidResponse
        }
        guard let token = try tokenStore.read(), !token.isEmpty else {
            throw ShareLumiServiceError.authenticationRequired
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShareLumiServiceError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200, 201:
            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw ShareLumiServiceError.invalidResponse
            }
        case 401:
            clearAuthentication()
            throw ShareLumiServiceError.authenticationRequired
        case 409:
            throw ShareLumiServiceError.conflict
        default:
            throw ShareLumiServiceError.server(
                statusCode: httpResponse.statusCode,
                message: Self.safeServerMessage(from: data)
                    ?? "Lumi couldn’t add this message. Please try again."
            )
        }
    }

    private static func safeServerMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let message = object["message"] as? String, !message.isEmpty { return message }
        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty { return message }
        return nil
    }

    private static func resolveBaseURL() -> URL {
        if let value = ProcessInfo.processInfo.environment["LUMI_API_BASE_URL"],
           let url = URL(string: value) {
            return url
        }
        return URL(string: "https://www.luminecklace.com")!
    }
}
