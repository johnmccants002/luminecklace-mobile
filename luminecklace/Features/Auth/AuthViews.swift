import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            LumiTheme.Colors.appGradient.ignoresSafeArea()
            FloatingHeartsBackground()

            VStack(spacing: 22) {
                Spacer()
                Text("Lumi")
                    .font(LumiTheme.Typography.display(54))
                    .foregroundStyle(.white)
                Text("Set up your necklace experience before it arrives.")
                    .font(LumiTheme.Typography.body(18))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                NavigationLink {
                    SenderEmailAuthView(viewModel: AuthViewModel(appState: appState))
                } label: {
                    Text("Continue with Email")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(24)
        }
        .navigationBarHidden(true)
    }
}

struct SenderEmailAuthView: View {
    @ObservedObject var viewModel: AuthViewModel

    var body: some View {
        ZStack {
            LumiTheme.Colors.pageBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    Text(viewModel.isCodeStep ? "Enter your code" : "Sign in with email")
                        .font(LumiTheme.Typography.display(34))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LumiTextField(label: "Email", text: $viewModel.email, keyboardType: .emailAddress)

                    if viewModel.isCodeStep {
                        LumiTextField(
                            label: "One-Time Code",
                            text: $viewModel.otpCode,
                            keyboardType: .numberPad,
                            autocapitalization: .characters
                        )
                    }

                    if let info = viewModel.infoMessage {
                        Text(info)
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    PrimaryButton(
                        title: viewModel.isCodeStep ? "Verify Code" : "Send Code",
                        isLoading: viewModel.isLoading
                    ) {
                        Task {
                            if viewModel.isCodeStep {
                                await viewModel.verifyOTP()
                            } else {
                                await viewModel.requestOTP()
                            }
                        }
                    }

                    if viewModel.isCodeStep {
                        Button("Use a different email") {
                            viewModel.resetFlow()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(24)
            }
        }
    }
}
