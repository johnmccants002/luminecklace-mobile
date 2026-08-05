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
        case attachment
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
            let attachment = try? container.decode(LumiLinkAttachment.self, forKey: .attachment)

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
                    presentation: presentation,
                    attachment: attachment
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
    let attachment: LumiLinkAttachment?

    init(
        revealSessionId: String,
        necklaceDisplayName: String,
        lumiId: String,
        text: String,
        presentation: NecklacePresentation,
        attachment: LumiLinkAttachment? = nil
    ) {
        self.revealSessionId = revealSessionId
        self.necklaceDisplayName = necklaceDisplayName
        self.lumiId = lumiId
        self.text = text
        self.presentation = presentation
        self.attachment = attachment
    }
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
    let revealPreset: LumiMessageRevealPreset
    let background: LumiBackgroundKey
    let font: LumiFontKey
    let textSize: LumiTextSizeKey
    let textAlignment: LumiTextAlignmentKey
    let textPosition: LumiTextPositionKey

    private enum CodingKeys: String, CodingKey {
        case theme
        case animation
        case sound
        case revealPreset
        case background
        case font
        case textSize
        case textAlignment
        case textPosition
    }

    init(
        theme: LumiPresentationTheme,
        animation: LumiPresentationAnimation,
        sound: LumiPresentationSound?,
        revealPreset: LumiMessageRevealPreset = .wordRise,
        background: LumiBackgroundKey? = nil,
        font: LumiFontKey = .serif,
        textSize: LumiTextSizeKey = .medium,
        textAlignment: LumiTextAlignmentKey = .center,
        textPosition: LumiTextPositionKey = .center
    ) {
        self.theme = theme
        self.animation = animation
        self.sound = sound
        self.revealPreset = revealPreset
        self.background = background
            ?? LumiBackgroundKey(rawValue: theme.rawValue)
            ?? .heart
        self.font = font
        self.textSize = textSize
        self.textAlignment = textAlignment
        self.textPosition = textPosition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let themeValue = try container.decodeIfPresent(String.self, forKey: .theme)
        let animationValue = try container.decodeIfPresent(String.self, forKey: .animation)
        let soundValue = try container.decodeIfPresent(String.self, forKey: .sound)
        let revealPresetValue = try container.decodeIfPresent(String.self, forKey: .revealPreset)
        let backgroundValue = try container.decodeIfPresent(String.self, forKey: .background)
        let fontValue = try container.decodeIfPresent(String.self, forKey: .font)
        let textSizeValue = try container.decodeIfPresent(String.self, forKey: .textSize)
        let textAlignmentValue = try container.decodeIfPresent(String.self, forKey: .textAlignment)
        let textPositionValue = try container.decodeIfPresent(String.self, forKey: .textPosition)

        theme = LumiPresentationTheme(rawValue: themeValue ?? "") ?? .heart
        animation = LumiPresentationAnimation(rawValue: animationValue ?? "") ?? .breathe
        sound = soundValue.flatMap(LumiPresentationSound.init(rawValue:))
        revealPreset = LumiMessageRevealPreset(rawValue: revealPresetValue ?? "") ?? .wordRise
        background = LumiBackgroundKey(rawValue: backgroundValue ?? theme.rawValue) ?? .heart
        font = LumiFontKey(rawValue: fontValue ?? "") ?? .serif
        textSize = LumiTextSizeKey(rawValue: textSizeValue ?? "") ?? .medium
        textAlignment = LumiTextAlignmentKey(rawValue: textAlignmentValue ?? "") ?? .center
        textPosition = LumiTextPositionKey(rawValue: textPositionValue ?? "") ?? .center
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

nonisolated enum LumiMessageRevealPreset: String, Decodable, Hashable {
    case wordRise
    case crossfade
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
