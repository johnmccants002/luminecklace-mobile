import XCTest
@testable import luminecklace

@MainActor
final class LumiReserveTests: XCTestCase {
    private let service = SenderService()

    func testDecodesFullReserveSummary() throws {
        let necklace = try XCTUnwrap(service.mapNecklace(from: Fixtures.necklace()))
        let reserve = try XCTUnwrap(necklace.reserve)

        XCTAssertTrue(reserve.enabled)
        XCTAssertNil(reserve.lumiCount)
    }

    func testMissingReserveFieldIsUnavailable() throws {
        let necklace = try XCTUnwrap(service.mapNecklace(from: Fixtures.necklace(reserve: nil)))

        XCTAssertNil(necklace.reserve)
        XCTAssertEqual(LumiReserveViewState(summary: necklace.reserve), .unavailable)
    }

    func testMalformedReserveFieldIsUnavailable() throws {
        let malformed: [String: Any] = [
            "enabled": true,
            "approvedCount": 19,
            "totalCount": 18,
            "categories": []
        ]
        let necklace = try XCTUnwrap(service.mapNecklace(from: Fixtures.necklace(reserve: malformed)))

        XCTAssertNil(necklace.reserve)
    }

    func testDisabledReserveState() throws {
        let summary = try decodeSummary(enabled: false, approvedCount: 18)
        let state = LumiReserveViewState(summary: summary)

        XCTAssertEqual(state, .disabled(summary))
        XCTAssertEqual(state.title, "Reserve is off")
        XCTAssertEqual(state.detail, "Only your personal Lumis will reveal on this necklace.")
    }

    func testEmptyReserveQueueState() throws {
        let summary = try decodeSummary(enabled: true, approvedCount: 0)
        let state = LumiReserveViewState(summary: summary)

        XCTAssertEqual(state, .empty(summary))
        XCTAssertEqual(state.title, "No Reserve Lumis")
        XCTAssertEqual(state.detail, "There are no extra Lumis behind your personal queue.")
    }

    func testLegacyApprovalCountIsNotDisplayedAsQueueCount() throws {
        let summary = try decodeSummary(enabled: true, approvedCount: 12)
        let state = LumiReserveViewState(summary: summary)

        XCTAssertEqual(state, .ready(summary))
        XCTAssertNil(summary.lumiCount)
        XCTAssertEqual(state.title, "Lumi Reserve ready")
        XCTAssertEqual(state.detail, "They wait behind your personal queue and begin once it is empty.")
    }

    func testAllApprovedTemplatesDoNotBecomeFixedReserveCount() throws {
        let summary = try decodeSummary(enabled: true, approvedCount: 18)
        let state = LumiReserveViewState(summary: summary)

        XCTAssertEqual(state, .ready(summary))
        XCTAssertNil(summary.lumiCount)
        XCTAssertEqual(state.title, "Lumi Reserve ready")
    }

    func testExplicitAvailableCountIsDisplayed() throws {
        let summary = try XCTUnwrap(
            service.mapReserveSummary(
                from: Fixtures.reserve(
                    enabled: true,
                    approvedCount: 18,
                    availableCount: 2
                )
            )
        )

        XCTAssertEqual(summary.lumiCount, 2)
        XCTAssertEqual(LumiReserveViewState(summary: summary).title, "2 Lumis in Reserve")
    }

    func testExplicitZeroAvailableCountDisplaysNone() throws {
        let summary = try XCTUnwrap(
            service.mapReserveSummary(
                from: Fixtures.reserve(
                    enabled: true,
                    approvedCount: 18,
                    availableCount: 0
                )
            )
        )

        XCTAssertEqual(summary.lumiCount, 0)
        XCTAssertEqual(LumiReserveViewState(summary: summary), .empty(summary))
        XCTAssertEqual(LumiReserveViewState(summary: summary).title, "No Reserve Lumis")
    }

    func testAccessibilityLabelUsesQueueLanguage() throws {
        let summary = try decodeSummary(enabled: true, approvedCount: 12)
        let state = LumiReserveViewState(summary: summary)

        XCTAssertEqual(
            state.accessibilityLabel,
            "Lumi Reserve. Lumi Reserve ready. They wait behind your personal queue and begin once it is empty."
        )
    }

    func testLoadingAndUnavailableStates() {
        XCTAssertEqual(LumiReserveViewState.loading.title, "Checking your Reserve")
        XCTAssertEqual(
            LumiReserveViewState.loading.detail,
            "Finding the Lumis waiting behind your personal queue."
        )
        XCTAssertEqual(LumiReserveViewState.unavailable.title, "Reserve unavailable")
        XCTAssertEqual(
            LumiReserveViewState.unavailable.detail,
            "Your personal queue is still ready and unaffected."
        )
    }

    func testReserveCountsAndContentStayOutOfPersonalQueue() throws {
        let personalQueue: [[String: Any]] = [
            Fixtures.lumi(id: "personal-1", text: "First personal Lumi"),
            Fixtures.lumi(id: "personal-2", text: "Second personal Lumi")
        ]
        var reserve = Fixtures.reserve()
        reserve["messages"] = [
            ["id": "reserve-1", "text": "This must not enter the personal queue"]
        ]

        let necklace = try XCTUnwrap(
            service.mapNecklace(
                from: Fixtures.necklace(
                    reserve: reserve,
                    availableLumiCount: 2,
                    queue: personalQueue
                )
            )
        )

        XCTAssertEqual(necklace.availableLumiCount, 2)
        XCTAssertEqual(necklace.queueSnapshot?.current?.id, "personal-1")
        XCTAssertEqual(necklace.queuedLumis.map(\.id), ["personal-2"])
        XCTAssertEqual(necklace.nextLumi?.id, "personal-1")
        XCTAssertFalse(necklace.queuedLumis.contains { $0.id == "reserve-1" })
    }

    func testPersonalQueueOrderRemainsBackendOrder() throws {
        let queue = [
            Fixtures.lumi(id: "first", text: "First"),
            Fixtures.lumi(id: "second", text: "Second"),
            Fixtures.lumi(id: "third", text: "Third")
        ]
        let necklace = try XCTUnwrap(
            service.mapNecklace(
                from: Fixtures.necklace(
                    reserve: Fixtures.reserve(),
                    availableLumiCount: 3,
                    queue: queue
                )
            )
        )

        XCTAssertEqual(necklace.queueSnapshot?.current?.id, "first")
        XCTAssertEqual(necklace.queuedLumis.map(\.id), ["second", "third"])
        XCTAssertTrue(necklace.queueSnapshot?.reserve.isEmpty == true)
    }

    func testDecodesRecentlyRevealedHistoryInBackendOrder() throws {
        let necklace = try XCTUnwrap(
            service.mapNecklace(
                from: Fixtures.necklace(
                    recentlyRevealed: [
                        Fixtures.revealedLumi(
                            id: "revealed-2",
                            text: "Most recent",
                            revealedAt: "2026-07-25T18:42:11.123Z"
                        ),
                        Fixtures.revealedLumi(
                            id: "revealed-1",
                            text: "Earlier",
                            revealedAt: "2026-07-24T08:12:00Z"
                        )
                    ]
                )
            )
        )

        XCTAssertEqual(necklace.recentlyRevealed.map(\.id), ["revealed-2", "revealed-1"])
        XCTAssertEqual(necklace.recentlyRevealed.map(\.text), ["Most recent", "Earlier"])
        XCTAssertLessThan(
            necklace.recentlyRevealed[1].revealedAt,
            necklace.recentlyRevealed[0].revealedAt
        )
    }

    func testMissingRecentlyRevealedFieldDecodesAsEmpty() throws {
        let necklace = try XCTUnwrap(service.mapNecklace(from: Fixtures.necklace()))

        XCTAssertTrue(necklace.recentlyRevealed.isEmpty)
    }

    func testMalformedRevealIsDroppedWithoutBreakingNecklace() throws {
        let necklace = try XCTUnwrap(
            service.mapNecklace(
                from: Fixtures.necklace(
                    recentlyRevealed: [
                        Fixtures.revealedLumi(
                            id: "valid",
                            text: "Still visible",
                            revealedAt: "2026-07-25T18:42:11Z"
                        ),
                        Fixtures.revealedLumi(
                            id: "invalid",
                            text: "Bad timestamp",
                            revealedAt: "not-a-date"
                        )
                    ]
                )
            )
        )

        XCTAssertEqual(necklace.recentlyRevealed.map(\.id), ["valid"])
    }

    func testRecentlyRevealedContentStaysOutOfPersonalQueue() throws {
        let necklace = try XCTUnwrap(
            service.mapNecklace(
                from: Fixtures.necklace(
                    queue: [Fixtures.lumi(id: "personal", text: "Still waiting")],
                    recentlyRevealed: [
                        Fixtures.revealedLumi(
                            id: "revealed",
                            text: "Already seen",
                            revealedAt: "2026-07-25T18:42:11Z"
                        )
                    ]
                )
            )
        )

        XCTAssertEqual(necklace.queueSnapshot?.current?.id, "personal")
        XCTAssertTrue(necklace.queuedLumis.isEmpty)
        XCTAssertEqual(necklace.recentlyRevealed.map(\.id), ["revealed"])
    }

    private func decodeSummary(enabled: Bool, approvedCount: Int) throws -> LumiReserveSummary {
        try XCTUnwrap(
            service.mapReserveSummary(
                from: Fixtures.reserve(enabled: enabled, approvedCount: approvedCount)
            )
        )
    }
}

private enum Fixtures {
    static func necklace(
        reserve: [String: Any]? = Fixtures.reserve(),
        availableLumiCount: Int = 2,
        queue: [[String: Any]] = [
            lumi(id: "personal-1", text: "First personal Lumi"),
            lumi(id: "personal-2", text: "Second personal Lumi")
        ],
        recentlyRevealed: [[String: Any]]? = nil
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "id": "f5bea6df-cdf4-4561-b570-b20ccf74f45c",
            "name": "My Lumi",
            "sku": "HEART-01",
            "themeKey": "heart",
            "lifecycleStatus": "active",
            "isPrimary": true,
            "availableLumiCount": availableLumiCount,
            "queue": queue
        ]
        payload["reserve"] = reserve
        payload["recentlyRevealed"] = recentlyRevealed
        return payload
    }

    static func reserve(
        enabled: Bool = true,
        approvedCount: Int = 18,
        availableCount: Int? = nil
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "enabled": enabled,
            "approvedCount": approvedCount,
            "totalCount": 18,
            "categories": [
                category("affection", approved: min(approvedCount, 4), total: 4),
                category("comfort", approved: approvedCount >= 8 ? 4 : 0, total: 4),
                category("encouragement", approved: approvedCount >= 12 ? 4 : 0, total: 4),
                category("presence", approved: approvedCount >= 15 ? 3 : 0, total: 3),
                category("reassurance", approved: approvedCount == 18 ? 3 : 0, total: 3)
            ]
        ]
        payload["availableCount"] = availableCount
        return payload
    }

    static func category(_ key: String, approved: Int, total: Int) -> [String: Any] {
        [
            "key": key,
            "approvedCount": approved,
            "totalCount": total
        ]
    }

    static func lumi(id: String, text: String) -> [String: Any] {
        [
            "id": id,
            "text": text,
            "presentation": [
                "theme": "heart",
                "animation": "breathe",
                "sound": "soft"
            ]
        ]
    }

    static func revealedLumi(id: String, text: String, revealedAt: String) -> [String: Any] {
        var payload = lumi(id: id, text: text)
        payload["revealedAt"] = revealedAt
        return payload
    }
}
