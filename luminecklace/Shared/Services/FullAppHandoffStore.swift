import Foundation

struct FullAppHandoffPayload {
    let necklaceName: String
    let tagId: String
    let basePackageIDs: [String]
    let completedAt: Date
}

enum FullAppHandoffConfig {
    static let appGroupID = "group.luminecklace.shared"
    static let keyPrefix = "handoff."
    static let ttlSeconds: TimeInterval = 600
}

final class FullAppHandoffStore {
    private let defaults: UserDefaults?
    private let isoFormatter = ISO8601DateFormatter()

    init(appGroupID: String = FullAppHandoffConfig.appGroupID) {
        defaults = UserDefaults(suiteName: appGroupID)
    }

    func consume(handoffID: String) -> FullAppHandoffPayload? {
        let key = FullAppHandoffConfig.keyPrefix + handoffID
        guard let raw = defaults?.dictionary(forKey: key) else { return nil }
        defaults?.removeObject(forKey: key)

        guard
            let necklaceName = raw["necklaceName"] as? String,
            let tagId = raw["tagId"] as? String,
            let basePackageIDs = raw["basePackageIDs"] as? [String],
            let completedAtString = raw["completedAt"] as? String,
            let completedAt = isoFormatter.date(from: completedAtString)
        else {
            return nil
        }

        let isExpired = Date().timeIntervalSince(completedAt) > FullAppHandoffConfig.ttlSeconds
        if isExpired { return nil }

        return FullAppHandoffPayload(
            necklaceName: necklaceName,
            tagId: tagId,
            basePackageIDs: basePackageIDs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() },
            completedAt: completedAt
        )
    }
}
