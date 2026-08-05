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
        appState.queueSnapshot?.current
    }

    var queuedMessages: [Message] {
        appState.queueSnapshot?.upNext ?? []
    }

    var reserveMessages: [Message] {
        appState.queueSnapshot?.reserve ?? []
    }

    var reserve: LumiReserveSummary? {
        appState.equippedReserve
    }

    var recentlyRevealed: [RevealedLumi] {
        appState.equippedNecklace?.recentlyRevealed ?? []
    }

    var greetingName: String {
        appState.user?.firstName ?? "there"
    }

    func greeting(for date: Date = Date()) -> String {
        HomeGreeting.greeting(for: date)
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

    var previewRevealState: RecipientRevealState {
        HomePreviewFactory.revealState(
            message: message,
            necklaceName: necklaceName
        )
    }

    func openUpNextEditor() {
        appState.openUpNextEditor()
    }

    func openReserveEditor() {
        appState.openReserveEditor()
    }

    func openLumiComposer() {
        appState.openLumiComposer()
    }

    func revealedSubtitle(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)

        if calendar.isDate(date, inSameDayAs: now) {
            return "Revealed today at \(time)"
        }

        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Revealed yesterday at \(time)"
        }

        let dateAndTime = date.formatted(
            .dateTime
                .month(.abbreviated)
                .day()
                .year()
                .hour()
                .minute()
        )
        return "Revealed \(dateAndTime)"
    }
}

enum HomeGreeting {
    static let pacificTimeZone = TimeZone(identifier: "America/Los_Angeles")!

    static func greeting(
        for date: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> String {
        var pacificCalendar = calendar
        pacificCalendar.timeZone = pacificTimeZone

        switch pacificCalendar.component(.hour, from: date) {
        case 0..<12:
            return "Good morning"
        case 12..<17:
            return "Good afternoon"
        default:
            return "Good evening"
        }
    }
}

enum HomePreviewFactory {
    static func revealState(
        message: Message?,
        necklaceName: String
    ) -> RecipientRevealState {
        guard let message else {
            return .empty
        }

        let presentation = NecklacePresentation(
            theme: LumiPresentationTheme(
                rawValue: message.experience.themeKey.lowercased()
            ) ?? .heart,
            animation: LumiPresentationAnimation(
                rawValue: message.experience.animationKey.lowercased()
            ) ?? .breathe,
            sound: LumiPresentationSound(
                rawValue: message.experience.soundKey.lowercased()
            ),
            revealPreset: .wordRise,
            background: message.experience.backgroundKey,
            font: message.experience.fontKey,
            textSize: message.experience.textSize,
            textAlignment: message.experience.textAlignment,
            textPosition: message.experience.textPosition
        )

        let lumi = ResolvedLumi(
            revealSessionId: "sender-preview-\(message.id)",
            necklaceDisplayName: necklaceName,
            lumiId: message.id,
            text: message.text,
            presentation: presentation
        )

        return .revealed(lumi, confirmationState: .pending)
    }
}
