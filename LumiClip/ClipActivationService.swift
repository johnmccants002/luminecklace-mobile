//
//  ClipActivationService.swift
//  lumiclip
//

import Foundation

struct ClipActivationResult: Identifiable, Hashable {
    let id = UUID()
    let necklaceID: String?
    let necklaceName: String
    let basePackageIDs: [String]
}

enum ClipActivationError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case invalidPayload
    case server(message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL."
        case .invalidResponse:
            return "Unexpected response from server."
        case .unauthorized:
            return "Sign in is required before activation."
        case .invalidPayload:
            return "Invalid activation response."
        case let .server(message):
            return message
        }
    }
}

final class ClipActivationService {
    private let session: URLSession
    private let baseURL: URL
    private let tokenStoreKey = "lumi_access_token"

    init(
        baseURL: URL = ClipActivationService.resolveBaseURL(),
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func validate(code: String) async throws -> ClipActivationResult {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ClipActivationError.invalidURL
        }
        components.path = "/api/activate"
        guard let url = components.url else {
            throw ClipActivationError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = UserDefaults.standard.string(forKey: tokenStoreKey), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "activationCode": code
        ])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClipActivationError.invalidResponse
        }

        let payload = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw ClipActivationError.unauthorized
            }
            let message = Self.extractMessage(from: payload) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw ClipActivationError.server(message: message)
        }

        if let necklace = Self.dictionary(payload, keys: ["necklace", "tag"]) {
            return ClipActivationResult(
                necklaceID: Self.string(necklace, keys: ["id", "_id", "tagId"]),
                necklaceName: Self.string(necklace, keys: ["name", "label", "necklaceName"]) ?? "Lumi",
                basePackageIDs: Self.stringArray(necklace, keys: ["basePackageIDs", "basePackageIds"]).map(normalizePackageID(_:))
            )
        }

        for root in Self.rootCandidates(from: payload) {
            if let id = Self.string(root, keys: ["id", "_id", "tagId"]) {
                return ClipActivationResult(
                    necklaceID: id,
                    necklaceName: Self.string(root, keys: ["name", "label", "necklaceName"]) ?? "Lumi",
                    basePackageIDs: Self.stringArray(root, keys: ["basePackageIDs", "basePackageIds"]).map(normalizePackageID(_:))
                )
            }
        }

        if let success = Self.bool(payload, keys: ["ok", "success"]), success {
            return ClipActivationResult(necklaceID: nil, necklaceName: "Lumi", basePackageIDs: [])
        }

        throw ClipActivationError.invalidPayload
    }

    private static func resolveBaseURL() -> URL {
        if let envValue = ProcessInfo.processInfo.environment["LUMI_API_BASE_URL"],
           let url = URL(string: envValue) {
            return url
        }
        if let defaultsValue = UserDefaults.standard.string(forKey: "LUMI_API_BASE_URL"),
           let url = URL(string: defaultsValue) {
            return url
        }
        return URL(string: "http://localhost:3000")!
    }

    private static func extractMessage(from json: [String: Any]) -> String? {
        if let message = string(json, keys: ["message", "error"]) {
            return message
        }
        if let nestedError = dictionary(json, keys: ["error"]),
           let message = string(nestedError, keys: ["message"]) {
            return message
        }
        if let data = dictionary(json, keys: ["data"]),
           let message = string(data, keys: ["message"]) {
            return message
        }
        return nil
    }

    private static func string(_ json: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = json[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func dictionary(_ json: [String: Any], keys: [String]) -> [String: Any]? {
        for key in keys {
            if let value = json[key] as? [String: Any] {
                return value
            }
        }
        return nil
    }

    private static func bool(_ json: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = json[key] as? Bool {
                return value
            }
        }
        return nil
    }

    private static func rootCandidates(from json: [String: Any]) -> [[String: Any]] {
        var roots: [[String: Any]] = [json]
        if let data = json["data"] as? [String: Any] {
            roots.append(data)
        }
        if let result = json["result"] as? [String: Any] {
            roots.append(result)
        }
        return roots
    }

    private func normalizePackageID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func stringArray(_ json: [String: Any], keys: [String]) -> [String] {
        for key in keys {
            if let value = json[key] as? [String] {
                return value
            }
        }
        return []
    }
}
