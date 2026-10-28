import Combine
import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var isResettingPassword = false
    @Published var resetConfirmation: String?

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    // No actor-isolated cleanup is needed when this screen model is released.
    nonisolated deinit {}

    func signIn() async {
        guard !isLoading else { return }
        resetConfirmation = nil
        guard !normalizedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Enter your email and password."
            return
        }
        guard isValidEmail else {
            errorMessage = "Enter a valid email address."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let result = try await appState.authService.signIn(
                email: normalizedEmail,
                password: password
            )
            appState.completeAuth(with: result)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func resetPassword() async {
        guard !isLoading else { return }
        resetConfirmation = nil
        guard isValidEmail else {
            errorMessage = "Enter your email address above so we can send a reset link."
            return
        }
        isLoading = true
        errorMessage = nil
        isResettingPassword = true
        defer { isLoading = false; isResettingPassword = false }
        do {
            try await appState.authService.resetPassword(email: normalizedEmail)
            resetConfirmation = "If an account matches this email, you’ll receive a password-reset link. Check your inbox and spam folder. Set your new password on the website, then return here to sign in. Allow a few minutes before requesting another email."
        } catch {
            errorMessage = "The reset email couldn’t be requested. Try again, or open Account help to contact Lumi support."
        }
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var isValidEmail: Bool {
        guard !normalizedEmail.contains(where: { $0.isWhitespace }) else {
            return false
        }

        let addressParts = normalizedEmail.split(
            separator: "@",
            omittingEmptySubsequences: false
        )
        guard addressParts.count == 2,
              !addressParts[0].isEmpty else {
            return false
        }

        let domainParts = addressParts[1].split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        return domainParts.count >= 2 && domainParts.allSatisfy { !$0.isEmpty }
    }
}
