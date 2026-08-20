import Foundation

struct AuthResult {
    let user: User
}

protocol AuthenticationServicing {
    func signIn(email: String, password: String) async throws -> AuthResult
    func resetPassword(email: String) async throws
    func me() async throws -> User
    func signOut() async throws
    func clearLocalSession()
    var hasAccessToken: Bool { get }
    var localSessionState: LocalSessionState { get }
}

extension AuthenticationServicing {
    var localSessionState: LocalSessionState {
        hasAccessToken ? .available : .missing
    }
}

struct AuthService: AuthenticationServicing {
    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func signIn(email: String, password: String) async throws -> AuthResult {
        let payload = try await client.requestObject(
            method: .post,
            path: "/api/auth/signin",
            body: [
                "email": email,
                "password": password
            ]
        )

        guard let token = parseToken(from: payload) else {
            client.tokenStore.accessToken = nil
            throw APIError.invalidPayload
        }
        client.tokenStore.accessToken = token

        do {
            let user = try await resolveUser(from: payload)
            return AuthResult(user: user)
        } catch {
            client.tokenStore.accessToken = nil
            throw error
        }
    }

    func resetPassword(email: String) async throws {
        _ = try await client.requestObject(
            method: .post,
            path: "/api/auth/password/reset",
            body: ["email": email]
        )
    }

    func me() async throws -> User {
        let payload = try await client.requestObject(method: .get, path: "/api/auth/me", authorized: true)
        guard let user = parseUser(from: payload) else {
            throw APIError.missingRequiredField("user")
        }
        return user
    }

    func signOut() async throws {
        if hasAccessToken {
            do {
                _ = try await client.requestObject(method: .post, path: "/api/auth/signout", authorized: true)
            } catch APIError.unauthorized {
                // Token is stale; local clear still succeeds.
            }
        } else {
            _ = try await client.requestObject(method: .post, path: "/api/auth/signout", authorized: false)
        }
        client.tokenStore.accessToken = nil
    }

    func clearLocalSession() {
        client.tokenStore.accessToken = nil
    }

    var hasAccessToken: Bool {
        if let token = client.tokenStore.accessToken {
            return !token.isEmpty
        }
        return false
    }

    var localSessionState: LocalSessionState {
        client.tokenStore.localSessionState
    }

    private func resolveUser(from payload: [String: Any]) async throws -> User {
        if let user = parseUser(from: payload) {
            return user
        }
        if hasAccessToken {
            return try await me()
        }
        throw APIError.invalidPayload
    }

    private func parseToken(from payload: [String: Any]) -> String? {
        for root in JSONLookup.rootCandidates(from: payload) {
            if let token = JSONLookup.string(root, keys: ["accessToken", "access_token", "token", "jwt"]) {
                return token
            }
            if let auth = JSONLookup.dictionary(root, keys: ["auth"]),
               let token = JSONLookup.string(auth, keys: ["accessToken", "access_token", "token", "jwt"]) {
                return token
            }
            if let session = JSONLookup.dictionary(root, keys: ["session"]),
               let token = JSONLookup.string(session, keys: ["accessToken", "access_token", "token", "jwt"]) {
                return token
            }
            if let data = JSONLookup.dictionary(root, keys: ["data"]),
               let session = JSONLookup.dictionary(data, keys: ["session"]),
               let token = JSONLookup.string(session, keys: ["accessToken", "access_token", "token", "jwt"]) {
                return token
            }
        }
        return nil
    }

    private func parseUser(from payload: [String: Any]) -> User? {
        for root in JSONLookup.rootCandidates(from: payload) {
            if var userDict = JSONLookup.dictionary(root, keys: ["user"]) {
                if displayName(in: userDict) == nil,
                   let profile = JSONLookup.dictionary(root, keys: ["profile"]),
                   let profileDisplayName = displayName(in: profile) {
                    userDict["displayName"] = profileDisplayName
                }

                if let user = mapUser(from: userDict) {
                    return user
                }
            }

            if let profile = JSONLookup.dictionary(root, keys: ["profile"]),
               let user = mapUser(from: profile) {
                return user
            }

            if let user = mapUser(from: root) {
                return user
            }
        }
        return nil
    }

    private func mapUser(from dict: [String: Any]) -> User? {
        guard let id = JSONLookup.string(dict, keys: ["id", "_id", "userId"]),
              let email = JSONLookup.string(dict, keys: ["email"]) else {
            return nil
        }
        let metadata = JSONLookup.dictionary(
            dict,
            keys: ["profile", "userMetadata", "user_metadata", "metadata"]
        )
        let displayName = displayName(in: dict) ?? metadata.flatMap(displayName(in:))
        let tierText = (JSONLookup.string(dict, keys: ["subscriptionTier", "tier", "subscription"]) ?? "free").lowercased()
        let tier: SubscriptionTier = tierText == "premium" ? .premium : .free
        return User(id: id, email: email, displayName: displayName, subscriptionTier: tier)
    }

    private func displayName(in dict: [String: Any]) -> String? {
        JSONLookup.string(
            dict,
            keys: ["firstName", "first_name", "displayName", "display_name", "fullName", "full_name", "name"]
        )
    }
}
