import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var soundEnabled: Bool
    @Published var hapticsEnabled: Bool

    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        self.soundEnabled = appState.settings.soundEnabled
        self.hapticsEnabled = appState.settings.hapticsEnabled

        appState.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
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

    func signOut() {
        appState.signOut()
    }
}
