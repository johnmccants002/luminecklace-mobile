import XCTest
@testable import luminecklace

@MainActor
final class HomePreviewTests: XCTestCase {
    func testPreviewUsesThePersonalLumiAndItsPresentation() throws {
        let message = Message(
            id: "message-1",
            text: "You make ordinary days feel special.",
            packageId: "personal",
            timestamp: Date(timeIntervalSince1970: 1),
            experience: Experience(
                themeKey: "rose",
                animationKey: "shimmer",
                soundKey: "soft"
            )
        )

        let state = HomePreviewFactory.revealState(
            message: message,
            necklaceName: "Kellie’s Necklace"
        )

        guard case let .revealed(lumi, confirmationState) = state else {
            return XCTFail("Expected Home Preview to render a resolved Lumi")
        }

        XCTAssertEqual(lumi.lumiId, message.id)
        XCTAssertEqual(lumi.text, message.text)
        XCTAssertEqual(lumi.necklaceDisplayName, "Kellie’s Necklace")
        XCTAssertEqual(lumi.presentation.theme, .rose)
        XCTAssertEqual(lumi.presentation.animation, .shimmer)
        XCTAssertEqual(lumi.presentation.sound, .soft)
        XCTAssertEqual(lumi.presentation.revealPreset, .wordRise)
        XCTAssertEqual(confirmationState, .pending)
    }

    func testPreviewUsesRecipientDefaultsForUnknownPresentationValues() throws {
        let message = Message(
            id: "message-2",
            text: "I’m always in your corner.",
            packageId: "personal",
            timestamp: Date(timeIntervalSince1970: 2),
            experience: Experience(
                themeKey: "unknown",
                animationKey: "unknown",
                soundKey: "none"
            )
        )

        let state = HomePreviewFactory.revealState(
            message: message,
            necklaceName: "Lumi Necklace"
        )

        guard case let .revealed(lumi, _) = state else {
            return XCTFail("Expected Home Preview to render a resolved Lumi")
        }

        XCTAssertEqual(lumi.presentation.theme, .heart)
        XCTAssertEqual(lumi.presentation.animation, .breathe)
        XCTAssertNil(lumi.presentation.sound)
    }

    func testPreviewWithoutAPersonalLumiUsesTheRecipientEmptyState() {
        XCTAssertEqual(
            HomePreviewFactory.revealState(
                message: nil,
                necklaceName: "Lumi Necklace"
            ),
            .empty
        )
    }

    func testSenderPreviewExplicitlyDisablesRecipientFeedback() {
        XCTAssertFalse(HomePreviewFactory.feedbackPresentationState.isEnabled)
    }
}
