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
            case .noOrderAssist:
                NavigationStack { NoOrderAssistView() }
            case .necklaceSelection:
                NavigationStack { NecklaceSelectionView() }
            case .firstMessageSetup:
                NavigationStack { FirstMessageSetupView() }
            case .senderHome:
                MainTabView()
            case .recipientReveal:
                NavigationStack { RecipientRevealView() }
            }
        }
        .task {
            await appState.restoreSessionIfNeeded()
        }
        .preferredColorScheme(.dark)
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
                PackagesView(viewModel: PackagesViewModel(appState: appState))
            }
            .tabItem {
                Label("Packages", systemImage: "gift.fill")
            }

            NavigationStack {
                FavoritesView(viewModel: FavoritesViewModel(appState: appState))
            }
            .tabItem {
                Label("Favorites", systemImage: "heart.fill")
            }

            NavigationStack {
                SettingsView(viewModel: SettingsViewModel(appState: appState))
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
        .tint(LumiTheme.Colors.blush)
    }
}
