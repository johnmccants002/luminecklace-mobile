import Combine
import Foundation

enum PushPreferenceKind {
    case reveals
    case reactions
    case responses
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var soundEnabled: Bool
    @Published var hapticsEnabled: Bool
    @Published private(set) var permissionState: PushNotificationPermissionState
    @Published private(set) var pushPreferences: PushPreferences?
    @Published private(set) var isLoadingNotifications = false
    @Published private(set) var isSavingPreferences = false
    @Published private(set) var notificationError: String?
    @Published private(set) var isSigningOut = false

    private let appState: AppState
    private let pushService: PushDeviceServicing
    private var cancellables = Set<AnyCancellable>()

    init(
        appState: AppState,
        pushService: PushDeviceServicing? = nil
    ) {
        self.appState = appState
        self.pushService = pushService ?? PushDeviceService()
        self.soundEnabled = appState.settings.soundEnabled
        self.hapticsEnabled = appState.settings.hapticsEnabled
        self.permissionState = appState.pushNotificationManager.permissionState

        appState.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        appState.pushNotificationManager.$permissionState
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self else { return }
                permissionState = state
                if state == .enabled {
                    Task { await self.loadNotifications() }
                } else {
                    pushPreferences = nil
                }
            }
            .store(in: &cancellables)
    }

    var userEmail: String {
        appState.user?.email ?? "guest@lumi.app"
    }

    var subscriptionTitle: String {
        appState.user?.subscriptionTier.rawValue ?? SubscriptionTier.free.rawValue
    }

    func applySettings() {
        appState.settings.soundEnabled = soundEnabled
        appState.settings.hapticsEnabled = hapticsEnabled
    }

    func loadNotifications() async {
        guard !isLoadingNotifications else { return }
        isLoadingNotifications = true
        notificationError = nil
        await appState.pushNotificationManager.refreshPermissionState()

        guard permissionState == .enabled else {
            pushPreferences = nil
            isLoadingNotifications = false
            return
        }

        do {
            pushPreferences = try await pushService.fetchPreferences()
        } catch {
            notificationError = "Notification preferences couldn’t be loaded."
        }
        isLoadingNotifications = false
    }

    func enableNotifications() {
        appState.pushNotificationManager.presentEducationFromSettings()
    }

    func openSystemSettings() {
        appState.pushNotificationManager.openSystemSettings()
    }

    func setPreference(_ kind: PushPreferenceKind, enabled: Bool) async {
        guard !isSavingPreferences, var optimistic = pushPreferences else { return }
        let previous = optimistic
        let update: PushPreferencesUpdate

        switch kind {
        case .reveals:
            optimistic.revealsEnabled = enabled
            update = PushPreferencesUpdate(revealsEnabled: enabled)
        case .reactions:
            optimistic.reactionsEnabled = enabled
            update = PushPreferencesUpdate(reactionsEnabled: enabled)
        case .responses:
            optimistic.responsesEnabled = enabled
            update = PushPreferencesUpdate(responsesEnabled: enabled)
        }

        notificationError = nil
        pushPreferences = optimistic
        isSavingPreferences = true
        do {
            pushPreferences = try await pushService.updatePreferences(update)
        } catch {
            pushPreferences = previous
            notificationError = "That preference couldn’t be saved. Please try again."
        }
        isSavingPreferences = false
    }

    func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        await appState.signOut()
        pushPreferences = nil
        isSigningOut = false
    }
}
