import Foundation

enum RecipientInvocationParser {
    static let productionHost = "www.luminecklace.com"

    static func token(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        guard components.queryItems?.isEmpty ?? true else {
            return nil
        }

        guard isAllowedSchemeAndHost(components) else {
            return nil
        }

        let pathComponents = url.pathComponents
        guard pathComponents.count == 3,
              pathComponents[0] == "/",
              pathComponents[1] == "t" else {
            return nil
        }

        let token = pathComponents[2]
        guard !token.isEmpty else {
            return nil
        }
        return token
    }

    private static func isAllowedSchemeAndHost(_ components: URLComponents) -> Bool {
        guard components.scheme == "https", let host = components.host else {
            return false
        }

        if host == productionHost {
            return true
        }

        #if DEBUG
        if let developmentHost = ProcessInfo.processInfo.environment["LUMI_DEVELOPMENT_LINK_HOST"],
           !developmentHost.isEmpty,
           host == developmentHost {
            return true
        }
        #endif

        return false
    }
}
