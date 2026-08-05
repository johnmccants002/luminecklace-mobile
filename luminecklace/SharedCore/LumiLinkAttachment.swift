import Foundation

/// A forward-compatible link attachment returned with a Lumi.
///
/// String-backed fields intentionally avoid making a new backend value fail the
/// entire Lumi response. Callers should use `supportedDestinationURL` before
/// presenting an action.
nonisolated struct LumiLinkAttachment: Codable, Hashable, Sendable {
    let type: String
    let provider: String
    let contentKind: String
    let urlString: String
    let host: String
    let ctaLabel: String
    let openMode: String

    private enum CodingKeys: String, CodingKey {
        case type
        case provider
        case contentKind
        case url
        case host
        case ctaLabel
        case openMode
    }

    init(
        type: String,
        provider: String,
        contentKind: String,
        urlString: String,
        host: String,
        ctaLabel: String,
        openMode: String
    ) {
        self.type = type
        self.provider = provider
        self.contentKind = contentKind
        self.urlString = urlString
        self.host = host
        self.ctaLabel = ctaLabel
        self.openMode = openMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        provider = try container.decode(String.self, forKey: .provider)
        contentKind = try container.decodeIfPresent(String.self, forKey: .contentKind) ?? "link"
        urlString = try container.decode(String.self, forKey: .url)
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
        ctaLabel = try container.decodeIfPresent(String.self, forKey: .ctaLabel) ?? ""
        openMode = try container.decode(String.self, forKey: .openMode)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(provider, forKey: .provider)
        try container.encode(contentKind, forKey: .contentKind)
        try container.encode(urlString, forKey: .url)
        try container.encode(host, forKey: .host)
        try container.encode(ctaLabel, forKey: .ctaLabel)
        try container.encode(openMode, forKey: .openMode)
    }

    var destinationURL: URL? {
        guard let components = URLComponents(string: urlString),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              let normalizedHost = components.host?.lowercased(),
              Self.supportedInstagramHosts.contains(normalizedHost) else {
            return nil
        }
        return components.url
    }

    var isSupportedInstagramLink: Bool {
        type.caseInsensitiveCompare("link") == .orderedSame
            && provider.caseInsensitiveCompare("instagram") == .orderedSame
            && openMode.caseInsensitiveCompare("external") == .orderedSame
            && destinationURL != nil
    }

    var supportedDestinationURL: URL? {
        isSupportedInstagramLink ? destinationURL : nil
    }

    var displayContentKind: String {
        switch contentKind.lowercased() {
        case "reel": "Reel"
        case "post": "Post"
        case "story": "Story"
        case "profile": "Profile"
        default: "Instagram link"
        }
    }

    var safeCallToActionLabel: String {
        let trimmed = ctaLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80 else {
            return "View on Instagram"
        }
        return trimmed
    }

    private static let supportedInstagramHosts: Set<String> = [
        "instagram.com",
        "www.instagram.com"
    ]
}
