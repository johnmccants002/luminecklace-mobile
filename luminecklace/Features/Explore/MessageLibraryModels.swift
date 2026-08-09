import Foundation

nonisolated struct MessageLibraryResponse: Codable, Equatable, Sendable {
    let categories: [MessageCategory]
    let messages: [MessageTemplate]
    let nextCursor: String?
}

nonisolated struct MessageCategory: Codable, Identifiable, Equatable, Sendable {
    let key: String
    let name: String
    let sortOrder: Int
    let messageCount: Int

    var id: String { key }
}

nonisolated struct MessageTemplate: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String?
    let text: String
    let secondaryText: String?
    let mood: String?
    let durationSeconds: Int?
    let experiencePresetKey: LumiExperiencePresetKey?
    let category: MessageTemplateCategory
    let presentation: LibraryMessagePresentation
    let isQueued: Bool?
    let queuedSection: QueueSection?
    let wasRecentlyRevealed: Bool?
    let lastUsedAt: String?

    init(
        id: String,
        title: String? = nil,
        text: String,
        secondaryText: String? = nil,
        mood: String? = nil,
        durationSeconds: Int? = nil,
        experiencePresetKey: LumiExperiencePresetKey? = nil,
        category: MessageTemplateCategory,
        presentation: LibraryMessagePresentation,
        isQueued: Bool? = nil,
        queuedSection: QueueSection? = nil,
        wasRecentlyRevealed: Bool? = nil,
        lastUsedAt: String? = nil
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.secondaryText = secondaryText
        self.mood = mood
        self.durationSeconds = durationSeconds
        self.experiencePresetKey = experiencePresetKey
        self.category = category
        self.presentation = presentation
        self.isQueued = isQueued
        self.queuedSection = queuedSection
        self.wasRecentlyRevealed = wasRecentlyRevealed
        self.lastUsedAt = lastUsedAt
    }
}

nonisolated struct MessageTemplateCategory: Codable, Equatable, Sendable {
    let key: String
    let name: String
}

nonisolated struct LibraryMessagePresentation: Codable, Equatable, Sendable {
    let theme: String
    let animation: String
    let sound: String
    let background: LumiBackgroundKey
    let font: LumiFontKey
    let textSize: LumiTextSizeKey
    let textAlignment: LumiTextAlignmentKey
    let textPosition: LumiTextPositionKey

    init(
        theme: String,
        animation: String,
        sound: String,
        background: LumiBackgroundKey? = nil,
        font: LumiFontKey = .serif,
        textSize: LumiTextSizeKey = .medium,
        textAlignment: LumiTextAlignmentKey = .center,
        textPosition: LumiTextPositionKey = .center
    ) {
        self.theme = theme
        self.animation = animation
        self.sound = sound
        self.background = background
            ?? LumiBackgroundKey(rawValue: theme.lowercased())
            ?? .heart
        self.font = font
        self.textSize = textSize
        self.textAlignment = textAlignment
        self.textPosition = textPosition
    }

    private enum CodingKeys: String, CodingKey {
        case theme
        case animation
        case sound
        case background
        case font
        case textSize
        case textAlignment
        case textPosition
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decodeIfPresent(String.self, forKey: .theme) ?? "heart"
        animation = try container.decodeIfPresent(String.self, forKey: .animation) ?? "breathe"
        sound = try container.decodeIfPresent(String.self, forKey: .sound) ?? "soft"
        background = try container.decodeIfPresent(LumiBackgroundKey.self, forKey: .background)
            ?? LumiBackgroundKey(rawValue: theme.lowercased())
            ?? .heart
        font = try container.decodeIfPresent(LumiFontKey.self, forKey: .font) ?? .serif
        textSize = try container.decodeIfPresent(LumiTextSizeKey.self, forKey: .textSize) ?? .medium
        textAlignment = try container.decodeIfPresent(LumiTextAlignmentKey.self, forKey: .textAlignment) ?? .center
        textPosition = try container.decodeIfPresent(LumiTextPositionKey.self, forKey: .textPosition) ?? .center
    }
}

nonisolated struct AddLibraryMessageRequest: Codable, Equatable, Sendable {
    let messageId: String
    let destination: QueueSection
    let customization: LibraryTextCustomization?

    init(
        messageId: String,
        destination: QueueSection,
        customization: LibraryTextCustomization? = nil
    ) {
        self.messageId = messageId
        self.destination = destination
        self.customization = customization
    }
}

nonisolated struct LibraryTextCustomization: Codable, Equatable, Sendable {
    let primaryText: String?
    let secondaryText: String?
}

nonisolated struct SenderLumiResponse: Codable, Equatable, Sendable {
    let lumi: SenderLumi
}

nonisolated struct SenderLumi: Codable, Equatable, Sendable {
    let id: String
    let text: String
    let experiencePresetKey: LumiExperiencePresetKey?
    let secondaryText: String?
    let queuePosition: Int
    let presentation: LibraryMessagePresentation
}

nonisolated struct MessageLibraryQuery: Equatable, Sendable {
    let category: String?
    let search: String?
    let cursor: String?
    let necklaceId: String?
    let limit: Int

    init(
        category: String? = nil,
        search: String? = nil,
        cursor: String? = nil,
        necklaceId: String? = nil,
        limit: Int = 20
    ) {
        self.category = category
        self.search = search
        self.cursor = cursor
        self.necklaceId = necklaceId
        self.limit = min(max(limit, 1), 50)
    }

    var queryItems: [URLQueryItem] {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let category, !category.isEmpty {
            items.append(URLQueryItem(name: "category", value: category))
        }
        let normalizedSearch = search?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        if let normalizedSearch, !normalizedSearch.isEmpty {
            items.append(URLQueryItem(name: "search", value: String(normalizedSearch.prefix(80))))
        }
        if let cursor, !cursor.isEmpty {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }
        if let necklaceId, !necklaceId.isEmpty {
            items.append(URLQueryItem(name: "necklaceId", value: necklaceId))
        }
        return items
    }
}
