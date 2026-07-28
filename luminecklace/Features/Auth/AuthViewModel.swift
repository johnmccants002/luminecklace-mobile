import Combine
import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func signIn() async {
        guard !normalizedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Enter your email and password."
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
    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
