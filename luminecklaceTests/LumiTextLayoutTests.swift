import SwiftUI
import XCTest
@testable import luminecklace

@MainActor
final class LumiTextLayoutTests: XCTestCase {
    func testCompletePresentationDecodesLayoutValues() throws {
        let presentation = try decodePresentation(
            """
            {
              "theme": "heart",
              "background": "midnight",
              "font": "rounded",
              "animation": "breathe",
              "sound": "soft",
              "textSize": "large",
              "textAlignment": "trailing",
              "textPosition": "bottom"
            }
            """
        )

        XCTAssertEqual(presentation.background, .midnight)
        XCTAssertEqual(presentation.font, .rounded)
        XCTAssertEqual(presentation.textSize, .large)
        XCTAssertEqual(presentation.textAlignment, .trailing)
        XCTAssertEqual(presentation.textPosition, .bottom)
    }

    func testOlderAndUnknownPresentationsUseSafeDefaults() throws {
        let old = try decodePresentation(
            #"{"theme":"heart","animation":"breathe","sound":"soft"}"#
        )
        let future = try decodePresentation(
            """
            {
              "background": "aurora",
              "font": "handwritten",
              "textSize": "enormous",
              "textAlignment": "justified",
              "textPosition": "floating"
            }
            """
        )

        for presentation in [old, future] {
            XCTAssertEqual(presentation.textSize, .medium)
            XCTAssertEqual(presentation.textAlignment, .center)
            XCTAssertEqual(presentation.textPosition, .center)
        }
        XCTAssertEqual(future.background, .heart)
        XCTAssertEqual(future.font, .serif)
    }

    func testExistingCachedMessageRemainsDecodableWithLayoutDefaults() throws {
        let json = """
        [{
          "id": "cached",
          "text": "Still here",
          "packageId": "love",
          "timestamp": 0,
          "experience": {
            "themeKey": "rose",
            "animationKey": "breathe",
            "soundKey": "soft"
          }
        }]
        """

        let messages = try JSONDecoder().decode([Message].self, from: Data(json.utf8))

        XCTAssertEqual(messages.first?.experience.backgroundKey, .rose)
        XCTAssertEqual(messages.first?.textSize, .medium)
        XCTAssertEqual(messages.first?.textAlignment, .center)
        XCTAssertEqual(messages.first?.textPosition, .center)
    }

    func testComposerDefaultsEditingAndCancelResetEveryLayoutControl() {
        let state = AppState()
        state.ownedNecklaces = [necklace]

        state.openLumiComposer()
        XCTAssertEqual(state.composerTextSize, .medium)
        XCTAssertEqual(state.composerTextAlignment, .center)
        XCTAssertEqual(state.composerTextPosition, .center)

        let message = styledMessage
        state.route = .reserveEditor
        state.openLumiComposer(editing: message, in: .reserve)
        XCTAssertEqual(state.composerBackground, .midnight)
        XCTAssertEqual(state.composerFont, .rounded)
        XCTAssertEqual(state.composerTextSize, .large)
        XCTAssertEqual(state.composerTextAlignment, .trailing)
        XCTAssertEqual(state.composerTextPosition, .bottom)

        state.cancelLumiComposer()
        XCTAssertEqual(state.composerTextSize, .medium)
        XCTAssertEqual(state.composerTextAlignment, .center)
        XCTAssertEqual(state.composerTextPosition, .center)
        XCTAssertEqual(state.composerBackground, .heart)
        XCTAssertEqual(state.composerFont, .serif)
        guard case .reserveEditor = state.route else {
            return XCTFail("Cancel should preserve the queue editor return route")
        }
    }

    func testSenderPresentationPayloadContainsEveryLayoutValue() {
        let payload = SenderService().presentationPayload(for: styledMessage.experience)

        XCTAssertEqual(payload["background"] as? String, "midnight")
        XCTAssertEqual(payload["font"] as? String, "rounded")
        XCTAssertEqual(payload["textSize"] as? String, "large")
        XCTAssertEqual(payload["textAlignment"] as? String, "trailing")
        XCTAssertEqual(payload["textPosition"] as? String, "bottom")
        XCTAssertEqual(
            Set(payload.keys),
            [
                "background", "font", "textSize", "textAlignment",
                "textPosition"
            ]
        )
        XCTAssertEqual(HTTPMethod.patch.rawValue, "PATCH")
    }

    func testExploreAndQueueMappingPreserveReturnedLayout() throws {
        let message = try XCTUnwrap(
            SenderService().mapLumi(
                from: [
                    "id": "explore-lumi",
                    "text": "From Explore",
                    "presentation": [
                        "background": "midnight",
                        "font": "rounded",
                        "textSize": "small",
                        "textAlignment": "leading",
                        "textPosition": "top"
                    ]
                ],
                fallbackThemeKey: "heart"
            )
        )

        XCTAssertEqual(message.experience.backgroundKey, .midnight)
        XCTAssertEqual(message.experience.fontKey, .rounded)
        XCTAssertEqual(message.textSize, .small)
        XCTAssertEqual(message.textAlignment, .leading)
        XCTAssertEqual(message.textPosition, .top)
    }

    func testSharedAlignmentAndPositionResolversMapAllCuratedValues() {
        XCTAssertEqual(LumiTextLayoutResolver.textAlignment(for: .leading), .leading)
        XCTAssertEqual(LumiTextLayoutResolver.textAlignment(for: .center), .center)
        XCTAssertEqual(LumiTextLayoutResolver.textAlignment(for: .trailing), .trailing)
        XCTAssertEqual(LumiTextLayoutResolver.horizontalAlignment(for: .leading), .leading)
        XCTAssertEqual(LumiTextLayoutResolver.horizontalAlignment(for: .center), .center)
        XCTAssertEqual(LumiTextLayoutResolver.horizontalAlignment(for: .trailing), .trailing)
        XCTAssertEqual(LumiTextLayoutResolver.verticalAlignment(for: .top), .top)
        XCTAssertEqual(LumiTextLayoutResolver.verticalAlignment(for: .center), .center)
        XCTAssertEqual(LumiTextLayoutResolver.verticalAlignment(for: .bottom), .bottom)
    }

    func testLongContentPolicyCoversCompactLandscapeAndAccessibilityLayouts() {
        XCTAssertTrue(
            LumiLongContentLayoutPolicy.requiresScrolling(
                preset: .calm,
                primaryCharacterCount: 500,
                primaryWordCount: 90,
                secondaryCharacterCount: 0,
                availableWidth: 320,
                isAccessibilitySize: false
            )
        )
        XCTAssertTrue(
            LumiLongContentLayoutPolicy.requiresScrolling(
                preset: .proudOfYou,
                primaryCharacterCount: 80,
                primaryWordCount: 12,
                secondaryCharacterCount: 0,
                availableWidth: 568,
                isAccessibilitySize: false
            )
        )
        XCTAssertTrue(
            LumiLongContentLayoutPolicy.requiresScrolling(
                preset: .midnight,
                primaryCharacterCount: 90,
                primaryWordCount: 16,
                secondaryCharacterCount: 0,
                availableWidth: 390,
                isAccessibilitySize: true
            )
        )
        XCTAssertFalse(
            LumiLongContentLayoutPolicy.requiresScrolling(
                preset: .classicWordRise,
                primaryCharacterCount: 45,
                primaryWordCount: 8,
                secondaryCharacterCount: 0,
                availableWidth: 390,
                isAccessibilitySize: false
            )
        )
    }

    func testLargeLongMessagesUseReadableBoundedEffectiveSize() {
        XCTAssertEqual(
            LumiTextLayoutResolver.effectivePointSize(for: .large, characterCount: 80),
            44
        )
        XCTAssertGreaterThanOrEqual(
            LumiTextLayoutResolver.effectivePointSize(for: .large, characterCount: 500),
            29
        )
        XCTAssertGreaterThan(
            LumiTextLayoutResolver.effectivePointSize(for: .large, characterCount: 500),
            LumiTextLayoutResolver.effectivePointSize(for: .small, characterCount: 500)
        )
    }

    private func decodePresentation(_ json: String) throws -> NecklacePresentation {
        try JSONDecoder().decode(NecklacePresentation.self, from: Data(json.utf8))
    }

    private var necklace: NecklaceTag {
        NecklaceTag(
            id: "necklace",
            name: "Lumi",
            sku: "TEST",
            themeKey: "heart",
            isEquipped: true,
            rarity: nil,
            includedPackage: "Love",
            lifecycleStatus: "active"
        )
    }

    private var styledMessage: Message {
        Message(
            id: "styled",
            text: "Styled",
            packageId: "love",
            timestamp: .now,
            experience: Experience(
                themeKey: "heart",
                animationKey: "breathe",
                soundKey: "soft",
                backgroundKey: .midnight,
                fontKey: .rounded,
                textSize: .large,
                textAlignment: .trailing,
                textPosition: .bottom
            )
        )
    }
}
