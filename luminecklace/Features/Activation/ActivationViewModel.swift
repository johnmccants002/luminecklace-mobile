import Combine
import Foundation

enum ActivationStatus {
    case empty
    case validating
    case success(NecklaceTag)
    case invalid(String)
}

@MainActor
final class ActivationViewModel: ObservableObject {
    @Published var activationCode = ""
    @Published var status: ActivationStatus = .empty

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func setActivationCodeInput(_ input: String) {
        activationCode = Self.formatActivationCode(input)
    }

    func activate() async {
        guard !activationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            status = .empty
            return
        }

        status = .invalid("Manual activation has been replaced by sender order linking.")
    }

    func continueToApp() async {
        appState.route = .noOrderAssist
    }

    func signOut() {
        appState.signOut()
    }

    private static func formatActivationCode(_ input: String) -> String {
        let raw = String(input.uppercased().filter { $0.isLetter || $0.isNumber })
        guard !raw.isEmpty else { return "" }

        if raw.hasPrefix("LUMI") {
            let suffix = String(raw.dropFirst(4))
            guard !suffix.isEmpty else { return "LUMI" }
            return "LUMI-" + grouped(suffix, by: 4)
        }

        return grouped(raw, by: 4)
    }

    private static func grouped(_ value: String, by size: Int) -> String {
        var output: [String] = []
        var current = ""

        for char in value {
            current.append(char)
            if current.count == size {
                output.append(current)
                current = ""
            }
        }

        if !current.isEmpty {
            output.append(current)
        }

        return output.joined(separator: "-")
    }
}
