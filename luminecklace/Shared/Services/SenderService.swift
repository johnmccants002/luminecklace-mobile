import Foundation

final class SenderService {
    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func listSenderNecklaces() async throws -> [NecklaceTag] {
        let payload = try await client.requestObject(
            method: .get,
            path: "/api/sender/necklaces",
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

    func addLumi(necklaceId: String, text: String) async throws -> Message {
        let payload = try await client.requestObject(
            method: .post,
            path: "/api/sender/necklaces/\(necklaceId)/lumis",
            body: ["text": text],
            authorized: true
        )

        guard let lumi = JSONLookup.dictionary(payload, keys: ["lumi"]),
              let message = mapLumi(from: lumi, fallbackThemeKey: "heart") else {
            throw APIError.invalidPayload
        }
        return message
    }

    func mapNecklace(from dict: [String: Any]) -> NecklaceTag? {
        let id = JSONLookup.string(dict, keys: ["id", "_id", "necklaceId", "tagId"]) ?? UUID().uuidString
        let name = JSONLookup.string(dict, keys: ["name", "label", "necklaceName"]) ?? "Lumi Necklace"
        let sku = JSONLookup.string(dict, keys: ["sku"]) ?? "LUMI-UNKNOWN"
        let themeKey = JSONLookup.string(dict, keys: ["themeKey", "theme"]) ?? "heart"
        let isPrimary = JSONLookup.bool(dict, keys: ["isPrimary"]) ?? false
        let rarity = JSONLookup.string(dict, keys: ["rarity"])
        let includedPackage = JSONLookup.string(dict, keys: ["includedPackage", "packageId", "packageName"]) ?? "Love"
        let lifecycleStatus = JSONLookup.string(dict, keys: ["lifecycleStatus"]) ?? "active"
        let queuedLumis = JSONLookup.array(dict, keys: ["queue", "messages", "lumis"])?.compactMap {
            mapLumi(from: $0, fallbackThemeKey: themeKey)
        } ?? []
        let nextLumi = queuedLumis.first ?? JSONLookup.dictionary(dict, keys: ["nextLumi"]).flatMap {
            mapLumi(from: $0, fallbackThemeKey: themeKey)
        }
        let availableLumiCount = dict["availableLumiCount"] as? Int ?? max(queuedLumis.count, nextLumi == nil ? 0 : 1)
        let recentlyRevealed = JSONLookup.array(dict, keys: ["recentlyRevealed"])?.compactMap {
            mapRevealedLumi(from: $0, fallbackThemeKey: themeKey)
        } ?? []
        let reserve = JSONLookup.dictionary(dict, keys: ["reserve"]).flatMap(mapReserveSummary(from:))
        return NecklaceTag(
            id: id,
            name: name,
            sku: sku,
            themeKey: themeKey,
            isEquipped: isPrimary,
            rarity: rarity,
            includedPackage: includedPackage,
            lifecycleStatus: lifecycleStatus,
            availableLumiCount: availableLumiCount,
            nextLumi: nextLumi,
            queuedLumis: queuedLumis.isEmpty ? nextLumi.map { [$0] } ?? [] : queuedLumis,
            recentlyRevealed: recentlyRevealed,
            reserve: reserve
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

    private func mapLumi(
        from dict: [String: Any],
        fallbackThemeKey: String
    ) -> Message? {
        guard let text = JSONLookup.string(dict, keys: ["text"]) else {
            return nil
        }

        let id = JSONLookup.string(dict, keys: ["id"]) ?? UUID().uuidString
        let presentation = JSONLookup.dictionary(dict, keys: ["presentation"]) ?? [:]
        let themeKey = JSONLookup.string(presentation, keys: ["theme"]) ?? fallbackThemeKey
        let animationKey = JSONLookup.string(presentation, keys: ["animation"]) ?? "breathe"
        let soundKey = JSONLookup.string(presentation, keys: ["sound"]) ?? "soft"

        return Message(
            id: id,
            text: text,
            packageId: "love",
            timestamp: Date(),
            experience: Experience(
                themeKey: themeKey,
                animationKey: animationKey,
                soundKey: soundKey
            )
        )
    }

    private func mapRevealedLumi(
        from dict: [String: Any],
        fallbackThemeKey: String
    ) -> RevealedLumi? {
        guard let id = JSONLookup.string(dict, keys: ["id"]),
              let text = JSONLookup.string(dict, keys: ["text"]),
              let revealedAtValue = JSONLookup.string(dict, keys: ["revealedAt"]),
              let revealedAt = parseISO8601Date(revealedAtValue) else {
            return nil
        }

        let presentation = JSONLookup.dictionary(dict, keys: ["presentation"]) ?? [:]
        return RevealedLumi(
            id: id,
            text: text,
            revealedAt: revealedAt,
            experience: Experience(
                themeKey: JSONLookup.string(presentation, keys: ["theme"]) ?? fallbackThemeKey,
                animationKey: JSONLookup.string(presentation, keys: ["animation"]) ?? "breathe",
                soundKey: JSONLookup.string(presentation, keys: ["sound"]) ?? "soft"
            )
        )
    }

    private func parseISO8601Date(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        return ISO8601DateFormatter().date(from: value)
    }

    func mapReserveSummary(from dict: [String: Any]) -> LumiReserveSummary? {
        let availableCountKeys = ["availableLumiCount", "availableCount", "remainingCount"]
        let hasExplicitAvailableCount = availableCountKeys.contains { dict[$0] != nil }
        let explicitAvailableCount = JSONLookup.int(dict, keys: availableCountKeys)

        guard let enabled = JSONLookup.bool(dict, keys: ["enabled"]),
              let approvedCount = JSONLookup.int(dict, keys: ["approvedCount"]),
              let totalCount = JSONLookup.int(dict, keys: ["totalCount"]),
              approvedCount >= 0,
              totalCount >= 0,
              approvedCount <= totalCount,
              !hasExplicitAvailableCount || explicitAvailableCount.map({ $0 >= 0 }) == true,
              let categoryPayloads = JSONLookup.array(dict, keys: ["categories"]) else {
            return nil
        }

        let validCategoryCount = categoryPayloads.compactMap { category -> Bool? in
            guard JSONLookup.string(category, keys: ["key"]) != nil,
                  let categoryApprovedCount = JSONLookup.int(category, keys: ["approvedCount"]),
                  let categoryTotalCount = JSONLookup.int(category, keys: ["totalCount"]),
                  categoryApprovedCount >= 0,
                  categoryTotalCount >= 0,
                  categoryApprovedCount <= categoryTotalCount else {
                return nil
            }
            return true
        }

        guard validCategoryCount.count == categoryPayloads.count else {
            return nil
        }

        return LumiReserveSummary(
            enabled: enabled,
            lumiCount: explicitAvailableCount ?? (approvedCount == 0 ? 0 : nil)
        )
    }
}
