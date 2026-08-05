import XCTest
@testable import luminecklace

@MainActor
final class QueueSnapshotTests: XCTestCase {
    private let service = SenderService()

    func testContinuousSequenceKeepsCurrentUpNextAndReserveOrder() throws {
        let snapshot = try QueueSnapshot(
            necklaceId: "necklace",
            revision: 7,
            current: message("current"),
            upNext: [message("up-1"), message("up-2")],
            reserve: [message("reserve-1"), message("reserve-2")]
        )

        XCTAssertEqual(
            snapshot.continuousSequence.map(\.id),
            ["current", "up-1", "up-2", "reserve-1", "reserve-2"]
        )
    }

    func testSnapshotRejectsMessageInMultipleSections() {
        XCTAssertThrowsError(
            try QueueSnapshot(
                necklaceId: "necklace",
                revision: 1,
                current: message("same"),
                upNext: [message("same")],
                reserve: []
            )
        )
    }

    func testServiceDecodesSnapshotWithoutSortingServerArrays() throws {
        let payload: [String: Any] = [
            "queue": [
                "revision": 9,
                "current": lumi("current"),
                "upNext": [lumi("up-2"), lumi("up-1")],
                "reserve": [lumi("reserve-2"), lumi("reserve-1")]
            ]
        ]

        let snapshot = try XCTUnwrap(
            service.mapQueueSnapshot(
                from: payload,
                necklaceId: "necklace",
                fallbackThemeKey: "heart"
            )
        )

        XCTAssertEqual(snapshot.current?.id, "current")
        XCTAssertEqual(snapshot.upNext.map(\.id), ["up-2", "up-1"])
        XCTAssertEqual(snapshot.reserve.map(\.id), ["reserve-2", "reserve-1"])
    }

    func testServiceRejectsDuplicateSnapshotMembership() {
        let payload: [String: Any] = [
            "queue": [
                "revision": 2,
                "current": lumi("current"),
                "upNext": [lumi("duplicate")],
                "reserve": [lumi("duplicate")]
            ]
        ]

        XCTAssertNil(
            service.mapQueueSnapshot(
                from: payload,
                necklaceId: "necklace",
                fallbackThemeKey: "heart"
            )
        )
    }

    func testMutationPayloadsDescribeExactQueueActions() {
        XCTAssertEqual(
            QueueMutation.reorder(
                section: .reserve,
                orderedMessageIDs: ["two", "one"]
            ).payload as NSDictionary,
            [
                "type": "reorder",
                "section": "reserve",
                "orderedMessageIds": ["two", "one"]
            ] as NSDictionary
        )

        XCTAssertEqual(
            QueueMutation.move(
                messageID: "message",
                destination: .upNext,
                placement: .first
            ).payload as NSDictionary,
            [
                "type": "move",
                "messageId": "message",
                "destination": "up_next",
                "placement": "first"
            ] as NSDictionary
        )
    }

    private func message(_ id: String) -> Message {
        Message(
            id: id,
            text: id,
            packageId: "test",
            timestamp: Date(timeIntervalSince1970: 1),
            experience: Experience(
                themeKey: "heart",
                animationKey: "breathe",
                soundKey: "soft"
            )
        )
    }

    private func lumi(_ id: String) -> [String: Any] {
        [
            "id": id,
            "text": id,
            "presentation": [
                "theme": "heart",
                "animation": "breathe",
                "sound": "soft"
            ]
        ]
    }
}
