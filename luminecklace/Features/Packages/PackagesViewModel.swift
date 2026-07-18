import Combine
import Foundation

@MainActor
final class PackagesViewModel: ObservableObject {
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        appState.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var packages: [Package] { appState.packages }
    var subscription: SubscriptionTier { appState.user?.subscriptionTier ?? .free }

    func toggle(_ package: Package, isOn: Bool) {
        appState.togglePackage(package.id, isEnabled: isOn)
    }
}
