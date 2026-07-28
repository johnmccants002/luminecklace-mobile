import Foundation
import SwiftUI
import Combine

enum RecipientPresentationPhase: Equatable {
    case loading
    case introVisible
    case introFading
    case messageRevealing
    case complete
    case error
}

nonisolated struct RecipientRevealTiming: Sendable {
    let minimumIntro: Duration
    let introFade: Duration
    let pauseAfterIntro: Duration
    let wordInterval: Duration
    let wordFade: Double
    let wordRise: CGFloat
    let reducedMotionCrossfade: Duration

    static let standard = RecipientRevealTiming(
        minimumIntro: .seconds(2),
        introFade: .milliseconds(500),
        pauseAfterIntro: .milliseconds(300),
        wordInterval: .milliseconds(180),
        wordFade: 0.42,
        wordRise: 7,
        reducedMotionCrossfade: .milliseconds(500)
    )
}

struct RecipientMessageToken: Identifiable, Equatable {
    let id: Int
    let text: String
    let wordIndex: Int?

    static func tokenize(_ message: String) -> [RecipientMessageToken] {
        guard !message.isEmpty else { return [] }

        var pieces: [String] = []
        var current = ""
        var currentIsWhitespace: Bool?

        for character in message {
            let isWhitespace = character.isWhitespace
            if let currentIsWhitespace, currentIsWhitespace != isWhitespace {
                pieces.append(current)
                current = ""
            }
            current.append(character)
            currentIsWhitespace = isWhitespace
        }
        if !current.isEmpty {
            pieces.append(current)
        }

        var nextWordIndex = 0
        return pieces.enumerated().map { index, piece in
            if piece.allSatisfy(\.isWhitespace) {
                return RecipientMessageToken(id: index, text: piece, wordIndex: nil)
            }

            defer { nextWordIndex += 1 }
            return RecipientMessageToken(id: index, text: piece, wordIndex: nextWordIndex)
        }
    }
}

@MainActor
final class RecipientPresentationCoordinator: ObservableObject {
    @Published private(set) var phase: RecipientPresentationPhase = .loading
    @Published private(set) var lumi: ResolvedLumi?
    @Published private(set) var terminalState: RecipientRevealState?
    @Published private(set) var revealedWordCount = 0

    let timing: RecipientRevealTiming

    private var introMinimumTask: Task<Void, Never>?
    private var revealTask: Task<Void, Never>?
    private var introMinimumElapsed = false
    private var reduceMotion = false
    private var isActive = false
    private var pendingLumi: ResolvedLumi?
    private var presentedLumiID: String?

    init(timing: RecipientRevealTiming = .standard) {
        self.timing = timing
    }

    var tokens: [RecipientMessageToken] {
        RecipientMessageToken.tokenize(lumi?.text ?? "")
    }

    var wordCount: Int {
        tokens.compactMap(\.wordIndex).count
    }

    func start(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
        guard !isActive else { return }
        isActive = true
        beginIntro()
    }

    func update(revealState: RecipientRevealState, reduceMotion: Bool) {
        let reduceMotionWasEnabled = !self.reduceMotion && reduceMotion
        self.reduceMotion = reduceMotion

        if reduceMotionWasEnabled, phase == .messageRevealing {
            finishRevealWithCrossfade()
        }

        switch revealState {
        case .awaitingInvocation:
            break
        case .resolving:
            if phase == .error || phase == .complete {
                beginIntro()
            }
        case let .waiting(lumi),
             let .revealing(lumi),
             let .revealed(lumi, _):
            receive(lumi)
        case .empty, .unavailable, .error:
            showTerminal(revealState)
        }
    }

    func cancel() {
        isActive = false
        introMinimumTask?.cancel()
        revealTask?.cancel()
        introMinimumTask = nil
        revealTask = nil
    }

    private func beginIntro() {
        introMinimumTask?.cancel()
        revealTask?.cancel()
        pendingLumi = nil
        lumi = nil
        terminalState = nil
        presentedLumiID = nil
        revealedWordCount = 0
        introMinimumElapsed = false
        phase = .introVisible

        introMinimumTask = Task { [weak self, timing] in
            do {
                try await Task.sleep(for: timing.minimumIntro)
                guard let self, !Task.isCancelled, self.isActive else { return }
                self.introMinimumElapsed = true
                self.beginRevealIfReady()
            } catch {
                return
            }
        }
    }

    private func receive(_ lumi: ResolvedLumi) {
        guard presentedLumiID != lumi.id else { return }
        pendingLumi = lumi
        beginRevealIfReady()
    }

    private func beginRevealIfReady() {
        guard isActive,
              introMinimumElapsed,
              let pendingLumi,
              revealTask == nil else {
            return
        }

        presentedLumiID = pendingLumi.id
        lumi = pendingLumi
        self.pendingLumi = nil
        let timing = timing
        let reduceMotion = reduceMotion
        let preset = pendingLumi.presentation.revealPreset

        revealTask = Task { [weak self] in
            guard let self else { return }
            self.phase = .introFading

            do {
                try await Task.sleep(for: timing.introFade)
                try Task.checkCancellation()
                try await Task.sleep(for: timing.pauseAfterIntro)
                try Task.checkCancellation()

                if reduceMotion || preset == .crossfade {
                    self.revealedWordCount = self.wordCount
                    withAnimation(.easeOut(duration: timing.reducedMotionCrossfade.timeInterval)) {
                        self.phase = .messageRevealing
                    }
                    try await Task.sleep(for: timing.reducedMotionCrossfade)
                } else {
                    self.phase = .messageRevealing
                    if self.wordCount > 0 {
                        for nextCount in 1...self.wordCount {
                            try Task.checkCancellation()
                            withAnimation(.easeOut(duration: timing.wordFade)) {
                                self.revealedWordCount = nextCount
                            }
                            if nextCount < self.wordCount {
                                try await Task.sleep(for: timing.wordInterval)
                            }
                        }
                    }
                }

                try Task.checkCancellation()
                self.phase = .complete
                self.revealTask = nil
            } catch {
                return
            }
        }
    }

    private func finishRevealWithCrossfade() {
        revealTask?.cancel()
        let timing = timing
        revealTask = Task { [weak self] in
            guard let self, self.isActive else { return }
            withAnimation(.easeOut(duration: timing.reducedMotionCrossfade.timeInterval)) {
                self.revealedWordCount = self.wordCount
            }
            do {
                try await Task.sleep(for: timing.reducedMotionCrossfade)
                try Task.checkCancellation()
                self.phase = .complete
                self.revealTask = nil
            } catch {
                return
            }
        }
    }

    private func showTerminal(_ state: RecipientRevealState) {
        introMinimumTask?.cancel()
        revealTask?.cancel()
        introMinimumTask = nil
        revealTask = nil
        pendingLumi = nil
        lumi = nil
        revealedWordCount = 0
        terminalState = state
        phase = .error
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
