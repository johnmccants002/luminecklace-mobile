import Combine
import Foundation
import UIKit
import UserNotifications

protocol NotificationAuthorizationProviding {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func clearBadge() async
}

struct SystemNotificationAuthorizationProvider: NotificationAuthorizationProviding {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    func clearBadge() async {
        try? await center.setBadgeCount(0)
    }
}

@MainActor
protocol RemoteNotificationRegistering {
    func registerForRemoteNotifications()
}

@MainActor
struct SystemRemoteNotificationRegistrar: RemoteNotificationRegistering {
    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }
}

@MainActor
protocol ApplicationSettingsOpening {
    func openNotificationSettings()
}

@MainActor
struct SystemApplicationSettingsOpener: ApplicationSettingsOpening {
    func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

protocol APNSEnvironmentProviding {
    func currentEnvironment() -> APNSEnvironment
}

struct SignedAppAPNSEnvironmentProvider: APNSEnvironmentProviding {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func currentEnvironment() -> APNSEnvironment {
        let configuredEnvironment = bundle.object(
            forInfoDictionaryKey: "LUMIAPNSEnvironmentFallback"
        ) as? String
        return configuredEnvironment?.lowercased() == "production"
            ? .production
            : .sandbox
    }
}

struct PushAppMetadata: Equatable, Sendable {
    static let fullAppBundleId = "luminecklace.luminecklace"

    let bundleId: String
    let appVersion: String
    let deviceModel: String

    static var current: PushAppMetadata {
        PushAppMetadata(
            bundleId: Bundle.main.bundleIdentifier ?? fullAppBundleId,
            appVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "1.0",
            deviceModel: UIDevice.current.model
        )
    }
}

@MainActor
final class PushNotificationManager: ObservableObject {
    @Published private(set) var permissionState: PushNotificationPermissionState = .notRequested
    @Published var isEducationPresented = false
    @Published private(set) var pendingDestination: PushNotificationDestination?
    @Published private(set) var lastRegistrationError: String?

    var foregroundEventHandler: ((PushNotificationPayload) -> Void)?
    var notificationResponseHandler: (() -> Void)?
    var shouldPresentForegroundNotification: (() -> Bool)?

    private struct RegistrationFingerprint: Codable, Equatable {
        let userId: String
        let deviceToken: String
        let environment: APNSEnvironment
        let bundleId: String
        let appVersion: String
    }

    private struct RegistrationCache: Codable {
        let fingerprint: RegistrationFingerprint
        let registeredAt: Date
    }

    private let deviceService: PushDeviceServicing
    private let authorizationProvider: NotificationAuthorizationProviding
    private let remoteRegistrar: RemoteNotificationRegistering
    private let settingsOpener: ApplicationSettingsOpening
    private let environmentProvider: APNSEnvironmentProviding
    private let metadata: PushAppMetadata
    private let defaults: UserDefaults
    private let now: () -> Date
    private let tokenKey = "lumi_push_device_token_v1"
    private let registrationCacheKey = "lumi_push_registration_v1"
    private let educationDismissedKey = "lumi_push_education_dismissed_v1"
    private let registrationRefreshInterval: TimeInterval = 24 * 60 * 60

    private var authenticatedUserId: String?
    private var isReconciling = false
    private var inFlightFingerprint: RegistrationFingerprint?
    private var reconcileAfterCurrent = false
    private var registrationSuspended = false
    private var reconciliationWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        deviceService: PushDeviceServicing? = nil,
        authorizationProvider: NotificationAuthorizationProviding? = nil,
        remoteRegistrar: RemoteNotificationRegistering? = nil,
        settingsOpener: ApplicationSettingsOpening? = nil,
        environmentProvider: APNSEnvironmentProviding? = nil,
        metadata: PushAppMetadata? = nil,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.deviceService = deviceService ?? PushDeviceService()
        self.authorizationProvider = authorizationProvider ?? SystemNotificationAuthorizationProvider()
        self.remoteRegistrar = remoteRegistrar ?? SystemRemoteNotificationRegistrar()
        self.settingsOpener = settingsOpener ?? SystemApplicationSettingsOpener()
        self.environmentProvider = environmentProvider ?? SignedAppAPNSEnvironmentProvider()
        self.metadata = metadata ?? .current
        self.defaults = defaults
        self.now = now
    }

    // The coordinator owns no actor-isolated teardown work. Keeping destruction
    // nonisolated also makes short-lived injected instances safe in XCTest.
    nonisolated deinit {}

    var currentDeviceToken: String? {
        defaults.string(forKey: tokenKey)
    }

    func start() async {
        await refreshPermissionState()
        if permissionState == .enabled {
            remoteRegistrar.registerForRemoteNotifications()
        }
    }

    func applicationDidBecomeActive() async {
        await refreshPermissionState()
        if permissionState == .enabled {
            remoteRegistrar.registerForRemoteNotifications()
            await reconcileRegistration()
        }
    }

    func refreshPermissionState() async {
        permissionState = PushNotificationPermissionState(
            authorizationStatus: await authorizationProvider.authorizationStatus()
        )
    }

    func considerContextualPrompt(isRecipientExperienceActive: Bool) async {
        await refreshPermissionState()
        guard authenticatedUserId != nil,
              !isRecipientExperienceActive,
              permissionState == .notRequested,
              !defaults.bool(forKey: educationDismissedKey) else { return }
        isEducationPresented = true
    }

    func presentEducationFromSettings() {
        guard permissionState != .denied else {
            settingsOpener.openNotificationSettings()
            return
        }
        isEducationPresented = true
    }

    func dismissEducation() {
        defaults.set(true, forKey: educationDismissedKey)
        isEducationPresented = false
    }

    func requestAuthorizationAfterEducation() async {
        isEducationPresented = false
        await refreshPermissionState()

        if permissionState == .denied {
            settingsOpener.openNotificationSettings()
            return
        }

        if permissionState == .enabled {
            remoteRegistrar.registerForRemoteNotifications()
            return
        }

        do {
            _ = try await authorizationProvider.requestAuthorization(
                options: [.alert, .sound, .badge]
            )
        } catch {
            // Permission and registration failures never block the signed-in app.
        }
        await refreshPermissionState()
        if permissionState == .enabled {
            remoteRegistrar.registerForRemoteNotifications()
        }
    }

    func openSystemSettings() {
        settingsOpener.openNotificationSettings()
    }

    func updateAuthenticatedUser(id: String?) {
        guard authenticatedUserId != id else { return }
        authenticatedUserId = id
        lastRegistrationError = nil
        guard id != nil else { return }
        registrationSuspended = false
        Task { await reconcileRegistration() }
    }

    func receiveDeviceToken(_ data: Data) {
        let normalized = Self.lowercaseHexToken(from: data)
        guard !normalized.isEmpty else { return }
        defaults.set(normalized, forKey: tokenKey)
        lastRegistrationError = nil
        Task { await reconcileRegistration() }
    }

    func receiveRegistrationFailure() {
        lastRegistrationError = "This device couldn’t register for notifications. We’ll retry automatically."
    }

    func reconcileRegistration() async {
        guard !registrationSuspended,
              permissionState == .enabled,
              let userId = authenticatedUserId,
              let token = currentDeviceToken,
              !token.isEmpty else { return }

        let environment = environmentProvider.currentEnvironment()
        let fingerprint = RegistrationFingerprint(
            userId: userId,
            deviceToken: token,
            environment: environment,
            bundleId: metadata.bundleId,
            appVersion: metadata.appVersion
        )

        if let cache = registrationCache,
           cache.fingerprint == fingerprint,
           now().timeIntervalSince(cache.registeredAt) < registrationRefreshInterval {
            return
        }

        if isReconciling {
            if inFlightFingerprint != fingerprint {
                reconcileAfterCurrent = true
            }
            return
        }

        isReconciling = true
        inFlightFingerprint = fingerprint

        do {
            try await deviceService.register(
                PushDeviceRegistration(
                    deviceToken: token,
                    environment: environment,
                    bundleId: metadata.bundleId,
                    appVersion: metadata.appVersion,
                    deviceModel: metadata.deviceModel
                )
            )
            registrationCache = RegistrationCache(
                fingerprint: fingerprint,
                registeredAt: now()
            )
            lastRegistrationError = nil
        } catch {
            lastRegistrationError = "Notifications will reconnect automatically."
        }

        let shouldReconcileAgain = reconcileAfterCurrent
        reconcileAfterCurrent = false
        isReconciling = false
        inFlightFingerprint = nil

        let waiters = reconciliationWaiters
        reconciliationWaiters.removeAll()
        waiters.forEach { $0.resume() }

        if shouldReconcileAgain, !registrationSuspended {
            await reconcileRegistration()
        }
    }

    func disableCurrentDevice() async {
        registrationSuspended = true
        if isReconciling {
            await withCheckedContinuation { continuation in
                reconciliationWaiters.append(continuation)
            }
        }

        guard authenticatedUserId != nil,
              let token = currentDeviceToken,
              !token.isEmpty else { return }
        do {
            try await deviceService.disable(
                PushDeviceDisableRequest(
                    deviceToken: token,
                    environment: environmentProvider.currentEnvironment(),
                    bundleId: metadata.bundleId
                )
            )
        } catch {
            // Sign-out remains best-effort and must not trap the user.
        }
    }

    func clearAuthenticatedState() {
        authenticatedUserId = nil
        registrationSuspended = true
        reconcileAfterCurrent = false
        registrationCache = nil
        pendingDestination = nil
        lastRegistrationError = nil
    }

    func handleNotificationResponse(userInfo: [AnyHashable: Any]) {
        pendingDestination = PushNotificationPayload(userInfo: userInfo).safeDestination
        notificationResponseHandler?()
    }

    @discardableResult
    func handleForegroundNotification(userInfo: [AnyHashable: Any]) -> Bool {
        let payload = PushNotificationPayload(userInfo: userInfo)
        if payload.type.isSupported {
            foregroundEventHandler?(payload)
        }
        return shouldPresentForegroundNotification?() ?? true
    }

    func consumePendingDestination() -> PushNotificationDestination? {
        defer { pendingDestination = nil }
        return pendingDestination
    }

    func clearPendingDestination() {
        pendingDestination = nil
    }

    func clearBadge() async {
        await authorizationProvider.clearBadge()
    }

    nonisolated static func lowercaseHexToken(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private var registrationCache: RegistrationCache? {
        get {
            guard let data = defaults.data(forKey: registrationCacheKey) else { return nil }
            return try? JSONDecoder().decode(RegistrationCache.self, from: data)
        }
        set {
            guard let newValue,
                  let data = try? JSONEncoder().encode(newValue) else {
                defaults.removeObject(forKey: registrationCacheKey)
                return
            }
            defaults.set(data, forKey: registrationCacheKey)
        }
    }
}
