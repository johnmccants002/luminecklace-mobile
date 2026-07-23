import Foundation

nonisolated struct ResolveTapRequest: Encodable, Equatable {
    let token: String
}

nonisolated enum ResolveTapResponse: Decodable, Equatable {
    case ready(ResolvedLumi)
    case empty
    case unavailable

    private enum CodingKeys: String, CodingKey {
        case status
        case revealSessionId
        case necklace
        case lumi
        case presentation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(String.self, forKey: .status)

        switch status {
        case "ready":
            let revealSessionId = try container.decode(String.self, forKey: .revealSessionId)
            let necklace = try container.decode(ResolvedNecklace.self, forKey: .necklace)
            let lumi = try container.decode(ResolvedLumiPayload.self, forKey: .lumi)
            let presentation = try container.decode(NecklacePresentation.self, forKey: .presentation)

            guard !revealSessionId.isEmpty,
                  !necklace.displayName.isEmpty,
                  !lumi.id.isEmpty,
                  !lumi.text.isEmpty else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Ready response is missing required data."
                    )
                )
            }

            self = .ready(
                ResolvedLumi(
                    revealSessionId: revealSessionId,
                    necklaceDisplayName: necklace.displayName,
                    lumiId: lumi.id,
                    text: lumi.text,
                    presentation: presentation
                )
            )
        case "empty":
            self = .empty
        case "unavailable":
            self = .unavailable
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .status,
                in: container,
                debugDescription: "Unsupported tap resolve status."
            )
        }
    }
}

nonisolated struct ResolvedLumi: Identifiable, Hashable {
    var id: String { revealSessionId }

    let revealSessionId: String
    let necklaceDisplayName: String
    let lumiId: String
    let text: String
    let presentation: NecklacePresentation
}

nonisolated private struct ResolvedNecklace: Decodable {
    let displayName: String
}

nonisolated private struct ResolvedLumiPayload: Decodable {
    let id: String
    let text: String
}

nonisolated struct NecklacePresentation: Decodable, Hashable {
    let theme: LumiPresentationTheme
    let animation: LumiPresentationAnimation
    let sound: LumiPresentationSound?

    private enum CodingKeys: String, CodingKey {
        case theme
        case animation
        case sound
    }

    init(theme: LumiPresentationTheme, animation: LumiPresentationAnimation, sound: LumiPresentationSound?) {
        self.theme = theme
        self.animation = animation
        self.sound = sound
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let themeValue = try container.decodeIfPresent(String.self, forKey: .theme)
        let animationValue = try container.decodeIfPresent(String.self, forKey: .animation)
        let soundValue = try container.decodeIfPresent(String.self, forKey: .sound)

        theme = LumiPresentationTheme(rawValue: themeValue ?? "") ?? .heart
        animation = LumiPresentationAnimation(rawValue: animationValue ?? "") ?? .breathe
        sound = soundValue.flatMap(LumiPresentationSound.init(rawValue:))
    }
}

nonisolated enum LumiPresentationTheme: String, Decodable, Hashable {
    case heart
    case champagne
    case rose
}

nonisolated enum LumiPresentationAnimation: String, Decodable, Hashable {
    case breathe
    case shimmer
    case still
}

nonisolated enum LumiPresentationSound: String, Decodable, Hashable {
    case soft
}

nonisolated struct ConfirmRevealRequest: Encodable, Equatable {
    let revealSessionId: String
}

nonisolated struct ConfirmRevealResponse: Decodable, Equatable {
    let status: String
    let revealedAt: Date
}

nonisolated enum RevealConfirmationState: Equatable {
    case pending
    case confirming
    case confirmed(Date)
    case temporarilyFailed
}

nonisolated enum RecipientRevealError: Equatable, LocalizedError {
    case invalidInvocation
    case invalidPayload
    case network

    var errorDescription: String? {
        switch self {
        case .invalidInvocation:
            return "We couldn't read this Lumi link."
        case .invalidPayload:
            return "We couldn't open this Lumi."
        case .network:
            return "The connection faded for a moment."
        }
    }
}

nonisolated enum RecipientRevealState: Equatable {
    case awaitingInvocation
    case resolving
    case waiting(ResolvedLumi)
    case revealing(ResolvedLumi)
    case revealed(ResolvedLumi, confirmationState: RevealConfirmationState)
    case empty
    case unavailable
    case error(RecipientRevealError)
}
