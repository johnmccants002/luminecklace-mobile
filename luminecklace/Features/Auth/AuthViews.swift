import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            LumiTheme.Colors.pageBackground.ignoresSafeArea()
            FloatingHeartsBackground()

            VStack(spacing: 22) {
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(LumiTheme.Colors.rose)
                    Text("Lumi")
                        .font(LumiTheme.Typography.display(54))
                        .foregroundStyle(LumiTheme.Colors.ink)
                }
                Text("Set up your necklace experience before it arrives.")
                    .font(LumiTheme.Typography.body(18))
                    .foregroundStyle(LumiTheme.Colors.ink.opacity(0.72))
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
                    Text("Sign in")
                        .font(LumiTheme.Typography.display(34))
                        .foregroundStyle(LumiTheme.Colors.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LumiTextField(label: "Email", text: $viewModel.email, keyboardType: .emailAddress)
                    LumiTextField(label: "Password", text: $viewModel.password, secure: true)

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(Color(red: 0.82, green: 0.23, blue: 0.34))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    PrimaryButton(
                        title: "Sign In",
                        isLoading: viewModel.isLoading
                    ) {
                        Task {
                            await viewModel.signIn()
                        }
                    }
                }
                .padding(24)
            }
        }
    }
}
