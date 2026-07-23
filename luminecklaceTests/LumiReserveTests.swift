import XCTest
@testable import luminecklace

@MainActor
final class LumiReserveTests: XCTestCase {
    private let service = SenderService()

    func testDecodesFullReserveSummary() throws {
        let necklace = try XCTUnwrap(service.mapNecklace(from: Fixtures.necklace()))
        let reserve = try XCTUnwrap(necklace.reserve)

        XCTAssertTrue(reserve.enabled)
        XCTAssertEqual(reserve.approvedCount, 18)
        XCTAssertEqual(reserve.totalCount, 18)
        XCTAssertEqual(reserve.categories.count, 5)
        XCTAssertEqual(reserve.categories.first?.key, "affection")
        XCTAssertEqual(reserve.categories.first?.approvedCount, 4)
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

        XCTAssertEqual(LumiReserveViewState(summary: summary), .disabled(summary))
        XCTAssertEqual(LumiReserveViewState(summary: summary).statusLabel, "Disabled")
        XCTAssertEqual(
            LumiReserveViewState(summary: summary).message,
            "Lumi Reserve is turned off for this necklace."
        )
    }

    func testZeroApprovedReserveState() throws {
        let summary = try decodeSummary(enabled: true, approvedCount: 0)

        XCTAssertEqual(LumiReserveViewState(summary: summary), .empty(summary))
        XCTAssertEqual(
            LumiReserveViewState(summary: summary).message,
            "No Reserve Lumis are approved yet."
        )
    }

    func testPartiallyApprovedReserveState() throws {
        let summary = try decodeSummary(enabled: true, approvedCount: 12)

        XCTAssertEqual(LumiReserveViewState(summary: summary), .partiallyApproved(summary))
        XCTAssertEqual(
            LumiReserveViewState(summary: summary).message,
            "12 of 18 Reserve Lumis approved."
        )
    }

    func testAllReserveMessagesApprovedState() throws {
        let summary = try decodeSummary(enabled: true, approvedCount: 18)

        XCTAssertEqual(LumiReserveViewState(summary: summary), .enabled(summary))
        XCTAssertEqual(
            LumiReserveViewState(summary: summary).message,
            "Lumi Reserve is ready when your personal queue runs out."
        )
    }

    func testKnownAndUnknownCategoryLabels() {
        XCTAssertEqual(
            LumiReserveCategorySummary(key: "encouragement", approvedCount: 4, totalCount: 4).displayName,
            "Encouragement"
        )
        XCTAssertEqual(
            LumiReserveCategorySummary(key: "quiet_support", approvedCount: 1, totalCount: 2).displayName,
            "Quiet Support"
        )
    }

    func testAccessibilityLabelsIncludeStatusAndCounts() throws {
        let summary = try decodeSummary(enabled: true, approvedCount: 12)
        let category = LumiReserveCategorySummary(
            key: "reassurance",
            approvedCount: 2,
            totalCount: 3
        )

        XCTAssertEqual(LumiReserveViewState(summary: summary).statusLabel, "Enabled")
        XCTAssertEqual(summary.approvalAccessibilityLabel, "12 of 18 Lumi Reserve messages approved")
        XCTAssertEqual(category.approvalAccessibilityLabel, "Reassurance, 2 of 3 approved")
    }

    func testLoadingAndUnavailableStates() {
        XCTAssertEqual(LumiReserveViewState.loading.statusLabel, "Loading")
        XCTAssertEqual(LumiReserveViewState.loading.message, "Loading Reserve details.")
        XCTAssertEqual(LumiReserveViewState.unavailable.statusLabel, "Unavailable")
        XCTAssertEqual(
            LumiReserveViewState.unavailable.message,
            "Reserve details are unavailable right now."
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
        XCTAssertEqual(necklace.queuedLumis.map(\.id), ["personal-1", "personal-2"])
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

        XCTAssertEqual(necklace.queuedLumis.map(\.id), ["first", "second", "third"])
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
        ]
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
        return payload
    }

    static func reserve(
        enabled: Bool = true,
        approvedCount: Int = 18
    ) -> [String: Any] {
        [
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
}
