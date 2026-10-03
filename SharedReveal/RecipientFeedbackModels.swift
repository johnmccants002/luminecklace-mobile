import Foundation

nonisolated enum LumiReaction: String, Codable, CaseIterable, Hashable, Sendable {
    case heart
    case touched
    case laugh
    case sparkle
    case hug
    case wow

    var emoji: String {
        switch self {
        case .heart: "❤️"
        case .touched: "🥹"
        case .laugh: "😂"
        case .sparkle: "✨"
        case .hug: "🫶"
        case .wow: "😮"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .heart: "Loved it"
        case .touched: "Felt this"
        case .laugh: "Made me laugh"
        case .sparkle: "Beautiful"
        case .hug: "Sending love"
        case .wow: "Wow"
        }
    }
}

nonisolated struct LumiFeedback: Codable, Equatable, Hashable, Sendable {
    let reaction: LumiReaction?
    let reactionAt: Date?
    let responseText: String?
    let respondedAt: Date?

    init(
        reaction: LumiReaction? = nil,
        reactionAt: Date? = nil,
        responseText: String? = nil,
        respondedAt: Date? = nil
    ) {
        self.reaction = reaction
        self.reactionAt = reactionAt
        self.responseText = responseText
        self.respondedAt = respondedAt
    }

    private enum CodingKeys: String, CodingKey {
        case reaction
        case reactionAt
        case responseText
        case respondedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reaction = try container.decodeIfPresent(String.self, forKey: .reaction)
            .flatMap(LumiReaction.init(rawValue:))
        reactionAt = try container.decodeIfPresent(Date.self, forKey: .reactionAt)
        responseText = try container.decodeIfPresent(String.self, forKey: .responseText)
        respondedAt = try container.decodeIfPresent(Date.self, forKey: .respondedAt)
    }

    var hasVisibleFeedback: Bool {
        reaction != nil
            || responseText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

nonisolated struct SetReactionRequest: Codable, Equatable, Sendable {
    let revealSessionId: String
    let reaction: LumiReaction
}

nonisolated struct SubmitResponseRequest: Codable, Equatable, Sendable {
    let revealSessionId: String
    let text: String
}

nonisolated struct ReactionSubmissionResponse: Codable, Equatable, Sendable {
    let status: String
    let feedback: LumiFeedback
}

nonisolated struct WrittenResponseSubmissionResponse: Codable, Equatable, Sendable {
    let status: String
    let feedback: LumiFeedback
}

nonisolated enum RecipientFeedbackServiceError: String, Error, Codable, Equatable, Sendable {
    case invalidRequest
    case revealNotConfirmed
    case expiredSession
    case alreadyResponded
    case temporaryFailure
    case invalidPayload

    var reactionMessage: String {
        switch self {
        case .expiredSession:
            "This Lumi’s response window has closed."
        case .revealNotConfirmed:
            "This Lumi is still finishing its reveal. Try again in a moment."
        case .invalidRequest, .alreadyResponded, .temporaryFailure, .invalidPayload:
            "Your reaction didn’t make it through. Try once more."
        }
    }

    var responseMessage: String {
        switch self {
        case .alreadyResponded:
            "A response has already been sent for this Lumi."
        case .expiredSession:
            "This Lumi’s response window has closed."
        case .revealNotConfirmed:
            "This Lumi is still finishing its reveal. Try again in a moment."
        case .invalidRequest:
            "Please check your response and try once more. Your words are still here."
        case .temporaryFailure, .invalidPayload:
            "Your response couldn’t be sent yet. Your words are still here."
        }
    }
}

nonisolated struct RecipientFeedbackState: Codable, Equatable, Sendable {
    var selectedReaction: LumiReaction?
    var attemptedReaction: LumiReaction?
    var isSubmittingReaction: Bool
    var reactionErrorMessage: String?
    var isResponseComposerPresented: Bool
    var draftResponse: String
    var isSubmittingResponse: Bool
    var submittedResponse: String?
    var responseErrorMessage: String?
    var isResponseLocked: Bool
    var isFeedbackWindowClosed: Bool

    init(
        selectedReaction: LumiReaction? = nil,
        attemptedReaction: LumiReaction? = nil,
        isSubmittingReaction: Bool = false,
        reactionErrorMessage: String? = nil,
        isResponseComposerPresented: Bool = false,
        draftResponse: String = "",
        isSubmittingResponse: Bool = false,
        submittedResponse: String? = nil,
        responseErrorMessage: String? = nil,
        isResponseLocked: Bool = false,
        isFeedbackWindowClosed: Bool = false
    ) {
        self.selectedReaction = selectedReaction
        self.attemptedReaction = attemptedReaction
        self.isSubmittingReaction = isSubmittingReaction
        self.reactionErrorMessage = reactionErrorMessage
        self.isResponseComposerPresented = isResponseComposerPresented
        self.draftResponse = String(draftResponse.prefix(250))
        self.isSubmittingResponse = isSubmittingResponse
        self.submittedResponse = submittedResponse
        self.responseErrorMessage = responseErrorMessage
        self.isResponseLocked = isResponseLocked
        self.isFeedbackWindowClosed = isFeedbackWindowClosed
    }

    static let empty = RecipientFeedbackState()
}

nonisolated struct RecipientFeedbackPresentationState: Codable, Equatable, Sendable {
    let isEnabled: Bool
    let selectedReaction: LumiReaction?
    let isSubmittingReaction: Bool
    let reactionErrorMessage: String?
    let isResponseComposerPresented: Bool
    let draftResponse: String
    let submittedResponse: String?
    let isSubmittingResponse: Bool
    let canSubmitResponse: Bool
    let isResponseLocked: Bool
    let responseErrorMessage: String?
    let isFeedbackWindowClosed: Bool

    static let disabled = RecipientFeedbackPresentationState(
        isEnabled: false,
        selectedReaction: nil,
        isSubmittingReaction: false,
        reactionErrorMessage: nil,
        isResponseComposerPresented: false,
        draftResponse: "",
        submittedResponse: nil,
        isSubmittingResponse: false,
        canSubmitResponse: false,
        isResponseLocked: false,
        responseErrorMessage: nil,
        isFeedbackWindowClosed: false
    )
}

extension RecipientFeedbackState {
    nonisolated func presentationState(isEnabled: Bool) -> RecipientFeedbackPresentationState {
        let trimmedDraft = draftResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        return RecipientFeedbackPresentationState(
            isEnabled: isEnabled,
            selectedReaction: selectedReaction,
            isSubmittingReaction: isSubmittingReaction,
            reactionErrorMessage: reactionErrorMessage,
            isResponseComposerPresented: isResponseComposerPresented,
            draftResponse: draftResponse,
            submittedResponse: submittedResponse,
            isSubmittingResponse: isSubmittingResponse,
            canSubmitResponse: isEnabled
                && !isFeedbackWindowClosed
                && !isResponseLocked
                && !isSubmittingResponse
                && !trimmedDraft.isEmpty,
            isResponseLocked: isResponseLocked,
            responseErrorMessage: responseErrorMessage,
            isFeedbackWindowClosed: isFeedbackWindowClosed
        )
    }
}
