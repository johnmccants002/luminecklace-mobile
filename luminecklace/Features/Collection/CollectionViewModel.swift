import Combine
import Foundation

@MainActor
final class CollectionViewModel: ObservableObject {
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

    var necklaces: [NecklaceTag] {
        appState.ownedNecklaces
    }

    func equip(_ necklace: NecklaceTag) {
        appState.setEquipped(necklaceId: necklace.id)
    }

    func retryLoad() async {
        await appState.bootstrapSenderFlowAfterAuth()
    }
}
