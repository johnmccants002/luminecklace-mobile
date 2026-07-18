import Foundation

struct ClaimPendingOrdersResult {
    let claimedOrders: [ClaimedOrder]
}

final class SenderService {
    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func claimPendingOrdersForUser() async throws -> ClaimPendingOrdersResult {
        let payload = try await client.requestObject(
            method: .post,
            path: "/api/sender/claim_pending_orders_for_user",
            authorized: true
        )

        var orders: [ClaimedOrder] = []
        for root in JSONLookup.rootCandidates(from: payload) {
            if let claimed = JSONLookup.array(root, keys: ["claimedOrders", "orders", "claimed"]),
               !claimed.isEmpty {
                orders = claimed.compactMap(mapClaimedOrder(from:))
                break
            }
        }

        return ClaimPendingOrdersResult(claimedOrders: orders)
    }

    func listSenderNecklacesWithCurrentMessage() async throws -> [NecklaceTag] {
        let payload = try await client.requestObject(
            method: .get,
            path: "/api/sender/list_sender_necklaces_with_current_message",
            authorized: true
        )

        for root in JSONLookup.rootCandidates(from: payload) {
            if let array = JSONLookup.array(root, keys: ["necklaces", "items", "data"]) {
                let necklaces = array.compactMap(mapNecklace(from:))
                if !necklaces.isEmpty {
                    return markEquipped(for: necklaces)
                }
            }
        }

        return []
    }

    func publishMessage(necklaceId: String, text: String, themeKey: String) async throws -> Message {
        let payload = try await client.requestObject(
            method: .post,
            path: "/api/sender/messages/publish",
            body: [
                "necklaceId": necklaceId,
                "content": text,
                "themeKey": themeKey
            ],
            authorized: true
        )

        guard let message = Self.parseMessage(from: payload, fallbackThemeKey: themeKey) else {
            throw APIError.invalidPayload
        }
        return message
    }

    func submitClaimAssistance(orderEmail: String?) async throws {
        var body: [String: Any] = [:]
        if let orderEmail, !orderEmail.isEmpty {
            body["orderEmail"] = orderEmail
        }
        _ = try await client.requestObject(
            method: .post,
            path: "/api/sender/claim-assistance",
            body: body.isEmpty ? nil : body,
            authorized: true
        )
    }

    private func mapClaimedOrder(from dict: [String: Any]) -> ClaimedOrder? {
        let id = JSONLookup.string(dict, keys: ["id", "_id", "orderId"]) ?? UUID().uuidString
        let externalOrderRef = JSONLookup.string(dict, keys: ["externalOrderRef", "orderRef", "orderNumber"])
        let status = JSONLookup.string(dict, keys: ["status"]) ?? "claimed"
        return ClaimedOrder(id: id, externalOrderRef: externalOrderRef, status: status)
    }

    private func mapNecklace(from dict: [String: Any]) -> NecklaceTag? {
        let id = JSONLookup.string(dict, keys: ["id", "_id", "necklaceId", "tagId"]) ?? UUID().uuidString
        let name = JSONLookup.string(dict, keys: ["name", "label", "necklaceName"]) ?? "Lumi Necklace"
        let sku = JSONLookup.string(dict, keys: ["sku"]) ?? "LUMI-UNKNOWN"
        let themeKey = JSONLookup.string(dict, keys: ["themeKey", "theme"]) ?? "heart"
        let isPrimary = JSONLookup.bool(dict, keys: ["isPrimary", "is_primary", "equipped"]) ?? false
        let rarity = JSONLookup.string(dict, keys: ["rarity"])
        let includedPackage = JSONLookup.string(dict, keys: ["includedPackage", "packageId", "packageName"]) ?? "Love"
        let hasPublishedMessage = JSONLookup.bool(dict, keys: ["hasPublishedMessage", "has_message", "messageConfigured"]) ?? false
        return NecklaceTag(
            id: id,
            name: name,
            sku: sku,
            themeKey: themeKey,
            isEquipped: isPrimary,
            rarity: rarity,
            includedPackage: includedPackage,
            hasPublishedMessage: hasPublishedMessage
        )
    }

    private func markEquipped(for necklaces: [NecklaceTag]) -> [NecklaceTag] {
        if necklaces.contains(where: \.isEquipped) {
            return necklaces
        }

        return necklaces.enumerated().map { index, item in
            var updated = item
            updated.isEquipped = index == 0
            return updated
        }
    }

    static func parseMessage(from payload: [String: Any], fallbackThemeKey: String) -> Message? {
        for root in JSONLookup.rootCandidates(from: payload) {
            if let message = parseMessageDict(root, experienceRoot: JSONLookup.dictionary(root, keys: ["experience"]), fallbackThemeKey: fallbackThemeKey) {
                return message
            }
            if let dict = JSONLookup.dictionary(root, keys: ["message"]),
               let message = parseMessageDict(dict, experienceRoot: JSONLookup.dictionary(root, keys: ["experience"]), fallbackThemeKey: fallbackThemeKey) {
                return message
            }
        }
        return nil
    }

    private static func parseMessageDict(
        _ dict: [String: Any],
        experienceRoot: [String: Any]?,
        fallbackThemeKey: String
    ) -> Message? {
        guard let text = JSONLookup.string(dict, keys: ["text", "content", "message"]) else {
            return nil
        }

        let id = JSONLookup.string(dict, keys: ["id", "_id", "messageId"]) ?? UUID().uuidString
        let packageId = JSONLookup.string(dict, keys: ["packageId", "package"]) ?? "love"

        let experienceDict = experienceRoot ?? dict
        let themeKey = JSONLookup.string(experienceDict, keys: ["themeKey", "theme"]) ?? fallbackThemeKey
        let animationKey = JSONLookup.string(experienceDict, keys: ["animationKey", "animation"]) ?? "breathe"
        let soundKey = JSONLookup.string(experienceDict, keys: ["soundKey", "sound"]) ?? "soft"

        return Message(
            id: id,
            text: text,
            packageId: packageId,
            timestamp: Date(),
            experience: Experience(
                themeKey: themeKey,
                animationKey: animationKey,
                soundKey: soundKey
            )
        )
    }
}
