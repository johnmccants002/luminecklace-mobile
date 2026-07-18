import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var burstTrigger = 0

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

    var equippedLabel: String {
        appState.equippedNecklace?.name ?? "No necklace equipped"
    }

    var enabledPackageIDs: [String] {
        appState.packages
            .filter(\.isEnabled)
            .map(\.id)
    }

    var showRetapHint: Bool {
        appState.showRetapHint
    }

    var message: Message? {
        appState.currentMessage
    }

    func simulateTap() async {
        isLoading = true
        await appState.fetchMessage()
        isLoading = false
    }

    func shuffle() async {
        await simulateTap()
    }

    func saveCurrentMessage() {
        guard let msg = appState.currentMessage else { return }
        appState.saveFavorite(msg)
        burstTrigger += 1
    }
}
