import Foundation
import XCTest
@testable import lumiclip

@MainActor
final class RecipientClipViewModelTests: XCTestCase {
    func testReadyMessageAppearsAndConfirmsWithoutInteraction() async throws {
        let lumi = makeLumi(text: "You are loved more than you know.")
        let service = MockRecipientTapService(resolveResults: [.success(.ready(lumi))])
        let viewModel = RecipientClipViewModel(tapService: service)

        viewModel.handle(url: try XCTUnwrap(URL(string: "https://www.luminecklace.com/t/test-ready")))

        try await waitUntil {
            guard case let .revealed(resolved, confirmationState) = viewModel.state else {
                return false
            }
            guard resolved == lumi else { return false }
            if case .confirmed = confirmationState {
                return true
            }
            return false
        }

        XCTAssertEqual(service.resolvedTokens, ["test-ready"])
        XCTAssertEqual(service.confirmedSessionIDs, [lumi.revealSessionId])
    }

    func testInvalidInvocationIsRejectedBeforeNetworking() throws {
        let url = try XCTUnwrap(URL(string: "http://www.luminecklace.com/t/not-secure"))

        XCTAssertNil(RecipientInvocationParser.token(from: url))
    }

    func testEmptyAndUnavailableResponsesRemainDistinct() async throws {
        let service = MockRecipientTapService(
            resolveResults: [.success(.empty), .success(.unavailable)]
        )
        let viewModel = RecipientClipViewModel(tapService: service)

        viewModel.handle(url: try XCTUnwrap(URL(string: "https://www.luminecklace.com/t/test-empty")))
        try await waitUntil { viewModel.state == .empty }

        viewModel.handle(url: try XCTUnwrap(URL(string: "https://www.luminecklace.com/t/test-unavailable")))
        try await waitUntil { viewModel.state == .unavailable }
    }

    func testNetworkFailureCanRetryIntoAnAutomaticReveal() async throws {
        let lumi = makeLumi(text: "I’m always in your corner.")
        let service = MockRecipientTapService(
            resolveResults: [
                .failure(RecipientTapServiceError.server),
                .success(.ready(lumi))
            ]
        )
        let viewModel = RecipientClipViewModel(tapService: service)

        viewModel.handle(url: try XCTUnwrap(URL(string: "https://www.luminecklace.com/t/test-retry")))
        try await waitUntil { viewModel.state == .error(.network) }

        viewModel.retry()

        try await waitUntil {
            guard case let .revealed(resolved, _) = viewModel.state else { return false }
            return resolved == lumi
        }
        XCTAssertEqual(service.resolvedTokens, ["test-retry", "test-retry"])
    }

    func testDuplicateInvocationDoesNotConsumeAnotherMessage() async throws {
        let first = makeLumi(text: "First message")
        let second = makeLumi(sessionID: "session-2", text: "Second message")
        let service = MockRecipientTapService(
            resolveResults: [.success(.ready(first)), .success(.ready(second))]
        )
        let viewModel = RecipientClipViewModel(tapService: service)
        let url = try XCTUnwrap(URL(string: "https://www.luminecklace.com/t/same-token"))

        viewModel.handle(url: url)
        try await waitUntil {
            guard case let .revealed(lumi, _) = viewModel.state else { return false }
            return lumi == first
        }

        viewModel.handle(url: url)
        await Task.yield()

        XCTAssertEqual(service.resolvedTokens, ["same-token"])
        guard case let .revealed(lumi, _) = viewModel.state else {
            return XCTFail("Expected the first message to remain visible")
        }
        XCTAssertEqual(lumi, first)
    }

    func testFastResponseWaitsForMinimumIntroBeforeRevealSequence() async throws {
        let coordinator = RecipientPresentationCoordinator(timing: testTiming(minimumIntro: .milliseconds(80)))
        let lumi = makeLumi(text: "Take your time.")

        coordinator.start(reduceMotion: false)
        coordinator.update(revealState: .revealed(lumi, confirmationState: .confirmed(.now)), reduceMotion: false)

        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(coordinator.phase, .introVisible)
        XCTAssertEqual(coordinator.revealedWordCount, 0)

        try await waitUntil { coordinator.phase == .complete }
        XCTAssertEqual(coordinator.revealedWordCount, 3)
    }

    func testSlowResponseDoesNotAddAnotherMinimumIntroDelay() async throws {
        let coordinator = RecipientPresentationCoordinator(timing: testTiming(minimumIntro: .milliseconds(30)))
        let lumi = makeLumi(text: "Already here.")

        coordinator.start(reduceMotion: false)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(coordinator.phase, .introVisible)

        coordinator.update(revealState: .revealed(lumi, confirmationState: .pending), reduceMotion: false)
        try await waitUntil { coordinator.phase == .introFading }
    }

    func testReduceMotionUsesCompleteMessageCrossfade() async throws {
        let coordinator = RecipientPresentationCoordinator(timing: testTiming(minimumIntro: .milliseconds(10)))
        let lumi = makeLumi(text: "Every word together.")

        coordinator.start(reduceMotion: true)
        coordinator.update(revealState: .revealed(lumi, confirmationState: .pending), reduceMotion: true)

        try await waitUntil { coordinator.phase == .messageRevealing }
        XCTAssertEqual(coordinator.revealedWordCount, 3)
        try await waitUntil { coordinator.phase == .complete }
    }

    func testCancellationStopsPendingRevealWork() async throws {
        let coordinator = RecipientPresentationCoordinator(
            timing: RecipientRevealTiming(
                minimumIntro: .milliseconds(10),
                introFade: .milliseconds(10),
                pauseAfterIntro: .milliseconds(10),
                wordInterval: .milliseconds(80),
                wordFade: 0.04,
                wordRise: 7,
                reducedMotionCrossfade: .milliseconds(10)
            )
        )
        let lumi = makeLumi(text: "One two three four.")

        coordinator.start(reduceMotion: false)
        coordinator.update(revealState: .revealed(lumi, confirmationState: .pending), reduceMotion: false)
        try await waitUntil { coordinator.phase == .messageRevealing && coordinator.revealedWordCount > 0 }

        coordinator.cancel()
        let countAtCancellation = coordinator.revealedWordCount
        try await Task.sleep(for: .milliseconds(120))

        XCTAssertEqual(coordinator.revealedWordCount, countAtCancellation)
        XCTAssertNotEqual(coordinator.phase, .complete)
    }

    func testTokenizerPreservesOriginalMessageExactly() {
        let message = "You’re loved,\nmore than  you know."
        let tokens = RecipientMessageToken.tokenize(message)

        XCTAssertEqual(tokens.map(\.text).joined(), message)
        XCTAssertEqual(tokens.compactMap(\.wordIndex), Array(0..<6))
    }

    func testRevealPresetDefaultsToWordRiseAndCanDecodeCrossfade() throws {
        let defaultPresentation = try JSONDecoder().decode(
            NecklacePresentation.self,
            from: Data(#"{"theme":"heart","animation":"breathe","sound":"soft"}"#.utf8)
        )
        let configuredPresentation = try JSONDecoder().decode(
            NecklacePresentation.self,
            from: Data(#"{"theme":"rose","animation":"still","revealPreset":"crossfade"}"#.utf8)
        )

        XCTAssertEqual(defaultPresentation.revealPreset, .wordRise)
        XCTAssertEqual(configuredPresentation.revealPreset, .crossfade)
    }

    func testAppClipDecodesCompleteLayoutAndDefaultsMissingOrUnknownValues() throws {
        let complete = try JSONDecoder().decode(
            NecklacePresentation.self,
            from: Data(
                #"""
                {
                  "background": "midnight",
                  "font": "rounded",
                  "textSize": "large",
                  "textAlignment": "leading",
                  "textPosition": "bottom"
                }
                """#.utf8
            )
        )
        let old = try JSONDecoder().decode(
            NecklacePresentation.self,
            from: Data(#"{"theme":"heart","animation":"breathe"}"#.utf8)
        )
        let future = try JSONDecoder().decode(
            NecklacePresentation.self,
            from: Data(
                #"""
                {
                  "textSize": "huge",
                  "textAlignment": "justified",
                  "textPosition": "floating"
                }
                """#.utf8
            )
        )

        XCTAssertEqual(complete.background, .midnight)
        XCTAssertEqual(complete.font, .rounded)
        XCTAssertEqual(complete.textSize, .large)
        XCTAssertEqual(complete.textAlignment, .leading)
        XCTAssertEqual(complete.textPosition, .bottom)

        for presentation in [old, future] {
            XCTAssertEqual(presentation.textSize, .medium)
            XCTAssertEqual(presentation.textAlignment, .center)
            XCTAssertEqual(presentation.textPosition, .center)
        }
    }

    func testAppClipUsesSharedPlacementAndLongMessagePolicy() {
        XCTAssertEqual(LumiTextLayoutResolver.horizontalAlignment(for: .leading), .leading)
        XCTAssertEqual(LumiTextLayoutResolver.horizontalAlignment(for: .center), .center)
        XCTAssertEqual(LumiTextLayoutResolver.horizontalAlignment(for: .trailing), .trailing)
        XCTAssertEqual(LumiTextLayoutResolver.verticalAlignment(for: .top), .top)
        XCTAssertEqual(LumiTextLayoutResolver.verticalAlignment(for: .center), .center)
        XCTAssertEqual(LumiTextLayoutResolver.verticalAlignment(for: .bottom), .bottom)
        XCTAssertGreaterThanOrEqual(
            LumiTextLayoutResolver.effectivePointSize(for: .large, characterCount: 500),
            29
        )
    }

    private func makeLumi(
        sessionID: String = "session-1",
        text: String
    ) -> ResolvedLumi {
        ResolvedLumi(
            revealSessionId: sessionID,
            necklaceDisplayName: "Lumi Necklace",
            lumiId: "lumi-\(sessionID)",
            text: text,
            presentation: NecklacePresentation(
                theme: .heart,
                animation: .breathe,
                sound: .soft
            )
        )
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let start = DispatchTime.now().uptimeNanoseconds
        while !condition() {
            if DispatchTime.now().uptimeNanoseconds - start > timeoutNanoseconds {
                XCTFail("Timed out waiting for App Clip state")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func testTiming(minimumIntro: Duration) -> RecipientRevealTiming {
        RecipientRevealTiming(
            minimumIntro: minimumIntro,
            introFade: .milliseconds(10),
            pauseAfterIntro: .milliseconds(10),
            wordInterval: .milliseconds(5),
            wordFade: 0.02,
            wordRise: 7,
            reducedMotionCrossfade: .milliseconds(10)
        )
    }
}

private final class MockRecipientTapService: RecipientTapServicing, @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var queuedResolveResults: [Result<ResolveTapResponse, Error>]
    nonisolated(unsafe) private var _resolvedTokens: [String] = []
    nonisolated(unsafe) private var _confirmedSessionIDs: [String] = []

    init(resolveResults: [Result<ResolveTapResponse, Error>]) {
        queuedResolveResults = resolveResults
    }

    var resolvedTokens: [String] {
        lock.withLock { _resolvedTokens }
    }

    var confirmedSessionIDs: [String] {
        lock.withLock { _confirmedSessionIDs }
    }

    func resolveTap(token: String) async throws -> ResolveTapResponse {
        let result = lock.withLock { () -> Result<ResolveTapResponse, Error> in
            _resolvedTokens.append(token)
            guard !queuedResolveResults.isEmpty else {
                return .failure(RecipientTapServiceError.server)
            }
            return queuedResolveResults.removeFirst()
        }
        return try result.get()
    }

    func confirmReveal(revealSessionId: String) async throws -> ConfirmRevealResponse {
        lock.withLock {
            _confirmedSessionIDs.append(revealSessionId)
        }
        return ConfirmRevealResponse(status: "revealed", revealedAt: Date(timeIntervalSince1970: 1))
    }
}
