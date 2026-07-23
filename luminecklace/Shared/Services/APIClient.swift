import Foundation

enum APIConfig {
    nonisolated static let baseURL: URL = {
        if let envValue = ProcessInfo.processInfo.environment["LUMI_API_BASE_URL"],
           let url = URL(string: envValue) {
            return url
        }
        if let defaultsValue = UserDefaults.standard.string(forKey: "LUMI_API_BASE_URL"),
           let url = URL(string: defaultsValue) {
            return url
        }
        return URL(string: "https://www.luminecklace.com")!
    }()
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
}

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(statusCode: Int, message: String)
    case missingRequiredField(String)
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL."
        case .invalidResponse:
            return "Unexpected response from server."
        case .unauthorized:
            return "Your session expired. Please sign in again."
        case let .serverError(_, message):
            return message
        case let .missingRequiredField(field):
            return "Missing required field: \(field)."
        case .invalidPayload:
            return "Invalid payload from server."
        }
    }
}

final class TokenStore {
    private let key = "lumi_access_token"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var accessToken: String? {
        get { defaults.string(forKey: key) }
        set {
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}

final class APIClient {
    static let shared = APIClient()

    let tokenStore: TokenStore
    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = APIConfig.baseURL,
        session: URLSession = .shared,
        tokenStore: TokenStore = TokenStore()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenStore = tokenStore
    }

    func requestObject(
        method: HTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: [String: Any]? = nil,
        authorized: Bool = false
    ) async throws -> [String: Any] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authorized {
            guard let token = tokenStore.accessToken, !token.isEmpty else {
                throw APIError.unauthorized
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let isSenderLumiWrite = path.hasPrefix("/api/sender/necklaces/")
            && path.hasSuffix("/lumis")
        let isVerbosePath = path == "/api/auth/signin"
            || path == "/api/sender/necklaces"
            || isSenderLumiWrite

        if isVerbosePath {
            let hasAuthHeader = request.value(forHTTPHeaderField: "Authorization") != nil
            let headers = (request.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { partial, entry in
                if entry.key.caseInsensitiveCompare("Authorization") == .orderedSame {
                    partial[entry.key] = "<redacted>"
                } else {
                    partial[entry.key] = entry.value
                }
            }
            let requestBody: String
            if path == "/api/auth/signin" || isSenderLumiWrite {
                requestBody = "<redacted>"
            } else {
                requestBody = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? "<empty>"
            }
            print("[API] \(path) request method=\(method.rawValue) url=\(url.absoluteString) hasAuth=\(hasAuthHeader) headers=\(headers) body=\(requestBody)")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if isVerbosePath {
            let bodyText = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            print("[API] \(path) status=\(httpResponse.statusCode) body=\(bodyText)")
        }

        let jsonObject = (try? JSONSerialization.jsonObject(with: data)) ?? [:]
        let jsonDict = jsonObject as? [String: Any] ?? [:]

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }

            let message = Self.extractMessage(from: jsonDict) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: message)
        }

        return jsonDict
    }

    private static func extractMessage(from json: [String: Any]) -> String? {
        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }
        if let error = json["error"] as? String, !error.isEmpty {
            return error
        }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }
        if let message = (json["data"] as? [String: Any])?["message"] as? String,
           !message.isEmpty {
            return message
        }
        return nil
    }
}

enum JSONLookup {
    static func string(_ json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = json[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    static func dictionary(_ json: [String: Any], keys: [String]) -> [String: Any]? {
        for key in keys {
            if let value = json[key] as? [String: Any] {
                return value
            }
        }
        return nil
    }

    static func array(_ json: [String: Any], keys: [String]) -> [[String: Any]]? {
        for key in keys {
            if let value = json[key] as? [[String: Any]] {
                return value
            }
        }
        return nil
    }

    static func stringArray(_ json: [String: Any], keys: [String]) -> [String]? {
        for key in keys {
            if let value = json[key] as? [String] {
                return value
            }
        }
        return nil
    }

    static func bool(_ json: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = json[key] as? Bool {
                return value
            }
        }
        return nil
    }

    static func int(_ json: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = json[key] as? Int {
                return value
            }
        }
        return nil
    }

    static func rootCandidates(from json: [String: Any]) -> [[String: Any]] {
        var roots: [[String: Any]] = [json]
        if let data = json["data"] as? [String: Any] {
            roots.append(data)
        }
        if let result = json["result"] as? [String: Any] {
            roots.append(result)
        }
        return roots
    }
}
