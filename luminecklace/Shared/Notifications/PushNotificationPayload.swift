import Foundation

enum PushNotificationEventType: Equatable, Sendable {
    case revealed
    case reacted
    case responded
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "lumi.revealed": self = .revealed
        case "lumi.reacted": self = .reacted
        case "lumi.responded": self = .responded
        default: self = .unknown(rawValue)
        }
    }

    var isSupported: Bool {
        if case .unknown = self { return false }
        return true
    }
}

struct PushNotificationPayload: Equatable, Sendable {
    let type: PushNotificationEventType
    let necklaceId: String?
    let lumiId: String?

    init(type: PushNotificationEventType, necklaceId: String?, lumiId: String?) {
        self.type = type
        self.necklaceId = Self.nonEmpty(necklaceId)
        self.lumiId = Self.nonEmpty(lumiId)
    }

    init(userInfo: [AnyHashable: Any]) {
        let rawType = userInfo["type"] as? String ?? ""
        self.init(
            type: PushNotificationEventType(rawValue: rawType),
            necklaceId: userInfo["necklaceId"] as? String,
            lumiId: userInfo["lumiId"] as? String
        )
    }

    var safeDestination: PushNotificationDestination {
        PushNotificationDestination(
            necklaceId: type.isSupported ? necklaceId : nil,
            lumiId: type.isSupported ? lumiId : nil,
            eventType: type
        )
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}

struct PushNotificationDestination: Equatable, Sendable {
    let necklaceId: String?
    let lumiId: String?
    let eventType: PushNotificationEventType
}
