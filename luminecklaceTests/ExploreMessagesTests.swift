import XCTest
@testable import luminecklace

@MainActor
final class ExploreMessagesTests: XCTestCase {
    func testDecodesPublishedMessageLibraryResponse() throws {
        let json = """
        {
          "categories": [{
            "key": "encouragement",
            "name": "Encouragement",
            "sortOrder": 3,
            "messageCount": 8
          }],
          "messages": [{
            "id": "00000000-0000-4000-8000-000000000001",
            "text": "I believe in you, especially right now.",
            "category": {"key": "encouragement", "name": "Encouragement"},
            "presentation": {"theme": "heart", "animation": "breathe", "sound": "soft"},
            "isQueued": false,
            "wasRecentlyRevealed": true,
            "lastUsedAt": "2026-07-20T12:00:00Z"
          }],
          "nextCursor": "opaque+cursor/value"
        }
        """

        let response = try JSONDecoder().decode(
            MessageLibraryResponse.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(response.categories.first?.key, "encouragement")
        XCTAssertEqual(response.messages.first?.text, "I believe in you, especially right now.")
        XCTAssertEqual(response.messages.first?.presentation.animation, "breathe")
        XCTAssertEqual(response.messages.first?.wasRecentlyRevealed, true)
        XCTAssertEqual(response.nextCursor, "opaque+cursor/value")
    }

    func testQueryItemsNormalizeAndSafelyEncodeCategorySearchCursorAndNecklace() throws {
        let query = MessageLibraryQuery(
            category: "comfort & care",
            search: "  doing   better & brighter  ",
            cursor: "opaque+/=",
            necklaceId: "necklace-id",
            limit: 100
        )
        var components = URLComponents(string: "https://example.com/api/sender/message-library")!
        components.queryItems = query.queryItems
        let url = try XCTUnwrap(components.url)

        XCTAssertTrue(url.absoluteString.contains("comfort%20%26%20care"))
        XCTAssertTrue(url.absoluteString.contains("doing%20better%20%26%20brighter"))
        XCTAssertEqual(query.queryItems.first(where: { $0.name == "cursor" })?.value, "opaque+/=")
        XCTAssertEqual(query.queryItems.first(where: { $0.name == "limit" })?.value, "50")
        XCTAssertEqual(query.queryItems.first(where: { $0.name == "necklaceId" })?.value, "necklace-id")
    }

    func testLoadingEmptyErrorAndRetryStates() async {
        let service = MockLibraryService()
        service.libraryResults = [
            .failure(TestError.unavailable),
            .success(.empty)
        ]
        let viewModel = makeViewModel(service: service)

        let loadingTask = Task { await viewModel.reload() }
        await Task.yield()
        XCTAssertTrue(viewModel.state == .loading || viewModel.state == .failed("Unavailable"))
        await loadingTask.value
        XCTAssertEqual(viewModel.state, .failed("Unavailable"))

        await viewModel.reload()
        XCTAssertEqual(viewModel.state, .empty)
        XCTAssertEqual(service.libraryCallCount, 2)
    }

    func testPublishedCatalogRendersLoadedAndDeduplicatesPagination() async {
        let template = Self.template()
        let service = MockLibraryService()
        service.libraryResults = [
            .success(Self.response(messages: [template], nextCursor: "next")),
            .success(Self.response(messages: [template], nextCursor: nil))
        ]
        let viewModel = makeViewModel(service: service)

        await viewModel.reload()
        XCTAssertEqual(viewModel.state, .loaded)
        XCTAssertEqual(viewModel.messages.map(\.id), [template.id])

        await viewModel.loadMoreIfNeeded(after: template)
        XCTAssertEqual(viewModel.messages.map(\.id), [template.id])
    }

    func testImmediateEnqueueUsesSelectedNecklaceUpdatesQueueAndConfirmation() async {
        let service = MockLibraryService()
        service.addResult = .success(Self.senderLumi(text: "I believe in you.", position: 4))
        let appState = makeAppState()
        let viewModel = ExploreViewModel(appState: appState, service: service)

        let succeeded = await viewModel.enqueue(Self.template(), destination: .upNext)

        XCTAssertTrue(succeeded)
        XCTAssertEqual(service.addRequests.first?.necklaceId, "necklace-a")
        XCTAssertEqual(service.addRequests.first?.request.destination, .upNext)
        XCTAssertEqual(appState.queueMessages.last?.text, "I believe in you.")
        XCTAssertEqual(viewModel.confirmation, "Added to Up Next as #4")
    }

    func testDoubleTapPreventionAllowsOnlyOneRequest() async {
        let service = MockLibraryService()
        service.addDelay = .milliseconds(80)
        service.addResult = .success(Self.senderLumi(position: 2))
        let viewModel = makeViewModel(service: service)
        let template = Self.template()

        async let first = viewModel.enqueue(template, destination: .upNext)
        try? await Task.sleep(for: .milliseconds(10))
        let second = await viewModel.enqueue(template, destination: .reserve)
        let firstResult = await first

        XCTAssertTrue(firstResult)
        XCTAssertFalse(second)
        XCTAssertEqual(service.addRequests.count, 1)
    }

    func testReserveEnqueueUsesExplicitDestination() async {
        let service = MockLibraryService()
        service.addResult = .success(Self.senderLumi(text: "Just for you.", position: 1))
        let viewModel = makeViewModel(service: service)
        let template = Self.template()

        let succeeded = await viewModel.enqueue(template, destination: .reserve)

        XCTAssertTrue(succeeded)
        XCTAssertEqual(service.addRequests.first?.request.messageId, template.id)
        XCTAssertEqual(service.addRequests.first?.request.destination, .reserve)
        XCTAssertEqual(viewModel.confirmation, "Added to Reserve as #1")
    }

    func testMultipleNecklaceTargetingReloadsUsageAndResetsConfirmation() async {
        let service = MockLibraryService()
        service.libraryResults = [.success(.empty)]
        let appState = makeAppState()
        let viewModel = ExploreViewModel(appState: appState, service: service)

        await viewModel.chooseNecklace("necklace-b")

        XCTAssertEqual(viewModel.selectedNecklace?.id, "necklace-b")
        XCTAssertEqual(service.libraryQueries.last?.necklaceId, "necklace-b")
    }

    func testSuccessfulEnqueueMarksDuplicateIndicator() async {
        let template = Self.template(isQueued: false)
        let service = MockLibraryService()
        service.libraryResults = [.success(Self.response(messages: [template]))]
        service.addResult = .success(Self.senderLumi(position: 3))
        let viewModel = makeViewModel(service: service)

        await viewModel.reload()
        _ = await viewModel.enqueue(template, destination: .reserve)

        XCTAssertEqual(viewModel.messages.first?.isQueued, true)
        XCTAssertEqual(viewModel.messages.first?.queuedSection, .reserve)
    }

    func testStaleSearchResponseCannotReplaceNewerResults() async {
        let old = Self.template(id: "old", text: "Old response")
        let new = Self.template(id: "new", text: "New response")
        let service = SearchRaceLibraryService(old: old, new: new)
        let viewModel = makeViewModel(service: service)

        viewModel.searchText = "old"
        let oldTask = Task { await viewModel.reload() }
        try? await Task.sleep(for: .milliseconds(10))
        viewModel.searchText = "new"
        await viewModel.reload()
        await oldTask.value

        XCTAssertEqual(viewModel.messages.map(\.id), ["new"])
    }

    private func makeViewModel(service: MessageLibraryServing) -> ExploreViewModel {
        ExploreViewModel(appState: makeAppState(), service: service)
    }

    private func makeAppState() -> AppState {
        let appState = AppState()
        appState.ownedNecklaces = [
            Self.necklace(id: "necklace-a", name: "Rose Lumi", isEquipped: true),
            Self.necklace(id: "necklace-b", name: "Gold Lumi", isEquipped: false)
        ]
        return appState
    }

    private static func necklace(id: String, name: String, isEquipped: Bool) -> NecklaceTag {
        NecklaceTag(
            id: id,
            name: name,
            sku: "LUMI-TEST",
            themeKey: "heart",
            isEquipped: isEquipped,
            rarity: nil,
            includedPackage: "Love",
            lifecycleStatus: "active"
        )
    }

    private static func template(
        id: String = "00000000-0000-4000-8000-000000000001",
        text: String = "I believe in you.",
        isQueued: Bool? = false
    ) -> MessageTemplate {
        MessageTemplate(
            id: id,
            text: text,
            category: MessageTemplateCategory(key: "encouragement", name: "Encouragement"),
            presentation: LibraryMessagePresentation(theme: "heart", animation: "breathe", sound: "soft"),
            isQueued: isQueued,
            queuedSection: nil,
            wasRecentlyRevealed: false,
            lastUsedAt: nil
        )
    }

    private static func response(
        messages: [MessageTemplate],
        nextCursor: String? = nil
    ) -> MessageLibraryResponse {
        MessageLibraryResponse(
            categories: [
                MessageCategory(key: "encouragement", name: "Encouragement", sortOrder: 3, messageCount: messages.count)
            ],
            messages: messages,
            nextCursor: nextCursor
        )
    }

    private static func senderLumi(
        text: String = "I believe in you.",
        position: Int
    ) -> QueueCreationResult {
        QueueCreationResult(
            message: Message(
                id: "00000000-0000-4000-8000-000000000099",
                text: text,
                packageId: "library",
                timestamp: Date(),
                experience: Experience(themeKey: "heart", animationKey: "breathe", soundKey: "soft")
            ),
            snapshot: nil,
            queuePosition: position
        )
    }
}

private enum TestError: LocalizedError {
    case unavailable

    var errorDescription: String? { "Unavailable" }
}

@MainActor
private final class MockLibraryService: MessageLibraryServing {
    struct AddCall {
        let necklaceId: String
        let request: AddLibraryMessageRequest
    }

    var libraryResults: [Result<MessageLibraryResponse, Error>] = []
    var addResult: Result<QueueCreationResult, Error> = .failure(TestError.unavailable)
    var addDelay: Duration?
    private(set) var libraryQueries: [MessageLibraryQuery] = []
    private(set) var addRequests: [AddCall] = []

    var libraryCallCount: Int { libraryQueries.count }

    func library(query: MessageLibraryQuery) async throws -> MessageLibraryResponse {
        libraryQueries.append(query)
        return try libraryResults.removeFirst().get()
    }

    func addMessage(
        necklaceId: String,
        request: AddLibraryMessageRequest
    ) async throws -> QueueCreationResult {
        addRequests.append(AddCall(necklaceId: necklaceId, request: request))
        if let addDelay {
            try? await Task.sleep(for: addDelay)
        }
        return try addResult.get()
    }
}

@MainActor
private final class SearchRaceLibraryService: MessageLibraryServing {
    let old: MessageTemplate
    let new: MessageTemplate

    init(old: MessageTemplate, new: MessageTemplate) {
        self.old = old
        self.new = new
    }

    func library(query: MessageLibraryQuery) async throws -> MessageLibraryResponse {
        if query.search == "old" {
            try? await Task.sleep(for: .milliseconds(100))
            return MessageLibraryResponse(categories: [], messages: [old], nextCursor: nil)
        }
        return MessageLibraryResponse(categories: [], messages: [new], nextCursor: nil)
    }

    func addMessage(
        necklaceId: String,
        request: AddLibraryMessageRequest
    ) async throws -> QueueCreationResult {
        throw TestError.unavailable
    }
}

private extension MessageLibraryResponse {
    static let empty = MessageLibraryResponse(categories: [], messages: [], nextCursor: nil)
}
