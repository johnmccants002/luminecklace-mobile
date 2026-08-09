import Foundation

enum APNSEnvironment: String, Codable, Sendable {
    case sandbox
    case production
}

struct PushDeviceRegistration: Codable, Equatable, Sendable {
    let deviceToken: String
    let environment: APNSEnvironment
    let bundleId: String
    let appVersion: String
    let deviceModel: String
}

struct PushDeviceDisableRequest: Codable, Equatable, Sendable {
    let deviceToken: String
    let environment: APNSEnvironment
    let bundleId: String
}

struct PushPreferences: Codable, Equatable, Sendable {
    var revealsEnabled: Bool
    var reactionsEnabled: Bool
    var responsesEnabled: Bool

    static let enabledByDefault = PushPreferences(
        revealsEnabled: true,
        reactionsEnabled: true,
        responsesEnabled: true
    )
}

struct PushPreferencesUpdate: Codable, Equatable, Sendable {
    var revealsEnabled: Bool?
    var reactionsEnabled: Bool?
    var responsesEnabled: Bool?

    init(
        revealsEnabled: Bool? = nil,
        reactionsEnabled: Bool? = nil,
        responsesEnabled: Bool? = nil
    ) {
        self.revealsEnabled = revealsEnabled
        self.reactionsEnabled = reactionsEnabled
        self.responsesEnabled = responsesEnabled
    }
}

protocol PushDeviceServicing {
    func register(_ registration: PushDeviceRegistration) async throws
    func disable(_ request: PushDeviceDisableRequest) async throws
    func fetchPreferences() async throws -> PushPreferences
    func updatePreferences(_ update: PushPreferencesUpdate) async throws -> PushPreferences
}

struct PushDeviceService: PushDeviceServicing {
    private struct SuccessResponse: Decodable {
        let ok: Bool
    }

    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func register(_ registration: PushDeviceRegistration) async throws {
        let response: SuccessResponse = try await client.request(
            method: .put,
            path: "/api/push/devices",
            body: registration,
            authorized: true
        )
        guard response.ok else { throw APIError.invalidResponse }
    }

    func disable(_ request: PushDeviceDisableRequest) async throws {
        let response: SuccessResponse = try await client.request(
            method: .delete,
            path: "/api/push/devices",
            body: request,
            authorized: true
        )
        guard response.ok else { throw APIError.invalidResponse }
    }

    func fetchPreferences() async throws -> PushPreferences {
        try await client.request(
            method: .get,
            path: "/api/push/preferences",
            authorized: true
        )
    }

    func updatePreferences(_ update: PushPreferencesUpdate) async throws -> PushPreferences {
        try await client.request(
            method: .patch,
            path: "/api/push/preferences",
            body: update,
            authorized: true
        )
    }
}
