import SwiftUI

@main
struct luminecklaceApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(appState)
                .onOpenURL { url in
                    appState.handleIncomingHandoff(url: url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                    guard let url = userActivity.webpageURL else { return }
                    appState.handleIncomingHandoff(url: url)
                }
        }
    }
}
