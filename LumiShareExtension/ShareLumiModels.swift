import Foundation

nonisolated struct ShareNecklace: Identifiable, Hashable, Decodable {
    let id: String
    let name: String
    let lifecycleStatus: String
    let isPrimary: Bool

    var isEligible: Bool {
        lifecycleStatus == "active" || lifecycleStatus == "pending_sender_setup"
    }

    init(id: String, name: String, lifecycleStatus: String, isPrimary: Bool) {
        self.id = id
        self.name = name
        self.lifecycleStatus = lifecycleStatus
        self.isPrimary = isPrimary
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case necklaceId
        case name
        case label
        case lifecycleStatus
        case isPrimary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decode(String.self, forKey: .necklaceId)
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .label)
            ?? "Lumi Necklace"
        lifecycleStatus = try container.decodeIfPresent(String.self, forKey: .lifecycleStatus)
            ?? "active"
        isPrimary = try container.decodeIfPresent(Bool.self, forKey: .isPrimary) ?? false
    }
}

nonisolated struct ShareNecklaceListResponse: Decodable {
    let necklaces: [ShareNecklace]

    private enum CodingKeys: String, CodingKey {
        case necklaces
        case items
        case data
        case result
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let direct = (try? container.decode([ShareNecklace].self, forKey: .necklaces))
            ?? (try? container.decode([ShareNecklace].self, forKey: .items))
            ?? (try? container.decode([ShareNecklace].self, forKey: .data))
            ?? (try? container.decode([ShareNecklace].self, forKey: .result)) {
            necklaces = direct
            return
        }
        if let nested = (try? container.decode(ShareNecklaceListResponse.self, forKey: .data))
            ?? (try? container.decode(ShareNecklaceListResponse.self, forKey: .result)) {
            necklaces = nested.necklaces
            return
        }
        if let array = try? decoder.singleValueContainer().decode([ShareNecklace].self) {
            necklaces = array
            return
        }
        necklaces = []
    }
}

nonisolated enum ShareQueueDestination: String, Codable, CaseIterable, Identifiable {
    case upNext = "up_next"
    case reserve

    var id: String { rawValue }
    var title: String { self == .upNext ? "Up Next" : "Reserve" }
}

nonisolated struct CreateSharedLumiRequest: Encodable, Equatable {
    let clientRequestId: UUID
    let url: String
    let text: String?
    let destination: ShareQueueDestination
}

nonisolated struct CreatedSharedLumi: Decodable, Equatable {
    let id: String
    let text: String
    let queuePosition: Int?
    let attachment: LumiLinkAttachment?

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case queuePosition
        case attachment
    }

    init(
        id: String,
        text: String,
        queuePosition: Int?,
        attachment: LumiLinkAttachment?
    ) {
        self.id = id
        self.text = text
        self.queuePosition = queuePosition
        self.attachment = attachment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        queuePosition = try container.decodeIfPresent(Int.self, forKey: .queuePosition)
        attachment = try? container.decode(LumiLinkAttachment.self, forKey: .attachment)
    }
}

nonisolated struct CreateSharedLumiResponse: Decodable, Equatable {
    let lumi: CreatedSharedLumi
    let idempotentReplay: Bool

    private enum CodingKeys: String, CodingKey {
        case lumi
        case idempotentReplay
    }

    init(lumi: CreatedSharedLumi, idempotentReplay: Bool) {
        self.lumi = lumi
        self.idempotentReplay = idempotentReplay
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lumi = try container.decode(CreatedSharedLumi.self, forKey: .lumi)
        idempotentReplay = try container.decodeIfPresent(Bool.self, forKey: .idempotentReplay) ?? false
    }
}

nonisolated struct ExtractedShareLink: Equatable {
    let url: URL
    let provider: LumiLinkProvider
    let host: String
    let contentKind: String

    var displayProviderName: String {
        provider.displayName
    }

    var displayContentKind: String {
        guard provider == .instagram else { return host }
        return switch contentKind {
        case "reel": "Reel"
        case "post": "Post"
        case "story": "Story"
        case "profile": "Profile"
        default: "Instagram link"
        }
    }
}

enum ShareLumiState: Equatable {
    case extracting
    case loadingNecklaces
    case ready
    case submitting
    case success
    case authenticationRequired
    case noEligibleNecklaces
    case unsupportedShare
    case failure(message: String)
}
