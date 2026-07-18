import Combine
import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var email = ""
    @Published var otpCode = ""
    @Published var isCodeStep = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func requestOTP() async {
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please enter your email."
            return
        }

        isLoading = true
        errorMessage = nil
        infoMessage = nil

        do {
            try await appState.authService.requestOTP(email: normalizedEmail)
            isCodeStep = true
            infoMessage = "Check your email and enter the one-time code."
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func verifyOTP() async {
        guard !normalizedEmail.isEmpty, !otpCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter your email and one-time code."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let result = try await appState.authService.verifyOTP(email: normalizedEmail, code: otpCode)
            appState.completeAuth(with: result)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func resetFlow() {
        isCodeStep = false
        otpCode = ""
        errorMessage = nil
        infoMessage = nil
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
