import Foundation

final class MessageService {
    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func getMessage(
        tagId: String?,
        fallbackThemeKey: String?,
        enabledPackages: [Package],
        subscriptionTier: SubscriptionTier
    ) async throws -> Message {
        let queryItems: [URLQueryItem]
        if let tagId, !tagId.isEmpty {
            queryItems = [URLQueryItem(name: "tagId", value: tagId)]
        } else {
            queryItems = []
        }

        let payload = try await client.requestObject(
            method: .get,
            path: "/api/tap",
            queryItems: queryItems,
            authorized: true
        )

        for root in JSONLookup.rootCandidates(from: payload) {
            if let messageDict = JSONLookup.dictionary(root, keys: ["message"]) {
                let experienceDict = JSONLookup.dictionary(root, keys: ["experience"])
                if let mapped = mapMessage(
                    from: messageDict,
                    experience: experienceDict,
                    fallbackThemeKey: fallbackThemeKey,
                    enabledPackages: enabledPackages,
                    subscriptionTier: subscriptionTier
                ) {
                    return mapped
                }
            }
            if let mapped = mapMessage(
                from: root,
                experience: JSONLookup.dictionary(root, keys: ["experience"]),
                fallbackThemeKey: fallbackThemeKey,
                enabledPackages: enabledPackages,
                subscriptionTier: subscriptionTier
            ) {
                return mapped
            }
            if let nested = JSONLookup.dictionary(root, keys: ["message", "tap"]),
               let mapped = mapMessage(
                from: nested,
                experience: JSONLookup.dictionary(root, keys: ["experience"]),
                fallbackThemeKey: fallbackThemeKey,
                enabledPackages: enabledPackages,
                subscriptionTier: subscriptionTier
               ) {
                return mapped
            }
        }

        throw APIError.invalidPayload
    }

    private func mapMessage(
        from dict: [String: Any],
        experience: [String: Any]?,
        fallbackThemeKey: String?,
        enabledPackages: [Package],
        subscriptionTier: SubscriptionTier
    ) -> Message? {
        guard let text = JSONLookup.string(dict, keys: ["text", "message", "content"]) else {
            return nil
        }

        let allowedPackages = enabledPackages.filter { package in
            !package.isPremium || subscriptionTier == .premium
        }
        let fallbackPackage = allowedPackages.first?.id ?? "love"
        let packageId = JSONLookup.string(dict, keys: ["packageId", "package"]) ?? fallbackPackage

        let messageId = JSONLookup.string(dict, keys: ["id", "_id", "messageId"]) ?? UUID().uuidString
        let themeKey = JSONLookup.string(experience ?? dict, keys: ["themeKey", "theme"]) ?? fallbackThemeKey ?? "classic"
        let animationKey = JSONLookup.string(experience ?? dict, keys: ["animationKey", "animation"]) ?? "pulse"
        let soundKey = JSONLookup.string(experience ?? dict, keys: ["soundKey", "sound"]) ?? "chime"

        return Message(
            id: messageId,
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
