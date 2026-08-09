import Foundation
import UserNotifications

enum PushNotificationPermissionState: Equatable {
    case notRequested
    case enabled
    case denied

    init(authorizationStatus: UNAuthorizationStatus) {
        switch authorizationStatus {
        case .notDetermined:
            self = .notRequested
        case .authorized, .provisional, .ephemeral:
            self = .enabled
        case .denied:
            self = .denied
        @unknown default:
            self = .denied
        }
    }

    var title: String {
        switch self {
        case .notRequested:
            return "Not requested"
        case .enabled:
            return "Enabled"
        case .denied:
            return "Disabled in iOS Settings"
        }
    }
}
