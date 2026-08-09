import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ZStack {
            LumiTheme.Colors.pageBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Settings")
                        .font(LumiTheme.Typography.display(34))
                        .foregroundStyle(LumiTheme.Colors.ink)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Profile")
                            .font(LumiTheme.Typography.headline(18))
                            .foregroundStyle(LumiTheme.Colors.ink)
                        Text(viewModel.userEmail)
                            .font(LumiTheme.Typography.body(14))
                            .foregroundStyle(LumiTheme.Colors.ink.opacity(0.72))
                    }
                    .glassCard()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Subscription")
                            .font(LumiTheme.Typography.headline(18))
                            .foregroundStyle(LumiTheme.Colors.ink)
                        Text(viewModel.subscriptionTitle)
                            .font(LumiTheme.Typography.body(15).weight(.semibold))
                            .foregroundStyle(LumiTheme.Colors.rose)
                    }
                    .glassCard()

                    notificationSection

                    Toggle("Sound", isOn: Binding(get: {
                        viewModel.soundEnabled
                    }, set: { newValue in
                        viewModel.soundEnabled = newValue
                        viewModel.applySettings()
                    }))
                    .tint(LumiTheme.Colors.rose)
                    .glassCard()

                    Toggle("Haptics", isOn: Binding(get: {
                        viewModel.hapticsEnabled
                    }, set: { newValue in
                        viewModel.hapticsEnabled = newValue
                        viewModel.applySettings()
                    }))
                    .tint(LumiTheme.Colors.rose)
                    .glassCard()

                    Button(viewModel.isSigningOut ? "Signing Out…" : "Sign Out") {
                        Task { await viewModel.signOut() }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(viewModel.isSigningOut)
                }
                .padding(20)
            }
        }
        .task {
            await viewModel.loadNotifications()
        }
    }

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Notifications", systemImage: "bell.fill")
                    .font(LumiTheme.Typography.headline(18))
                    .foregroundStyle(LumiTheme.Colors.ink)
                Spacer()
                Text(viewModel.permissionState.title)
                    .font(LumiTheme.Typography.body(12).weight(.semibold))
                    .foregroundStyle(
                        viewModel.permissionState == .enabled
                            ? LumiTheme.Colors.rose
                            : LumiTheme.Colors.ink.opacity(0.62)
                    )
                    .multilineTextAlignment(.trailing)
            }

            switch viewModel.permissionState {
            case .notRequested:
                Text("Choose which Lumi moments you want to hear about.")
                    .font(LumiTheme.Typography.body(14))
                    .foregroundStyle(LumiTheme.Colors.ink.opacity(0.72))
                Button("Enable Notifications") {
                    viewModel.enableNotifications()
                }
                .buttonStyle(SecondaryButtonStyle())

            case .denied:
                Text("Notifications are turned off for Lumi at the system level.")
                    .font(LumiTheme.Typography.body(14))
                    .foregroundStyle(LumiTheme.Colors.ink.opacity(0.72))
                Button("Open iOS Settings") {
                    viewModel.openSystemSettings()
                }
                .buttonStyle(SecondaryButtonStyle())

            case .enabled:
                preferenceControls
            }

            if let error = viewModel.notificationError {
                Text(error)
                    .font(LumiTheme.Typography.body(13))
                    .foregroundStyle(.red.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .glassCard()
    }

    @ViewBuilder
    private var preferenceControls: some View {
        if viewModel.isLoadingNotifications && viewModel.pushPreferences == nil {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(LumiTheme.Colors.rose)
                Text("Loading preferences…")
                    .font(LumiTheme.Typography.body(14))
                    .foregroundStyle(LumiTheme.Colors.ink.opacity(0.72))
            }
        } else if let preferences = viewModel.pushPreferences {
            notificationToggle(
                "Lumi reveals",
                isOn: preferences.revealsEnabled,
                kind: .reveals
            )
            notificationToggle(
                "Reactions",
                isOn: preferences.reactionsEnabled,
                kind: .reactions
            )
            notificationToggle(
                "Written responses",
                isOn: preferences.responsesEnabled,
                kind: .responses
            )
        } else {
            Button("Retry") {
                Task { await viewModel.loadNotifications() }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func notificationToggle(
        _ title: String,
        isOn: Bool,
        kind: PushPreferenceKind
    ) -> some View {
        Toggle(title, isOn: Binding(
            get: { isOn },
            set: { enabled in
                Task { await viewModel.setPreference(kind, enabled: enabled) }
            }
        ))
        .tint(LumiTheme.Colors.rose)
        .disabled(viewModel.isSavingPreferences)
    }
}
