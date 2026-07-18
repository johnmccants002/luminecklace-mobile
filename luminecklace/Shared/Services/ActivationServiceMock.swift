import Foundation

final class ActivationService {
    private let client: APIClient
    private let claimTokenKey = "lumi_activation_claim_token"

    init(client: APIClient = .shared) {
        self.client = client
    }

    var hasPendingClaimToken: Bool {
        if let token = UserDefaults.standard.string(forKey: claimTokenKey) {
            return !token.isEmpty
        }
        return false
    }

    func validate(code: String) async throws -> NecklaceTag {
        let payload = try await client.requestObject(
            method: .post,
            path: "/api/activate",
            body: [
                "activationCode": code
            ],
            authorized: false
        )

        for root in JSONLookup.rootCandidates(from: payload) {
            if let claim = JSONLookup.dictionary(root, keys: ["claim"]),
               let claimToken = JSONLookup.string(claim, keys: ["claimToken"]) {
                UserDefaults.standard.set(claimToken, forKey: claimTokenKey)
                break
            }
        }

        for root in JSONLookup.rootCandidates(from: payload) {
            if let activation = JSONLookup.dictionary(root, keys: ["activation"]),
               let necklace = parseNecklace(from: activation) {
                return necklace
            }
            if let necklace = parseNecklace(from: root) {
                return necklace
            }
            if let nested = JSONLookup.dictionary(root, keys: ["necklace", "tag"]),
               let necklace = parseNecklace(from: nested) {
                return necklace
            }
        }

        if let success = JSONLookup.bool(payload, keys: ["ok", "success"]), success {
            return MockData.activationReward
        }

        throw APIError.invalidPayload
    }

    func claimPendingActivationIfNeeded() async throws {
        guard let claimToken = UserDefaults.standard.string(forKey: claimTokenKey), !claimToken.isEmpty else {
            return
        }

        _ = try await client.requestObject(
            method: .post,
            path: "/api/activate/claim",
            body: [
                "claimToken": claimToken
            ],
            authorized: true
        )

        UserDefaults.standard.removeObject(forKey: claimTokenKey)
    }

    func clearPendingClaimToken() {
        UserDefaults.standard.removeObject(forKey: claimTokenKey)
    }

    private func parseNecklace(from dict: [String: Any]) -> NecklaceTag? {
        guard let id = JSONLookup.string(dict, keys: ["id", "_id", "tagId"]) else {
            return nil
        }

        let name = JSONLookup.string(dict, keys: ["name", "label", "necklaceName"]) ?? "Lumi Necklace"
        let sku = JSONLookup.string(dict, keys: ["sku"]) ?? "LUMI-UNKNOWN"
        let themeKey = JSONLookup.string(dict, keys: ["themeKey", "theme"]) ?? "classic"
        let rarity = JSONLookup.string(dict, keys: ["rarity"])
        let firstPackage = JSONLookup.stringArray(dict, keys: ["basePackageIDs"])?.first
        let includedPackage = JSONLookup.string(dict, keys: ["includedPackage", "packageName", "packageId"]) ?? firstPackage ?? "Love"

        return NecklaceTag(
            id: id,
            name: name,
            sku: sku,
            themeKey: themeKey,
            isEquipped: true,
            rarity: rarity,
            includedPackage: includedPackage
        )
    }
}

enum ActivationError: LocalizedError {
    case invalidCode

    var errorDescription: String? {
        switch self {
        case .invalidCode:
            return "That code is invalid. Check the box insert and try again."
        }
    }
}
