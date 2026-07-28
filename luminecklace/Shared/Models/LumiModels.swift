import Foundation

enum SubscriptionTier: String, Codable {
    case free = "Free"
    case premium = "Premium"
}

struct User: Identifiable, Codable {
    let id: String
    let email: String
    let displayName: String?
    let subscriptionTier: SubscriptionTier

    var firstName: String? {
        guard let displayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !displayName.isEmpty,
              let firstName = displayName.split(whereSeparator: \.isWhitespace).first else {
            return nil
        }

        return String(firstName)
    }
}

struct Experience: Codable, Hashable {
    let themeKey: String
    let animationKey: String
    let soundKey: String
}

struct LumiReserveSummary: Hashable {
    let enabled: Bool
    let lumiCount: Int?
}

enum LumiReserveViewState: Hashable {
    case loading
    case unavailable
    case disabled(LumiReserveSummary)
    case empty(LumiReserveSummary)
    case ready(LumiReserveSummary)

    init(summary: LumiReserveSummary?) {
        guard let summary else {
            self = .unavailable
            return
        }

        if !summary.enabled {
            self = .disabled(summary)
        } else if summary.lumiCount == 0 {
            self = .empty(summary)
        } else {
            self = .ready(summary)
        }
    }

    var summary: LumiReserveSummary? {
        switch self {
        case .loading, .unavailable:
            return nil
        case let .disabled(summary),
             let .empty(summary),
             let .ready(summary):
            return summary
        }
    }

    var title: String {
        switch self {
        case .loading:
            return "Checking your Reserve"
        case .unavailable:
            return "Reserve unavailable"
        case .disabled:
            return "Reserve is off"
        case .empty:
            return "No Reserve Lumis"
        case let .ready(summary):
            guard let lumiCount = summary.lumiCount else {
                return "Lumi Reserve ready"
            }
            let noun = lumiCount == 1 ? "Lumi" : "Lumis"
            return "\(lumiCount) \(noun) in Reserve"
        }
    }

    var detail: String {
        switch self {
        case .loading:
            return "Finding the Lumis waiting behind your personal queue."
        case .unavailable:
            return "Your personal queue is still ready and unaffected."
        case .disabled:
            return "Only your personal Lumis will reveal on this necklace."
        case .empty:
            return "There are no extra Lumis behind your personal queue."
        case .ready:
            return "They wait behind your personal queue and begin once it is empty."
        }
    }

    var accessibilityLabel: String {
        "Lumi Reserve. \(title). \(detail)"
    }
}

struct NecklaceTag: Identifiable, Hashable {
    let id: String
    let name: String
    let sku: String
    let themeKey: String
    var isEquipped: Bool
    let rarity: String?
    let includedPackage: String
    var lifecycleStatus: String = "active"
    var availableLumiCount: Int = 0
    var nextLumi: Message? = nil
    var queuedLumis: [Message] = []
    var recentlyRevealed: [RevealedLumi] = []
    var reserve: LumiReserveSummary? = nil
}

struct Package: Identifiable, Hashable {
    let id: String
    let title: String
    let isPremium: Bool
    var isEnabled: Bool
}

struct Message: Identifiable, Hashable, Codable {
    let id: String
    let text: String
    let packageId: String
    let timestamp: Date
    let experience: Experience
}

struct RevealedLumi: Identifiable, Hashable {
    let id: String
    let text: String
    let revealedAt: Date
    let experience: Experience
}

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
    let revealPreset: LumiMessageRevealPreset

    private enum CodingKeys: String, CodingKey {
        case theme
        case animation
        case sound
        case revealPreset
    }

    init(
        theme: LumiPresentationTheme,
        animation: LumiPresentationAnimation,
        sound: LumiPresentationSound?,
        revealPreset: LumiMessageRevealPreset = .wordRise
    ) {
        self.theme = theme
        self.animation = animation
        self.sound = sound
        self.revealPreset = revealPreset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let themeValue = try container.decodeIfPresent(String.self, forKey: .theme)
        let animationValue = try container.decodeIfPresent(String.self, forKey: .animation)
        let soundValue = try container.decodeIfPresent(String.self, forKey: .sound)
        let revealPresetValue = try container.decodeIfPresent(String.self, forKey: .revealPreset)

        theme = LumiPresentationTheme(rawValue: themeValue ?? "") ?? .heart
        animation = LumiPresentationAnimation(rawValue: animationValue ?? "") ?? .breathe
        sound = soundValue.flatMap(LumiPresentationSound.init(rawValue:))
        revealPreset = LumiMessageRevealPreset(rawValue: revealPresetValue ?? "") ?? .wordRise
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

struct UserSettings {
    var soundEnabled: Bool = true
    var hapticsEnabled: Bool = true
}

enum RootRoute {
    case auth
    case postAuthBootstrap
    case noNecklace
    case senderLoadError
    case queueEditor
    case lumiComposer
    case senderHome
    case recipientReveal
}
