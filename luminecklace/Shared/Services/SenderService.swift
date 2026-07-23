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

    func mapReserveSummary(from dict: [String: Any]) -> LumiReserveSummary? {
        guard let enabled = JSONLookup.bool(dict, keys: ["enabled"]),
              let approvedCount = JSONLookup.int(dict, keys: ["approvedCount"]),
              let totalCount = JSONLookup.int(dict, keys: ["totalCount"]),
              approvedCount >= 0,
              totalCount >= 0,
              approvedCount <= totalCount,
              let categoryPayloads = JSONLookup.array(dict, keys: ["categories"]) else {
            return nil
        }

        let categories = categoryPayloads.compactMap { category -> LumiReserveCategorySummary? in
            guard let key = JSONLookup.string(category, keys: ["key"]),
                  let categoryApprovedCount = JSONLookup.int(category, keys: ["approvedCount"]),
                  let categoryTotalCount = JSONLookup.int(category, keys: ["totalCount"]),
                  categoryApprovedCount >= 0,
                  categoryTotalCount >= 0,
                  categoryApprovedCount <= categoryTotalCount else {
                return nil
            }

            return LumiReserveCategorySummary(
                key: key,
                approvedCount: categoryApprovedCount,
                totalCount: categoryTotalCount
            )
        }

        guard categories.count == categoryPayloads.count else {
            return nil
        }

        return LumiReserveSummary(
            enabled: enabled,
            approvedCount: approvedCount,
            totalCount: totalCount,
            categories: categories
        )
    }
}
