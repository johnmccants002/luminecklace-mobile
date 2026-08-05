import Foundation

enum QueueMutation {
    case reorder(section: QueueSection, orderedMessageIDs: [String])
    case move(messageID: String, destination: QueueSection, placement: QueuePlacement)
    case remove(messageID: String)

    var payload: [String: Any] {
        switch self {
        case let .reorder(section, orderedMessageIDs):
            return [
                "type": "reorder",
                "section": section.rawValue,
                "orderedMessageIds": orderedMessageIDs
            ]
        case let .move(messageID, destination, placement):
            return [
                "type": "move",
                "messageId": messageID,
                "destination": destination.rawValue,
                "placement": placement.rawValue
            ]
        case let .remove(messageID):
            return [
                "type": "remove",
                "messageId": messageID
            ]
        }
    }
}

struct QueueCreationResult {
    let message: Message
    let snapshot: QueueSnapshot?
    let queuePosition: Int?
}

struct SharedLinkCreationResult {
    let message: Message
    let idempotentReplay: Bool
}

enum SenderQueueError: LocalizedError {
    case conflict(QueueSnapshot?)

    var errorDescription: String? {
        "This queue changed somewhere else. The latest order has been loaded."
    }
}

struct SenderService {
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

    func addLumi(
        necklaceId: String,
        text: String,
        destination: QueueSection,
        experience: Experience
    ) async throws -> QueueCreationResult {
        let payload = try await client.requestObject(
            method: .post,
            path: "/api/sender/necklaces/\(necklaceId)/lumis",
            body: [
                "text": text,
                "destination": destination.rawValue,
                "presentation": presentationPayload(for: experience)
            ],
            authorized: true
        )

        guard let lumi = JSONLookup.dictionary(payload, keys: ["lumi"]),
              let message = mapLumi(from: lumi, fallbackThemeKey: "heart") else {
            throw APIError.invalidPayload
        }
        return QueueCreationResult(
            message: message,
            snapshot: mapQueueSnapshot(from: payload, necklaceId: necklaceId, fallbackThemeKey: "heart"),
            queuePosition: JSONLookup.int(lumi, keys: ["queuePosition", "position"])
        )
    }

    func addSharedLinkLumi(
        necklaceId: String,
        clientRequestId: UUID,
        url: URL,
        text: String?,
        destination: QueueSection
    ) async throws -> SharedLinkCreationResult {
        var body: [String: Any] = [
            "clientRequestId": clientRequestId.uuidString,
            "url": url.absoluteString,
            "destination": destination.rawValue
        ]
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["text"] = text
        }

        let payload = try await client.requestObject(
            method: .post,
            path: "/api/sender/necklaces/\(necklaceId)/lumis/from-share",
            body: body,
            authorized: true
        )
        guard let lumi = JSONLookup.dictionary(payload, keys: ["lumi"]),
              let message = mapLumi(from: lumi, fallbackThemeKey: "heart") else {
            throw APIError.invalidPayload
        }
        return SharedLinkCreationResult(
            message: message,
            idempotentReplay: JSONLookup.bool(payload, keys: ["idempotentReplay"]) ?? false
        )
    }

    func editLumi(
        necklaceId: String,
        messageId: String,
        text: String,
        experience: Experience
    ) async throws -> QueueCreationResult {
        let payload = try await client.requestObject(
            method: .patch,
            path: "/api/sender/necklaces/\(necklaceId)/lumis/\(messageId)",
            body: [
                "text": text,
                "presentation": presentationPayload(for: experience)
            ],
            authorized: true
        )

        guard let lumi = JSONLookup.dictionary(payload, keys: ["lumi"]),
              let message = mapLumi(from: lumi, fallbackThemeKey: experience.themeKey) else {
            throw APIError.invalidPayload
        }
        return QueueCreationResult(
            message: message,
            snapshot: mapQueueSnapshot(
                from: payload,
                necklaceId: necklaceId,
                fallbackThemeKey: experience.themeKey
            ),
            queuePosition: JSONLookup.int(lumi, keys: ["queuePosition", "position"])
        )
    }

    func mutateQueue(
        necklaceId: String,
        expectedRevision: Int,
        operation: QueueMutation
    ) async throws -> QueueSnapshot {
        do {
            let payload = try await client.requestObject(
                method: .post,
                path: "/api/sender/necklaces/\(necklaceId)/queue/mutations",
                body: [
                    "expectedRevision": expectedRevision,
                    "idempotencyKey": UUID().uuidString,
                    "operation": operation.payload
                ],
                authorized: true
            )
            guard let snapshot = mapQueueSnapshot(
                from: payload,
                necklaceId: necklaceId,
                fallbackThemeKey: "heart"
            ) else {
                throw APIError.invalidPayload
            }
            return snapshot
        } catch let APIError.conflict(payload) {
            throw SenderQueueError.conflict(
                mapQueueSnapshot(
                    from: payload,
                    necklaceId: necklaceId,
                    fallbackThemeKey: "heart"
                )
            )
        }
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
        let explicitSnapshot = mapQueueSnapshot(
            from: dict,
            necklaceId: id,
            fallbackThemeKey: themeKey
        )
        let legacyQueue = JSONLookup.array(dict, keys: ["queue", "messages", "lumis"])?.compactMap {
            mapLumi(from: $0, fallbackThemeKey: themeKey)
        } ?? []
        let legacyCurrent = JSONLookup.dictionary(dict, keys: ["nextLumi"]).flatMap {
            mapLumi(from: $0, fallbackThemeKey: themeKey)
        }
        let current = explicitSnapshot?.current ?? legacyCurrent ?? legacyQueue.first
        let queuedLumis = explicitSnapshot?.upNext
            ?? (current == legacyQueue.first ? Array(legacyQueue.dropFirst()) : legacyQueue)
        let availableLumiCount = explicitSnapshot?.continuousSequence.count
            ?? (dict["availableLumiCount"] as? Int)
            ?? ((current == nil ? 0 : 1) + queuedLumis.count)
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
            nextLumi: current,
            queuedLumis: queuedLumis,
            recentlyRevealed: recentlyRevealed,
            reserve: reserve,
            queueSnapshot: explicitSnapshot
                ?? (try? QueueSnapshot(
                    necklaceId: id,
                    revision: 0,
                    current: current,
                    upNext: queuedLumis,
                    reserve: []
                ))
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

    func mapQueueSnapshot(
        from payload: [String: Any],
        necklaceId: String,
        fallbackThemeKey: String
    ) -> QueueSnapshot? {
        let roots = JSONLookup.rootCandidates(from: payload)
        let queue = roots.lazy.compactMap {
            JSONLookup.dictionary($0, keys: ["queue", "queueSnapshot", "snapshot"])
        }.first

        guard let queue,
              let revision = JSONLookup.int(queue, keys: ["revision"]),
              let upNextPayload = JSONLookup.array(queue, keys: ["upNext"]),
              let reservePayload = JSONLookup.array(queue, keys: ["reserve"]) else {
            return nil
        }

        let currentPayload = queue["current"] as? [String: Any]
        let current = currentPayload.flatMap {
            mapLumi(from: $0, fallbackThemeKey: fallbackThemeKey)
        }
        let upNext = upNextPayload.compactMap {
            mapLumi(from: $0, fallbackThemeKey: fallbackThemeKey)
        }
        let reserve = reservePayload.compactMap {
            mapLumi(from: $0, fallbackThemeKey: fallbackThemeKey)
        }

        guard upNext.count == upNextPayload.count,
              reserve.count == reservePayload.count,
              currentPayload == nil || current != nil else {
            return nil
        }

        return try? QueueSnapshot(
            necklaceId: necklaceId,
            revision: revision,
            current: current,
            upNext: upNext,
            reserve: reserve
        )
    }

    func mapLumi(
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
        let backgroundKey = LumiBackgroundKey(
            rawValue: JSONLookup.string(presentation, keys: ["background"]) ?? themeKey
        ) ?? .heart
        let fontKey = LumiFontKey(
            rawValue: JSONLookup.string(presentation, keys: ["font"]) ?? ""
        ) ?? .serif
        let textSize = LumiTextSizeKey(
            rawValue: JSONLookup.string(presentation, keys: ["textSize"]) ?? ""
        ) ?? .medium
        let textAlignment = LumiTextAlignmentKey(
            rawValue: JSONLookup.string(presentation, keys: ["textAlignment"]) ?? ""
        ) ?? .center
        let textPosition = LumiTextPositionKey(
            rawValue: JSONLookup.string(presentation, keys: ["textPosition"]) ?? ""
        ) ?? .center

        return Message(
            id: id,
            text: text,
            packageId: "love",
            timestamp: Date(),
            experience: Experience(
                themeKey: themeKey,
                animationKey: animationKey,
                soundKey: soundKey,
                backgroundKey: backgroundKey,
                fontKey: fontKey,
                textSize: textSize,
                textAlignment: textAlignment,
                textPosition: textPosition
            ),
            attachment: mapAttachment(from: dict)
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
                soundKey: JSONLookup.string(presentation, keys: ["sound"]) ?? "soft",
                backgroundKey: LumiBackgroundKey(
                    rawValue: JSONLookup.string(presentation, keys: ["background", "theme"])
                        ?? fallbackThemeKey
                ) ?? .heart,
                fontKey: LumiFontKey(
                    rawValue: JSONLookup.string(presentation, keys: ["font"]) ?? ""
                ) ?? .serif,
                textSize: LumiTextSizeKey(
                    rawValue: JSONLookup.string(presentation, keys: ["textSize"]) ?? ""
                ) ?? .medium,
                textAlignment: LumiTextAlignmentKey(
                    rawValue: JSONLookup.string(presentation, keys: ["textAlignment"]) ?? ""
                ) ?? .center,
                textPosition: LumiTextPositionKey(
                    rawValue: JSONLookup.string(presentation, keys: ["textPosition"]) ?? ""
                ) ?? .center
            ),
            attachment: mapAttachment(from: dict)
        )
    }

    private func mapAttachment(from dict: [String: Any]) -> LumiLinkAttachment? {
        guard let payload = JSONLookup.dictionary(dict, keys: ["attachment"]),
              JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return nil
        }
        return try? JSONDecoder().decode(LumiLinkAttachment.self, from: data)
    }

    func presentationPayload(for experience: Experience) -> [String: Any] {
        [
            "background": experience.backgroundKey.rawValue,
            "font": experience.fontKey.rawValue,
            "textSize": experience.textSize.rawValue,
            "textAlignment": experience.textAlignment.rawValue,
            "textPosition": experience.textPosition.rawValue
        ]
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
