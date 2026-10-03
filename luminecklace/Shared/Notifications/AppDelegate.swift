import UIKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private weak var notificationManager: PushNotificationManager?
    private var pendingDeviceToken: Data?
    private var pendingNotificationResponse: [AnyHashable: Any]?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func configure(notificationManager: PushNotificationManager) {
        self.notificationManager = notificationManager
        if let pendingDeviceToken {
            self.pendingDeviceToken = nil
            notificationManager.receiveDeviceToken(pendingDeviceToken)
        }
        if let pendingNotificationResponse {
            self.pendingNotificationResponse = nil
            notificationManager.handleNotificationResponse(userInfo: pendingNotificationResponse)
        }
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        guard let notificationManager else {
            pendingDeviceToken = deviceToken
            return
        }
        notificationManager.receiveDeviceToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        notificationManager?.receiveRegistrationFailure()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let shouldPresent = notificationManager?.handleForegroundNotification(
            userInfo: notification.request.content.userInfo
        ) ?? true
        completionHandler(shouldPresent ? [.banner, .list, .sound] : [])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let notificationManager {
            notificationManager.handleNotificationResponse(userInfo: userInfo)
        } else {
            pendingNotificationResponse = userInfo
        }
        completionHandler()
    }
}
