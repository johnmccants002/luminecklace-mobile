//
//  ClipModel.swift
//  lumiclip
//

import Foundation
import Combine

final class ClipModel: ObservableObject {
    @Published var incomingURL: URL?
    @Published var nfcID: String?

    func loadInitialInvocationURLIfNeeded() {
        guard incomingURL == nil else { return }

        if let url = invocationURLFromEnvironment() ?? invocationURLFromLaunchArguments() {
            handle(url: url)
        }
    }

    func handle(url: URL) {
        incomingURL = url

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            nfcID = nil
            return
        }

        let extractedID = components.queryItems?
            .first(where: { $0.name.lowercased() == "nfc_id" })?
            .value?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        nfcID = (extractedID?.isEmpty == false) ? extractedID : nil
    }

    private func invocationURLFromEnvironment() -> URL? {
        let env = ProcessInfo.processInfo.environment
        let keys = ["_XCAppClipURL", "XCAppClipURL", "APP_CLIP_URL"]

        for key in keys {
            guard let value = env[key], let url = URL(string: value) else { continue }
            return url
        }

        return nil
    }

    private func invocationURLFromLaunchArguments() -> URL? {
        let arguments = ProcessInfo.processInfo.arguments

        // Xcode App Clip testing may pass the invocation URL as a launch argument.
        for (index, value) in arguments.enumerated() {
            let lowercased = value.lowercased()
            if lowercased.contains("appclipurl") || lowercased == "_xcappclipurl" {
                let nextIndex = index + 1
                if nextIndex < arguments.count, let url = URL(string: arguments[nextIndex]) {
                    return url
                }
            }
        }

        return arguments
            .first(where: { $0.hasPrefix("https://") || $0.hasPrefix("http://") })
            .flatMap(URL.init(string:))
    }
}
