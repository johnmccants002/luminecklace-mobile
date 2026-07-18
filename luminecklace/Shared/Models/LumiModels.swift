import Foundation

enum SubscriptionTier: String, Codable {
    case free = "Free"
    case premium = "Premium"
}

struct User: Identifiable, Codable {
    let id: String
    let email: String
    let subscriptionTier: SubscriptionTier
}

struct ClaimedOrder: Identifiable, Codable, Hashable {
    let id: String
    let externalOrderRef: String?
    let status: String
}

struct Experience: Codable, Hashable {
    let themeKey: String
    let animationKey: String
    let soundKey: String
}

struct NecklaceTag: Identifiable, Hashable {
    let id: String
    let name: String
    let sku: String
    let themeKey: String
    var isEquipped: Bool
    let rarity: String?
    let includedPackage: String
    var hasPublishedMessage: Bool = false
}

struct Package: Identifiable, Hashable {
    let id: String
    let title: String
    let isPremium: Bool
    var isEnabled: Bool
}

struct Message: Identifiable, Hashable {
    let id: String
    let text: String
    let packageId: String
    let timestamp: Date
    let experience: Experience
}

enum RecipientRevealState: Equatable {
    case idle
    case resolving
    case message
    case fallback
    case softError
}

struct UserSettings {
    var soundEnabled: Bool = true
    var hapticsEnabled: Bool = true
}

enum RootRoute {
    case auth
    case postAuthBootstrap
    case noOrderAssist
    case necklaceSelection
    case firstMessageSetup
    case senderHome
    case recipientReveal
}
