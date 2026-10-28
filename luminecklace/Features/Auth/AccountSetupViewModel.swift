import Combine
import Foundation

protocol InvitationRecoveryServicing {
    func requestSetupLink(email: String) async throws
}

struct InvitationRecoveryService: InvitationRecoveryServicing {
    var client: APIClient = .shared

    func requestSetupLink(email: String) async throws {
        let response = try await client.requestObject(
            method: .post,
            path: "/api/auth/invitations/recover",
            body: ["email": email]
        )
        guard response["success"] as? Bool == true else {
            throw APIError.invalidPayload
        }
    }
}

@MainActor
final class AccountSetupViewModel: ObservableObject {
    @Published var email: String
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var requestedEmail: String?

    private let service: any InvitationRecoveryServicing

    init(email: String = "", service: any InvitationRecoveryServicing = InvitationRecoveryService()) {
        self.email = email
        self.service = service
    }

    nonisolated deinit {}

    func requestSetupLink() async {
        guard !isLoading else { return }
        requestedEmail = nil
        errorMessage = nil
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        guard !address.contains(where: { $0.isWhitespace }),
              parts.count == 2, !parts[0].isEmpty,
              parts[1].split(separator: ".", omittingEmptySubsequences: false).count >= 2,
              parts[1].split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty }) else {
            errorMessage = "Enter the email address used for your Lumi order."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await service.requestSetupLink(email: address)
            requestedEmail = address
        } catch {
            errorMessage = "The setup link couldn’t be requested. Try again, or email Lumi support below."
        }
    }
}
