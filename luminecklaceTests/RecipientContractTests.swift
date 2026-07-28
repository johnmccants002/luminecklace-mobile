import XCTest
@testable import luminecklace

final class RecipientContractTests: XCTestCase {
    func testReadyResponseDecodingRemainsSourceNeutral() throws {
        let response = try decode(Fixtures.readyResponse)
        guard case let .ready(lumi) = response else {
            return XCTFail("Expected a ready response")
        }

        XCTAssertEqual(lumi.revealSessionId, Fixtures.revealSessionID)
        XCTAssertEqual(lumi.lumiId, "reserve-or-personal-id")
        XCTAssertEqual(lumi.text, "You are loved more than you know.")
        XCTAssertEqual(lumi.presentation.theme, .heart)
        XCTAssertFalse(
            Mirror(reflecting: lumi).children.contains { child in
                child.label?.lowercased().contains("source") == true
            }
        )
    }

    func testRepeatedResolveCanReuseRevealSessionID() throws {
        let first = try decode(Fixtures.readyResponse)
        let second = try decode(Fixtures.readyResponse)

        guard case let .ready(firstLumi) = first,
              case let .ready(secondLumi) = second else {
            return XCTFail("Expected ready responses")
        }

        XCTAssertEqual(firstLumi.revealSessionId, secondLumi.revealSessionId)
        XCTAssertEqual(firstLumi, secondLumi)
    }

    func testUnknownSourceFieldDoesNotChangeRecipientModel() throws {
        var payload = Fixtures.readyResponse
        payload["source"] = "reserve"

        let response = try decode(payload)
        guard case let .ready(lumi) = response else {
            return XCTFail("Expected a ready response")
        }

        XCTAssertEqual(lumi.revealSessionId, Fixtures.revealSessionID)
        XCTAssertEqual(lumi.text, "You are loved more than you know.")
    }

    func testEmptyAndUnavailableStatesRemainUnchanged() throws {
        XCTAssertEqual(try decode(["status": "empty"]), .empty)
        XCTAssertEqual(try decode(["status": "unavailable"]), .unavailable)
    }

    private func decode(_ payload: [String: Any]) throws -> ResolveTapResponse {
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(ResolveTapResponse.self, from: data)
    }
}

private enum Fixtures {
    static let revealSessionID = "622598ad-2856-4ec9-b6f4-4c49918fa07b"

    static let readyResponse: [String: Any] = [
        "status": "ready",
        "revealSessionId": revealSessionID,
        "necklace": [
            "displayName": "Lumi Necklace"
        ],
        "lumi": [
            "id": "reserve-or-personal-id",
            "text": "You are loved more than you know."
        ],
        "presentation": [
            "theme": "heart",
            "animation": "breathe",
            "sound": "soft"
        ]
    ]
}
