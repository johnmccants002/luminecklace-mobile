import Combine
import Foundation

@MainActor
final class ExploreViewModel: ObservableObject {
    enum CatalogState: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case failed(String)
    }

    @Published var categories: [MessageCategory] = []
    @Published var messages: [MessageTemplate] = []
    @Published var selectedCategoryKey: String?
    @Published var searchText = ""
    @Published private(set) var state: CatalogState = .idle
    @Published private(set) var loadingMore = false
    @Published private(set) var enqueuingMessageIDs: Set<String> = []
    @Published private(set) var confirmation: String?
    @Published private(set) var actionError: String?

    private let appState: AppState
    private let service: MessageLibraryServing
    private var nextCursor: String?
    private var requestGeneration = 0
    private var loadedNecklaceId: String?

    init(
        appState: AppState,
        service: MessageLibraryServing? = nil
    ) {
        self.appState = appState
        self.service = service ?? MessageLibraryService()
    }

    var necklaces: [NecklaceTag] { appState.ownedNecklaces }
    var selectedNecklace: NecklaceTag? { appState.equippedNecklace }
    var canEnqueue: Bool { appState.canAddLumiToEquippedNecklace }
    var hasMore: Bool { nextCursor != nil }

    func loadIfNeeded() async {
        let necklaceId = selectedNecklace?.id
        guard state == .idle || loadedNecklaceId != necklaceId else { return }
        await reload()
    }

    func reload() async {
        requestGeneration += 1
        let generation = requestGeneration
        let necklaceId = selectedNecklace?.id
        loadedNecklaceId = necklaceId
        state = .loading
        nextCursor = nil
        actionError = nil

        do {
            let response = try await service.library(
                query: MessageLibraryQuery(
                    category: selectedCategoryKey,
                    search: searchText,
                    necklaceId: necklaceId
                )
            )
            guard generation == requestGeneration else { return }
            categories = response.categories.sorted { $0.sortOrder < $1.sortOrder }
            messages = unique(response.messages)
            nextCursor = response.nextCursor
            state = messages.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            return
        } catch {
            guard generation == requestGeneration else { return }
            state = .failed(error.localizedDescription)
        }
    }

    func selectCategory(_ key: String?) async {
        guard selectedCategoryKey != key else { return }
        selectedCategoryKey = key
        await reload()
    }

    func searchChanged() async {
        guard state != .idle else { return }
        do {
            try await Task.sleep(for: .milliseconds(350))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        await reload()
    }

    func loadMoreIfNeeded(after message: MessageTemplate) async {
        guard message.id == messages.last?.id,
              let cursor = nextCursor,
              !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        let generation = requestGeneration

        do {
            let response = try await service.library(
                query: MessageLibraryQuery(
                    category: selectedCategoryKey,
                    search: searchText,
                    cursor: cursor,
                    necklaceId: selectedNecklace?.id
                )
            )
            guard generation == requestGeneration else { return }
            categories = response.categories.sorted { $0.sortOrder < $1.sortOrder }
            messages = unique(messages + response.messages)
            nextCursor = response.nextCursor
            state = messages.isEmpty ? .empty : .loaded
        } catch {
            guard generation == requestGeneration else { return }
            actionError = "More messages couldn’t be loaded. Please try again."
        }
    }

    func chooseNecklace(_ necklaceId: String) async {
        guard selectedNecklace?.id != necklaceId else { return }
        appState.chooseNecklace(necklaceId)
        enqueuingMessageIDs = []
        confirmation = nil
        await reload()
    }

    @discardableResult
    func enqueue(
        _ template: MessageTemplate,
        destination: QueueSection,
        customization: LibraryTextCustomization? = nil
    ) async -> Bool {
        guard let necklace = selectedNecklace, canEnqueue else {
            actionError = "Choose an active Lumi necklace before adding a message."
            return false
        }
        guard !enqueuingMessageIDs.contains(template.id) else { return false }

        enqueuingMessageIDs.insert(template.id)
        actionError = nil
        confirmation = nil
        defer { enqueuingMessageIDs.remove(template.id) }

        do {
            let result = try await service.addMessage(
                necklaceId: necklace.id,
                request: AddLibraryMessageRequest(
                    messageId: template.id,
                    destination: destination,
                    customization: customization
                )
            )
            guard selectedNecklace?.id == necklace.id else { return false }
            appState.applyLibraryLumi(
                result,
                destination: destination,
                toNecklaceId: necklace.id
            )
            markQueued(template.id, section: destination)
            let position = result.queuePosition.map { " as #\($0)" } ?? ""
            confirmation = "Added to \(destination.displayName)\(position)"
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    func clearConfirmation() {
        confirmation = nil
    }

    func clearActionError() {
        actionError = nil
    }

    private func unique(_ values: [MessageTemplate]) -> [MessageTemplate] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }
    }

    private func markQueued(_ id: String, section: QueueSection) {
        messages = messages.map { message in
            guard message.id == id else { return message }
            return MessageTemplate(
                id: message.id,
                title: message.title,
                text: message.text,
                secondaryText: message.secondaryText,
                mood: message.mood,
                durationSeconds: message.durationSeconds,
                experiencePresetKey: message.experiencePresetKey,
                category: message.category,
                presentation: message.presentation,
                isQueued: true,
                queuedSection: section,
                wasRecentlyRevealed: message.wasRecentlyRevealed,
                lastUsedAt: message.lastUsedAt
            )
        }
    }
}
