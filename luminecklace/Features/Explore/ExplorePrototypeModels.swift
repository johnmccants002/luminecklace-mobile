import SwiftUI

struct ExploreLumi: Identifiable, Hashable {
    let id: String
    let title: String
    let message: String
    let secondaryText: String?
    let category: String
    let mood: String
    let durationSeconds: Int
    let presetKey: LumiExperiencePresetKey

    var content: LumiExperienceContent {
        LumiExperienceContent(
            presetKey: presetKey,
            primaryText: message,
            secondaryText: secondaryText
        )
    }

    var displayMessage: String {
        [message, secondaryText].compactMap { $0 }.joined(separator: "\n\n")
    }

    var foregroundColor: Color {
        presetKey == .proudOfYou ? Color(red: 0.13, green: 0.15, blue: 0.24) : .white
    }

    var animationName: String {
        switch presetKey {
        case .classicWordRise, .goldenHour: "Soft Word Reveal"
        case .midnight: "Starlight Drift"
        case .proudOfYou: "Bold Stagger"
        case .playful: "Playful Bounce"
        case .calm: "Slow Fade"
        case .memory: "Cinematic Entrance"
        case .timedSurprise: "Timed Reveal"
        }
    }

    var backgroundName: String {
        switch presetKey {
        case .classicWordRise: "Classic Lumi"
        case .goldenHour: "Golden Hour"
        case .midnight: "Midnight Sky"
        case .proudOfYou: "Bright Day"
        case .playful: "Color Pop"
        case .calm: "Quiet Tide"
        case .memory: "Soft Focus"
        case .timedSurprise: "Velvet Glow"
        }
    }

    init(template: MessageTemplate) {
        id = template.id
        title = template.title ?? template.text
        message = template.text
        secondaryText = template.secondaryText
        category = template.category.name
        mood = template.mood ?? "Thoughtful"
        durationSeconds = template.durationSeconds ?? 8
        presetKey = template.experiencePresetKey ?? .classicWordRise
    }

    init(
        id: String,
        title: String,
        message: String,
        secondaryText: String?,
        category: String,
        mood: String,
        durationSeconds: Int,
        presetKey: LumiExperiencePresetKey
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.secondaryText = secondaryText
        self.category = category
        self.mood = mood
        self.durationSeconds = durationSeconds
        self.presetKey = presetKey
    }
}

extension ExploreLumi {
    static let prototypes: [ExploreLumi] = [
        .init(id: "golden-hour", title: "Golden Hour", message: "Just a reminder that someone is thinking about you.", secondaryText: nil, category: "Thinking of You", mood: "Warm", durationSeconds: 8, presetKey: .goldenHour),
        .init(id: "midnight", title: "Midnight", message: "You crossed my mind tonight.", secondaryText: nil, category: "Romantic", mood: "Intimate", durationSeconds: 7, presetKey: .midnight),
        .init(id: "proud-of-you", title: "Proud of You", message: "Look how far you've come.", secondaryText: nil, category: "Encouragement", mood: "Uplifting", durationSeconds: 6, presetKey: .proudOfYou),
        .init(id: "playful", title: "Favorite Person", message: "Okay but seriously… you're my favorite person.", secondaryText: nil, category: "Just Because", mood: "Playful", durationSeconds: 6, presetKey: .playful),
        .init(id: "calm", title: "Breathe", message: "You don't have to figure everything out tonight.", secondaryText: nil, category: "Comfort", mood: "Calm", durationSeconds: 9, presetKey: .calm),
        .init(id: "memory", title: "That Night", message: "Remember that night we couldn't stop laughing?", secondaryText: nil, category: "Memories", mood: "Nostalgic", durationSeconds: 8, presetKey: .memory),
        .init(id: "surprise", title: "Something to Tell You", message: "I have something to tell you…", secondaryText: "I'm really glad you're in my life.", category: "Just Because", mood: "Heartfelt", durationSeconds: 10, presetKey: .timedSurprise)
    ]
}
