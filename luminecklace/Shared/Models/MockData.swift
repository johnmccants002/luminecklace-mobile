import Foundation

enum MockData {
    static let defaultPackages: [Package] = [
        Package(id: "love", title: "Love", isPremium: false, isEnabled: true),
        Package(id: "motivation", title: "Motivation", isPremium: false, isEnabled: true),
        Package(id: "calm", title: "Calm", isPremium: false, isEnabled: true),
        Package(id: "midnight", title: "Midnight Letters", isPremium: true, isEnabled: false),
        Package(id: "manifest", title: "Manifesting", isPremium: true, isEnabled: false)
    ]

    static let initialNecklaces: [NecklaceTag] = [
        NecklaceTag(
            id: UUID().uuidString,
            name: "Rose Halo Necklace",
            sku: "LUMI-RH-101",
            themeKey: "rose",
            isEquipped: true,
            rarity: "Rare",
            includedPackage: "Love"
        ),
        NecklaceTag(
            id: UUID().uuidString,
            name: "Crimson Arc Necklace",
            sku: "LUMI-CA-210",
            themeKey: "crimson",
            isEquipped: false,
            rarity: nil,
            includedPackage: "Motivation"
        )
    ]

    static let activationReward = NecklaceTag(
        id: UUID().uuidString,
        name: "Lumi Heart Necklace",
        sku: "LUMI-HRT-001",
        themeKey: "heart",
        isEquipped: true,
        rarity: "Legendary",
        includedPackage: "Love"
    )
}
