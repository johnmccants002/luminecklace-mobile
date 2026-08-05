import Foundation
import UniformTypeIdentifiers

nonisolated protocol ShareItemExtracting: Sendable {
    func extract(from items: [NSExtensionItem]) async throws -> ExtractedInstagramLink?
}

nonisolated enum ShareItemExtractorError: Error {
    case cancelled
}

nonisolated final class ShareItemExtractor: ShareItemExtracting, @unchecked Sendable {
    func extract(from items: [NSExtensionItem]) async throws -> ExtractedInstagramLink? {
        try Task.checkCancellation()
        let providers = items.flatMap { $0.attachments ?? [] }

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            try Task.checkCancellation()
            if let value = try? await load(provider, type: UTType.url.identifier),
               let url = Self.url(from: value),
               let link = Self.validatedLink(url) {
                return link
            }
        }

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            try Task.checkCancellation()
            if let value = try? await load(provider, type: UTType.plainText.identifier),
               let text = Self.text(from: value),
               let link = Self.firstInstagramLink(in: text) {
                return link
            }
        }

        for item in items {
            try Task.checkCancellation()
            if let text = item.attributedContentText?.string,
               let link = Self.firstInstagramLink(in: text) {
                return link
            }
        }
        return nil
    }

    private func load(_ provider: NSItemProvider, type: String) async throws -> NSSecureCoding? {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<NSSecureCoding?, Error>) in
                provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: item)
                    }
                }
        }
    }

    private static func url(from value: NSSecureCoding?) -> URL? {
        switch value {
        case let url as URL: url
        case let url as NSURL: url as URL
        case let string as String: URL(string: string)
        case let string as NSString: URL(string: string as String)
        default: nil
        }
    }

    private static func text(from value: NSSecureCoding?) -> String? {
        switch value {
        case let string as String: string
        case let string as NSString: string as String
        case let url as URL: url.absoluteString
        case let url as NSURL: (url as URL).absoluteString
        default: nil
        }
    }

    static func firstInstagramLink(in text: String) -> ExtractedInstagramLink? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in detector.matches(in: text, options: [], range: range) {
            if let url = match.url, let link = validatedLink(url) {
                return link
            }
        }
        return nil
    }

    static func validatedLink(_ url: URL) -> ExtractedInstagramLink? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              let host = components.host?.lowercased(),
              host == "instagram.com" || host == "www.instagram.com",
              let normalizedURL = components.url else {
            return nil
        }

        let segments = components.path.split(separator: "/").map { $0.lowercased() }
        let contentKind: String
        switch segments.first {
        case "reel", "reels": contentKind = "reel"
        case "p", "tv": contentKind = "post"
        case "stories": contentKind = "story"
        case .some: contentKind = segments.count == 1 ? "profile" : "link"
        case .none: contentKind = "link"
        }
        return ExtractedInstagramLink(url: normalizedURL, contentKind: contentKind)
    }
}
