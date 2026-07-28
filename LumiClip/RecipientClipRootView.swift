import SwiftUI

struct RecipientClipRootView: View {
    @ObservedObject var viewModel: RecipientClipViewModel

    var body: some View {
        RecipientRevealPresentationView(
            revealState: viewModel.state,
            retryAction: viewModel.retry
        )
    }
}

#Preview {
    RecipientClipRootView(viewModel: RecipientClipViewModel())
}
