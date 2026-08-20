import SwiftUI

struct AppRootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        AppRootContent(notificationManager: appState.pushNotificationManager)
    }
}

private struct AppRootContent: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var notificationManager: PushNotificationManager

    var body: some View {
        Group {
            switch appState.route {
            case .sessionRestoring:
                NavigationStack { SessionRestoringView() }
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
        .sheet(isPresented: $notificationManager.isEducationPresented) {
            PushPermissionEducationView(manager: notificationManager)
                .presentationDetents([.height(390)])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
        }
        .preferredColorScheme(.light)
    }
}

private struct PushPermissionEducationView: View {
    @ObservedObject var manager: PushNotificationManager

    var body: some View {
        ZStack {
            LumiTheme.Colors.pageBackground.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "bell.and.waves.left.and.right.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(LumiTheme.Colors.rose)
                    .frame(width: 72, height: 72)
                    .background(LumiTheme.Colors.rose.opacity(0.12))
                    .clipShape(Circle())

                Text("Know when your Lumi reaches them")
                    .font(LumiTheme.Typography.headline(24))
                    .foregroundStyle(LumiTheme.Colors.ink)
                    .multilineTextAlignment(.center)

                Text("Get a gentle notification when your message is revealed, reacted to, or answered.")
                    .font(LumiTheme.Typography.body(15))
                    .foregroundStyle(LumiTheme.Colors.ink.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryButton(title: "Turn On Notifications") {
                    Task { await manager.requestAuthorizationAfterEducation() }
                }

                Button("Not Now") {
                    manager.dismissEducation()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(24)
        }
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
                ExploreFeedView(appState: appState)
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
