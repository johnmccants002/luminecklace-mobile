import SwiftUI

struct ActivationView: View {
    @ObservedObject var viewModel: ActivationViewModel

    var body: some View {
        ZStack {
            LumiTheme.Colors.pageBackground.ignoresSafeArea()

            VStack(spacing: 18) {
                Text("Activate Necklace")
                    .font(LumiTheme.Typography.display(34))
                    .foregroundStyle(.white)

                Text("Enter the activation code from your Lumi box.")
                    .font(LumiTheme.Typography.body(15))
                    .foregroundStyle(.white.opacity(0.82))

                TextField("LUMI-9382-XZ", text: Binding(get: {
                    viewModel.activationCode
                }, set: { newValue in
                    viewModel.setActivationCodeInput(newValue)
                }))
                    .font(LumiTheme.Typography.mono(20))
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(LumiTheme.Colors.ink.opacity(0.32))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.24), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .textInputAutocapitalization(.characters)

                PrimaryButton(
                    title: viewModel.buttonTitle,
                    isLoading: viewModel.isLoading
                ) {
                    Task { await viewModel.activate() }
                }

                statusView

                Button("Use Different Account") {
                    viewModel.signOut()
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer()
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch viewModel.status {
        case .empty:
            EmptyStateView(
                title: "No code entered",
                subtitle: "Use the code printed on your card insert.",
                systemImage: "qrcode.viewfinder"
            )
        case .validating:
            EmptyStateView(
                title: "Validating...",
                subtitle: "Checking your necklace code.",
                systemImage: "hourglass"
            )
        case let .invalid(message):
            EmptyStateView(
                title: "Invalid Code",
                subtitle: message,
                systemImage: "xmark.octagon"
            )
        case let .success(necklace):
            VStack(spacing: 14) {
                NecklaceCardView(necklace: necklace)
                    .transition(.move(edge: .bottom).combined(with: .opacity))

                PrimaryButton(title: "Continue") {
                    Task { await viewModel.continueToApp() }
                }
            }
        }
    }
}

private extension ActivationViewModel {
    var isLoading: Bool {
        if case .validating = status { return true }
        return false
    }

    var buttonTitle: String {
        switch status {
        case .success:
            return "Activated"
        default:
            return "Activate"
        }
    }
}
