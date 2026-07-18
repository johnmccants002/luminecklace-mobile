import Foundation

struct TapResolution {
    let state: RecipientRevealState
    let message: Message
}

final class TapResolutionService {
    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func resolveTap(tapToken: String) async throws -> TapResolution {
        let payload = try await client.requestObject(
            method: .get,
            path: "/api/tap/resolve_tap_message",
            queryItems: [URLQueryItem(name: "tap_token", value: tapToken)],
            authorized: false
        )

        for root in JSONLookup.rootCandidates(from: payload) {
            let status = (JSONLookup.string(root, keys: ["status", "state"]) ?? "").lowercased()
            let fallbackTheme = JSONLookup.string(root, keys: ["fallbackThemeKey", "themeKey"]) ?? "heart"

            if status == "message_ready",
               let message = SenderService.parseMessage(from: root, fallbackThemeKey: fallbackTheme) {
                return TapResolution(state: .message, message: message)
            }

            if status == "fallback_ready",
               let message = SenderService.parseMessage(from: root, fallbackThemeKey: fallbackTheme) {
                return TapResolution(state: .fallback, message: message)
            }

            if let message = SenderService.parseMessage(from: root, fallbackThemeKey: fallbackTheme) {
                return TapResolution(state: .message, message: message)
            }
        }

        return TapResolution(
            state: .softError,
            message: Message(
                id: UUID().uuidString,
                text: "Your Lumi is warming up. Come back in a little while for a personalized reveal.",
                packageId: "love",
                timestamp: Date(),
                experience: Experience(
                    themeKey: "heart",
                    animationKey: "breathe",
                    soundKey: "soft"
                )
            )
        )
    }
}
