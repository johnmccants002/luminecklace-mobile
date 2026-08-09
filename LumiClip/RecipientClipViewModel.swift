import Foundation
import Combine

@MainActor
final class RecipientClipViewModel: ObservableObject {
    @Published var state: RecipientRevealState = .awaitingInvocation
    @Published var feedbackState: RecipientFeedbackState = .empty

    private let tapService: RecipientTapServicing
    private var currentToken: String?
    private var resolutionTask: Task<Void, Never>?
    private var confirmationTask: Task<Void, Never>?
    private var reactionTask: Task<Void, Never>?
    private var responseTask: Task<Void, Never>?
    private var confirmationSessionIDs: Set<String> = []
    private var feedbackSessionID: String?

    init(tapService: RecipientTapServicing = RecipientTapService()) {
        self.tapService = tapService
    }

    func loadInitialInvocationURLIfNeeded() {
        guard currentToken == nil else { return }

        if let url = invocationURLFromEnvironment() ?? invocationURLFromLaunchArguments() {
            handle(url: url)
        } else {
            state = .error(.invalidInvocation)
        }
    }

    func handle(url: URL) {
        guard let token = RecipientInvocationParser.token(from: url) else {
            resolutionTask?.cancel()
            confirmationTask?.cancel()
            currentToken = nil
            resetFeedbackState(for: nil)
            state = .error(.invalidInvocation)
            return
        }

        resolve(token: token)
    }

    func retry() {
        guard let currentToken else {
            state = .error(.invalidInvocation)
            return
        }
        resolve(token: currentToken, force: true)
    }

    var feedbackPresentationState: RecipientFeedbackPresentationState {
        feedbackState.presentationState(isEnabled: true)
    }

    func retryRevealConfirmation() {
        guard case let .revealed(lumi, confirmationState) = state,
              confirmationState == .temporarilyFailed else { return }
        confirmRevealIfNeeded(lumi)
    }

    func selectReaction(_ reaction: LumiReaction) {
        guard reactionTask == nil,
              !feedbackState.isFeedbackWindowClosed,
              feedbackState.selectedReaction != reaction,
              let lumi = confirmedLumi else { return }

        feedbackState.attemptedReaction = reaction
        feedbackState.isSubmittingReaction = true
        feedbackState.reactionErrorMessage = nil

        reactionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let feedback = try await tapService.setReaction(
                    revealSessionId: lumi.revealSessionId,
                    reaction: reaction
                )
                guard !Task.isCancelled, feedbackSessionID == lumi.revealSessionId else { return }
                feedbackState.selectedReaction = feedback.reaction ?? reaction
                if let responseText = feedback.responseText,
                   !responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    feedbackState.submittedResponse = responseText
                    feedbackState.isResponseLocked = true
                }
                feedbackState.isSubmittingReaction = false
                feedbackState.reactionErrorMessage = nil
                reactionTask = nil
            } catch {
                guard !Task.isCancelled, feedbackSessionID == lumi.revealSessionId else { return }
                let feedbackError = error as? RecipientFeedbackServiceError ?? .temporaryFailure
                feedbackState.isSubmittingReaction = false
                feedbackState.reactionErrorMessage = feedbackError.reactionMessage
                if feedbackError == .expiredSession {
                    feedbackState.isFeedbackWindowClosed = true
                    feedbackState.isResponseLocked = true
                    feedbackState.responseErrorMessage = feedbackError.responseMessage
                }
                reactionTask = nil
            }
        }
    }

    func retryReaction() {
        guard let attemptedReaction = feedbackState.attemptedReaction else { return }
        selectReaction(attemptedReaction)
    }

    func setResponseComposerPresented(_ isPresented: Bool) {
        guard !feedbackState.isSubmittingResponse else { return }
        if isPresented {
            guard confirmedLumi != nil,
                  !feedbackState.isResponseLocked,
                  !feedbackState.isFeedbackWindowClosed else { return }
        }
        feedbackState.isResponseComposerPresented = isPresented
    }

    func updateResponseDraft(_ draft: String) {
        guard !feedbackState.isResponseLocked else { return }
        feedbackState.draftResponse = String(draft.prefix(250))
        feedbackState.responseErrorMessage = nil
    }

    func submitResponse() {
        guard responseTask == nil,
              !feedbackState.isResponseLocked,
              !feedbackState.isFeedbackWindowClosed,
              let lumi = confirmedLumi else { return }

        let trimmed = feedbackState.draftResponse
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 250 else { return }

        feedbackState.isSubmittingResponse = true
        feedbackState.responseErrorMessage = nil

        responseTask = Task { [weak self] in
            guard let self else { return }
            do {
                let feedback = try await tapService.submitResponse(
                    revealSessionId: lumi.revealSessionId,
                    text: trimmed
                )
                guard !Task.isCancelled, feedbackSessionID == lumi.revealSessionId else { return }
                feedbackState.selectedReaction = feedback.reaction ?? feedbackState.selectedReaction
                feedbackState.submittedResponse = feedback.responseText ?? trimmed
                feedbackState.draftResponse = feedback.responseText ?? trimmed
                feedbackState.isSubmittingResponse = false
                feedbackState.isResponseLocked = true
                feedbackState.isResponseComposerPresented = false
                feedbackState.responseErrorMessage = nil
                responseTask = nil
            } catch {
                guard !Task.isCancelled, feedbackSessionID == lumi.revealSessionId else { return }
                let feedbackError = error as? RecipientFeedbackServiceError ?? .temporaryFailure
                feedbackState.isSubmittingResponse = false
                feedbackState.responseErrorMessage = feedbackError.responseMessage
                if feedbackError == .alreadyResponded || feedbackError == .expiredSession {
                    feedbackState.isResponseLocked = true
                    feedbackState.isResponseComposerPresented = false
                }
                if feedbackError == .expiredSession {
                    feedbackState.isFeedbackWindowClosed = true
                }
                responseTask = nil
            }
        }
    }

    private func resolve(token: String, force: Bool = false) {
        if !force, currentToken == token {
            return
        }

        resolutionTask?.cancel()
        if currentToken != token {
            confirmationTask?.cancel()
            resetFeedbackState(for: nil)
        }

        currentToken = token
        state = .resolving

        resolutionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await tapService.resolveTap(token: token)
                guard !Task.isCancelled else { return }
                switch response {
                case let .ready(lumi):
                    resetFeedbackState(for: lumi.revealSessionId)
                    state = .revealed(lumi, confirmationState: .pending)
                    confirmRevealIfNeeded(lumi)
                case .empty:
                    resetFeedbackState(for: nil)
                    state = .empty
                case .unavailable:
                    resetFeedbackState(for: nil)
                    state = .unavailable
                }
            } catch RecipientTapServiceError.invalidPayload {
                guard !Task.isCancelled else { return }
                state = .error(.invalidPayload)
            } catch {
                guard !Task.isCancelled else { return }
                resetFeedbackState(for: nil)
                state = .error(.network)
            }
        }
    }

    private func confirmRevealIfNeeded(_ lumi: ResolvedLumi) {
        guard !confirmationSessionIDs.contains(lumi.revealSessionId) else { return }
        confirmationSessionIDs.insert(lumi.revealSessionId)
        state = .revealed(lumi, confirmationState: .confirming)

        confirmationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await confirmRevealWithSingleRetry(revealSessionId: lumi.revealSessionId)
                guard !Task.isCancelled else { return }
                state = .revealed(lumi, confirmationState: .confirmed(response.revealedAt))
            } catch {
                guard !Task.isCancelled else { return }
                confirmationSessionIDs.remove(lumi.revealSessionId)
                state = .revealed(lumi, confirmationState: .temporarilyFailed)
            }
        }
    }

    private var confirmedLumi: ResolvedLumi? {
        guard case let .revealed(lumi, confirmationState) = state,
              case .confirmed = confirmationState else {
            return nil
        }
        return lumi
    }

    private func resetFeedbackState(for revealSessionID: String?) {
        guard feedbackSessionID != revealSessionID else { return }
        reactionTask?.cancel()
        responseTask?.cancel()
        reactionTask = nil
        responseTask = nil
        feedbackSessionID = revealSessionID
        feedbackState = .empty
    }

    private func confirmRevealWithSingleRetry(revealSessionId: String) async throws -> ConfirmRevealResponse {
        do {
            return try await tapService.confirmReveal(revealSessionId: revealSessionId)
        } catch {
            try await Task.sleep(nanoseconds: 900_000_000)
            return try await tapService.confirmReveal(revealSessionId: revealSessionId)
        }
    }

    private func invocationURLFromEnvironment() -> URL? {
        let env = ProcessInfo.processInfo.environment
        let keys = ["_XCAppClipURL", "XCAppClipURL", "APP_CLIP_URL"]

        for key in keys {
            guard let value = env[key], let url = URL(string: value) else { continue }
            return url
        }

        return nil
    }

    private func invocationURLFromLaunchArguments() -> URL? {
        let arguments = ProcessInfo.processInfo.arguments

        for (index, value) in arguments.enumerated() {
            let lowercased = value.lowercased()
            if lowercased.contains("appclipurl") || lowercased == "_xcappclipurl" {
                let nextIndex = index + 1
                if nextIndex < arguments.count, let url = URL(string: arguments[nextIndex]) {
                    return url
                }
            }
        }

        return arguments
            .first(where: { $0.hasPrefix("https://") })
            .flatMap(URL.init(string:))
    }
}
