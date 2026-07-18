//
//  ClipHandoffStore.swift
//  lumiclip
//

import Foundation

struct ClipHandoffPayload {
    let necklaceName: String
    let tagId: String
    let basePackageIDs: [String]
    let completedAt: Date
}

enum ClipHandoffConfig {
    static let appGroupID = "group.luminecklace.shared"
    static let keyPrefix = "handoff."
}

final class ClipHandoffStore {
    private let defaults: UserDefaults?
    private let isoFormatter = ISO8601DateFormatter()

    init(appGroupID: String = ClipHandoffConfig.appGroupID) {
        defaults = UserDefaults(suiteName: appGroupID)
    }

    @discardableResult
    func createHandoff(payload: ClipHandoffPayload) -> String {
        let handoffID = UUID().uuidString.lowercased()
        let key = ClipHandoffConfig.keyPrefix + handoffID

        let value: [String: Any] = [
            "necklaceName": payload.necklaceName,
            "tagId": payload.tagId,
            "basePackageIDs": payload.basePackageIDs,
            "completedAt": isoFormatter.string(from: payload.completedAt)
        ]

        defaults?.set(value, forKey: key)
        return handoffID
    }
}
