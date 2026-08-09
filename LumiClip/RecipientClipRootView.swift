import SwiftUI

struct RecipientClipRootView: View {
    @ObservedObject var viewModel: RecipientClipViewModel

    var body: some View {
        RecipientRevealPresentationView(
            revealState: viewModel.state,
            retryAction: viewModel.retry,
            retryConfirmationAction: viewModel.retryRevealConfirmation,
            feedbackState: viewModel.feedbackPresentationState,
            selectReaction: viewModel.selectReaction,
            retryReaction: viewModel.retryReaction,
            setResponseComposerPresented: viewModel.setResponseComposerPresented,
            updateResponseDraft: viewModel.updateResponseDraft,
            submitResponse: viewModel.submitResponse
        )
    }
}

#Preview {
    RecipientClipRootView(viewModel: RecipientClipViewModel())
}
