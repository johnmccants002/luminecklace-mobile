import Foundation
import Combine
import UIKit

@MainActor
final class RecipientClipViewModel: ObservableObject {
    @Published var state: RecipientRevealState = .awaitingInvocation

    private let tapService: RecipientTapServicing
    private var currentToken: String?
    private var resolutionTask: Task<Void, Never>?
    private var confirmationTask: Task<Void, Never>?
    private var confirmationSessionIDs: Set<String> = []

    init(tapService: RecipientTapServicing = RecipientTapService()) {
        self.tapService = tapService
    }

    func loadInitialInvocationURLIfNeeded() {
        guard currentToken == nil else { return }

        if let url = invocationURLFromEnvironment() ?? invocationURLFromLaunchArguments() {
            handle(url: url)
        }
    }

    func handle(url: URL) {
        guard let token = RecipientInvocationParser.token(from: url) else {
            state = .awaitingInvocation
            return
        }

        resolve(token: token)
    }

    func retry() {
        guard let currentToken else {
            state = .awaitingInvocation
            return
        }
        resolve(token: currentToken, force: true)
    }

    func completeHold(for lumi: ResolvedLumi) {
        guard case let .waiting(current) = state,
              current.revealSessionId == lumi.revealSessionId else {
            return
        }

        state = .revealing(lumi)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 420_000_000)
            guard let self, !Task.isCancelled else { return }
            self.state = .revealed(lumi, confirmationState: .pending)
            self.confirmRevealIfNeeded(lumi)
        }
    }

    private func resolve(token: String, force: Bool = false) {
        if !force,
           currentToken == token,
           shouldIgnoreDuplicateInvocation {
            return
        }

        resolutionTask?.cancel()
        if currentToken != token {
            confirmationTask?.cancel()
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
                    state = .waiting(lumi)
                case .empty:
                    state = .empty
                case .unavailable:
                    state = .unavailable
                }
            } catch RecipientTapServiceError.invalidPayload {
                guard !Task.isCancelled else { return }
                state = .error(.invalidPayload)
            } catch {
                guard !Task.isCancelled else { return }
                state = .error(.network)
            }
        }
    }

    private var shouldIgnoreDuplicateInvocation: Bool {
        switch state {
        case .resolving, .waiting, .revealing:
            return true
        case .awaitingInvocation, .revealed, .empty, .unavailable, .error:
            return false
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
                state = .revealed(lumi, confirmationState: .temporarilyFailed)
            }
        }
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
