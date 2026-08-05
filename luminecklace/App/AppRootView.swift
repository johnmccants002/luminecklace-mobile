import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch appState.route {
            case .auth:
                NavigationStack { WelcomeView() }
            case .postAuthBootstrap:
                NavigationStack { PostAuthBootstrapView() }
            case .noNecklace:
                NavigationStack { NoNecklaceView() }
            case .senderLoadError:
                NavigationStack { SenderLoadErrorView() }
            case .upNextEditor:
                UpNextEditorView()
            case .reserveEditor:
                ReserveEditorView()
            case .lumiComposer:
                NavigationStack { LumiComposerView() }
            case .senderHome:
                MainTabView()
            case .recipientReveal:
                NavigationStack { RecipientRevealView() }
            }
        }
        .task {
            await appState.restoreSessionIfNeeded()
        }
        .preferredColorScheme(.light)
    }
}

struct MainTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            NavigationStack {
                HomeView(viewModel: HomeViewModel(appState: appState))
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }

            NavigationStack {
                CollectionView(viewModel: CollectionViewModel(appState: appState))
            }
            .tabItem {
                Label("Collection", systemImage: "sparkles.square.filled.on.square")
            }

            NavigationStack {
                ExploreView(appState: appState)
            }
            .tabItem {
                Label("Explore", systemImage: "heart.text.square.fill")
            }

            NavigationStack {
                SettingsView(viewModel: SettingsViewModel(appState: appState))
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
        .tint(LumiTheme.Colors.rose)
    }
}
