import Foundation

struct AuthResult {
    let user: User
}

final class AuthService {
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
            throw APIError.unauthorized
        }
        client.tokenStore.accessToken = token
        print("[API] otp token stored length=\(token.count)")

        let user = try await resolveUser(from: payload, fallbackEmail: email)
        return AuthResult(user: user)
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

    private func resolveUser(from payload: [String: Any], fallbackEmail: String) async throws -> User {
        if let user = parseUser(from: payload) {
            return user
        }
        if hasAccessToken {
            do {
                return try await me()
            } catch {
                // Continue with a local fallback when /me is unavailable.
            }
        }
        return User(id: UUID().uuidString, email: fallbackEmail, subscriptionTier: .free)
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
            let userDict = JSONLookup.dictionary(root, keys: ["user", "profile"]) ?? root
            if let user = mapUser(from: userDict) {
                return user
            }
        }
        return nil
    }

    private func mapUser(from dict: [String: Any]) -> User? {
        guard let email = JSONLookup.string(dict, keys: ["email"]) else {
            return nil
        }
        let id = JSONLookup.string(dict, keys: ["id", "_id", "userId"]) ?? UUID().uuidString
        let tierText = (JSONLookup.string(dict, keys: ["subscriptionTier", "tier", "subscription"]) ?? "free").lowercased()
        let tier: SubscriptionTier = tierText == "premium" ? .premium : .free
        return User(id: id, email: email, subscriptionTier: tier)
    }
}
