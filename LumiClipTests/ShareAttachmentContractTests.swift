import XCTest
@testable import lumiclip

final class ShareAttachmentContractTests: XCTestCase {
    func testReadyResponseWithAndWithoutAttachment() throws {
        var payload = readyPayload
        payload["attachment"] = attachmentPayload
        guard case let .ready(attached) = try decode(payload) else {
            return XCTFail("Expected attached Lumi")
        }
        XCTAssertTrue(attached.attachment?.isSupportedInstagramLink == true)

        guard case let .ready(textOnly) = try decode(readyPayload) else {
            return XCTFail("Expected text-only Lumi")
        }
        XCTAssertNil(textOnly.attachment)
    }

    func testMalformedAttachmentDoesNotFailResolveOrConfirmationIdentity() throws {
        var payload = readyPayload
        payload["attachment"] = ["type": 10, "provider": false]
        guard case let .ready(first) = try decode(payload),
              case let .ready(second) = try decode(payload) else {
            return XCTFail("Expected ready responses")
        }
        XCTAssertNil(first.attachment)
        XCTAssertEqual(first.revealSessionId, second.revealSessionId)
        XCTAssertEqual(first, second)
    }

    func testAppClipDecodesSharedExperienceAndFallsBackForUnknownPreset() throws {
        var richPayload = readyPayload
        richPayload["lumi"] = [
            "id": "lumi-1",
            "text": "First reveal",
            "secondaryText": "Second reveal",
            "experiencePresetKey": "timed_surprise_v1"
        ]
        guard case let .ready(rich) = try decode(richPayload) else {
            return XCTFail("Expected rich Lumi")
        }
        XCTAssertEqual(rich.experiencePresetKey, .timedSurprise)
        XCTAssertEqual(rich.secondaryText, "Second reveal")

        richPayload["lumi"] = [
            "id": "lumi-2",
            "text": "Future reveal",
            "experiencePresetKey": "not_shipped_yet_v2"
        ]
        guard case let .ready(fallback) = try decode(richPayload) else {
            return XCTFail("Expected fallback Lumi")
        }
        XCTAssertEqual(fallback.experiencePresetKey, .classicWordRise)
    }

    private func decode(_ payload: [String: Any]) throws -> ResolveTapResponse {
        try JSONDecoder().decode(
            ResolveTapResponse.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )
    }

    private var readyPayload: [String: Any] {
        [
            "status": "ready",
            "revealSessionId": "session-1",
            "necklace": ["displayName": "Lumi Necklace"],
            "lumi": ["id": "lumi-1", "text": "A message with a link"],
            "presentation": ["theme": "heart", "animation": "breathe"]
        ]
    }

    private var attachmentPayload: [String: Any] {
        [
            "type": "link",
            "provider": "instagram",
            "contentKind": "post",
            "url": "https://instagram.com/p/example/",
            "host": "instagram.com",
            "ctaLabel": "View on Instagram",
            "openMode": "external"
        ]
    }
}
