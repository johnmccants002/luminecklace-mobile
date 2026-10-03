import SwiftUI

@main
struct luminecklaceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(appState)
                .task {
                    appDelegate.configure(
                        notificationManager: appState.pushNotificationManager
                    )
                    await appState.pushNotificationManager.start()
                }
                .onOpenURL { url in
                    appState.handleIncomingHandoff(url: url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                    guard let url = userActivity.webpageURL else { return }
                    appState.handleIncomingHandoff(url: url)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    Task {
                        await appState.handleApplicationDidBecomeActive()
                    }
                }
        }
    }
}
