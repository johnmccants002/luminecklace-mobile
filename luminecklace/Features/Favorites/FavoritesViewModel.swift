import Combine
import Foundation

@MainActor
final class FavoritesViewModel: ObservableObject {
    @Published var selectedPackageId: String = "all"

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

    var packageFilters: [String] {
        ["all"] + Array(Set(appState.favorites.map(\.packageId))).sorted()
    }

    var filteredFavorites: [Message] {
        if selectedPackageId == "all" {
            return appState.favorites
        }
        return appState.favorites.filter { $0.packageId == selectedPackageId }
    }

    func remove(_ message: Message) {
        appState.removeFavorite(message)
    }
}
