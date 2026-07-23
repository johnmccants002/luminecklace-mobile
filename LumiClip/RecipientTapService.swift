import Foundation

enum RecipientTapServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case server
    case invalidPayload
}

nonisolated protocol RecipientTapServicing {
    func resolveTap(token: String) async throws -> ResolveTapResponse
    func confirmReveal(revealSessionId: String) async throws -> ConfirmRevealResponse
}

nonisolated final class RecipientTapService: RecipientTapServicing {
    private let baseURL: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder: JSONDecoder

    init(baseURL: URL = RecipientTapService.resolveBaseURL(), session: URLSession = .shared) {
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
            throw RecipientTapServiceError.invalidPayload
        }
        return response
    }

    private func post<Request: Encodable, Response: Decodable>(
        path: String,
        body: Request,
        responseType: Response.Type
    ) async throws -> Response {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw RecipientTapServiceError.invalidURL
        }
        components.path = path
        guard let url = components.url else {
            throw RecipientTapServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RecipientTapServiceError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw RecipientTapServiceError.server
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw RecipientTapServiceError.invalidPayload
        }
    }

    private static func resolveBaseURL() -> URL {
        if let envValue = ProcessInfo.processInfo.environment["LUMI_API_BASE_URL"],
           let url = URL(string: envValue) {
            return url
        }
        #if DEBUG
        if let defaultsValue = UserDefaults.standard.string(forKey: "LUMI_API_BASE_URL"),
           let url = URL(string: defaultsValue) {
            return url
        }
        return URL(string: "http://localhost:3000")!
        #else
        return URL(string: "https://www.luminecklace.com")!
        #endif
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
