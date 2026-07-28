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
    let text: String
    let category: MessageTemplateCategory
    let presentation: LibraryMessagePresentation
    let isQueued: Bool?
    let wasRecentlyRevealed: Bool?
    let lastUsedAt: String?
}

nonisolated struct MessageTemplateCategory: Codable, Equatable, Sendable {
    let key: String
    let name: String
}

nonisolated struct LibraryMessagePresentation: Codable, Equatable, Sendable {
    let theme: String
    let animation: String
    let sound: String
}

nonisolated struct AddLibraryMessageRequest: Codable, Equatable, Sendable {
    let messageId: String
    let text: String?

    init(messageId: String, text: String? = nil) {
        self.messageId = messageId
        self.text = text
    }
}

nonisolated struct SenderLumiResponse: Codable, Equatable, Sendable {
    let lumi: SenderLumi
}

nonisolated struct SenderLumi: Codable, Equatable, Sendable {
    let id: String
    let text: String
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
