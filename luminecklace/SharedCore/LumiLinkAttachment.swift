import Darwin
import Foundation

nonisolated enum LumiLinkProvider: String, Codable, Hashable, Sendable {
    case instagram
    case website

    var displayName: String {
        switch self {
        case .instagram: "Instagram"
        case .website: "Website"
        }
    }
}

nonisolated struct ValidatedLumiLink: Hashable, Sendable {
    let url: URL
    let provider: LumiLinkProvider
    let host: String
    let contentKind: String
}

/// The shared trust boundary for links accepted by the Share Extension and
/// opened by recipient experiences. Validation is deliberately local: it does
/// not resolve DNS, follow redirects, or download destination content.
nonisolated enum LumiLinkURLPolicy {
    static let maximumURLLength = 4_096

    private static let instagramHosts: Set<String> = [
        "instagram.com",
        "www.instagram.com"
    ]

    private static let localOrReservedSuffixes: Set<String> = [
        "arpa",
        "example",
        "home",
        "internal",
        "invalid",
        "lan",
        "local",
        "localdomain",
        "localhost",
        "test"
    ]

    static func validatedLink(_ url: URL) -> ValidatedLumiLink? {
        guard url.absoluteString.utf8.count <= maximumURLLength,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              let firstNormalizedURL = components.url,
              var normalizedComponents = URLComponents(
                  url: firstNormalizedURL,
                  resolvingAgainstBaseURL: false
              ),
              let parsedHost = firstNormalizedURL.host?.lowercased() else {
            return nil
        }

        let host = parsedHost.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !host.isEmpty, isPublicHost(host) else { return nil }

        normalizedComponents.scheme = "https"
        normalizedComponents.host = isIPv6Literal(host) ? "[\(host)]" : host
        guard let normalizedURL = normalizedComponents.url,
              normalizedURL.absoluteString.utf8.count <= maximumURLLength else {
            return nil
        }

        if instagramHosts.contains(host) {
            return ValidatedLumiLink(
                url: normalizedURL,
                provider: .instagram,
                host: host,
                contentKind: instagramContentKind(path: normalizedComponents.path)
            )
        }

        return ValidatedLumiLink(
            url: normalizedURL,
            provider: .website,
            host: host,
            contentKind: "link"
        )
    }

    private static func instagramContentKind(path: String) -> String {
        let segments = path.split(separator: "/").map { $0.lowercased() }
        switch segments.first {
        case "reel", "reels": return "reel"
        case "p", "tv": return "post"
        case "stories": return "story"
        case .some: return segments.count == 1 ? "profile" : "link"
        case .none: return "link"
        }
    }

    private static func isPublicHost(_ host: String) -> Bool {
        if isIPv4Literal(host) {
            return isPublicIPv4(host)
        }
        if isIPv6Literal(host) {
            return isPublicIPv6(host)
        }

        guard host.utf8.count <= 253 else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2,
              let suffix = labels.last,
              !localOrReservedSuffixes.contains(String(suffix)) else {
            return false
        }
        if labels.allSatisfy({ label in label.utf8.allSatisfy({ (48...57).contains($0) }) }) {
            return false // Reject legacy abbreviated IPv4 spellings such as 127.1.
        }

        return labels.allSatisfy { label in
            guard !label.isEmpty,
                  label.utf8.count <= 63,
                  label.first != "-",
                  label.last != "-" else {
                return false
            }
            return label.utf8.allSatisfy { byte in
                (byte >= 97 && byte <= 122)
                    || (byte >= 48 && byte <= 57)
                    || byte == 45
            }
        }
    }

    private static func isIPv4Literal(_ host: String) -> Bool {
        var address = in_addr()
        return host.withCString { inet_pton(AF_INET, $0, &address) } == 1
    }

    private static func isIPv6Literal(_ host: String) -> Bool {
        var address = in6_addr()
        return host.withCString { inet_pton(AF_INET6, $0, &address) } == 1
    }

    private static func isPublicIPv4(_ host: String) -> Bool {
        var address = in_addr()
        guard host.withCString({ inet_pton(AF_INET, $0, &address) }) == 1 else {
            return false
        }
        let bytes = withUnsafeBytes(of: &address) { Array($0) }
        let first = bytes[0]
        let second = bytes[1]
        let third = bytes[2]

        if first == 0 || first == 10 || first == 127 || first >= 224 { return false }
        if first == 100 && (64...127).contains(second) { return false }
        if first == 169 && second == 254 { return false }
        if first == 172 && (16...31).contains(second) { return false }
        if first == 192 && second == 168 { return false }
        if first == 192 && second == 0 && third == 0 { return false }
        if first == 192 && second == 0 && third == 2 { return false }
        if first == 192 && second == 88 && third == 99 { return false }
        if first == 198 && (second == 18 || second == 19) { return false }
        if first == 198 && second == 51 && third == 100 { return false }
        if first == 203 && second == 0 && third == 113 { return false }
        return true
    }

    private static func isPublicIPv6(_ host: String) -> Bool {
        var address = in6_addr()
        guard host.withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else {
            return false
        }
        let bytes = withUnsafeBytes(of: &address) { Array($0) }

        if bytes.allSatisfy({ $0 == 0 }) { return false } // Unspecified.
        if bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes.last == 1 { return false } // Loopback.
        if bytes[0] == 0xff { return false } // Multicast.
        if bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80 { return false } // Link-local.
        if (bytes[0] & 0xfe) == 0xfc { return false } // Unique local.
        if bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8 {
            return false // Documentation.
        }
        if bytes[0] == 0x01 && bytes.dropFirst().prefix(7).allSatisfy({ $0 == 0 }) {
            return false // Discard-only 100::/64.
        }
        if bytes.prefix(10).allSatisfy({ $0 == 0 }) && bytes[10] == 0xff && bytes[11] == 0xff {
            return false // IPv4-mapped addresses are validated only in IPv4 form.
        }
        return true
    }
}

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

    private var validatedLink: ValidatedLumiLink? {
        guard type.caseInsensitiveCompare("link") == .orderedSame,
              openMode.caseInsensitiveCompare("external") == .orderedSame,
              let url = URL(string: urlString),
              let link = LumiLinkURLPolicy.validatedLink(url),
              provider.caseInsensitiveCompare(link.provider.rawValue) == .orderedSame else {
            return nil
        }
        return link
    }

    var destinationURL: URL? {
        validatedLink?.url
    }

    var isSupportedLink: Bool {
        validatedLink != nil
    }

    var isSupportedInstagramLink: Bool {
        validatedLink?.provider == .instagram
    }

    var isSupportedWebsiteLink: Bool {
        validatedLink?.provider == .website
    }

    var supportedDestinationURL: URL? {
        validatedLink?.url
    }

    var displayHost: String? {
        validatedLink?.host
    }

    var displayProviderName: String {
        validatedLink?.provider.displayName ?? "Link"
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

    var badgeTitle: String? {
        guard let link = validatedLink else { return nil }
        switch link.provider {
        case .instagram:
            return "Instagram · \(displayContentKind)"
        case .website:
            return "Website · \(link.host)"
        }
    }

    var recipientDetail: String? {
        guard let link = validatedLink else { return nil }
        switch link.provider {
        case .instagram: return "Instagram \(displayContentKind)"
        case .website: return link.host
        }
    }

    var attachmentAccessibilityLabel: String? {
        guard let link = validatedLink else { return nil }
        switch link.provider {
        case .instagram: return "Instagram \(displayContentKind) attachment"
        case .website: return "Website attachment from \(link.host)"
        }
    }

    var openAccessibilityHint: String {
        switch validatedLink?.provider {
        case .instagram: "Opens Instagram or your web browser"
        case .website: "Opens the website in your web browser"
        case nil: "Opens the link in your web browser"
        }
    }

    var safeCallToActionLabel: String {
        let trimmed = ctaLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 80 else {
            return validatedLink?.provider == .website ? "Open website" : "View on Instagram"
        }
        return trimmed
    }
}
