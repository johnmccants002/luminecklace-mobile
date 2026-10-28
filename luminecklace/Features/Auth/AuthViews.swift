import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            LumiTheme.Colors.pageBackground.ignoresSafeArea()
            FloatingHeartsBackground()

            GeometryReader { geometry in
                ScrollView {
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
                        Text("A little message. A meaningful moment.")
                            .font(LumiTheme.Typography.body(18))
                            .foregroundStyle(LumiTheme.Colors.ink.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 16) {
                            Label("Write a personal message", systemImage: "square.and.pencil")
                            Label("They tap their necklace to reveal it", systemImage: "heart.circle")
                            Label("See their reactions and replies", systemImage: "bubble.left.and.bubble.right")
                        }
                        .font(.body)
                        .foregroundStyle(LumiTheme.Colors.ink)
                        .padding(.vertical)

                        Spacer()

                        NavigationLink {
                            SenderEmailAuthView(viewModel: AuthViewModel(appState: appState))
                        } label: {
                            Text("Continue with Email")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(24)
                    .frame(minHeight: geometry.size.height)
                }
            }
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

                    Text("Use the email connected to your Lumi order. You can prepare messages before the necklace arrives.")
                        .font(.subheadline)
                        .foregroundStyle(LumiTheme.Colors.ink.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LumiTextField(label: "Email", text: $viewModel.email, keyboardType: .emailAddress, contentType: .username)
                    LumiTextField(label: "Password", text: $viewModel.password, secure: true, contentType: .password)

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(Color(red: 0.82, green: 0.23, blue: 0.34))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let confirmation = viewModel.resetConfirmation {
                        Label(confirmation, systemImage: "envelope.badge")
                            .font(.subheadline)
                            .foregroundStyle(LumiTheme.Colors.ink)
                            .accessibilityAddTraits(.updatesFrequently)
                    }

                    Button("Forgot password?") {
                        Task { await viewModel.resetPassword() }
                    }
                    .frame(minHeight: 44)
                    .disabled(viewModel.isLoading)

                    PrimaryButton(
                        title: viewModel.isResettingPassword ? "Sending reset link…" : "Sign In",
                        isLoading: viewModel.isLoading
                    ) {
                        Task {
                            await viewModel.signIn()
                        }
                    }
                    NavigationLink("First time? Set up your account") {
                        AccountHelpView(initialEmail: viewModel.email)
                    }
                    .frame(minHeight: 44)
                }
                .padding(24)
            }
        }
        .tint(LumiTheme.Colors.rose)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink("Account help") { AccountHelpView(initialEmail: viewModel.email) }
            }
        }
    }
}

struct AccountHelpView: View {
    var initialEmail = ""
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Getting connected").font(LumiTheme.Typography.display(34))
                if let email = appState.user?.email {
                    Text("Signed in as \(email)").font(.subheadline.weight(.semibold))
                }
                help("1. Find your order email", "Use the email address on your order confirmation. If the necklace was a gift, ask the purchaser which address was used for setup.")
                help("2. Set your password from the email", "Open your Lumi setup email, including checking spam. The link takes you to the website to set your password. Then return to Lumi and sign in with your order email.")
                NavigationLink {
                    AccountSetupView(email: appState.user?.email ?? initialEmail)
                } label: {
                    Label("Request a new setup link", systemImage: "envelope")
                }
                .buttonStyle(SecondaryButtonStyle())
                Text("Setup links are for orders whose account setup is unfinished. Already set a password? Use Forgot password on the sign-in screen. If the reset email doesn’t arrive, contact support below.")
                    .font(.subheadline)
                help("3. Check for your necklace", "Once setup is complete, return here and check again. If it’s still missing, email support with your order number and order email.")
                LumiAccountSupportLink()
                if appState.user != nil {
                    PrimaryButton(title: "Check for my necklace") {
                        Task { await appState.bootstrapSenderFlowAfterAuth() }
                    }
                    Button("Use another account") {
                        Task { await appState.signOut() }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                } else {
                    Button("Back to sign in") { dismiss() }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(20)
        }
        .background(LumiTheme.Colors.pageBackground)
        .foregroundStyle(LumiTheme.Colors.ink)
        .navigationTitle("Account help")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func help(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(detail).font(.body).foregroundStyle(LumiTheme.Colors.ink.opacity(0.8))
        }
    }
}

struct AccountSetupView: View {
    @StateObject private var viewModel: AccountSetupViewModel

    init(email: String = "") {
        _viewModel = StateObject(wrappedValue: AccountSetupViewModel(email: email))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Finish your account setup")
                    .font(LumiTheme.Typography.display(32))
                Text("Enter the email used for your Lumi order to request a fresh setup link. This is for accounts that haven’t completed setup yet.")
                LumiTextField(label: "Order email", text: $viewModel.email, keyboardType: .emailAddress, contentType: .emailAddress)
                    .disabled(viewModel.isLoading)
                if let email = viewModel.requestedEmail {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Request received", systemImage: "envelope.badge")
                            .font(.headline)
                        Text("If \(email) has an eligible order with unfinished setup, you’ll receive a new link. Check your inbox and spam folder. Allow five minutes before requesting another link.")
                        Text("Open the newest email, set your password on the website, then return to Lumi and sign in with that email. If no email arrives, contact support below.")
                    }
                    .accessibilityAddTraits(.updatesFrequently)
                }
                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
                PrimaryButton(title: "Request setup link", isLoading: viewModel.isLoading) {
                    Task { await viewModel.requestSetupLink() }
                }
                LumiAccountSupportLink()
            }
            .padding(24)
        }
        .background(LumiTheme.Colors.pageBackground)
        .foregroundStyle(LumiTheme.Colors.ink)
        .navigationTitle("Account setup")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LumiAccountSupportLink: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Link(destination: URL(string: "mailto:support@luminecklace.com?subject=Lumi%20account%20help")!) {
                Label("Email Lumi support", systemImage: "envelope")
            }
            .buttonStyle(SecondaryButtonStyle())
            Text("support@luminecklace.com")
                .font(.footnote)
                .textSelection(.enabled)
        }
    }
}
