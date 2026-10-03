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
