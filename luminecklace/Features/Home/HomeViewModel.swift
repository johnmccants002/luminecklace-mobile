import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
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

    var queuedMessages: [Message] {
        appState.queueMessages
    }

    var reserve: LumiReserveSummary? {
        appState.equippedReserve
    }

    var greetingName: String {
        guard let email = appState.user?.email.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty else {
            return "John"
        }

        let localPart = email.split(separator: "@").first.map(String.init) ?? email
        let pieces = localPart
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        guard let first = pieces.first, !first.isEmpty else {
            return "John"
        }

        return first.prefix(1).uppercased() + first.dropFirst()
    }

    var avatarInitials: String {
        let tokens = greetingName
            .split(whereSeparator: { $0 == " " || $0 == "-" })
            .map(String.init)

        if tokens.count >= 2 {
            return String(tokens[0].prefix(1) + tokens[1].prefix(1)).uppercased()
        }

        return String(greetingName.prefix(2)).uppercased()
    }

    var heroHeadline: String {
        "Here’s what’s waiting in your necklace."
    }

    var necklaceName: String {
        equippedLabel == "No necklace equipped" ? "Lumi Necklace" : equippedLabel
    }

    var canAddLumi: Bool {
        appState.canAddLumiToEquippedNecklace
    }

    func openQueueEditor() {
        appState.openQueueEditor()
    }

    func openLumiComposer() {
        appState.openLumiComposer()
    }

}
